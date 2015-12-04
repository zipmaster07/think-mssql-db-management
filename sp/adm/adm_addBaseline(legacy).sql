/*
**	This stored procedure is used to create new baseline databases for the usp_THKRestoreDb stored procedure.  After adding a baseline database you can call the usp with
**	the special "##" command in the @setBackupFile parameter (see sp documentation for more information).	
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'adm_addBaseline')
	DROP PROCEDURE [dbo].[adm_addBaseline];
GO

CREATE PROCEDURE [dbo].[adm_addBaseline] (
	@baselineFile		nvarchar(512)	--Required:	The filename, including path, of the baseline database that is to be added.
	,@majorVersionOrder	int				--Required:	The major_version_order of the baseline being added.
	,@minorVersionOrder	int				--Required:	The minor_version_order of the baseline being added.
	,@patchVersionOrder	int				--Required:	The patch_version_order of the baseline being added.
	,@baselineAvailable	bit = 1			--Optional:	Sets if the baseline is going to be available. This is only changed if you wish to add an entry to the baseline_versions table without actually adding a baseline.
	,@baselineDebug		nchar(1) = 'n'	--Optional:	When set, returns additional debugging information to diagnose errors.
) WITH EXECUTE AS OWNER
AS

DECLARE @newBaselineDb				sysname			--The name of the temporary database that will be used to stage the baseline DB.
		,@filename					nvarchar(256)	--The name of the final baseline backup file.
		,@mssqlVersion				nvarchar(8)		--The version of MSSQL that the final baseline backup is being taken on. This is the represented as the MSSQL version year (i.e. MSSQL 2008, 2012, 2014, 2016, etc).
		,@definedTempTableId		int				--Used to ID all temp tables.  This is used so that multiple restores can take place at once (a.k.a. multiple people can run the stored procedure at once).
		,@userOverride				nvarchar(32)	--The name of the user creating the new baseline.
		,@thkVersionOUT				nvarchar(16)	--Version of the restored database.
		,@thkVersion				nvarchar(16)	--Version of the restored database without dots.
		,@backupLocation			nvarchar(512)	--The filename, including the path, of the baseline backup.
		,@privilegedUser			bit				--If the user is part of the sysadmin or securityadmin roles then they are a privileged user.
		,@sql						nvarchar(4000)
		,@printMessage				nvarchar(4000);

SET @newBaselineDb = 'newBaselineDb'
SET @definedTempTableId = 1

SET NOCOUNT ON;

/*
**	Step 1: Check for parameter integrity, pull think version, and temp table ID
*/
BEGIN

	EXECUTE AS CALLER;
		SET @userOverride = COALESCE(@userOverride, (SELECT user_name FROM user_mappings WHERE domain_name = SYSTEM_USER)); --Pulls the user actually calling the sp, used for audit purposes.
	REVERT;

	BEGIN TRAN updateTempTableId

		SELECT @definedTempTableId = CAST((SELECT p_value FROM params WITH (ROWLOCK, HOLDLOCK) WHERE p_key = 'tempTableId') AS int); --SQL locks are held on this select so that only one user can get a specific tempTableId
		SET @definedTempTableId = @definedTempTableId + 1;

		UPDATE params WITH (ROWLOCK, HOLDLOCK) --SQL locks are held on this update so that only one user can update the tempTableId at a time
		SET p_value = CAST(@definedTempTableId AS varchar(20))
		WHERE p_key = 'tempTableId'
	COMMIT TRAN;

	SET @sql = N'SET @thkVersionIN = (SELECT cur_vers FROM ' + @newBaselineDb + N'.dbo.config)';
	EXEC sp_executesql @sql, N'@thkVersionIN nvarchar(16) OUTPUT', @thkVersionOUT OUTPUT; --Finds the THINK Enterprise version of the restored database.
	SET @thkVersion = REPLACE(@thkVersionOUT, '.', '') --Removes the dots (.) from the version

	IF @baselineAvailable = 0 --This statement needs to be last to ensure that all the proper variables are gathered first.
	BEGIN

		SET @printMessage = 'The baseline is not available, skipping restoration and backup processes.'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		GOTO insert_baseline
	END;

	IF @baselineDebug not in ('y', 'n')
			RAISERROR('Value for parameter @baselineDebug must be "y" or "n".', 16, 1) WITH LOG;

	IF @baselineDebug = 'y'
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

	IF (@privilegedUser = 0 AND @baselineDebug = 'y')
	BEGIN
			
		SET @baselineDebug = 'n';
		RAISERROR(90502, -1, -1) WITH NOWAIT;
	END;
END;

/*
**	Step 2: Delete, create, restore, and backup
**
**	This steps checks if the temporary database that is going to be use is already created. If it is, it deletes is, then recreates it (or initially creates it). It then restores
**	over the new temporary database with the baseline file provided by the user. It then finally backs up the restored database to be stored in the baseline directory.
*/
BEGIN

	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @newBaselineDb) --Checks if the temporary database is already created and, if it is, deletes it.
		EXEC dbo.adm_deleteDatabase @deleteDbName = @newBaselineDb
			,@deleteBackupHist = 1
			,@deleteDebug = @baselineDebug;

	EXEC dbo.sub_createDatabase @newDbName = @newBaselineDb --Creates a new temporary database that will be used to make the final baseline backup.
		,@createDebug = @baselineDebug;

	EXEC dbo.sub_restoreDatabase @restoreDbName = @newBaselineDb --Restores the baseline database and modifies it.
		,@backupFile = @baselineFile
		,@tempTableId = @definedTempTableId
		,@restoreDebug = @baselineDebug

	EXEC dbo.sub_backupDatabase @backupDbName = @newBaselineDb --With the restored database modified we can take a backup of it to the baseline directory.
		,@backupPath = 'baseline'
		,@backupType = 'full'
		,@method = 'native'
		,@client = 'baseline'
		,@user = @userOverride
		,@backupThkVersion = @thkVersion
		,@backupDbType = 'S'
		,@cleanStatus = 'clean'
		,@backupRetention = 0
		,@newMediaFamily = 1
		,@backupDebug = @baselineDebug
END;

/*
**	Step 3: Update metadata
**
**	Updates the baseline_versions table in the dbAdmin database to reflect the new baseline information and if the baseline is available. Also deletes the temporary database used to
**	restore the baseline.
*/
BEGIN

	insert_baseline:

	SET @mssqlVersion =
		CASE 
			WHEN CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(16)) like '9.%'
				THEN 'sql05_'
			WHEN CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(16)) like '10.%'
				THEN 'sql08_'
			WHEN CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(16)) like '11.%'
				THEN 'sql12_'
			WHEN CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(16)) like '12.%'
				THEN 'sql14_'
			WHEN CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(16)) like '13.%'
				THEN 'sql16_'
		ELSE 'sql'
	END;

	SET @filename = 'baseline_' + @mssqlVersion + @thkVersion + N'.bak';

	SET @backupLocation = '\\PRVTHKDB01\BASELINES\' + @filename;

	INSERT INTO dbAdmin.dbo.baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
		VALUES (@thkVersionOUT, @majorVersionOrder, @minorVersionOrder, @patchVersionOrder, @backupLocation, @baselineAvailable)

	EXEC dbo.adm_deleteDatabase @deleteDbName = @newBaselineDb
			,@deleteBackupHist = 1;
END;