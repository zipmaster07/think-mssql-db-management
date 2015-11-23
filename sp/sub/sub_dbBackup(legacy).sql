USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_backupDatabase')
	DROP PROCEDURE [dbo].[sub_backupDatabase];
GO

CREATE PROCEDURE [dbo].[sub_backupDatabase](
	@backupDbName		nvarchar(128)
	,@backupType		nvarchar(4)
	,@method			varchar(16)
	,@client			nvarchar(128)
	,@user				nvarchar(64)
	,@backupThkVersion	nvarchar(32)
	,@backupDbType		char(1)
	,@cleanStatus		char(5)
	,@probNbr			nvarchar(16) = null
	,@backupRetention	int
)
AS

DECLARE @fileext			nvarchar(16)
		,@filepath			nvarchar(1024)
		,@timestamp			varchar(16)
		,@datestamp			varchar(16)
		,@servername		nvarchar(256)
		,@lsbackuptype		varchar(16)
		,@backup_id			int
		,@counter			tinyint
		,@count_msg			nvarchar(32)
		,@backup_stmt		nvarchar(2000)
		,@backup_file_stmt	nvarchar(4000)
		,@backupCommand		nvarchar(4000)
		,@stmt				nvarchar(4000)
		,@threshold			decimal(18,1)
		,@rows				int
		,@result			int
		,@errorNbr			int
		,@errorMsg			varchar(max)
		,@backupPath		nvarchar(1024)
		,@file_count		tinyint
		,@debug				char(1) --Legacy, need to remove
		,@printMessage		nvarchar(4000)
		,@dept				nvarchar(64)
		,@auditBackupType	char(1);

SET @debug = 'n';

SET NOCOUNT ON;

BEGIN	

	SET @backupType = LOWER(@backupType);
	SET @method = LOWER(@method);
	SET @debug = LOWER(@debug);
	SET @backupDbType = UPPER(@backupDbType);
	SET @cleanStatus = LOWER(@cleanStatus);
	SET @dept = (SELECT dept_name FROM user_mappings WHERE user_name = @user)

	IF @probNbr is null
		SET @probNbr = '00000';
	
	RAISERROR('Starting database backup:', 10, 1) WITH NOWAIT;

	/*
	**	Get our backup path
	*/
	SET @backupPath = COALESCE(@backupPath, (SELECT p_value FROM dbo.params WHERE p_key = 'DefaultBackupDirectory'));

	IF @backupPath is null
	   RAISERROR('The @backupPath parameter has not been specified and the DefaultBackupDirectory parameter has not been found in dbAdmin.dbo.params.', 16, 1) WITH LOG;

	SET @printMessage = '	Using backup path at: ' + @backupPath;
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF (RIGHT(@backupPath, 1) <> '\')
		SET @backupPath = @backupPath + '\';

	/*
	**	Set the backup method
	*/
	IF @backupDbName in ('master', 'model', 'msdb')
		SET @method = 'native';

	SET @servername = REPLACE(CAST(SERVERPROPERTY('servername') AS SYSNAME), '\', '$');
	SET @timestamp = LEFT(REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', ''), 4) + 'MST';
	SET @datestamp = CONVERT(VARCHAR, GETDATE(), 112);

	/*
	**	Determine the number of files to use for the backup.
	*/
	SET @printMessage = '	Determining number of files to use for ' + @backupDbName;
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @threshold = COALESCE( ( SELECT p_value FROM dbo.params WHERE p_key = 'FileCountThreshold' ), 100 );

	CREATE TABLE #spaceused(DataGB INT, LogGB INT);
	CREATE TABLE #XpResult(xpresult INT, err INT);

	SET @stmt = N'USE ' + QUOTENAME( @backupDbName ) + N';
				SELECT
				--   db_name() AS DBName, 
				   CEILING( SUM( CASE FILEPROPERTY( name, ''IsLogFile'') WHEN 1 THEN 0 ELSE FILEPROPERTY( name, ''SpaceUsed'' ) END ) / ( 131072.0 ) ) AS [Data_UsedGB], 
				   CEILING( SUM( CASE FILEPROPERTY( name, ''IsLogFile'') WHEN 1 THEN FILEPROPERTY( name, ''SpaceUsed'' ) ELSE 0 END ) / ( 131072.0 ) ) AS [Log_UsedGB]
				FROM dbo.sysfiles'

	INSERT #spaceused
	EXECUTE(@stmt);

	SELECT @file_count = COALESCE(@file_count,
								  CASE WHEN @backupType = N'full' THEN CEILING(dataGB/@threshold)
									   WHEN @backupType = N'log' THEN CEILING(logGB/@threshold)
									   ELSE 1
								  END, 1)
	FROM #spaceused

	/*
	**	SQL Server only handles a maximum of 64 files.
	*/
	If @file_count > 64 BEGIN
		SET @file_count = 64;
	END;

	IF @debug = 'y' BEGIN
		SELECT @method AS 'Method';
	END;

	IF @method = 'native' 
		SET @fileext  = N'.bak';
	ELSE
		SET @fileext  = N'.sls';

	/*
	**	Create a record in the backup_history table.
	*/
	BEGIN TRAN

		SET @printMessage = '	Recording initial backup information and statistics'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		SET @auditBackupType = SUBSTRING(@backupType, 1, 1);
		EXEC dbo.sub_auditTrail @auditDbName = @backupDbName, @operationType = 1, @backupType = @auditBackupType

		/*
		**	For each file to create, build backup file name and backup statements.
		*/
		SET @counter = 1;
		WHILE @counter <= @file_count
		BEGIN

			IF @file_count = 1 
				SET @count_msg = N'';
			ELSE
				SET @count_msg = N'_' + cast(@counter AS NVARCHAR(3)) + N'_of_' + CAST(@file_count AS NVARCHAR(3) );

			SET @filepath = @backupPath + LOWER(@client) + '_' + LOWER(@user) + '_' + @datestamp + '_' + @timestamp + '_' + @backupThkVersion + '_' + UPPER(@backupDbType) + '_' + LOWER(@cleanStatus) + '_' + @probNbr + @count_msg + @fileext;

			IF @counter = 1 
			  SET @backup_file_stmt =
				CASE
					WHEN @method='native'
						THEN 'TO DISK = ''' + @filepath + ''''
					WHEN @method='litespeed'
						THEN ',@filename = ''' + @filepath + ''''
				END
			ELSE
				SET @backup_file_stmt = @backup_file_stmt + CHAR(10) + 
											CASE
												WHEN @method='native'
													THEN '  ,DISK = ''' + @filepath + ''''
												WHEN @method='litespeed'
													THEN ',@filename = ''' + @filepath + ''''
											END;
			
			SET @printMessage = '	Recording backup file information for backup file number: ' + CAST(@counter AS varchar(16))
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

			EXEC dbo.sub_auditTrail @auditDbName = @backupDbName, @operationFile = @filepath, @operationType = 3, @backupCounter = @counter;
	   
			--Add check on rowcount; error if no rows are inserted
			SELECT @errorNbr = @@error;
				
			IF @errorNbr <> 0
				GOTO history_tran;

			IF @counter = 255
				BREAK;

			SET @counter = @counter + 1;
		END;

	history_tran:
	IF @errorNbr = 0 
	   COMMIT TRANSACTION;
	ELSE
	BEGIN
	   ROLLBACK TRANSACTION;
	   RETURN -1;
	END;

	SET @printMessage = '	Configuring backup statement';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF @method = 'native' 
	BEGIN
		SET @backup_stmt =
			CASE
				WHEN @backupType = N'full'
					THEN 'BACKUP DATABASE ' + QUOTENAME(@backupDbName)
				WHEN @backupType = N'diff'
					THEN 'BACKUP DATABASE ' + QUOTENAME(@backupDbName)
				WHEN @backupType = N'log'
					THEN 'BACKUP LOG ' + QUOTENAME(@backupDbName)
			END;
		SET @backup_file_stmt = @backup_file_stmt + CHAR(10) +
									CASE
										WHEN @backupType = N'diff'
											THEN 'WITH DIFFERENTIAL, CHECKSUM'
										ELSE 'WITH CHECKSUM, STATS = 5'
									END;
	END;

	-----------------------------------
	-- configure litespeed statement --
	-----------------------------------
	IF @method = 'litespeed' 
	BEGIN
		IF (@backupType <> N'log')
			SET @backup_stmt = 'declare @result int;exec @result = [master].[dbo].[xp_backup_database]' + CHAR(10) +
								' @database = ' + QUOTENAME(@backupDbName);             
		ELSE
			SET @backup_stmt = 'declare @result int;exec @result = [master].[dbo].[xp_backup_log]' + CHAR(10) +
								' @database = ' + QUOTENAME(@backupDbName);
	
		SET @backup_file_stmt = @backup_file_stmt + CHAR( 10 ) + 
									CASE
										WHEN @backupType = N'diff'
											THEN ',@with = ''CHECKSUM, DIFFERENTIAL''' 
										ELSE ',@with = ''CHECKSUM'''
									END + CHAR(10) + ';' + CHAR(10) + 'INSERT INTO #XpResult VALUES( @result, @@error )';
	END;

	/*
	**	Form  backup command and execute.
	*/
	SET @backupCommand = @backup_stmt + @backup_file_stmt;

	SET @printMessage = '	Backing up the "' + @backupDbName + '" database' + char(13) + char(10) + char(13) + char(10);
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @errorNbr = 0;
	SET @errorMsg = 0;
	BEGIN TRY
	   EXEC(@backupCommand);
	END TRY
	BEGIN CATCH
		SET @errorNbr = ERROR_NUMBER();
		SET @errorMsg =	'Error: ' + CONVERT( VARCHAR( 50 ), ERROR_NUMBER() ) + CHAR( 13 ) +
						'Description:  ' + ERROR_MESSAGE() + CHAR( 13 ) +
						'Severity: ' + CONVERT( VARCHAR( 5 ), ERROR_SEVERITY() ) + CHAR( 13 ) +
						'State: ' + CONVERT( VARCHAR( 5 ), ERROR_STATE() ) + CHAR( 13 ) +
						'Procedure: ' + COALESCE( ERROR_PROCEDURE(), '-') + CHAR( 13 ) +
						'Line: ' + CONVERT( VARCHAR( 5 ), ERROR_LINE() )  + CHAR( 13 );
	END CATCH;


	SET @printMessage = '';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SELECT @result = COALESCE(xpresult, 0) + COALESCE(err, 0) FROM #XpResult;
	RETURN COALESCE(@result, @errorNbr, 0);
END
GO


