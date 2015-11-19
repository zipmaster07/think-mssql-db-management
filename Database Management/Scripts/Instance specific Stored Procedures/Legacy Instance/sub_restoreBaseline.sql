USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_restoreBaseline')
	DROP PROCEDURE [dbo].[sub_restoreBaseline]
GO

CREATE PROCEDURE [dbo].[sub_restoreBaseline](
	@restoreVersionPath	nvarchar(4000) OUTPUT
	,@tempTableId		int
)
AS

DECLARE @restoreVersion				nvarchar(64)	--The baseline version found
		,@sql						nvarchar(4000)
		,@count						int
		,@dotPos					int				--Stores the current dot position
		,@previousDotPos			int				--Stores the previous dot position
		,@dotCount					int				--Used to find how many dots are in a the @restoreVersionPath string
		,@betweenDotCount			int				--Used to find how many characters are between dots
		,@eof						int
		,@restoreVersionPrecision	int				--The length of the version number
		,@versionMatch				bit				--Indicates if version has been found: 0 = not found, 1 = found
		,@versionOrder				nvarchar(32)	--Specifies the current version level of detail based off the @currentVersionOrder parameter
		,@currentVersionOrder		tinyint			--What part of the version are we trying to match on: 1 = major, 2 = minor, 3 = patch
		,@lastDeletedChar			char(1)			--Stores the last deleted character from the version as a match is trying to be made
		,@majorVersionNbr			nvarchar(16)	--The major version number
		,@majorVersionLength		int				--The length of the major version number
		,@patchVersionNbr			nvarchar(8)		--The patch version number
		,@patchVersionLength		int				--The length of the patch version number
		,@patchNonNumberPos			int				--The first non number position in the patch number
		,@isAvailable				bit				--Checks if the version selected/found is available for restore
		,@castedTempTableId			varchar(16)		--@tempTableId casted as a varchar
		,@printMessage				nvarchar(4000)
		,@errorMessage				nvarchar(4000)
		,@errorSeverity				int
		,@errorNumber				int

SET @count = 1
SET @dotPos = 0
SET @dotCount = 0
SET @versionMatch = 0

SET NOCOUNT ON;

BEGIN TRY

	SET @printMessage = char(13) + char(10) + 'Finding baseline database'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @castedTempTableId = CAST(@tempTableId AS varchar(16));

	SET @sql = N'CREATE TABLE ##restore_baseline_principals_' + @castedTempTableId + N'(
					dot_count_id		int identity(1000,1)	not null
					,dot_count			int						not null
					,dot_pos			int						not null
					,between_dot_count	int						null
					
					,CONSTRAINT PK_TEMP_RESTORE_BASELINE_PRINCIPALS_' + @castedTempTableId + N' PRIMARY KEY CLUSTERED(
						dot_count_id
					)
				);';
	EXEC sp_executesql @sql;

	SET @eof = LEN(@restoreVersionPath)

	/*
	**	This while loop finds the major and minor version numbers and inserts key dot positions into a temp table
	*/
	BEGIN

		WHILE @dotPos < @eof
		BEGIN

			SET @previousDotPos = @dotPos
			SET @dotPos = (CHARINDEX('.', @restoreVersionPath, (@dotPos + 1)));

			IF @dotPos > 0
			BEGIN

				SET @dotCount = @dotCount + 1;
				IF @dotCount > 1 --Finds everything after the first major version number (excluding the actual patch number)
				BEGIN
					BEGIN TRAN findRemainingDotPositions
				
						SET @betweenDotCount = ((@dotPos - @previousDotPos) - 1)
						SET @sql = N'INSERT INTO ##restore_baseline_principals_' + @castedTempTableId + N'(dot_count, dot_pos, between_dot_count)
										VALUES (@dotCountIN, @dotPosIN, @betweenDotCountIN)'
						EXEC sp_executesql @sql, N'@dotCountIN int, @dotPosIN int, @betweenDotCountIN int', @dotCount, @dotPos, @betweenDotCount
					COMMIT TRAN;
				END;
				ELSE --Finds the first major version number and it's length
				BEGIN
					BEGIN TRAN findFirstDotPosition

						SET @majorVersionNbr = SUBSTRING(@restoreVersionPath, (PATINDEX('%[0123456789]%', @restoreVersionPath)),(@dotPos - (PATINDEX('%[0123456789]%', @restoreVersionPath))));
						SET @majorVersionLength = LEN(@majorVersionNbr);

						SET @sql = N'INSERT INTO ##restore_baseline_principals_' + @castedTempTableId + N'(dot_count, dot_pos)
										VALUES (@dotCountIN, @dotPosIN)'
						EXEC sp_executesql @sql, N'@dotCountIN int, @dotPosIN int', @dotCount, @dotPos;
					COMMIT TRAN;
				END;
			END;
			ELSE
				SET @dotPos = @eof;
		END;
	END;

	/*
	**	We now need to find the remaining version numbers.  If no dots were found then we simply find the first number in the string
	**	and try to match that to a version number. 
	*/
	BEGIN
		
		IF @dotCount > 0
		BEGIN

			IF @dotCount > 3
				SET @dotCount = 3; --We don't care about anything after the third dot

			SET @currentVersionOrder =
			CASE
				WHEN @dotCount = 3
					THEN 3
				WHEN @dotCount = 2
					THEN 2
				WHEN @dotCount = 1
					THEN 1
				ELSE 0
			END;
			SET @versionOrder =
			CASE
				WHEN @currentVersionOrder = 3
					THEN 'patch_version_order'
				WHEN @currentVersionOrder = 2
					THEN 'minor_version_order'
				WHEN @currentVersionOrder = 1
					THEN 'major_version_order'
				ELSE ''
			END;

			SET @sql = N'SET @dotPosIN = (SELECT dot_pos FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count = @dotCountIN)'
			EXEC sp_executesql @sql, N'@dotPosIN int OUTPUT, @dotCountIN int', @dotPos OUTPUT, @dotCount;

			SET @patchVersionNbr = SUBSTRING(@restoreVersionPath, @dotPos + 1, LEN(@restoreVersionPath))
			SET @patchNonNumberPos = PATINDEX('%[^0123456789]%', @patchVersionNbr)
	
			IF @patchNonNumberPos = 0
				SET @patchVersionNbr = SUBSTRING(@patchVersionNbr, 1, LEN(@patchVersionNbr))
			ELSE
				SET @patchVersionNbr = SUBSTRING(@patchVersionNbr, 1, @patchNonNumberPos - 1)

			SET @patchVersionLength = LEN(@patchVersionNbr)
		END;
		ELSE
			SELECT @majorVersionLength = 0
					,@patchVersionLength = 0
					,@currentVersionOrder = 1
					,@versionOrder = 'major_version_order';
	END;

	/*
	**	We find the dot count and total length of the version number and then find that actual version number
	*/
	BEGIN

		SET @sql = N'SET @restoreVersionPrecisionIN = ((SELECT SUM(between_dot_count) FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count <= 3 AND between_dot_count is not null) + @dotCountIN);';
		EXEC sp_executesql @sql, N'@restoreVersionPrecisionIN int OUTPUT, @dotCountIN int', @restoreVersionPrecision OUTPUT, @dotCount;

		IF @restoreVersionPrecision is null
			SET @restoreVersionPrecision = 1;

		SET @restoreVersionPrecision = @restoreVersionPrecision + @majorVersionLength + @patchVersionLength;
		SET @restoreVersionPath = SUBSTRING(@restoreVersionPath, (PATINDEX('%[0123456789]%', @restoreVersionPath)), @restoreVersionPrecision) --The actual entered version
		
		SET @printMessage = '	Trying to find version "' + @restoreVersionPath + '" in baseline database';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END;

	/*
	**	Now try to find a match in the baseline_version table
	*/
	BEGIN

		SET @sql = N'SET @dotPosIN = (SELECT dot_pos FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count = @dotCountIN);'; --This is simply precautionary.  Resetting the @dotPos parameter to the value of the highest @dotCount.  The @dotPos parameter should already be set to this, but we are resetting it just in case
		EXEC sp_executesql @sql, N'@dotPosIN int OUTPUT, @dotCountIN int', @dotPos OUTPUT, @dotCount;

		WHILE @versionMatch = 0
		BEGIN

			SET @sql = N'IF EXISTS (SELECT 1 FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%''))
							SET @versionMatchIN = 1'
			EXEC sp_executesql @sql, N'@restoreVersionPathIN nvarchar(4000), @versionMatchIN int OUTPUT', @restoreVersionPath, @versionMatch OUTPUT;
			IF @versionMatch = 1 --A match was found
			BEGIN

				SET @sql = N'SELECT @restoreVersionPathIN = (SELECT TOP(1) backup_path FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC)
									,@restoreVersionIN = (SELECT TOP(1) baseline_version FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC)
									,@isAvailableIN = (SELECT TOP(1) is_available FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC);';
				EXEC sp_executesql @sql, N'@restoreVersionPathIN nvarchar(4000) OUTPUT, @restoreVersionIN nvarchar(64) OUTPUT, @isAvailableIN bit OUTPUT', @restoreVersionPath OUTPUT, @restoreVersion OUTPUT, @isAvailable OUTPUT;
				GOTO returnMessage;
			END;

			SET @lastDeletedChar = SUBSTRING(@restoreVersionPath, (LEN(@restoreVersionPath)), 1);
			SET @restoreVersionPath = SUBSTRING(@restoreVersionPath, 1, @dotPos - @count)
			SET @count = @count + 1

			IF CHARINDEX('.',@lastDeletedChar) > 0 --We couldn't find a match on the patch, minor, or major version.  Trying to find a match on the next most specific version type (major or minor)
				SET @currentVersionOrder = @currentVersionOrder - 1;

			IF @restoreVersionPath is null
				GOTO returnMessage;

			IF @currentVersionOrder = 0
				GOTO returnMessage;

			SET @versionOrder =
			CASE
				WHEN @currentVersionOrder = 3
					THEN 'patch_version_order'
				WHEN @currentVersionOrder = 2
					THEN 'minor_version_order'
				WHEN @currentVersionOrder = 1
					THEN 'major_version_order'
				ELSE 'major_version_order'
			END;
		END;
	END;

	/*
	**	Return a message based on what we found.
	*/
	BEGIN

		returnMessage:
		SET @printMessage =
		CASE
			WHEN @count > 1 AND @dotCount = 3 AND @restoreVersionPath is not null AND @patchVersionLength > 0 AND @versionMatch = 1 --The entire version number was provided but a match was not found immedately.  Found a mismatched patch version number
				THEN '	Found match with mismatched patch version number, taking highest patch version: ' + @restoreVersion
			WHEN @count > 1 AND @dotCount = 2 AND @restoreVersionPath is not null AND @versionMatch = 1 --The patch version number was not provided and a match was not found.  Found a mismatched minor version number
				THEN '	Found match with mismatched minor version number, taking highest minor & patch version: ' + @restoreVersion
			WHEN @count > 1 AND @dotCount = 1 AND @restoreVersionPath is not null AND @versionMatch = 1 --The minor versio number was not provided and a match was not found.  Found a mismatched major version number
				THEN '	Found match with mismatched major version number, taking highest major, minor, & patch version: ' + @restoreVersion

			WHEN @count > 1 AND @currentVersionOrder = 3 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched patch version number, taking highest patch version: ' + @restoreVersion
			WHEN @count > 1 AND @currentVersionOrder = 2 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched minor version number, taking highest minor & patch version: ' + @restoreVersion
			WHEN @count > 1 AND @currentVersionOrder = 1 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched major version number, taking highest major, minor, & patch version: ' + @restoreVersion

			WHEN @count = 1 AND @dotCount = 3 AND @restoreVersionPath is not null AND @patchVersionLength > 0 AND @versionMatch = 1 --The entire version number was provided and we immediately found a match (exact match)
				THEN '	Found match on exact version: ' + @restoreVersion
			WHEN @count = 1 AND @dotCount = 2 AND @restoreVersionPath is not null AND @versionMatch = 1 --The patch version number was not provided, but a match was found immediately
				THEN '	Found match on exact version with patch version number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @dotCount = 1 AND @restoreVersionPath is not null AND @versionMatch = 1 --The minor version number was not provided, but a match was found immediately
				THEN '	Found match on exact version with minor version number missing, taking highest minor & patch version: ' + @restoreVersion

			WHEN @count = 1 AND @currentVersionOrder = 3 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with patch number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @currentVersionOrder = 2 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with minor version number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @currentVersionOrder = 1 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with major version number missing, taking highest minor & patch version: ' + @restoreVersion

			ELSE '	Could not find any match.. Try harder'
		END;

		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END;

	/*
	**	This creates a common table expression that orders all the baseline_versions by one keyed field.  It then finds the
	**	next available version among the keyed fields
	*/
	BEGIN

		IF @isAvailable = 0
		BEGIN

			RAISERROR('	A version was found (see above) but is not available, finding next available version', 10, 1) WITH NOWAIT;
			SET @count = 1 --Reset @count
		END;

		WHILE @isAvailable = 0
		BEGIN

			WITH available_version_CTE (keyed_baseline, baseline_version, backup_path, is_available)
			AS (
				SELECT ROW_NUMBER() OVER (ORDER BY major_version_order, minor_version_order, patch_version_order) [keyed_baseline], baseline_version, backup_path, is_available
				FROM dbAdmin.dbo.baseline_versions
			)

			SELECT @restoreVersionPath = (SELECT backup_path FROM available_version_CTE WHERE keyed_baseline = ((SELECT keyed_baseline FROM available_version_CTE WHERE baseline_version = @restoreVersion) + @count) AND is_available = 1)
					,@restoreVersion = (SELECT baseline_version FROM available_version_CTE WHERE keyed_baseline = ((SELECT keyed_baseline FROM available_version_CTE WHERE baseline_version = @restoreVersion) + @count) AND is_available = 1);

			IF @restoreVersionPath is not null
			BEGIN

				SET @printMessage = '	The next available version is: ' + @restoreVersion
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

				SET @isAvailable = 1
			END;

			SET @count = @count + 1;
		END;
	END;

	IF @versionMatch = 1
		RAISERROR('Baseline database found', 10, 1) WITH NOWAIT;
	ELSE
		RAISERROR('No vaild baseline versions were found, unable to perform restore', 16, 1) WITH LOG;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER();

	RAISERROR(@errorMessage, @errorSeverity, 1);
	RETURN -1;
END CATCH;
GO


