/*
**	This stored procedure creates databases on any MSSQL instance.  It creates the data and log files under directories that are defined in the meta database.  This sp
**	is a sub stored procedure.  It is not meant to be called directly but through a user stored procedure.  The sp takes a name provided by the USP and checks to see if
**	the name is available on the instance it is currently running under.
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_createDatabase')
	DROP PROCEDURE [dbo].[sub_createDatabase];
GO

CREATE PROCEDURE [dbo].[sub_createDatabase] (
	@newDbName		sysname			--Required:	The name of the database to be created.
	,@createDebug	nchar(1) = 'n'	--Optional: When set, returns additional debugging information to diagnose errors.
)
AS

DECLARE @defaultDataDirectory	nvarchar(500)	--The directory on the database server which will house the .mdf file(s).
		,@defaultLogDirectory	nvarchar(500)	--The directory on the database server which will house the .ldf file(s).
		,@createDatabase		bit = 1			--Indicates if it is possible to create the database or if the sp has to return an error and quit: 0 = do not attempt to create database, 1 = attempt to create database
		,@count					int = 0			--Counter for any arbitrary number of operations.
		,@dataFilename			nvarchar(128)	--The name of the actual data file for the new database.
		,@logFilename			nvarchar(128)	--The name of the actual log file for the new database.
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorState			int
		,@errorLine				int
		,@errorProcedure		nvarchar(128)
		,@errorSeverity			int
		,@errorNumber			int;

SET NOCOUNT ON;

BEGIN TRY

	SET @defaultDataDirectory = (SELECT p_value FROM params WHERE p_key = 'defaultDataDirectory'); --As each instance has its own meta database, the sp will pull an instance specific directory location.
	SET @defaultLogDirectory = (SELECT p_value FROM params WHERE p_key = 'defaultLogDirectory');
	
	IF (RIGHT(@defaultDataDirectory, 1) <> '\') --Append a backslash character to the defaultDataDirectory if one is not already present.
		SET @defaultDataDirectory = @defaultDataDirectory + '\';

	IF (RIGHT(@defaultLogDirectory, 1) <> '\') --Append a backslash character to the defaultLogDirectory if one is not already present.
		SET @defaultLogDirectory = @defaultLogDirectory + '\';

	SET @printMessage =  'Checking database availability:'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	
	IF EXISTS(SELECT 1 FROM sys.databases WHERE name = @newDbName) --Check if the database already exists.  Halt the script if it does.
		RAISERROR('	Database name already exists.  Specify a different name', 16, 1) WITH LOG;

	SET @printMessage =  '	Database available, Creating'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @dataFilename = @newDbName + N'.mdf'; --Set the data filename to the exact same name as the actual database.  If an error is encountered while trying to create this filename than the name is altered.
	SET @logFilename = @newDbName + N'_log.ldf'; --Set the log filename to the exact same name as the actual database.  If an error is encountered while trying to create this filename than the name is altered.
	
	/*
	**	The CREATE DATABASE statement is created dynamically as the database name is not known.  This creates the database using the default directories and starts the new
	**	database with a 3MB data file and a 1MB log file.  The data file grows at 1MB intervals, while the log file grows by 10%.  The statement is put inside a nested
	**	TRY...CATCH statement which is also placed inside a WHILE statement.  This is used in an attempt to create the database.  If that attempt fails then changes can be
	**	made and another attempt is made to create the database.  This can be useful when the database does not exist on the server, but the filenames are taken (which means
	**	that the original database wasn't deleted properly).
	*/
	WHILE @createDatabase = 1
	BEGIN
		BEGIN TRY

			SET @count = @count + 1;
			SET @sql = N'CREATE DATABASE ' + QUOTENAME(@newDbName) + N' ON  PRIMARY' + char(13) + char(10) +
						N'(NAME = N' + QUOTENAME(@newDbName, '''') + N',FILENAME = N''' + @defaultDataDirectory + @dataFilename + N''',SIZE = 3072KB,FILEGROWTH = 1024KB)
						LOG ON 
						(NAME = N''' + @newDbName + N'_log'',FILENAME = N''' + @defaultLogDirectory + @logFilename + N''',SIZE = 1024KB,FILEGROWTH = 10%)'
			EXEC sp_executesql @sql;
			SET @createDatabase = 0; --End the loop after successfully running the CREATE DATABASE statement.
		END TRY
		BEGIN CATCH

			IF @@TRANCOUNT > 0
				ROLLBACK;

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER()
					,@errorProcedure = COALESCE('dbo.sub_createDatabase', ERROR_PROCEDURE(), NULL)
					,@errorLine = ERROR_LINE();

			SET @printMessage = N'Error encountered while processing' + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
						N'Error Number			Error Severity			Error Procedure				Error Line #' + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
						CONVERT(nvarchar(8), @errorNumber) + '					' + CONVERT(nvarchar(8), @errorSeverity) + '						' + ISNULL(CONVERT(nvarchar(32), @errorProcedure), 'NULL') + '		' + CONVERT(nvarchar(8), @errorLine) + char(13) + char(10) + char(13) + char(10) + char(13) + char(10) +
						N'Error Message:		' + @errorMessage + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------'

			IF @count > 10 --After 10 failed attempts to create the database just give up.
				RAISERROR(@errorMessage, @errorSeverity, 1);

			IF @errorNumber = 1802 --Database could not be created because the same filename already exists on the database server.
			BEGIN

				SET @printMessage = '	Filename: "' + @dataFilename + '" and/or "' + @logFilename + '" already exists for the ' + @newDbName + ' database, alerting filename structure';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
				SET @dataFilename = @newDbName + CAST(@count AS nvarchar(2)); --Change the name of the data file by appending a number to it.
				SET @logFilename = @newDbName + CAST(@count AS nvarchar(2)); --Change the name of the log file by appending a number to it.
			END
			ELSE
				RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
	END;

	/*
	**	Once the database has been created then several ALTER DATABASE statements are run to set defaults on the new database.  What each database option does is specified
	**	below in further comments.
	*/
	SET @sql = N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET COMPATIBILITY_LEVEL = 100' + char(13) + char(10) +			--Compatibility Level set to SQL 2008.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET ANSI_NULL_DEFAULT OFF ' + char(13) + char(10) +				--New columns are not explicitly nullable without specifying.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET ANSI_NULLS OFF' + char(13) + char(10) +						--Equals (=) and not equals (<>) comparions evaluate to TRUE against NULL values.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET ANSI_PADDING OFF' + char(13) + char(10) +					--For varchar & varbinary, trailing blanks/zeros are trimmed.  Char & binary follow same rules are varchar & varbinary.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET ANSI_WARNINGS OFF' + char(13) + char(10) +					--ISO standard behavior for several error conditions is turned off (http://technet.microsoft.com/en-us/library/ms190368.aspx).
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET ARITHABORT OFF' + char(13) + char(10) +						--If arithmetic overflow or divide-by-zero error occurs batch or query is not terminated.  Warning is displayed and NULL value is assigned to the arithmetic operation.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET AUTO_CLOSE OFF' + char(13) + char(10) +						--Does not automatically close after the last users exits.  Setting AUTO_CLOSE to ON can degrade performance for frequently accessed databases.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET AUTO_CREATE_STATISTICS ON' + char(13) + char(10) +			--Enable automatic creation of statistics.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET AUTO_SHRINK OFF' + char(13) + char(10) +						--The database will not automatically release free space.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET AUTO_UPDATE_STATISTICS ON' + char(13) + char(10) +			--Enable automatic update of statistics.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET CURSOR_CLOSE_ON_COMMIT OFF' + char(13) + char(10) +			--The server will not close cursors with a COMMIT TRANSACTION statement.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET CURSOR_DEFAULT  GLOBAL' + char(13) + char(10) +				--When cursors are created they are defined as global unless specifically created as local.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET CONCAT_NULL_YIELDS_NULL OFF' + char(13) + char(10) +			--Concatenating any string with a NULL value yields a string value.  NULL is treated as an empty string.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET NUMERIC_ROUNDABORT OFF' + char(13) + char(10) +				--When rounding in an expressions results in a loss of precision no errors or warnings are given and the result is rounded.  If set to ON then SET ARITHABORT controls the behavior.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET QUOTED_IDENTIFIER OFF' + char(13) + char(10) +				--literal strings in expressions can be delimited by single or double quotation marks. If a literal string is delimited by double quotation marks, the string can contain embedded single quotation marks, such as apostrophes.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET RECURSIVE_TRIGGERS OFF' + char(13) + char(10) +				--Do not allow recursive triggers (http://technet.microsoft.com/en-us/library/ms190739.aspx).
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET DISABLE_BROKER' + char(13) + char(10) +						--The service broker is disabled for the specified database.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET AUTO_UPDATE_STATISTICS_ASYNC OFF' + char(13) + char(10) +	--Specifies that statistics updates for the AUTO_UPDATE_STATISTICS option are synchronous. The query optimizer waits for statistcs updates to complete before it compiles queries.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET DATE_CORRELATION_OPTIMIZATION OFF' + char(13) + char(10) +	--Correlation statistics are not maintained.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET PARAMETERIZATION SIMPLE' + char(13) + char(10) +				--Queries are parameterized based on the default behavior of the database.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET READ_COMMITTED_SNAPSHOT OFF' + char(13) + char(10) +			--Transactions specifying the READ COMMITTED isolation level use locking.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET READ_WRITE' + char(13) + char(10) +							--The database is available for read and write operations.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET RECOVERY FULL' + char(13) + char(10) +						--Provides full recovery after media failure by using transaction log backups. If a data file is damaged, media recovery can restore all committed transactions.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET MULTI_USER' + char(13) + char(10) +							--All users that have the appropriate permissions to connect to the database are allowed.
				N'ALTER DATABASE ' + QUOTENAME(@newDbName) + N'SET PAGE_VERIFY CHECKSUM'										--SQL calculates checksums for whole pages and recomputes checksums when pages are read (http://technet.microsoft.com/en-us/library/bb402873.aspx).
	EXEC sp_executesql @sql;

	SET @sql = N'USE ' + QUOTENAME(@newDbName) + char(13) + char(10) +
				N'IF NOT EXISTS (SELECT name FROM sys.filegroups WHERE is_default=1 AND name = N''PRIMARY'')
				ALTER DATABASE ' + QUOTENAME(@newDbName) + N' MODIFY FILEGROUP [PRIMARY] DEFAULT' --Changes the default database filegroup to [PRIMARY]. Only one filegroup in the database can be the default filegroup.
	EXEC sp_executesql @sql;

	SET @printMessage =  '	Database created' + char(13) + char(10);
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
	
	SELECT @errorMessage = ERROR_MESSAGE()
		,@errorSeverity = ERROR_SEVERITY()
		,@errorNumber = ERROR_NUMBER()
		,@errorProcedure = COALESCE('dbo.sub_createDatabase', ERROR_PROCEDURE(), NULL)
		,@errorLine = ERROR_LINE();

	SET @printMessage = N'Error encountered while processing' + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
						N'Error Number			Error Severity			Error Procedure				Error Line #' + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
						CONVERT(nvarchar(8), @errorNumber) + '					' + CONVERT(nvarchar(8), @errorSeverity) + '						' + ISNULL(CONVERT(nvarchar(32), @errorProcedure), 'NULL') + '		' + CONVERT(nvarchar(8), @errorLine) + char(13) + char(10) + char(13) + char(10) + char(13) + char(10) +
						N'Error Message:		' + @errorMessage + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------'

	RAISERROR(@printMessage, @errorSeverity, 1);
END CATCH;