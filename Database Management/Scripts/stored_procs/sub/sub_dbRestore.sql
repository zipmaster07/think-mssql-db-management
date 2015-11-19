/*
**	This stored procedure restores a THINK Enterprise database.  It has the ability to restore a database from both native MSSQL backups and Litespeed backups (provided
**	Litespeed is installed on the database server).  It can also restore databases under numerous scenarios such as multi-data/log databases, multi-file backups, diff and
**	transaction log backups, etc.  This sp is a sub stored procedure.  It is not meant to be called directly but through a user stored procedure.  The sp takes the name of
**	the database you wish to restore over, the backup file location, what recovery mode to leave the database in after restore, and an adhoc generated ID.  All parameters
**	are provided by the USP.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_restoreDatabase')
	DROP PROCEDURE [dbo].[sub_restoreDatabase];
GO

CREATE Procedure [dbo].[sub_restoreDatabase](
	@restoreDbName	nvarchar(128)		--Required:	The name of the database that the backup file will overwrite.
	,@backupFile	nvarchar(4000)		--Required:	The path and full name, including filename extension, to the backup file.  This is relative to the database server, not the calling server/workstation.
	,@recovery		varchar(1) = 'y'	--Optional:	The recovery mode to leave the database in after the restore: y = NO RECOVERY, n = WITH RECOVERY.
	,@tempTableId	int					--Required:	Unique ID that is appended to temporary tables.
	,@restoreDebug	nchar(1) = 'n'		--Optional: When set, returns additional debugging information to diagnose errors.
)
AS
SET NOCOUNT ON

DECLARE @physicalDataFile		sysname			--The physical data file that the logical data file will be restored to.
		,@physicalLogFile		sysname			--The physical log file that the logical log file will be restored to.
		,@logicalDataFile		sysname			--The logical data file from the backup that is moved to the physical data file specfied.
		,@logicalLogFile		sysname			--The logical log file from the backup that is moved to the physical log file specified.
		,@dataFilesCmd			nvarchar(1000)	--Part of the restore script to move the physical data/log files.
		,@dataFilesCmdOUT		nvarchar(1000)	--Used to dynamically create the @dataFilesCmd variable.
		,@logFilesCmd			nvarchar(1000)	--Part of the restore script to move the logical data/log files.
		,@logFilesCmdOUT		nvarchar(1000)	--Used to dynamically create the @logFilesCmd variable.
		,@defaultDataDirectory	nvarchar(200)	--The directory used for the .mdf/.ndf files, pulled from the meta database.
		,@defaultLogDirectory	nvarchar(200)	--The directory used for the .ldf files, pulled from the meta database.
		,@fileExtension			varchar(5)		--The physical data and log file extension.
		,@restoreStmt			nvarchar(max)	--The entire restore statement pieced together through other variables and strings.
		,@recoveryStmt			nvarchar(1000)	--Part of the restore script to specify what recovery mode the database should be put in after the restore.
		,@fileStmt				nvarchar(4000)	--Part of the restore script to correctly point to the actual backup file(s).
		,@backupFileExtension	varchar(5)		--The actual backup file(s) file extension.  For multi-file backups each file must have the same extension.
		,@hasMultipleFiles		tinyint			--Indicates if the script needs to account for a multi-file backup.
		,@count					int				--Counter for any arbitrary number of operations.
		,@fileIdCount			int				--Used to create multiple data/log files.
		,@eof					int				--The Length of the backup file string.
		,@tempFilename			nvarchar(2000)	--Used to find individual files in multi-file backups.
		,@semiColonPos			int				--Finds where semi-colons are located in multi-file backups.
		,@sql					nvarchar(4000)
		,@sqlOUT				nvarchar(max)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorState			int
		,@errorLine				int
		,@errorNumber			int;

BEGIN TRY

	IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE name = @restoreDbName) --Check if the database exists.
		RAISERROR('Database name does not exist', 16, 1);

	IF (SELECT [state] FROM sys.databases WHERE name = @restoreDbName) = 6 --Check if the database is offline and attempt to bring it back online.
	BEGIN TRY

		RAISERROR('The database is in an OFFLINE STATE, attempting to bring back online...', 10, 1) WITH NOWAIT;
		RAISERROR('status:', 10, 1) WITH NOWAIT;

		SET @sql = N'ALTER DATABASE ' + QUOTENAME(@restoreDbName) + ' SET ONLINE;';
		EXEC sp_executesql @sql;

		SET @printMessage = '	' + CAST((SELECT state FROM sys.databases WHERE name = @restoreDbName) AS nvarchar(2)) + ' - ' +
		(CASE (SELECT state FROM sys.databases WHERE name = @restoreDbName)
			WHEN 0
				THEN 'ONLINE'
			WHEN 1
				THEN 'RESTORING'
			WHEN 2
				THEN 'RECOVERING'
			WHEN 3
				THEN 'RECOVERY_PENDING'
			WHEN 4
				THEN 'SUSPECT'
			WHEN 5
				THEN 'EMERGENCY'
			WHEN 6
				THEN 'OFFLINE'
			ELSE NULL
		END);

		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END TRY
	BEGIN CATCH --If an error is encountered while trying to bring the database back online stop processing and quit.

		IF @@TRANCOUNT > 0
		ROLLBACK;

		SELECT @errorMessage = ERROR_MESSAGE()
				,@errorSeverity = ERROR_SEVERITY()
				,@errorNumber = ERROR_NUMBER();

		SET @printMessage = '	' + CAST((SELECT state FROM sys.databases WHERE name = @restoreDbName) AS nvarchar(2));
		SET @errorMessage = 'Unable to bring the database back online exiting procedure' + char(13) + char(10) + @errorMessage;

		RAISERROR(@printMessage, 10, 1) WITH NOWAIT; --Give a friendly message to the user.
		RAISERROR(@errorMessage, @errorSeverity, 1); --Give the actual system error to the user then quit.
	END CATCH;

	IF (SELECT [state] FROM sys.databases WHERE name = @restoreDbName) not in (0, 1) --Check if the database is available for restore.
		RAISERROR('The database is not in an "ONLINE" or "RESTORING" state.  Cannot restore database.', 16, 1) WITH LOG;
	
	SET @printMessage = 'Database exists/created, Restoring:' + char(13) + char(10);	
	RAISERROR (@printMessage, 10, 1) WITH NOWAIT;

	/*
	**	Initialize values and set the default directories from the meta database.  As each instance has its own meta database the directories will be instance specific.
	*/
	SET @defaultDataDirectory = (SELECT p_value FROM params WHERE p_key = 'DefaultDataDirectory');
	SET @defaultLogDirectory = (SELECT p_value FROM params WHERE p_key = 'DefaultLogDirectory');
	SET @count = 0;
	SET @dataFilesCmd = '';
	SET @logFilesCmd = '';

	IF (RIGHT(@defaultDataDirectory, 1) <> '\') --Append a backslash to the end of the defaultDataDirectory string if it does not already exist.
		SET @defaultDataDirectory = @defaultDataDirectory + '\';

	IF (RIGHT(@defaultLogDirectory, 1) <> '\') --Append a backslash to the end of the defaultLogDirectory string if it does not already exist.
		SET @defaultLogDirectory = @defaultLogDirectory + '\';

	IF RIGHT(@backupFile, 1) != ';' --Append a semi-colon to the backupFile string if it does not already exist.
		SET @backupFile = @backupFile + ';';

	SET @eof = LEN(@backupFile); --Must set @eof after checking if @backupFile ends with a semi-colon
	SET @backupFileExtension = SUBSTRING(@backupFile, LEN(@backupFile) - 4, 4); --Find the file extension of the backup file.  In multi-backup files this technically pulls the extension of the last file given, however all files must have the same extension in multi-file backups.

	/*
	**	We have to parse the filename out.  It is theoretically possible to restore up to 64 files.  Each filename is stored as a row in the below temp table and is used
	**	when building the restore statement.
	*/
	SET @sql = N'CREATE TABLE ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
				db_file_id			int	identity(1000,1)	not null
				,original_filename	nvarchar(4000)			not null
				,filename			nvarchar(2000)			not null
			);';
	EXEC sp_executesql @sql;

	WHILE @count < @eof
	BEGIN

		SET @semiColonPos = CHARINDEX(';', @backupFile, @count); --Find the position of the next semi-colon.  If this is the first iteration then this is the first semi-colon.  There is always at least one.
		SET @tempFilename = SUBSTRING(@backupFile, @count, (@semiColonPos - @count)); --Pull everything from the last position up to the next semi-colon.  If this is the first iteration than the last position is the beginning of the string.  This becomes the path + filename + filename extension.

		SET @sql = N'INSERT INTO ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'VALUES (''' + @backupFile + N''', ''' + @tempFilename + N''');';
		EXEC sp_executesql @sql;

		SET @count = @semiColonPos + 1;
	END;

	SET @sql = N'SET @hasMultipleFilesIN = (SELECT COUNT(*) FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N')' --Capture and store the number of files in @hasMultipleFiles.
	EXEC sp_executesql @sql, N'@hasMultipleFilesIN tinyint OUTPUT', @hasMultipleFiles OUTPUT;

	SET @sql = N'SET @backupFileIN = (SELECT filename FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N' WHERE db_file_id = (SELECT MIN(db_file_id) FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N'))' --Change @backupFile to the first file
	EXEC sp_executesql @sql, N'@backupFileIN nvarchar(4000) OUTPUT', @backupFile OUTPUT;

	SET @count = 1; --Reset @count so that it can be used for data and log file collection.

	/*
	**	These dynamic SQL statements run the RESTORE FILELISTONLY command (http://technet.microsoft.com/en-us/library/ms173778.aspx), however depending on the backup type
	**	(native or Litespeed) the result set is different.  This will check what type of backup file was provided based on the filename extension and create the proper
	**	temporary table accordingly.
	*/
	IF @backupFileExtension != '.sls' --For native backups.
	BEGIN

		SET @sql = N'CREATE TABLE ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
					logical_name			nvarchar(128)					not null
					,physical_name			nvarchar(256)					not null
					,type					char(1)							null
					,file_group_name		nvarchar(128)					null
					,size					numeric(20,0)					null
					,max_size				numeric(20,0)					null
					,file_id				int								null
					,create_lsn				numeric(25,0)					null
					,drop_lsn				numeric(25,0)					null
					,unique_id				uniqueidentifier				null
					,read_only_lsn			numeric(25,0)					null
					,read_write_lsn			numeric(25,0)					null
					,backup_size_in_bytes	bigint							null
					,source_block_size		int								null
					,file_group_id			int								null
					,log_group_guid			uniqueidentifier				null
					,differential_base_lsn	numeric(25)						null
					,differential_base_guid	uniqueidentifier				null
					,is_read_only			int								null
					,is_present				int								null
					,tde_thumbprint			nvarchar(128)					null
				);';
		EXEC (@sql)

		SET @sql = N'INSERT ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					'EXEC (''RESTORE FILELISTONLY FROM DISK = ''''' + @backupFile +N''''''')'
		EXEC (@sql)
	END
	ELSE --For Litespeed backups.
	BEGIN

		SET @sql = N'CREATE TABLE ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
					logical_name			nvarchar(128)					not null
					,physical_name			nvarchar(256)					not null
					,type					char(1)							null
					,file_group_name		nvarchar(128)					null 
					,size					numeric(20,0)					null
					,max_size				numeric(20,0)					null
					,file_id				int								null
					,backup_size_in_bytes	bigint							null
					,file_group_id			int								null
				);';
		EXEC (@sql)

		SET @sql = N'INSERT ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					'EXEC master.dbo.xp_restore_filelistonly @filename = ''' + @backupFile + ''''
		EXEC (@sql)
	END

	/*
	**	This transaction collects all the data files and creates the @dataFilesCmd variable.  It deals with data files only.  There are several scenarios that can be
	**	encountered.  The backup file may have multiple data files, the database being overwritten may have less data files than the backup file, or the backup file may
	**	only have one data file while the database has more.  All of these situations must be accounted for to properly structure the restore statement.
	*/
	BEGIN TRAN collectNativeDataFiles

		/*
		**	Count the number of data files in the backup.
		*/
		SET @sql = 'SET @sqlIN = ''''
					SET @sqlIN = (SELECT count(type) FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + N' WHERE type = ''D'');';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		/*
		**	The backup file has as many data rows or less then the database, but more than 1.  Since the database already has enough rows we just need to map which logical
		**	files go to which physical files.  There is no need to create additional data files.
		*/
		IF @sqlOUT <= (SELECT count(database_id) FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'ROWS') AND @sqlOUT > 1
		BEGIN
	
			/*
			**	Create a cursor to scroll through the already present data files in the database being overwritten (from the sys.master_files system table).  This is just
			**	done synchronously.
			*/
			DECLARE dbDataFiles CURSOR
				FOR SELECT name, physical_name
				FROM sys.master_files
				WHERE database_id = db_id(@restoreDbName)
					AND type_desc = 'ROWS';

			OPEN dbDataFiles;

			FETCH NEXT FROM dbDataFiles
				INTO @logicalDataFile, @physicalDataFile;

			WHILE @@FETCH_STATUS = 0
			BEGIN

				SET @dataFilesCmd = @dataFilesCmd + N',MOVE N''' + @logicalDataFile + N''' TO N''' + @physicalDataFile + N'''' + char(13) + char(10); --Create the actual restore syntax and map logical files to physical files.
			
				FETCH NEXT FROM dbDataFiles
					INTO @logicalDataFile, @physicalDataFile;
			END;

			CLOSE dbDataFiles;
			DEALLOCATE dbDataFiles;
		END
		/*
		**	The backup file has more data rows than the database.  In this situation we have to create the extra data files in the database in order to properly map all the
		**	data files from the backup file.  This section uses dynamic SQL as opposed to using a cursor.
		*/
		ELSE IF @sqlOUT > (SELECT count(database_id) FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'ROWS')
		BEGIN
	
			SET @dataFilesCmd = '';
			SET @fileIdCount = 1;

			WHILE @count <= @sqlOUT
			BEGIN	

				IF @count = 1 --Is this the first data file?
				BEGIN

					SET @fileExtension = '.mdf'; --The first data file gets a .mdf extension.  All other data files get a .ndf extension.

					/*
					**	This dynamic SQL statement creates the dataFilesCmd string with a new .mdf filename based on the database name being overwritten and places it in
					**	the defaultDataDirectory.
					*/
					SET @sql = N'SET @dataFilesCmdIN = ''''
								SELECT @dataFilesCmdIN = @dataFilesCmdIN + N'',MOVE N'''''' + logical_name + N'''''' TO N''''' + @defaultDataDirectory + @restoreDbName + @fileExtension + N''''''' + char(13) + char(10)
								FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
								N'WHERE type = ''D''
									AND file_group_name = ''PRIMARY''
									AND file_id = @fileIdCountIN;';
					EXEC sp_executesql @sql, N'@dataFilesCmdIN nvarchar(1000) OUTPUT, @fileIdCountIN int', @dataFilesCmdOUT OUTPUT, @fileIdCount;

					SET @dataFilesCmd =  @dataFilesCmd + @dataFilesCmdOUT; --Build @dataFilesCmd.
				END;
				ELSE
				BEGIN

					SET @fileExtension = '.ndf'; --The first data file gets a .mdf extension.  All other data files get a .ndf extension.

					/*
					**	This dynamic SQL statement creates the dataFilesCmd string with new .ndf filenames based on the database name being overwritten and places it in
					**	the defaultDataDirectory.  It appends a number to the database name followed by the filename extension (Ex: harmonywave1.ndf, harmonywave2.ndf, etc).
					*/
					SET @sql = N'SET @dataFilesCmdIN = ''''
								SELECT @dataFilesCmdIN = @dataFilesCmdIN + N'',MOVE N'''''' + logical_name + N'''''' TO N''''' + @defaultDataDirectory + @restoreDbName + CAST(@count AS varchar(2)) + @fileExtension + N''''''' + char(13) + char(10)
								FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
								N'WHERE type = ''D''
									AND file_id = @fileIdCountIN;';
					EXEC sp_executesql @sql, N'@dataFilesCmdIN nvarchar(1000) OUTPUT, @fileIdCountIN int', @dataFilesCmdOUT OUTPUT, @fileIdCount;

					SET @dataFilesCmd =  @dataFilesCmd + @dataFilesCmdOUT; --Build @dataFilesCmd.
				END;
				SET @sql = N'SET @fileIdCountIN = (SELECT TOP(1) file_id FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(16)) + ' WHERE file_id > @fileIdCountIN AND type = ''D'' ORDER BY file_id)'
				EXEC sp_executesql @sql, N'@fileIdCountIN int OUTPUT', @fileIdCount OUTPUT; --Increment @fileIdCount.
				SET @count = @count + 1;
			END
		END
		/*
		**	The backup file only has one data row.  As the database will always have at least one data file row it's not worth checking how many it actually has.  That being
		**	said, we must make sure that we only return one data row back to restore over (preferably the main .mdf file).
		*/
		ELSE IF @sqlOUT = 1
		BEGIN
	
			/*
			**	Pull the logical name from the backup file.
			*/
			SET @sql = N'SET @logicalDataFileIN = (SELECT logical_name FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(16)) + N' WHERE type = ''D'')'
			EXEC sp_executesql @sql, N'@logicalDataFileIN sysname OUTPUT', @logicalDataFile OUTPUT;

			SET @physicalDataFile = (SELECT TOP(1) physical_name FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'ROWS' ORDER BY file_id); --Pull the physical name from the database making sure to only return one row.  The row should be the .mdf file.

			SET @dataFilesCmd = ',MOVE N''' + @logicalDataFile + N''' TO N''' + @physicalDataFile + N''''; --Build @dataFilesCmd.
		END;
		ELSE --If all else fails, blame someone else!
		BEGIN
		
			SET @errorMessage = 'No data file match could be made from source disk at "' + @backupFile + '" with destination database of "' + @restoreDbName + '".  Manual restore and backup may be necessary.  You should probably contact Kevin about this, not me'
			RAISERROR(@errorMessage, 16, 1)
		END
	COMMIT TRAN;

	/*
	**	This transaction collects all the log files and creates the @logFilesCmd variable.  It deals with log files only.  There are several scenarios that can be
	**	encountered.  The backup file may have multiple log files, the database being overwritten may have less log files than the backup file, or the backup file may
	**	only have one log file while the database has more.  All of these situations must be accounted for to properly structure the restore statement.
	*/
	BEGIN TRAN collectNativeLogFiles

		/*
		**	Count the number of log files in the backup.
		*/
		SET @sql = 'SET @sqlIN = ''''
					SET @sqlIN = (SELECT count(type) FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + N' WHERE type = ''L'');';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		/*
		**	The backup file has as many log rows or less then the database, but more than 1.  Since the database already has enough rows we just need to map which logical
		**	files go to which physical files.  There is no need to create additional log files.
		*/
		IF @sqlOUT <= (SELECT count(database_id) FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'LOG') AND @sqlOUT > 1
		BEGIN
	
			/*
			**	Create a cursor to scroll through the already present log files in the database being overwritten (from the sys.master_files system table).  This is just
			**	done synchronously.
			*/
			DECLARE dbLogFiles CURSOR
				FOR SELECT name, physical_name
				FROM sys.master_files
				WHERE database_id = db_id(@restoreDbName)
					AND type_desc = 'LOG';

			OPEN dbLogFiles;

			FETCH NEXT FROM dbLogFiles
				INTO @logicalLogFile, @physicalLogFile;

			WHILE @@FETCH_STATUS = 0
			BEGIN

				SET @logFilesCmd = @logFilesCmd + N', MOVE N''' + @logicalLogFile + N''' TO N''' + @physicalLogFile + N'''' + char(13) + char(10); --Create the actual restore syntax and map logical files to physical files.

				FETCH NEXT FROM dbLogFiles
					INTO @logicalLogFile, @physicalLogFile;
			END;
		
			CLOSE dbLogFiles;
			DEALLOCATE dbLogFiles;
		END;
		/*
		**	The backup file has more log rows than the database.  In this situation we have to create the extra log files in the database in order to properly map all the
		**	log files from the backup file.  This section uses dynamic SQL as opposed to using a cursor.
		*/
		ELSE IF @sqlOUT > (SELECT count(database_id) FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'LOG')
		BEGIN

			SET @count = 1;
			SET @logFilesCmd = '';
			SET @fileExtension = '.ldf';
			SET @sql = N'SET @fileIdCountIN = (SELECT MIN(file_id) [file_id] FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(16)) + ' WHERE type = ''L'')'
			EXEC sp_executesql @sql, N'@fileIdCountIN int OUTPUT', @fileIdCount OUTPUT;

				WHILE @count <= @sqlOUT
				BEGIN
			
					/*
					**	This dynamic SQL statement creates the logFilesCmd string with new .ldf filenames based on the database name being overwritten and places it in the
					**	defaultLogDirectory.
					*/
					SET @sql = N'SET @logFilesCmdIN = ''''
								SELECT @logFilesCmdIN = @logFilesCmdIN + N'',MOVE N'''''' + logical_name + N'''''' TO N''''' + @defaultLogDirectory + @restoreDbName + N'_log' + CAST(@count AS varchar(20)) + @fileExtension + N''''''' + char(13) + char(10)
								FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
								N'WHERE type = ''L''
									AND file_id = @fileIdCountIN;';
					EXEC sp_executesql @sql, N'@logFilesCmdIN nvarchar(1000) OUTPUT, @fileIdCountIN int', @logFilesCmdOUT OUTPUT, @fileIdCount;

					SET @sql = N'SET @fileIdCountIN = (SELECT TOP(1) file_id FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(16)) + ' WHERE file_id > @fileIdCountIN AND type = ''L'' ORDER BY file_id)'
					EXEC sp_executesql @sql, N'@fileIdCountIN int OUTPUT', @fileIdCount OUTPUT; --Increment @fileIdCount.

					SET @logFilesCmd =  @logFilesCmd + @logFilesCmdOUT; --Build @logFilesCmd.
					SET @count = @count + 1;
				END;
		END
		/*
		**	The backup file only has one log row.  As the database will always have at least one log file row it's not worth checking how many it actually has.
		*/
		ELSE IF @sqlOUT = 1
		BEGIN

			/*
			**	Pull the logical name from the backup file.
			*/
			SET @sql = N'SET @logicalLogFileIN = (SELECT logical_name FROM ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(16)) + N' WHERE type = ''L'')'
			EXEC sp_executesql @sql, N'@logicalLogFileIN sysname OUTPUT', @logicalLogFile OUTPUT;

			SET @physicalLogFile = (SELECT physical_name FROM sys.master_files WHERE database_id = db_id(@restoreDbName) AND type_desc = 'LOG'); --Pull the physical name from the database.

			SET @logFilesCmd = ',MOVE N''' + @logicalLogFile + N''' TO N''' + @physicalLogFile + N''''; --Build @logFilesCmd.
		END;
		ELSE --If all else fails, blame someone else!
		BEGIN

			SET @errorMessage = 'No log file match could be made from source disk at "' + @backupFile + '" with destination database of "' + @restoreDbName + '".  Manual restore and backup may be necessary.  You should probably contact Kevin about this, not me'
			RAISERROR(@errorMessage, 16, 1)
		END
	COMMIT TRAN;

	SET @printMessage =  char(13) + char(10) + SUBSTRING(@dataFilesCmd,2,LEN(@dataFilesCmd)) + char(13) + char(10) + SUBSTRING(@logFilesCmd,2,LEN(@logFilesCmd)) + char(13) + char(10);
	RAISERROR(@printMessage, 10 ,1) WITH NOWAIT;

	IF (SELECT state FROM sys.databases WHERE name = @restoreDbName) = 0
	BEGIN

		SET @sql = 'ALTER DATABASE '+ QUOTENAME(@restoreDbName) + ' SET OFFLINE WITH ROLLBACK IMMEDIATE;'; --Make the database unavailable.
		EXEC sp_executesql @sql;
	END;

	/*
	**	Build the entire restore statement.  First start by building the file statement which accounts for a multi-file backup.  Then the recovery statement is created and
	**	finally the restore statement is built based off all the other statements.  This first statement creates the "FROM DISK =" portion of the restore statement.  At
	**	this point we are just creating the first disk to restore from.  For multi-file backups other files will be pulled in later.
	*/
	SET @sql = CASE
		WHEN @backupFileExtension != '.sls' --For native backups.
			THEN N'SET @sqlIN = ''''

				SELECT TOP(1) @sqlIN = @sqlIN + N''FROM DISK = N'''''' + filename + N''''''''
				FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20))
		ELSE N'SET @sqlIN = ''''

			SELECT TOP(1) @sqlIN = @sqlIN + N'',@filename = '''''' + filename + N''''''''
			FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) --For Litespeed backups.
	END;

	EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
	SET @fileStmt = @sqlOUT;

	/*
	**	For multi-file backups continue creating the "FROM DISK =" portion of the restore statement.
	*/
	IF @hasMultipleFiles > 1
	BEGIN

		SET @sql = CASE
			WHEN @backupFileExtension != '.sls'
				THEN N'SET @sqlIN = ''''

					SELECT @sqlIN = @sqlIN + N'',DISK = N'''''' + filename + N'''''''' + char(13) + char(10)
					FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N'
					WHERE db_file_id != (SELECT MIN(db_file_id) FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N')'

		ELSE N'SET @sqlIN = ''''
							
			SELECT @sqlIN = @sqlIN + N'',@filename = '''''' + filename + N''''''''
			FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N'
			WHERE db_file_id != (SELECT MIN(db_file_id) FROM ##database_files_principals_' + CAST(@tempTableId AS varchar(20)) + N')'
		END;

		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @fileStmt = @fileStmt + @sqlOUT;
	END;

	/*
	**	Set the recovery mode based on what was provided by the user.
	*/
	SET @recoveryStmt = CASE
		WHEN @recovery = 'y'
			THEN N'RECOVERY'
		ELSE N'NORECOVERY'
	END;

	/*
	**	This is it, finally create the actual restore statement.  All of the complex parts have already been created as part of other variables and strings.  Most of the 
	**	static text here is trival or doesn't ever change between restores.  It should be noted that Litespeed restores are performed by an extended stored procedure
	**	provided by Litespeed.  The sp must be present on the server (a.k.a. Litespeed must be installed) to restore Litespeed backups.
	*/
	SET @restoreStmt = CASE
		WHEN @backupFileExtension != '.sls'
			THEN N'USE [master]' + char(13) + char(10) +
				N'RESTORE DATABASE ' + QUOTENAME(@restoreDbName) + char(13) + char(10) +
				@fileStmt + N' WITH FILE = 1' + char(13) + char(10) +
				@dataFilesCmd + @logFilesCmd +
				N',' + @recoveryStmt +
				N',NOUNLOAD,REPLACE,STATS = 5'
		ELSE N'master.dbo.xp_restore_database @database = ''' + @restoreDbName + N'''' +
			@fileStmt +
			N',@with = N''REPLACE''
			,@with = N''STATS = 5''
			,@with = @dataFilesCmdIN' +
			N',@with = @logFilesCmdIN' +
			N',@with = ''' + @recoveryStmt + N'''' +
			N',@affinity = 0
			,@logging = 0'
	END;

	EXEC sp_executesql @restoreStmt, N'@dataFilesCmdIN nvarchar(1000), @logFilesCmdIN nvarchar(1000)', @dataFilesCmd, @logFilesCmd; --Actually runs the restore.
	
	/*
	**	After successfully restoring a database with "NORECOVERY" The rest of the sp should not be executed.  Bank def changes, cc cleaning, audit logging, etc, will be
	**	handled by the sp that sets the database with RECOVERY.  Even if a subsequent sp is not called the database will remain in a "RESTORING" state, so will be
	**	unaccessible.  Users do not have rights to change the state of a database outside of calling another sp.
	*/
	IF @recovery = 'n'
		RETURN;

	SET @sql = N'ALTER DATABASE ' + QUOTENAME(@restoreDbName) + N'SET COMPATIBILITY_LEVEL = 100' --Set the compatibility level of the restored database to MSSQL 2008.
	EXEC (@sql);

	SET @printMessage =  char(13) + char(10) + 'Hold your horses... Just because the restore completed, doesn''t mean we''re done yet...' + char(13) + char(10) + char(13) + char(10);
	RAISERROR(@printMessage, 10 ,1) WITH NOWAIT;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @restoreDebug = 'y'
	BEGIN
		
		SET @printMessage = 'An error occured in the sub_restoreDatabase sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = N'IF object_id (''tempdb..##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##restore_filelistonly_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC (@sql);

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;