USE [dbAdmin]
GO

/****** Object:  StoredProcedure [dbo].[backup_all_tlogs]    Script Date: 10/2/2012 1:31:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[backup_all_tlogs](	
	@debug		CHAR(1) = 'n'	-- valid values: 'n', 'y'
)
AS

SET NOCOUNT ON;

DECLARE @DatabaseName	SYSNAME
		,@result		INTEGER
		,@ReturnValue	INTEGER


SET @ReturnValue = 0;
SET @debug = LOWER(@debug);

SET @DatabaseName =(SELECT TOP 1 name
					FROM master.sys.databases
					WHERE recovery_model_desc <> 'SIMPLE'
						AND is_in_standby = 0
						AND state_desc = 'ONLINE'
						AND source_database_id IS NULL -- omit snapshots
						AND name NOT IN ('tempdb', 'model')
					ORDER BY name ASC
					);
						
WHILE @DatabaseName IS NOT NULL 
BEGIN
	PRINT 'Backup transaction log for database: ' + @DatabaseName;
	
	EXEC @result = DBA_Admin.dbo.backup_database @dbname = @DatabaseName, @backuptype = 'log';
	
	IF @result <> 0 
	BEGIN
		RAISERROR( 'Error occurred within execution of Backup_Database procedure.', 16, 1 ) WITH LOG;
		SET @ReturnValue = 1;
	END;
	
	SET @DatabaseName =(SELECT TOP 1 name
						FROM master.sys.databases
						WHERE recovery_model_desc <> 'SIMPLE'
							AND is_in_standby = 0
							AND state_desc = 'ONLINE'
							AND source_database_id IS NULL -- omit snapshots
							AND name NOT IN ('tempdb', 'model')
							AND name > @DatabaseName
						ORDER BY name ASC
						);
END;


-- if any errors occurred, we want the job to show failure
IF @ReturnValue <> 0
	raiserror('One or more transaction log backups failed.  See database-level errors for details.', 16, 1) with log;

-- return 0 for success; 1 for failure
RETURN @ReturnValue;

GO


