/*
**	This stored procedure restores and cleans THINK Enterprise databases.  It also records database restores for audit purposes.  It runs several different steps
**	including the actual restore, SQL login/user cleanup and maintenance, purges credit card information and other PCI sensitive data, insures that bank definitions
**	are pointed to test gateway servers, logs restore times, files used, files created, etc.  Most steps are run modularly through sub stored procedures.  This allows
**	plugging in new functionality into the user stored procedure (usp).  USP's are executed as owner, which provides an "allow only the permissions necessary"
**	paradigm for end users.  sub stored procedures are not directly accessible to regular users.  This sp should always be created/recreated with the sa account.  The sp
**	also has a special mechanism to restore a THINK Enterprise baseline to a database by only specifying the verison of the baseline you want to restore and the database
**	you want to restore it to.
**
**	The sp, and all its sub sp's are kept in a meta database (no different than any other database) called dbAdmin.  It is called from this database and uses dynamic
**	SQL heavily to act on other databases and the instance as a whole.
**
**	The sp allows restoring THINK Enterprise databases without cleaning them.  This is called restoring a database as dirty.  This is only useful for problems that
**	require actual PCI data instead of the substituted data.  Additional audit information is captured when a DB is restored as dirty.  It is also possible to not
**	specify a clean status.  The sp then assumes that a database is already clean.  This way system resources are not used to clean a database that is already clean.
**	
**	There are many other features of this sp.  Documentation for is kept at:
**	"\\brighton\Public\Customer Service\Projects\SQL Server Operations\Database Management\Documentation".
**	
**	Note: Temp tables should not be heaps.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_THKRestoreDB')
	DROP PROCEDURE [dbo].[usp_THKRestoreDB];
GO

CREATE PROCEDURE [dbo].[usp_THKRestoreDB](
	@setDbName		nvarchar(128)			--Required:		Name of the database that is being restored.  If @setCreate is set to 'y' then this will be the name of the new database.
	,@setBackupFile	nvarchar(4000)			--Required:		Backup file that is being used to restore the database.
	,@setRecovery	varchar(1) = 'y'		--Optional:		Sets whether the backup file being restored is the last backup file.  Only used when restoring diff and transaction log files.  Default is set to 'y'.
	,@setCreate		varchar(1) = 'n'		--Optional:		Sets whether a new database should be created and the backup file specific should restore over the new database, or the backup file should be restored over an existing database (default).  Default is set to 'n'.
	,@setUserRights	int = 1					--Optional:		Sets how users should be kept/restored to the original and restored database.  Default is set to 1.
	,@setClient		nvarchar(128) = null	--Optional:		Name of the client to whose database is being restored.
	,@setDbType		varchar(2) = null		--Optional:		Type of database the client provided (Test, Live, Staging, Conversion, QA, Dev, Other).
	,@userOverride	varchar(80) = null		--Undocumented:	Only used when a specific user needs to be passed to the backup sp other then the current user.
	,@cleanOverride	varchar(5) = null		--Undocumented:	Only used when a specific clean status needs to be passed to the backup sp.  Used when restoring dirty databases.
	,@setProbNbr	nvarchar(16) = null		--Undocumented:	Used for auditing.
	,@setDebug		nchar(1) = 'n'			--Optional:		When set, returns additional debugging information to diagnose errors.
) WITH EXECUTE AS OWNER
AS

DECLARE @restoreStartTime		datetime		--Date and time the database restore started.
		,@restoreEndTime		datetime		--Date and time the database restore stopped.
		,@daysToLive			int = 0			--How many days the backup should be kept.  Only used when @cleanOverride is not set to null.  When set to "clean", the backup is kept indefinitely.  When set to "dirty", the backup is kept for 60 days (shorter than default).
		,@thkVersionOUT			nvarchar(20)	--Version of the restored database.
		,@thkVersion			numeric(2,1)	--The version of the restored database converted to a numeric value.  Used to determine which clean script should be used (pre or post 7.3).
		,@definedTempTableId	int				--Used to ID all temp tables.  This is used so that multiple restores can take place at once (a.k.a. multiple people can run the stored procedure at once).
		,@binaryCheck			tinyint			--Used to find if the first character in the @setDbName parameter is uppercase (it actually does more than this now).  If it is and the @setCreate parameter is set to "y" then a message is given.
		,@errorCheck			int				--Not yet implemented.  Advanced error handling and recovery.  Used to reference how far the sp got before it ran into an error.  The reference can then be used to rollback changes.
		,@restoreBaseline		bit = 0			--When set it will call the sub_restoreBaseline sp.
		,@privilegedUser		bit = 0			--Denotes that the user running the stored procedure is either in the sysadmin or securityadmin groups.  This is used to determine if the user has the ability to run the sp with the debug flag set.
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorNumber			int
		,@errorLine				int
		,@errorState			int;

BEGIN TRY

	/*
	**	Step 1: Check for parameter integrity and pull temp table ID.
	*/
	BEGIN
		
		SET NOCOUNT ON;

		IF RIGHT(@setBackupFile, 1) != ';' --Append a semi-colon to the backup file name.
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

		IF @setUserRights != 1 --Just a warning, most users do not want this set 99% of the time.
			RAISERROR('Value for parameter @setUserRights was changed from the default of 1.  Make sure you wanted to do this!', 10, 1) WITH NOWAIT;

		IF (@cleanOverride = 'dirty' AND @setProbNbr is NULL) --Currently just warning the user that they did not set the problem number when restoring as dirty.  This could be changed to force a problem number if restoring as dirty.
			RAISERROR('You are attempting to restore a database as "dirty" and a value for parameter @setProbNbr was not set.  Is this restore associated to a particular problem number?', 10, 1) WITH NOWAIT;

		IF (SUBSTRING(@setBackupFile, LEN(@setBackupFile) - 4, 4)) != '.sls' --Finds the extension of the backup file and determines if it is a litespeed backup.  For multi-file backups, you cannot mix different file types (a.k.a. native and litespeed).
			RAISERROR('Based on the extension of the backup file you provided you are not restoring a litespeed backup. If this is a litespeed backup the restore step will fail.  All litespeed backups must have a ".sls" extension, otherwise we assume you are restoring a native backup', 10, 1) WITH NOWAIT;

		IF @setRecovery = 'n'
		BEGIN

			RAISERROR('You are restoring a database with "NORECOVERY" all other options will be ignored', 10, 1) WITH NOWAIT;
			SET @setUserRights = 1; --Since all other options are ignored make sure @setUserRights is set to 1 so that it does not trigger the sub_databasePrincipals sp in Step 2.
		END;

		IF SUBSTRING(@setBackupFile, 1, 2) = '##' --If the backup file string starts with "##" (without quotes) then the script will restore a THINK Enterprise baseline.  See the documentation for more information
		BEGIN

			RAISERROR('You have entered a special value (##) into the @setBackupFile parameter... restoring database to a baseline', 10, 1) WITH NOWAIT;
			SET @restoreBaseline = 1
		END;

		/*
		**	This section checks to see if the user used the proper naming convention when creating databases
		**	Full naming conventions cannot be checked without plugging in an outside program (such as using SQL CLR)
		*/
		IF @setCreate = 'y' 
		BEGIN

			SET @binaryCheck =
				CASE
					WHEN BINARY_CHECKSUM(SUBSTRING(@setDbName,1,1)) = BINARY_CHECKSUM(LOWER(SUBSTRING(@setDbName,1,1))) --User captialized the first word of the database name
						THEN 0
					ELSE 1 
				END

			IF (CHARINDEX('_',@setDbName)) > 0 --User used an underscore in the database name
				SET @binaryCheck = 1
			IF (CHARINDEX('-',@setDbName)) > 0 --User used a hyphen in the database name
				SET @binaryCheck = 1
			IF (CHARINDEX(char(32),@setDbName)) > 0 --User used a space character in the database name
				SET @binaryCheck = 1
		END;

		IF @binaryCheck = 1 --If set than the sp will scold the user for not reading the documentation closely enough, but will continue otherwise.
			RAISERROR('Tisk Tisk, you are not following the standard naming convention when creating databases, perhaps you should read the docs more closly', 10, 1) WITH NOWAIT;

		IF @setDebug = 'y'
		BEGIN

			EXECUTE AS CALLER --Find if the user running the sp is part of the sysadmin or securityadmin fixed server role
				SET @privilegedUser =
					CASE
						WHEN IS_SRVROLEMEMBER('sysadmin') = 1
							THEN 1
						WHEN IS_SRVROLEMEMBER('securityadmin') = 1
							THEN 1
						ELSE 0
					END
			REVERT;
		END

		IF (@privilegedUser = 0 AND @setDebug = 'y')
		BEGIN
			
			SET @setDebug = 'n';
			RAISERROR('Only members of the sysadmin and securityadmin fixed server roles may view debug statements.  No debug statements will be printed', 10, 1) WITH NOWAIT;
		END
		
		/*
		**	Pulling a restore ID from the meta database.  The restore ID (called tempTableID) is appended to many temp tables that are created throughout the entire
		**	sp, including all of its sub sp's.  This allows multiple users to run the stored procedure at the same time, otherwise the temp tables that are created
		**	would get overwritten mid restore for some users and cause problems.
		*/
		BEGIN TRAN updateTempTableId

			SELECT @definedTempTableId = CAST((SELECT p_value FROM params WITH (ROWLOCK, HOLDLOCK) WHERE p_key = 'tempTableId') AS int); --SQL locks are held on this select so that only one user can get a specific tempTableId
			SET @definedTempTableId = @definedTempTableId + 1;

			UPDATE params WITH (ROWLOCK, HOLDLOCK) --SQL locks are held on this update so that only one user can update the tempTableId at a time
			SET p_value = CAST(@definedTempTableId AS varchar(20))
			WHERE p_key = 'tempTableId'
		COMMIT TRAN;
		
		SET NOCOUNT OFF;
	END;

	/*
	**	Step 2:	Restore database
	**
	**	Either restores over an existing database or creates a new database and restores over that. Sets the restore start time and then calls the sub stored procedure
	**	"sub_restoreDatabase".  If it succeeds then the restore end time is captured.  Both variables will be used when inserting data into the restore_history table.
	**	Depending on how @setUserRights is set the sub_databasePrincipals sp may be called to gather users.  Also, depending on how @restoreBaseline is set the
	**	sub_restoreBaseline sp may be called.
	*/
	BEGIN

		IF @setCreate = 'y' --If set to 'y' call the "sub_createDatabase" sp.  Pass the @setDbName value to the sub sp.
			EXEC dbo.sub_createDatabase @newDbName = @setDbName;

		/*
		**	Calling the "sub_databasePrincipals" sp here gather SQL user information in a temp table.  This user information is then used in the restored database later.
		*/
		IF @setUserRights = 0 --If set to 0 call the "sub_databasePrincipals" sp.  Pass the @setDbName, @setUserRights, and @defintedTempTableId values to the sub sp.
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;

		IF @restoreBaseline = 1 --If set to 1 call the "sub_restoreBaseline" sp.  Pass the @setBackupFile and @definedTempTableId value to the sub sp.  Unless most sub sp's, the "sub_restoreBaseline" sp returns a value.  It overrides the @setBackupFile parameter with the location of the desired baseline.
			EXEC dbo.sub_restoreBaseline @restoreVersionPath = @setBackupFile OUTPUT, @tempTableId = @definedTempTableId;

		SET @restoreStartTime = GETDATE(); --This more accurately represents when the restore sp is called, not when the actual restore started.  The same can be said for the @restoreEndTime parameter
		EXEC dbo.sub_restoreDatabase @restoreDbName = @setDbName, @backupFile = @setBackupFile, @recovery = @setRecovery, @tempTableId = @definedTempTableId, @restoreDebug = @setDebug;
		SET @restoreEndTime = GETDATE();

		IF @setRecovery = 'n' --Used when restoring with "NORECOVERY".  Indicates if the restore was successful and the sp should immediately stop.
			GOTO recordAuditTrail;
	END;

	/*
	**	Step 3:	Set users and user rights on database
	**
	**	This step varies depending on how @setUserRights was set.  If set to 0 then you are attempting to to restore the users that were in the original database. If set to
	**	1 (the default) then the sp will wipe out all existing users and replace them with a standard set of users (defined in user_mappings in the meta database). It also
	**	grants sp rights to all the restored users, changes the default THINK Enterprise user's password ("THK" or "ZZS"), and then adds the thkapp user (see comment below).
	**	Finally it checks for certain running processes and stops them if it finds any.
	*/
	BEGIN

		IF @setUserRights = 0 --If users were gathered in the previous database the stored list can now be used on the restored database.
		BEGIN

			SET @setUserRights = 3 --See the "sub_databasePrincipals" sp for why we immediately change the value of @setUserRights to 3.
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId; --Call the "sub_databasePrincipals" sp again with the new value.
		END
		ELSE IF @setUserRights = 1 --Removing all non-THINK related users/stored procedures/tables/views/etc and added a standard template (pulled from the meta database).
		BEGIN

			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId; --If @setUserRights was set to 1 (default) this is the first time the "sub_databasePrincipals" sp is called
			
			SET @setUserRights = 2 --See the "sub_databasePrincipals" sp for why we immediately change the value of @setUserRights to 2.
			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;
		END
		ELSE IF @setUserRights = 2 --Add the standard user template without removing the exsting users/stored procedures/tables/views/etc.
		BEGIN

			EXEC dbo.sub_databasePrincipals @principalDbName = @setDbName, @gatherUsers = @setUserRights, @tempTableId = @definedTempTableId;
		END;

		/*
		**	This sub sp grants rights to SQL Users for THINK Enterprise specific stored procedures such as zz_helpdomain, zz_dbver, etc.  It has nothing to do with granting
		**	rights to this sp or its sub sp's.
		*/
		EXEC dbo.sub_grantSpRights @spGrantDbName = @setDbName, @tempTableId = @definedTempTableId;

		/*
		**	This sub sp checks for any running THINK Enterprise processes in the target database.  Specifically, it checks to see if the Email/Event Queue process is running
		**	as this can email real people even in test databases.  if it is running then it stops the process.  It should be noted that is does stop processes forcefully and
		**	does not attempt any graceful shutdowns.
		*/
		EXEC dbo.sub_checkProcesses @processDbName = @setDbName, @tempTableId = @definedTempTableId;

		/*
		**	This sub sp resets either the "THK" or "ZZS" user code password to "basel1ne" (without quotes) if the database version is 7.3 or higher.  If the database version
		**	is pre 7.3 than is simply sets the change_password flag so that the next login attempt will require the user to change the password (without needing to know the
		**	previous password).
		*/
		EXEC dbo.sub_resetAccount @userDbName = @setDbName;

		/*
		**	The following is hard-coded, as the 'thkapp' login will always be the db_owner on every THINK Enterprise database.  Setting @setUserRights to specific numbers
		**	may result in the thkapp login already being created (however this is not guaranteed).  This portion of the code is still run, regardless, it should simply
		**	errors out, indicating that the thkapp login was already mapped to a user.
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
				,@errorNumber = ERROR_NUMBER();

			SET @printMessage = 'User "thkapp" already exists for database "' + @setDbName + '".  Skipping CREATE USER statement.';

			IF @errorNumber = 15023 --"User already exists in current database" error
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END CATCH;
	END;

	/*
	**	Step 4:	Set bankdef on database
	**
	**	Pretty simple and short step, just calling the sub_setBankDefs sp here.  Look at the actual sp for additional info. Bank definition information is is kept in most
	**	cases, however when cleaning the database or when restoring as dirty then additional values are changed, otherwise the sp just makes sure that all bank defs are
	**	pointing to a test server.
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
	**	If the @cleanOverride parameter is set then the following step will be executed.  If it is not, meaning it is NULL, then we are assuming that the database is
	**	already clean (which is acceptable) or we are purposefully restoring a dirty database.
	*/
	BEGIN

		/*
		**	The following two statements collect information about the current database.  This information is actually passed to the sp by the user themselves.  This
		**	information is only ever used if the @cleanOverride parameter is set to "clean" or "dirty", otherwise the information is not actually needed.  It is
		**	ultimately used in naming the backup of the cleaned database.
		*/
		SET @setClient = COALESCE(@setClient, 'THINK');
		SET @setDbType = COALESCE(@setDbType, 'T');

		SET @sql = N'SET @thkVersionIN = (SELECT cur_vers FROM ' + @setDbName + N'.dbo.config)';
		EXEC sp_executesql @sql, N'@thkVersionIN nvarchar(20) OUTPUT', @thkVersionOUT OUTPUT; --Finds the THINK Enterprise version of the restored database and converts it to a numeric value.
		SET @thkVersion = CAST(SUBSTRING(@thkVersionOUT,1,3) AS numeric(2,1))

		EXECUTE AS CALLER;
			SET @userOverride = COALESCE(@userOverride, (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER)); --Pulls the user actually calling the sp, used for audit purposes.
		REVERT;

		IF @cleanOverride = 'clean' --The user wanted to specifically clean the database of PCI sensitive data
		BEGIN

			EXEC dbo.sub_cleanDatabase @cleanDbName = @setDbName, @thkVersion = @thkVersion, @tempTableId = @definedTempTableId; --Calling the "sub_cleanDatabase" sp before backing up the restored database.  Passing @setDbName, @thkVersion, and @definedTempTableId values to the sub sp.
			EXEC dbo.sub_backupDatabase @backupDbName = @setDbName, @backupType = 'full', @method = 'litespeed', @client = @setClient, @user = @userOverride, @backupThkVersion = @thkVersionOUT, @backupDbType = @setDbType, @cleanStatus = 'clean', @probNbr = @setProbNbr, @backupRetention = @daysToLive;
		END
		ELSE IF @cleanOverride = 'dirty' --The user wanted to specifically NOT clean the database of PCI sensitive data
		BEGIN

			SET @daysToLive = 60 --Because the database contains PCI sensitive data we do not want to store the backup of the database any longer than 60 days
			EXEC dbo.sub_backupDatabase @backupDbName = @setDbName, @backupType = 'full', @method = 'litespeed', @client = @setClient, @user = @userOverride, @backupThkVersion = @thkVersionOUT, @backupDbType = @setDbType, @cleanStatus = 'dirty', @probNbr = @setProbNbr, @backupRetention = @daysToLive;
		END
	END;

	/*
	**	Step 6:	Update restore_history table
	**
	**	Now that the restore, clean, and backup are completed the sp records audit information about the restore (filename, time stamps, user information, etc)
	*/
	BEGIN
		recordAuditTrail: --GOTO marker.  Used to skip most of the sp when restoring with @setRecovery = 'n'

		EXECUTE AS CALLER
			SET @userOverride = (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER); --Pull the actual user who called the sp regardless of what the @userOverride parameter was set to.  This is used for recording purposes only
		REVERT;
	
		EXEC sub_auditTrail @auditDbName = @setDbName, @operationFile = @setBackupFile, @operationType = 0, @auditCleanStatus = @cleanOverride, @auditUserName = @userOverride, @auditThkVersion = @thkVersionOUT, @auditProbNbr = @setProbNbr, @auditClient = @setClient, @auditRetention = @daysToLive, @operationStart = @restoreStartTime, @operationStop = @restoreEndTime; --Calling the "sub_auditDbName" sp.  Passing many values to it from current parameters (to lazy to list them out)!
	END;

	SET @printMessage = char(13) + char(10) + 'Congratulations!!! The restore has completed successfully'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
	
	IF @@TRANCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();


	IF @setDebug = 'y'
	BEGIN

		SET @sql = COALESCE(@sql, ISNULL(@sql, 'None'))
		SET @printMessage = 'DEBUG: last sql statement' + char(13) + char(10) + @sql;
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	RAISERROR(@errorMessage, @errorSeverity, 1);
	RETURN -1;
END CATCH;
GO
/*
**	The following code is determined dynamically depending on which instance this stored procedure is running under.  This finds the current SQL users of an instance and
**	gives them rights to this stored procedure.
*/
DECLARE @sql			nvarchar(4000)
		,@printMessage	nvarchar(4000);

SET @sql =
	CASE
		WHEN @@SERVICENAME = 'SUPPORT' --If running under the SUPPORT instance add the listed MPLS accounts.
			THEN N'GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\bjensen]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\cjenkins]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\jschaeffer]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\lzibetti]'
		WHEN @@SERVICENAME = 'QA' --If running under the QA instance add the listed MPLS account.
			THEN N'GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\rwalgren]'
		WHEN @@SERVICENAME = 'DEV' --If running under the DEV instance add the listed MPLS accounts.
			THEN N'GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\akennedy]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\mheil]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\shokanson]'
		WHEN @@SERVICENAME = 'SQL11' --If running under the SQL11 instance add the listed MPLS accounts.
			THEN N'GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\akennedy]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\cjenkins]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\jschaeffer]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\lzibetti]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\mheil]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\rwalgren]
					GRANT EXECUTE ON [dbo].[usp_THKRestoreDB] TO [MPLS\shokanson]'
		ELSE NULL
	END;

SET @printMessage = 'Current instance [' + @@SERVICENAME + '] is not a supported instance.  Could not authorize user list.'

IF @sql = NULL
	RAISERROR(@printMessage, 16, 1) WITH LOG;

EXEC sp_executesql @sql; --Actually run the SQL statement.
GO
