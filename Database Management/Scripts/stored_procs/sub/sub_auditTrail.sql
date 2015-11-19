/*
**	This stored procedure records audit information for other sp's.  This sp is a sub stored procedure.  It is not meant to be called directly but through a user stored
**	procedure.  What is records depends on how it is called.  It has a modularity mechanism in place so that additional recording features can be added.  In its current
**	state is is capable of recording restore and backup information.  This information includes when the backup/restore was performed, files that were created or used, who
**	backed up/restored the database, how long backup files are meant to be kept, etc.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_auditTrail')
	DROP PROCEDURE [dbo].[sub_auditTrail];
GO

CREATE PROCEDURE [dbo].[sub_auditTrail](
	@auditDbName		nvarchar(128)			--Required:	Name of the database that was restored/backed up.
	,@operationFile		nvarchar(4000) = null	--Optional:	Name of the backup file that was generated in the backup sp or used to restore the database.
	,@operationType		tinyint					--Required:	The type of operation being audited: 0 = Restore, 1 = Inital backup entry, 2 = Full backup update, 3 = Record specific backup filename info.
	,@backupType		char(1) = null			--Optional:	The type of backup that was taken: f = Full, d = Diff, l = Log.
	,@backupCounter		tinyint = null			--Optional:	The backup number in multi-file backups.
	,@auditCleanStatus	char(5) = null			--Optional:	Indicates if the database/backup file has been sanatized of PCI sensitive data.
	,@auditUserName		sysname = null			--Optional:	Name of the user that restored/backed up the database.
	,@auditThkVersion	nvarchar(16) = null		--Optional:	The version of the database being restored or backed up.
	,@auditProbNbr		nvarchar(16) = null		--Optional:	The problem number associated to the restore or backup.
	,@auditClient		nvarchar(64) = null		--Optional:	The client associated with the restore or backup.
	,@auditRetention	int = null				--Optional:	How long a backup file should be kept.
	,@operationStart	datetime = null			--Optional:	The time the restore sub sp was started.
	,@operationStop		datetime = null			--Optional:	The time the restore sub sp was stop/completed.
	,@errorNumber		int = null				--Optional:	If an error is encountered during the restore or backup process, then this is used to pass the MSSQL error number.
	,@auditDebug		nchar(1) = 'n'			--Optional: When set, returns additional debugging information to diagnose errors.
)
AS

DECLARE @restoreId				int				--The primary key kept in the restore_history table of the meta database.
		,@backupId				int				--The primary key kept in the backup_history table of the meta database.
		,@backupFileExtension	varchar(5)		--The filename extension for the file in question.
		,@filetype				varchar(2)		--Determine if the backup was a native SQL backup or Litespeed backup.
		,@dept					nvarchar(64)	--The department the user who called the sp is under.
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorLine				int
		,@errorState			int;

SET NOCOUNT ON;

BEGIN TRY

	/*
	**	This tries to determine (as best it can) what the current PCI status (clean, dirty, unknown) of the operation is.  If an explicit value is passed than this is used,
	**	otherwise it looks at past related entries in the meta database to this operation and tries to find the currnet PCI status.  If all else fails it reports and unknown
	**	status.
	*/
	SET @auditCleanStatus = COALESCE(@auditCleanStatus, (SELECT TOP(1) clean_status FROM dbAdmin.dbo.backup_history WHERE database_name = @auditDbName ORDER BY backup_end_date DESC), 'unknw');

	/*
	**	If a restore operation needs to be recorded the sp makes sure that is knows certain items about the operation such as what type of restore was made (native or
	**	Litespeed), the filename extension of the backup file, etc.  This information is need before actually recording information.
	*/
	IF @operationType = 0
	BEGIN

		IF RIGHT(@operationFile, 1) != ';'
			SET @operationFile = @operationFile + ';';

		SET @backupFileExtension = SUBSTRING(@operationFile, LEN(@operationFile) - 4, 4);

		SET @filetype = CASE --Determine if the backup was a native SQL backup or Litespeed backup (n: native, l: litespeed)
			WHEN @backupFileExtension != '.sls'
				THEN 'n'
			ELSE 'l'
		END;
	END;

	BEGIN TRAN recordAuditTrail

		/*
		**	This portion of the sp records information for a restore operation.  It inserts data from the sp's parameters into the restore_history and restore_history_file
		**	tables of the meta database.
		*/
		IF @operationType = 0
		BEGIN

			SET @printMessage = '	Recording restore information and statistics'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

			/*
			**	Record the database name, when the restore started, ended, who ran the restore, and any errors that were encountered.
			*/
			INSERT INTO dbAdmin.dbo.restore_history (database_name, restore_start_date, restore_end_date, user_name, err_nbr)
				VALUES (@auditDbName, @operationStart, @operationStop, @auditUserName, @errorNumber);

			SET @restoreId = SCOPE_IDENTITY() --Pull the next primary key ID number from the restore_history_file table.

			/*
			**	Record the name of the file used to restore the database and what type of file it was.
			*/
			INSERT INTO dbAdmin.dbo.restore_history_file (restore_id, filename, filetype)
				VALUES(@restoreId, @operationFile, @filetype);
		END;

		/*
		**	This portion of the sp records information for an initial backup entry.  Because not all the information is available yet (such as backup filename, user
		**	information, etc) the backup audit information is captured in stages.  This is the first stage of that process.  This portion should not be called without also
		**	calling related portions of the script later, otherwise it leaves the database in an intermediate state (at least according to the logs).
		*/
		ELSE IF @operationType = 1
		BEGIN

			/*
			**	Record the database that is being backed up, the type of backup being taken, and a backup status (set statically).
			*/
			INSERT INTO dbAdmin.dbo.backup_history(database_name, type, backup_status)
				VALUES (@auditDbName, @backupType, 'i') --i = "in progress"
		END;

		/*
		**	This portion of the sp records information for a backup operation.  This portion should be run after calling the inital backup entry audit.  This then records
		**	the remain information.
		*/
		ELSE IF @operationType = 2
		BEGIN

			SET @printMessage = '	Recording remaining backup information and statistics'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

			SET @backupId = IDENT_CURRENT('dbAdmin.dbo.backup_history'); --Pull the current primary key ID from the backup_history table.
			SET @dept = (SELECT dept_name FROM user_mappings WHERE user_name = @auditUserName); --Find the department that the user who called the sp is under.

			UPDATE dbAdmin.dbo.backup_history
			SET backup_start_date = @operationStart
				,backup_end_date = @operationStop
				,backup_status = 's'
				,error_message = @errorMessage
				,clean_status = @auditCleanStatus
				,owner = @auditUserName
				,dept = @dept
				,thkVersion = @auditThkVersion
				,problem_num = @auditProbNbr
				,client = @auditClient
				,days_to_save = @auditRetention
			WHERE backup_id = @backupId;
		END;

		/*
		**	This portion of the sp records information for a backup operation.  It inserts data into the backup_history_file table in the meta database.
		*/
		ELSE IF @operationType = 3
		BEGIN

			SET @backupId = IDENT_CURRENT('dbAdmin.dbo.backup_history'); --Pull the current primary key ID from the backup_history table.

			/*
			**	Records the file number (as part of a multi-file backup), filename, and if the file still exists on the database server
			*/
			INSERT INTO dbo.backup_history_file(backup_id, file_number, filename, deleted)
				VALUES(@backupId, @backupCounter, @operationFile, 'n');
		END;
		ELSE
			RAISERROR('Unable to determine operation type for audit logging, information auditing has stopped', 16, 1) WITH LOG;
	COMMIT TRAN;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @auditDebug = 'y'
	BEGIN
		
		SET @printMessage = 'An error occured in the sub_auditTrail sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;