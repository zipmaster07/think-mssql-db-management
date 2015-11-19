USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_THKBackupDB')
	DROP PROCEDURE [dbo].[usp_THKBackupDB];
GO

CREATE PROCEDURE [dbo].[usp_THKBackupDB](
	@setDbName				nvarchar(128)				--Required:		Name of the database that is being backed up
	,@setClient				nvarchar(128)				--Required:		Name of the client to whose database is being backed up
	,@setBackupType			nvarchar(4) = 'full'		--Optional:		How will the database be backed up: Full, Diff, or Log
	,@setBackupMethod		nvarchar(16) = 'litespeed'	--Optional:		How will the backup be performed: Native or Litespeed
	,@setDbType				char(1) = null				--Optional:		Type of database the client provided (Test, Live, Staging, Conversion, QA, Dev, Other)
	,@setProbNbr			nvarchar(16) = null			--Optional:		Used to associate a specific problem number to a backup
	,@setBackupRetention	int = null					--Optional:		How long the backup will/should be kept before being deleted
	,@userOverride			nvarchar(32) = null			--Undocumented:	Used to set the user of who the backup is associated with, otherwise the user calling the sp is used.
	,@cleanStatusOverride	char(5) = 'clean'			--Undocumented:	Indicates if the database is clean or dirty.  the sp assumes the database is clean unless otherwise explicity set to dirty
) WITH EXECUTE AS OWNER
AS

DECLARE @callingDept		nvarchar(256)
		,@thkVersion		nvarchar(32)
		,@backupStartTime	datetime
		,@backupStopTime	datetime
		,@sql				nvarchar(4000)
		,@printMessage		nvarchar(4000)
		,@errorMsg			nvarchar(4000)
		,@errorSeverity		int
		,@errorNbr			int;

BEGIN TRY
	
	/*
	**	Step 1: Check for parameter integrity
	*/
	BEGIN

		IF @setDbType not in (NULL,'T','L','S','C','Q','D','O')
			RAISERROR('Value for parameter @setDbType must be "T", "L", "S", "C", "Q", "D", or "O".', 16, 1) WITH LOG;

		IF @cleanStatusOverride not in (NULL, 'clean', 'dirty')
			RAISERROR('Value for parameter @cleanStatusOverride must be "clean" or "dirty".', 16, 1) WITH LOG;

		IF @setBackupType not in ('full', 'diff', 'log')
			RAISERROR('Value for parameter @setBackuptype must be "full", "diff", or "log".', 16, 1) WITH LOG;

		IF @setBackupMethod not in ('native', 'litespeed')
			RAISERROR('Value for parameter @setBackupMethod must be "native" or "litespeed".', 16, 1)

		--IF @setProbNbr is not null AND @setProbNbr < 630
			--RAISERROR('You did not enter a valid problem number.. Try harder', 16, 1) WITH LOG;

		IF @setBackupRetention > 999
		BEGIN

			RAISERROR('Yeah nice try, we aren''t keeping the backup that long, resetting @setBackupRetention parameter to max value', 10, 1) WITH NOWAIT;
			SET @setBackupRetention = 999
		END;
	END;

	/*
	**	Step 2: Gather parameter values
	*/
	BEGIN

		EXECUTE AS CALLER
			SET @userOverride = COALESCE(@userOverride, (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER)); --Pulls the user actually calling the sp
		REVERT;

		SET @sql = N'SET @cleanThkVersionIN = (SELECT cur_vers FROM ' + @setDbName + N'.dbo.config)';
		EXEC sp_executesql @sql, N'@cleanThkVersionIN nvarchar(32) OUTPUT', @thkVersion OUTPUT;

		SET @setBackupRetention = COALESCE(@setBackupRetention, (SELECT CAST(p_value AS int) FROM params WHERE p_key = 'FullBackupRetention'))
		SET @setBackupMethod = COALESCE(@setBackupMethod, (SELECT p_value FROM dbAdmin.dbo.params WHERE p_key = 'DefaultBackupMethod'), 'native');
		SET @setDbType = COALESCE(@setDbType, 'T');
	END;

	/*
	**	Step 3: Run backup sub sp
	*/
	BEGIN

		SET @backupStartTime = GETDATE()
		EXEC dbo.sub_backupDatabase @backupDbName = @setDbName, @backupType = @setBackupType, @method = @setBackupMethod, @client = @setClient, @user = @userOverride, @backupThkVersion = @thkVersion, @backupDbType = @setDbType, @cleanStatus = @cleanStatusOverride, @probNbr = @setProbNbr, @backupRetention = @setBackupRetention;
		SET @backupStopTime = GETDATE()
	END;

	/*
	**	Step 4: Update backup_history table
	*/
	BEGIN

		EXECUTE AS CALLER
			SET @userOverride = (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER); --Pull the actual user who called the sp regardless of what the @userOverride parameter was set to.  This is used for recording purposes only
		REVERT;

		SET @setBackupType = SUBSTRING(@setBackupType, 1, 1)

		EXEC dbo.sub_auditTrail @auditDbName = @setDbName, @operationType = 1, @backupType = @setBackupType, @auditCleanStatus = @cleanStatusOverride, @auditUserName = @userOverride, @auditThkVersion = @thkVersion, @auditProbNbr = @setProbNbr, @auditClient = @setClient, @auditRetention = @setBackupRetention, @operationStart = @backupStartTime, @operationStop = @backupStopTime, @errorNbr = @errorNbr
	END;

	SET @printMessage = char(13) + char(10) + 'Congratulations!!! The backup has completed successfully'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK

	SELECT @errorMsg = ERROR_MESSAGE()
		,@errorSeverity = ERROR_SEVERITY()
		,@errorNbr = ERROR_NUMBER();

	RAISERROR(@errorMsg, @errorSeverity, 1);
	RETURN -1;
END CATCH
GO

GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\akennedy]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\cjenkins]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\jschaeffer]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\lzibetti]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\mheil]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\rwalgren]
GRANT EXECUTE ON [dbo].[usp_THKBackupDB] TO [MPLS\shokanson]
GO