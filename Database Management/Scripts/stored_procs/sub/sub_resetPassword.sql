/*
**	This stored procedure resets the THINK Enterprise "think" or "zzsoft" user password to: "basel1ne" (without quotes).  This sp is a sub stored procedure. It is not meant
**	to be called directly but through a user stored procedure.  The sp also checks User Account access.  If it finds that the user does not have rights to User Account than
**	it grants the user access.  It does not update any other THINK Enterprise modules.  Password access was changed in version 7.2.7 (7.3) and above.  In prior versions it
**	was possible to set the change_password flag and the system would simply ask the user for a new password, however now it also asks for the old password.  The script,
**	therefore, changes the actual password of the THINK Enterprise user (along with other fields).
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_resetAccount')
	DROP PROCEDURE [dbo].[sub_resetAccount];
GO

CREATE PROCEDURE [dbo].[sub_resetAccount] (
	@userDbName		nvarchar(128)	--Required: The name of the database where the THINK Enterprise user will be changed.
	,@resetDebug	nchar(1) = 'n'	--Optional: When set, returns additional debugging information to diagnose errors.
)
AS
SET NOCOUNT ON;

DECLARE @userRightsId						int				--dbo.right_desc.right_desc_id for the User Accounts module.
		,@insufficentUserRightsUserGroup	nvarchar(64)	--The user group of the user that has insufficent rights.
		,@userGroupRightsSeq				int				--dbo.mru_user_group_rights_seq.user_group + 1.
		,@user								nvarchar(4)		--Think Enterprise user.
		,@userExists						bit = 0			--Used to indicate if the user exists in the database: 0 = Does not exist, 1 = Does exist.
		,@hasRights							bit = 1			--Used to indicate if the user has rights to the User Accounts module: 0 = Does not have access, 1 = Has access.
		,@thkVersion						numeric(2,1)	--The THINK Enterprise database version.
		,@thkVersionOUT						nvarchar(16)	--Used in dynamic SQL statements to populate the @thkVersion variable.
		,@datetimeOverride					datetime		--Gets the current date and time.
		,@sql								nvarchar(4000)
		,@printMessage						nvarchar(4000)
		,@errorMessage						nvarchar(4000)
		,@errorSeverity						int
		,@errorNumber						int
		,@errorLine							int
		,@errorState						int;

BEGIN TRY

	SET @datetimeOverride = GETDATE();
	
	SET @printMessage = 'Finding THINK Enterprise Users to reset credentials:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @sql = N'SET @thkVersionIN = (SELECT cur_vers FROM ' + @userDbName + N'.dbo.config)';
	EXEC sp_executesql @sql, N'@thkVersionIN nvarchar(16) OUTPUT', @thkVersionOUT OUTPUT; --Finds the THINK Enterprise version of the database and converts it to a numeric value.
	SET @thkVersion = CAST(SUBSTRING(@thkVersionOUT,1,3) AS numeric(2,1))

	IF @thkVersion >= 7.3
	BEGIN

		SET @printMessage = '	Running post 7.3 password reset scripts...';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
					N'SET @userRightsIdIN = (SELECT right_desc_id FROM right_desc WHERE description = ''Applications, User Accounts'');';
		EXEC sp_executesql @sql, N'@userRightsIdIN int OUTPUT', @userRightsId OUTPUT; --Find the right_desc_id in the right_desc table.  This ID uniquely identifies the User Accounts module for access purposes.  If a user has this ID set, then it means they have rights to the module.

		SET @user = 'THK'; --First look for the 'THK' user.
		
		/*
		**	Updates the user_code table in the target database.  It specifically finds if the THK user has rights to the User Accounts module, if it doesn't than it grants
		**	it rights.  It then resets the password, salt, locked_out, disabled, invalid_access_attempts, and other fields for the user.
		*/
		BEGIN TRAN thkPost73UserUpdate
			
			SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
						N'IF EXISTS (SELECT 1 FROM user_code WHERE user_code = @userIN)
							SET @userExistsIN = 1;';
			EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userExistsIN bit OUTPUT', @user, @userExists OUTPUT; --Find if the "THK" user exists in the database

			IF @userExists = 1
			BEGIN

				SET @printMessage =  '	Found "' + @user + '" user in target database, checking User Account module access';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

				SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'IF NOT EXISTS (SELECT 1 FROM user_code uc, user_group_rights ugr WHERE uc.user_group = ugr.user_group AND uc.user_code = @userIN AND ugr.right_desc_id = @userRightsIdIN)
								SET @hasRightsIN = 0;';
				EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userRightsIdIN int, @hasRightsIN bit OUTPUT', @user, @userRightsId, @hasRights OUTPUT; --Check if the user has access to the User Accounts module.

				IF @hasRights = 0
				BEGIN

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'SET @insufficentUserRightsUserGroupIN = (SELECT user_group FROM user_code WHERE user_code = @userIN);';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64) OUTPUT, @userIN nvarchar(4)', @insufficentUserRightsUserGroup OUTPUT, @user; --Find the group the "THK" user belongs to.

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'SET @userGroupRightsSeqIN = (SELECT mru_user_group_rights_seq FROM user_group WHERE user_group = @insufficentUserRightsUserGroupIN) + 1;';
					EXEC sp_executesql @sql, N'@userGroupRightsSeqIN int OUTPUT, @insufficentUserRightsUserGroupIN nvarchar(64)', @userGroupRightsSeq OUTPUT, @insufficentUserRightsUserGroup; --Find the current mru_user_group_rights_seq and increment by 1.
				
					IF @userGroupRightsSeq IS NULL
						SET @userGroupRightsSeq = 1; --The mru seq is currently NULL, manually set it to 1.

					SET @printMessage = '	User code "' + @user + '" has insufficent rights, now changing permissions in target database'; --Damn straight I'll change your permissions if I feel like it
					RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'INSERT INTO user_group_rights (user_group,user_group_rights_seq,right_desc_id)
									VALUES (@insufficentUserRightsUserGroupIN, @userGroupRightsSeqIN, @userRightsIdIN);';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64), @userGroupRightsSeqIN int, @userRightsIdIN int', @insufficentUserRightsUserGroup, @userGroupRightsSeq, @userRightsId; --Grants the user rights to the User Accounts module.
				
					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'UPDATE user_group
								SET mru_user_group_rights_seq = (SELECT mru_user_group_rights_seq FROM user_group WHERE user_group = @insufficentUserRightsUserGroupIN) + 1
								WHERE user_group = @insufficentUserRightsUserGroupIN;';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64)', @insufficentUserRightsUserGroup;--Increment the mru_user_group_rights_seq field.
				END;
				BEGIN

					IF @hasRights = 0
						RAISERROR('	Permissions granted!  Now changing user''s password', 10, 1) WITH NOWAIT;
					ELSE
					BEGIN

						SET @printMessage = '	User code "' + @user + '" already has sufficent rights, changing user''s password';
						RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
					END

					/*
					**	Changes the password of the "THK" user in the target database.
					*/
					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'UPDATE user_code
								SET password = ''eoAtWlyHhuyi95eIkzAjzHbDaXU=''
									,salt = 23623
									,change_password = 0
									,disabled = 0
									,locked_out = 0
									,invalid_access_attempts = 0
									,password_set_date = @datetimeOverrideIN
								WHERE user_code = @userIN;';
					EXEC sp_executesql @sql, N'@datetimeOverrideIN datetime, @userIN nvarchar(4)', @datetimeOverride, @user;

					SET @printMessage = '	User code "' + @user + '''s" password has been changed';
					RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
				END;
			END;
		COMMIT TRAN;
	
		/*
		**	Reset the @userExists and @hasRights variables then look for the "ZZS" user.
		*/
		SET @user = 'ZZS';
		SET @userExists = 0
		SET @hasRights = 1

		/*
		**	Updates the user_code table in the target database.  It specifically finds if the ZZS user has rights to the User Accounts module, if it doesn't than it grants
		**	it rights.  It then resets the password, salt, locked_out, disabled, invalid_access_attempts, and other fields for the user.
		*/
		BEGIN TRAN zzsPost73UserUpdate

			SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
						N'IF EXISTS (SELECT 1 FROM user_code WHERE user_code = @userIN)
							SET @userExistsIN = 1;';
			EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userExistsIN bit OUTPUT', @user, @userExists OUTPUT; --Find if the "ZZS" user exists in the database

			IF @userExists = 1
			BEGIN

				SET @printMessage =  '	Found "' + @user + '" user in target database, checking User Account module access';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

				SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'IF NOT EXISTS (SELECT 1 FROM user_code uc, user_group_rights ugr WHERE uc.user_group = ugr.user_group AND uc.user_code = @userIN AND ugr.right_desc_id = @userRightsIdIN)
								SET @hasRightsIN = 0;';
				EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userRightsIdIN int, @hasRightsIN bit OUTPUT', @user, @userRightsId, @hasRights OUTPUT; --Check if the user has access to the User Accounts module.

				IF @hasRights = 0
				BEGIN

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'SET @insufficentUserRightsUserGroupIN = (SELECT user_group FROM user_code WHERE user_code = @userIN);';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64) OUTPUT, @userIN nvarchar(4)', @insufficentUserRightsUserGroup OUTPUT, @user; --Find the group the "ZZS" user belongs to.

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'SET @userGroupRightsSeqIN = (SELECT mru_user_group_rights_seq FROM user_group WHERE user_group = @insufficentUserRightsUserGroupIN) + 1;';
					EXEC sp_executesql @sql, N'@userGroupRightsSeqIN int OUTPUT, @insufficentUserRightsUserGroupIN nvarchar(64)', @userGroupRightsSeq OUTPUT, @insufficentUserRightsUserGroup; --Find the current mru_user_group_rights_seq and increment by 1.
				
					IF @userGroupRightsSeq IS NULL
						SET @userGroupRightsSeq = 1; --The mru seq is currently NULL, manually set it to 1.

					SET @printMessage = '	User code "' + @user + '" has insufficent rights, now changing permissions in target database'; --Damn straight I'll change your permissions if I feel like it
					RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'INSERT INTO user_group_rights (user_group,user_group_rights_seq,right_desc_id)
									VALUES (@insufficentUserRightsUserGroupIN, @userGroupRightsSeqIN, @userRightsIdIN);';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64), @userGroupRightsSeqIN int, @userRightsIdIN int', @insufficentUserRightsUserGroup, @userGroupRightsSeq, @userRightsId; --Grants the user rights to the User Accounts module.
				
					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'UPDATE user_group
								SET mru_user_group_rights_seq = (SELECT mru_user_group_rights_seq FROM user_group WHERE user_group = @insufficentUserRightsUserGroupIN) + 1
								WHERE user_group = @insufficentUserRightsUserGroupIN;';
					EXEC sp_executesql @sql, N'@insufficentUserRightsUserGroupIN nvarchar(64)', @insufficentUserRightsUserGroup;--Increment the mru_user_group_rights_seq field.
				END;
				BEGIN

					IF @hasRights = 0
						RAISERROR('	Permissions granted!  Now changing user''s password', 10, 1) WITH NOWAIT;
					ELSE
					BEGIN

						SET @printMessage = '	User code "' + @user + '" already has sufficent rights, changing user''s password';
						RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
					END

					/*
					**	Changes the password of the "ZZS" user in the target database.
					*/
					SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
								N'UPDATE user_code
								SET password = ''eoAtWlyHhuyi95eIkzAjzHbDaXU=''
									,salt = 23623
									,change_password = 0
									,disabled = 0
									,locked_out = 0
									,invalid_access_attempts = 0
									,password_set_date = @datetimeOverrideIN
								WHERE user_code = @userIN;';
					EXEC sp_executesql @sql, N'@datetimeOverrideIN datetime, @userIN nvarchar(4)', @datetimeOverride, @user;

					SET @printMessage = '	User code "' + @user + '''s" password has been changed';
					RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
				END;
			END;
		COMMIT TRAN;
	END;
	ELSE
	BEGIN

		RAISERROR('	Running pre 7.3 password reset scripts...', 10, 1) WITH NOWAIT;

		SET @user = 'THK'; --First look for the 'THK' user.

		BEGIN TRAN thkPre73UserUpdate

			SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'IF EXISTS (SELECT 1 FROM user_code WHERE user_code = @userIN)
								SET @userExistsIN = 1;';
			EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userExistsIN bit OUTPUT', @user, @userExists OUTPUT; --Find if the "THK" user exists in the database

			IF @userExists = 1
			BEGIN

				SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'UPDATE user_code
							SET change_password = 1
							WHERE user_code = @userIN;';
				EXEC sp_executesql @sql, N'@userIN nvarchar(4)', @user; --Update the "THK" user code and set the change password flag.  On next login the user will be required to change their password without knowing the previous password

				SET @printMessage = char(13) + char(10) + '	The change password flag will be set, you will be prompted to change the password of the "' + @user + '" user on next login' + char(13) + char(10) + '	You will not be required to know the previous password';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Reset the @userExists and @hasRights variables then look for the "ZZS" user.
		*/
		SET @user = 'ZZS';
		SET @userExists = 0
		SET @hasRights = 1

		BEGIN TRAN zzsPre73UserUpdate

			SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'IF EXISTS (SELECT 1 FROM user_code WHERE user_code = @userIN)
								SET @userExistsIN = 1;';
			EXEC sp_executesql @sql, N'@userIN nvarchar(4), @userExistsIN bit OUTPUT', @user, @userExists OUTPUT; --Find if the "ZZS" user exists in the database

			IF @userExists = 1
			BEGIN

				SET @sql = N'USE ' + QUOTENAME(@userDbName) + ';' + char(13) + char(10) +
							N'UPDATE user_code
							SET change_password = 1
							WHERE user_code = @userIN;';
				EXEC sp_executesql @sql, N'@userIN nvarchar(4)', @user; --Update the "ZZS" user code and set the change password flag.  On next login the user will be required to change their password without knowing the previous password

				SET @printMessage = char(13) + char(10) + '	The change password flag will be set, you will be prompted to change the password of the "' + @user + '" user on next login' + char(13) + char(10) + '	You will not be required to know the previous password';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
	END;

	RAISERROR('Credentials reset successfully', 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @resetDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_resetAccount sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	RAISERROR(@errorMessage, @errorSeverity, 1)
END CATCH;
GO