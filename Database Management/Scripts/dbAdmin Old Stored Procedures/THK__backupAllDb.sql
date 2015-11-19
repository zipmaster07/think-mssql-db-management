USE [dbAdmin]
GO

/****** Object:  StoredProcedure [dbo].[backup_all_databases]    Script Date: 10/2/2012 1:28:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[backup_all_databases](	
	@ForceFull	CHAR(1)	= 'n'	-- valid values: 'n', 'y'
	,@debug		CHAR(1) = 'n'	-- valid values: 'n', 'y'
)
AS

SET NOCOUNT ON;

DECLARE @DatabaseName	SYSNAME
		,@msg			VARCHAR(MAX)
		,@BkupType		NVARCHAR(4)
		,@result		INTEGER
		,@ReturnValue	INTEGER
		,@DBlist		CURSOR
		,@JobStartTime	DATETIME	
		,@BackupControl	VARCHAR(7);


SET @ReturnValue = 0;
SET @JobStartTime = GETDATE();
SET @ForceFull = LOWER(@ForceFull);
SET @debug = LOWER(@debug);

IF @ForceFull NOT IN ('n', 'y')
BEGIN
	RAISERROR( 'Invalid parameter provided.  Optional values for @ForceFull are ''y'', ''n''.', 16, 1 ) WITH LOG;
	RETURN 1;
END;

-- Check backup definition formating
IF NOT EXISTS(
	SELECT *
	FROM dbo.params
	WHERE p_key = 'DailyBackupControl' 
		AND LEN(LTRIM(RTRIM(p_value))) = 7 -- must be seven characters long
		AND p_value NOT LIKE '%[^dfn]%' -- can only contain the characters d, f, and n
		AND p_value LIKE '%f%' -- Must specify a full backup on at least one day of the week
	) 
BEGIN
	RAISERROR( 'DailyBackupControl improperly formatted; check the dbo.params table', 16, 1 ) WITH LOG
	RETURN 1;
END;

-- Set Sunday as the 1st day of the week (default for US English language).
SET DATEFIRST 7;

SELECT @BackupControl = LOWER(SUBSTRING( p_value, DATEPART( dw, GETDATE() ), 1 ))
FROM dbo.params 
WHERE p_key = 'DailyBackupControl';

IF @debug = 'y'
	PRINT 'Backup Control Parameter: ' + @BackupControl;

CREATE TABLE #DBlist(
	DBname			VARCHAR(200)
	,BackupType		VARCHAR(4)
	,ErrorMessage	VARCHAR(MAX)
	);

-- INSERT databases, daily backup type, and error messages	
INSERT INTO #DBlist(DBname, BackupType, ErrorMessage)
SELECT sd.name,
	CASE @BackupControl
		WHEN 'f' THEN N'Full'
		WHEN 'd' THEN N'Diff'
		ELSE		  N'None'
	END,
	CASE	
		WHEN sd.name IN('master', 'model', 'msdb') -- never prevent system databases from being backed up
			THEN NULL		
		WHEN sd.is_in_standby = 1 
			THEN 'Database is in STANDBY mode and cannot be backed up.' 
		WHEN sd.state_desc <> 'ONLINE' 
			THEN 'Database is NOT ONLINE and cannot be backed up.' 
		WHEN me.DBName IS NOT NULL AND @ForceFull <> 'y'
			THEN 'Database has been listed for exclusion from daily backups. Query dbo.MaintExceptions'
		WHEN @BackupControl = 'n'
			THEN 'Daily Backup Control specified no backup today.'
		ELSE NULL 
	END  
FROM master.sys.databases sd
	LEFT OUTER JOIN dbo.MaintExceptions me ON sd.name = me.DBName
		AND me.p_key = 'skip backup'
		AND me.p_value = 'yes'
WHERE sd.name <> 'tempdb'
	AND sd.source_database_id IS NULL; -- do not include snapshots

--Use Exception DailyBackupControl, if applicable
UPDATE dbl
SET dbl.BackupType =
		CASE LOWER(SUBSTRING( me.p_value, DATEPART( dw, GETDATE() ), 1 ))
			WHEN 'f' THEN N'Full'
			WHEN 'd' THEN N'Diff'
			ELSE		  N'None'
		END,
	dbl.ErrorMessage = 
		CASE LOWER(SUBSTRING( me.p_value, DATEPART( dw, GETDATE() ), 1 ))
			WHEN 'f' THEN NULL
			WHEN 'd' THEN NULL
			ELSE		  N'Exception specified no backup today.'
		END
FROM #DBlist dbl
	LEFT OUTER JOIN MaintExceptions me ON dbl.DBName = me.DBName
WHERE me.p_key = 'DailyBackupControl'

-- Full backup if no full in last 7 days, or if there is no backup
UPDATE #DBlist
SET BackupType = 'Full'
WHERE DBname NOT IN (
	SELECT  database_name
	FROM    backup_history
	WHERE   [type] = 'f' AND backup_status = 's'
	GROUP BY database_name		
	HAVING DATEDIFF(d, MAX(backup_start_date), @JobStartTime) < 7
);

-- Full backup if a restore has occurred since last full.
UPDATE #DBlist
SET BackupType = 'Full'
WHERE DBname IN (
	SELECT bh.database_name
	FROM backup_history bh
		INNER JOIN (SELECT MAX(restore_date) AS restore_date, destination_database_name
					FROM [msdb].[dbo].[restorehistory]
					GROUP By destination_database_name) rh
			ON bh.database_name = rh.destination_database_name
	WHERE rh.restore_date > bh.backup_start_date);

-- Diff backup if already a full backup in less than 18 hours
UPDATE #DBlist
SET BackupType = 'Diff'
WHERE DBname IN (
	SELECT  database_name
	FROM    backup_history
	WHERE   [type] = 'f' AND backup_status = 's' 
	GROUP BY database_name		
	HAVING DATEDIFF(hh, MAX(backup_start_date), GETDATE()) < 18
);

-- Full backup of system DBs daily	
UPDATE #DBlist
SET BackupType = 'Full'
WHERE DBname IN ('master', 'model', 'msdb');

-- Force full if force parameter is sent.
IF @ForceFull = 'y'
	UPDATE #DBlist
	SET BackupType = 'Full';
	
IF @debug = 'y'
BEGIN
	PRINT 'DBlist Table:';
	SELECT * FROM #DBlist;
END;

-- Set up cursor to loop through each database and take the appropriate backup
SET @DBlist = CURSOR FAST_FORWARD FOR 
SELECT DBname, BackupType, ErrorMessage
FROM #DBlist;

OPEN @DBlist;

FETCH NEXT FROM @DBlist INTO @DatabaseName, @BkupType, @msg;
WHILE @@FETCH_STATUS = 0 
BEGIN
	IF (@msg IS NULL) --If a message is present, skip backup and log exception
	BEGIN
		PRINT 'Backup database: ' + @DatabaseName;
		
		IF @debug = 'y'
		BEGIN
			PRINT 'DBA_Admin.dbo.backup_database @dbname = '+@DatabaseName+', @backuptype = '+@BkupType;
			SET @result = 0;
		END
		
		EXEC @result = DBA_Admin.dbo.backup_database @dbname = @DatabaseName, @backuptype = @BkupType;
		
		IF @result <> 0 
		BEGIN
			RAISERROR( 'Error occurred within execution of Backup_Database procedure.', 16, 1 ) WITH LOG;
			SET @ReturnValue = 1;
		END;

	END 
	ELSE BEGIN -- log the backup exception
		IF @debug = 'y'
			PRINT 'DBname: ' + @DatabaseName + ' Backup Type: ' + @BkupType + ' Message: ' + @msg;
					
		INSERT INTO dbo.backup_history(
			database_name
			,backup_start_date
			,[type]
			,backup_status
			,backup_errcode
			,[error_message]
		)
		VALUES(
			@DatabaseName
			,GETDATE()
			,LOWER(LEFT(@BkupType, 1))
			,'s'
			,1
			,@msg
		)
	END;
	
	FETCH NEXT FROM @DBlist INTO @DatabaseName, @BkupType, @msg;
END;

CLOSE @DBlist;
DEALLOCATE @DBlist;
DROP TABLE #DBlist;

-- if any errors occurred, we want the job to show failure
IF @ReturnValue <> 0
	raiserror('One or more backups failed.  See database-level errors for details.', 16, 1) with log;

-- return 0 for success; 1 for failure
RETURN @ReturnValue;

GO


