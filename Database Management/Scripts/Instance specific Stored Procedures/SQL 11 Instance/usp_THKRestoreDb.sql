/*
**	Note: Temp tables should not be heaps
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_THKRestoreDB')
	DROP PROCEDURE [dbo].[usp_THKRestoreDB];
GO

CREATE PROCEDURE [dbo].[usp_THKRestoreDB](
	@setDbName		nvarchar(128)			--Required:		Name of the database that is being restored.  If @setCreate is set to 'y' then this will be the name of the new database
	,@setBackupFile	nvarchar(4000)			--Required:		Backup file that is being used to restore the database
	,@setRecovery	varchar(1) = 'y'		--Optional:		Sets whether the backup file being restored is the last backup file.  Only used when restoring diff and transaction log files.  Default is set to 'y'
	,@setCreate		varchar(1) = 'n'		--Optional:		Sets whether a new database should be created and the backup file specific should restore over the new database, or the backup file should be restored over an existing database (default).  Default is set to 'n'
	,@setUserRights	int = 1					--Optional:		Sets how users should be kept/restored to the original and restored database.  Default is set to 1
	,@setClient		nvarchar(128) = null	--Optional:		Name of the client to whose database is being restored
	,@setDbType		varchar(2) = null		--Optional:		Type of database the client provided (Test, Live, Staging, Conversion, QA, Dev, Other)
	,@userOverride	varchar(80) = null		--Undocumented:	Only used when a specific user needs to be passed to the backup sp other then the current user
	,@cleanOverride	varchar(5) = null		--Undocumented:	Only used when a specific clean status needs to be passed to the backup sp.  Used when restoring dirty databases
	,@setProbNbr	nvarchar(16) = null		--Undocumented:	Used for auditing
) WITH EXECUTE AS OWNER
AS

DECLARE @restoreStartTime		datetime		--Date and time the database restore started
		,@restoreEndTime		datetime		--Date and time the database restore stopped
		,@daysToLive			int = 0			--How many days the backup should be kept.  Only used when @cleanOverride is not set to null.  When set to yes, the backup is kept indefinitely.  When set to no, the backup is kept for 60 days (shorter than default)
		,@thkVersionOUT			nvarchar(20)	--Version of the restored database
		,@thkVersion			numeric(2,1)	--The version of the restored database converted to a numeric value.  Used to determine which clean script should be used (pre or post 7.3)
		,@definedTempTableId	int				--Used to ID all temp tables.  This is used so that multiple restores can take place at once (a.k.a. multiple people can run the stored procedure at once)
		,@binaryCheck			tinyint			--Used to find if the first character in the @setDbName parameter is uppercase (it actually does more than this now).  If it is and the @setCreate parameter is set to "y" then a message is given
		,@errorCheck			int				--Not yet implemented.  Advanced error handling and recovery.  Used to reference how far the sp got before it ran into an error.  The reference can then be used to rollback changes
		,@restoreBaseline		bit = 0			--When set it will call the sub_restoreBaseline sp
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorNbr				int;

BEGIN TRY

	/*
	**	Step 1: Check for parameter integrity and pull temp table ID
	*/
	BEGIN
		
		SET NOCOUNT ON;

		IF RIGHT(@setBackupFile, 1) != ';' --Append a semi-colon to the backup file name
			SET @setBackupFile = @setBackupFile + ';';

		IF @setRecovery not in ('y','n')		
			RAISERROR('Value for parameter @setRecovery must be "y" or "n".', 16, 1) WITH LOG;

		IF @setCreate not in ('y','n')
			RAISERROR('Value for parameter @setCreate must be "y" or "n".', 16, 1) WITH LOG;

		IF @setUserRights not in (0,1,2)
			RAISERROR('Value for parameter @setUserRights must be "0", "1", or "2".', 16, 1) WITH LOG;

		IF @setDbType not in (NULL,'T','L','S','C','Q','D','O')
			RAISERROR('Value for parameter @setDbType must be "T", "L", "S", "C", "Q", "D", or "O".', 16, 1) WITH LOG;

		IF @cleanOverride not in (NULL,'clean','dirty')
			RAISERROR('Value for parameter @cleanOverride must either not be set or be set to "clean" or "dirty".', 16, 1) WITH LOG;

		IF @setUserRights != 1
			RAISERROR('Value for parameter @setUserRights was changed from the default of 1.  Make sure you wanted to do this!', 10, 1) WITH NOWAIT;

		IF (@cleanOverride = 'dirty' AND @setProbNbr is NULL)
			RAISERROR('You are attempting to restore a database as "dirty" and a value for parameter @setProbNbr was not set.  Is this restore associated to a particular problem number?', 10, 1) WITH NOWAIT;

		IF (SUBSTRING(@setBackupFile, LEN(@setBackupFile) - 4, 4)) != '.sls'
			RAISERROR('Based on the extension of the backup file you provided you are not restoring a litespeed backup. If this is a litespeed backup the restore step will fail.  All litespeed backups must have a ".sls" extension, otherwise we assume you are restoring a native backup', 10, 1) WITH NOWAIT;

		IF @setRecovery = 'n'
		BEGIN

			RAISERROR('You are restoring a database with "NORECOVERY" all other options will be ignored', 10, 1) WITH NOWAIT;
			SET @setUserRights = 1; --Since all other options are ignored make sure @setUserRights is set to 1 so that it does not trigger the sub_databasePrincipals sp in Step 2.
		END;

		IF SUBSTRING(@setBackupFile, 1, 2) = '##'
		BEGIN

			RAISERROR('You have entered a special value (##) into the @setBackupFile parameter... restoring database to a baseline', 10, 1) WITH NOWAIT;
			SET @restoreBaseline = 1
		END;

		IF @setCreate = 'y'
		BEGIN

			SET @binaryCheck =
				CASE
					WHEN BINARY_CHECKSUM(SUBSTRING(@setDbName,1,1)) = BINARY_CHECKSUM(LOWER(SUBSTRING(@setDbName,1,1)))
						THEN 0
					ELSE 1
				END

			IF (CHARINDEX('_',@setDbName)) > 0
				SET @binaryCheck = 1
			IF (CHARINDEX('-',@setDbName)) > 0
				SET @binaryCheck = 1
			IF (CHARINDEX(char(32),@setDbName)) > 0
				SET @binaryCheck = 1
		END;

		IF @binaryCheck = 1
			RAISERROR('Tisk Tisk, you are not following the standard naming convention when creating databases, perhaps you should read the docs more closly', 10, 1) WITH NOWAIT;
		
		BEGIN TRAN updateTempTableId

			SELECT @definedTempTableId = CAST((SELECT p_value FROM params WITH (ROWLOCK, HOLDLOCK) WHERE p_key = 'tempTableId') AS int);
			SET @definedTempTableId = @definedTempTableId + 1;

			UPDATE params WITH (ROWLOCK, HOLDLOCK)
			SET p_value = CAST(@definedTempTableId AS varchar(20))
			WHERE p_key = 'tempTableId'
		COMMIT TRAN;
		
		SET NOCOUNT OFF;
	END;

	/*
	**	Step 2:	Restore database
	**
	**	Either restores over an existing database or creates a new database and restores over that.
	**	Sets the restore start time and then calls the sub stored procedure "sub_restoreDatabase".  If it
	**	succeeds then the restore end time is captured.  Both variables will be used when inserting data into
	**	the restore_history table.  Depending on how @setUserRights is set the sub_databasePrincipals sp may
	**	be called to gather users.
	*/
	BEGIN

		IF @setCreate = 'y'
			EXEC dbo.sub_createDatabase @newDbName = @setDbName;

		IF @setUserRights = 0
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;

		IF @restoreBaseline = 1
			EXEC dbo.sub_restoreBaseline @restoreVersionPath = @setBackupFile OUTPUT, @tempTableId = @definedTempTableId;

		SET @restoreStartTime = GETDATE(); --This more accurately represents when the restore sp is called, not when the actual restore started.  The same can be said for the @restoreEndTime parameter
		EXEC dbo.sub_restoreDatabase @restoreDbName = @setDbName, @backupFile = @setBackupFile, @recovery = @setRecovery, @tempTableId = @definedTempTableId;
		SET @restoreEndTime = GETDATE();

		IF @setRecovery = 'n' --Used when restoring with "NORECOVERY".  Indicates if the restore was successful and the sp should immediately stop
			GOTO recordAuditTrail;
	END;

	/*
	**	Step 3:	Set users and user rights on database
	**
	**	This step varies depending on how @setUserRights was set.  If set to 0 then you are attempting to 
	**	to restore the users that were in the original database.  If set to 1 (the default) then the sp will
	**	wipe out all existing users and replace them with a standard set of users (defined in user_mappings).
	**	It also grants sp rights to all the restored users and then adds the thkapp user (see comment below).
	*/
	BEGIN

		IF @setUserRights = 0 --If users were gathered in the previous database the stored list can now be used on the restored database
		BEGIN

			SET @setUserRights = 3
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;
		END
		ELSE IF @setUserRights = 1 --Removing all non-THINK related users/stored procedures/tables/views/etc and added a standard template
		BEGIN

			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;
			
			SET @setUserRights = 2
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;;
		END
		ELSE IF @setUserRights = 2 --Add the standard user template without removing the exsting users/stored procedures/tables/views/etc
		BEGIN

			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;;
		END;

		EXEC dbo.sub_grantSpRights @spGrantDbName = @setDbName, @tempTableId = @definedTempTableId;;
		/*
		**	The following is hard-coded as the 'thkapp' login will always be the db_owner on every
		**	THINK Enterprise database.  Setting @setUserRights to specific numbers may result in
		**	the thkapp login already being created (however this is not guaranteed).  This portion of
		**	the code is still run, regardless, it should simply error, indicating that the thkapp
		**	login was already mapped to a user.
		*/
		BEGIN TRY
			BEGIN TRAN createSystemUser

				SET @sql = N'USE ' + QUOTENAME(@setDbName) + char(13) + char(10) +
							N'CREATE USER [thkapp_NEW] FOR LOGIN [thkapp]' + char(13) + char(10) +
							N'ALTER USER [thkapp_NEW] WITH DEFAULT_SCHEMA = [dbo]';
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@setDbName) + char(13) + char(10) +
							N'EXEC sp_addrolemember N''db_owner'', N''thkapp_NEW''';
				EXEC sp_executesql @sql;
			COMMIT TRAN;
		END TRY
		BEGIN CATCH

			IF @@TRANCOUNT > 0
				ROLLBACK;

			SELECT @errorMessage = ERROR_MESSAGE()
				,@errorSeverity = ERROR_SEVERITY()
				,@errorNbr = ERROR_NUMBER();

			SET @printMessage = 'User "thkapp" already exists for database "' + @setDbName + '".  Skipping CREATE USER statement.';

			IF @errorNbr = 15023
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END CATCH;
	END;

	/*
	**	Step 4:	Set bankdef on database
	**
	**	Pretty simple, just calling the sub_setBankDefs sp here.  Look at the actual sp for additional info.
	**	Bank definition information is is kept in most cases, however when cleaning the database or when
	**	restoring as dirty then additional values are changed, otherwise the sp just make sure that all
	**	bank defs are pointing to a test server.
	*/
	BEGIN

		IF @cleanOverride is not null
			EXEC dbo.sub_setBankDefs @icsDbName = @setDbName, @retainBankDefInfo = 0;
		ELSE
			EXEC dbo.sub_setBankDefs @icsDbName = @setDbName, @retainBankDefInfo = 1;
	END;

	/*
	**	Step 5:	Clean database
	**
	**	If the @cleanOverride parameter is set then the following step will be executed.  If it is not (meaning
	**	it is NULL) then we are assuming that the database is already clean (which is acceptable) or we are 
	**	purposefully restoring a dirty database.
	*/
	BEGIN

		SET @setClient = COALESCE(@setClient, 'THINK');
		SET @setDbType = COALESCE(@setDbType, 'T');

		SET @sql = N'SET @thkVersionIN = (SELECT cur_vers FROM ' + @setDbName + N'.dbo.config)';
		EXEC sp_executesql @sql, N'@thkVersionIN nvarchar(20) OUTPUT', @thkVersionOUT OUTPUT; --Finds the THINK version of the restored database and converts it to a numeric value
		SET @thkVersion = CAST(SUBSTRING(@thkVersionOUT,1,3) AS numeric(2,1))

		EXECUTE AS CALLER;
			SET @userOverride = COALESCE(@userOverride, (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER)); --Pulls the user actually calling the sp
		REVERT;

		IF @cleanOverride = 'clean'
		BEGIN

			EXEC dbo.sub_cleanDatabase @cleanDbName = @setDbName, @thkVersion = @thkVersion, @tempTableId = @definedTempTableId;
			EXEC dbo.sub_backupDatabase @backupDbName = @setDbName, @backupType = 'full', @method = 'litespeed', @client = @setClient, @user = @userOverride, @backupThkVersion = @thkVersionOUT, @backupDbType = @setDbType, @cleanStatus = 'clean', @probNbr = @setProbNbr, @backupRetention = @daysToLive;
		END
		ELSE IF @cleanOverride = 'dirty'
		BEGIN

			SET @daysToLive = 60
			EXEC dbo.sub_backupDatabase @backupDbName = @setDbName, @backupType = 'full', @method = 'litespeed', @client = @setClient, @user = @userOverride, @backupThkVersion = @thkVersionOUT, @backupDbType = @setDbType, @cleanStatus = 'dirty', @probNbr = @setProbNbr, @backupRetention = @daysToLive;
		END
	END;

	/*
	**	Step 6:	Update restore_history table
	*/
	BEGIN
		recordAuditTrail:

		EXECUTE AS CALLER
			SET @userOverride = (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER); --Pull the actual user who called the sp regardless of what the @userOverride parameter was set to.  This is used for recording purposes only
		REVERT;
	
		EXEC sub_auditTrail @auditDbName = @setDbName, @operationFile = @setBackupFile, @operationType = 0, @auditCleanStatus = @cleanOverride, @auditUserName = @userOverride, @auditThkVersion = @thkVersionOUT, @auditProbNbr = @setProbNbr, @auditClient = @setClient, @auditRetention = @daysToLive, @operationStart = @restoreStartTime, @operationStop = @restoreEndTime;
	END;

	SET @printMessage = char(13) + char(10) + 'Congratulations!!! The restore has completed successfully'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
	
	IF @@TRANCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
		,@errorSeverity = ERROR_SEVERITY()
		,@errorNbr = ERROR_NUMBER();

	RAISERROR(@errorMessage, @errorSeverity, 1);
	RETURN -1;
END CATCH;
GO

GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\akennedy]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\cjenkins]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\jschaeffer]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\lzibetti]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\mheil]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\rwalgren]
GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\shokanson]
GO