/*
**	This stored procedure deletes a database. It records which database was deleted and updates the delete_history table in the dbAdmin database.
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'adm_deleteDatabase')
	DROP PROCEDURE [dbo].[adm_deleteDatabase];
GO

CREATE PROCEDURE [dbo].[adm_deleteDatabase] (
	@deleteDbName		nvarchar(128)	--Required:	The name of the database to be deleted.
	,@deleteBackupHist	bit =  0		--Optional:	Indicates if the backup and restore history should be kept: 0 - keep history, 1 - delete history.
	,@deleteDebug		nchar(1) = 'n'	--Optional:	Returns additional debugging messages.
) WITH EXECUTE AS OWNER
AS

DECLARE @severity			int				--Stores the severity of redirected error messages. Helps to determine if processing should continue or be aborted.
		,@privilegedUser	bit				--If the user is part of the sysadmin or securityadmin roles then they are a privileged user.
		,@printMessage		nvarchar(4000)
		,@sql				nvarchar(4000)
		


SET NOCOUNT ON;

/*
**	Step 1: Parameter integrity
*/
BEGIN

	IF @deleteDebug not in ('y', 'n')
			RAISERROR('Value for parameter @deleteDebug must be "y" or "n".', 16, 1) WITH LOG;

	IF @deleteDebug = 'y'
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

	IF (@privilegedUser = 0 AND @deleteDebug = 'y')
	BEGIN
			
		SET @deleteDebug = 'n';
		RAISERROR(90502, -1, -1) WITH NOWAIT;
	END

	IF @deleteBackupHist = 1
		SET @printMessage = 'Deleting backup and restore history for: ' + @deleteDbName;
	ELSE
		SET @printMessage = 'Keeping backup and restore history for: ' + @deleteDbName;

	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END;

/*
**	Step 2: Delete the database
*/
BEGIN

	IF @deleteBackupHist = 1
		EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @deleteDbName;

	SET @sql = N'ALTER DATABASE ' + QUOTENAME(@deleteDbName) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
	BEGIN TRY
		EXEC sp_executesql @sql;
	END TRY
	BEGIN CATCH
		EXEC dbo.sub_formatErrorMsg @formatSpName = 'dbo.adm_deleteDatabase'
			,@errorSeverity = @severity OUTPUT
			,@formatDebug = @deleteDebug;
			IF @severity >= 16
				RETURN -1
	END CATCH;

	SET @printMessage = 'Attempting to drop database: ' + @deleteDbName;
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @sql = N'DROP DATABASE ' + QUOTENAME(@deleteDbName);
	BEGIN TRY
		EXEC sp_executesql @sql;
	END TRY
	BEGIN CATCH
		EXEC dbo.sub_formatErrorMsg @formatSpName = 'dbo.adm_deleteDatabase'
			,@errorSeverity = @severity OUTPUT
			,@formatDebug = @deleteDebug;
			IF @severity > 10
				RETURN -1
	END CATCH;

	RAISERROR(90501, -1, -1) WITH NOWAIT;
END;