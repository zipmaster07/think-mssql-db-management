/*
**	This stored procedure returns a UNC path to a calling stored procedure.  This sp is a sub stored procedure.  It is not meant to be called directly but through a user
**	stored procedure.  The sp takes as input a THINK Enterprise version and then outputs (on the same variable) the path to a backup of that baseline version.  The sp
**	does not actually restore any databases.  It also takes an ad-hoc generated ID passed by a USP.  The sp is capable of dynamically figuring out a version number when
**	it is given a string (as it always is).  Since the string can have any number of character and any character type the sp starts by finding the first number in the
**	string and then methodically moves along the rest of the string finding dots (periods) in the string to help it determine exactly what version number the user wants to
**	restore.  The sp also makes sure that the requested baseline version (once found) is available for restore.  If a mistake is made in the version numbering, or if it is
**	simply not available the sp finds the next available version.  If a patch number is not available the sp finds the next highest patch version for the same major and
**	minor version numbers.  If a minor version is not available the sp finds the highest minor version with the highest patch number for the same major version number.  If
**	the major version number is not avaiable then the sp finds the next highest major version number along with its highest minor version and patch number.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_restoreBaseline')
	DROP PROCEDURE [dbo].[sub_restoreBaseline]
GO

CREATE PROCEDURE [dbo].[sub_restoreBaseline](
	@restoreVersionPath	nvarchar(4000) OUTPUT	--Required:	As input it is used to determine what baseline version is going to be restored, as output it is used to point to the location of the backup file for restore.
	,@tempTableId		int						--Required:	Unique ID that is appended to temporary tables.
	,@baselineDebug		nchar(1) = 'n'			--Optional: When set, returns additional debugging information to diagnose errors.
)
AS

DECLARE @restoreVersion				nvarchar(64)	--The baseline version found.
		,@sql						nvarchar(4000)
		,@count						int = 1			--Counter for any arbitrary number of operations.
		,@dotPos					int = 0			--Stores the current dot position.
		,@previousDotPos			int				--Stores the previous dot position.
		,@dotCount					int = 0			--Used to find how many dots are in a the @restoreVersionPath string.
		,@betweenDotCount			int				--Used to find how many characters are between dots.
		,@eof						int				--Length of the @restoreVersionPath variable.
		,@restoreVersionPrecision	int				--The length of the version number.
		,@versionMatch				bit = 0			--Indicates if a version has been found: 0 = not found, 1 = found.
		,@versionOrder				nvarchar(32)	--Specifies the current version level of detail based off the @currentVersionOrder parameter.
		,@currentVersionOrder		tinyint			--What part of the version are we trying to match on: 1 = major, 2 = minor, 3 = patch.
		,@lastDeletedChar			char(1)			--Stores the last deleted character from the version as a match is trying to be made.
		,@majorVersionNbr			nvarchar(16)	--The major version number.
		,@majorVersionLength		int				--The length of the major version number.
		,@patchVersionNbr			nvarchar(8)		--The patch version number.
		,@patchVersionLength		int				--The length of the patch version number.
		,@patchNonNumberPos			int				--The first non number position in the patch number.
		,@isAvailable				bit				--Checks if the version selected/found is available for restore.
		,@castedTempTableId			varchar(16)		--@tempTableId casted as a varchar.
		,@printMessage				nvarchar(4000)
		,@errorMessage				nvarchar(4000)
		,@errorSeverity				int
		,@errorNumber				int
		,@errorLine					int
		,@errorState				int;

SET NOCOUNT ON;

BEGIN TRY

	SET @printMessage = char(13) + char(10) + 'Finding baseline database'
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @castedTempTableId = CAST(@tempTableId AS varchar(16));

	/*
	**	This temporary table is used to help parse the input version number.  It finds all the dots in the string, their positions, and how many charaters are between each
	**	dot.
	*/
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

	BEGIN

		/*
		**	This while loop finds the major and minor version numbers and inserts key dot positions into the temp table.
		*/
		WHILE @dotPos < @eof
		BEGIN

			SET @previousDotPos = @dotPos --Keep track of the last known dot position.  For the first iteration no dot positions have been found and all values are set to 0.
			SET @dotPos = (CHARINDEX('.', @restoreVersionPath, (@dotPos + 1))); --Find the next dot position starting just after the current dot position.

			IF @dotPos > 0 --Only called if a dot is found since the previous dot position.  For the first iteration this only happens if at least one dot exists.  For all other iterations this only happens if a dot exists after the current dot.
			BEGIN

				SET @dotCount = @dotCount + 1; --Keeps track of all the dots found up to this point.
				IF @dotCount > 1 --Finds everything after the first major version number (excluding the actual patch number)
				BEGIN
					BEGIN TRAN findRemainingDotPositions
				
						SET @betweenDotCount = ((@dotPos - @previousDotPos) - 1) --Finds the length of characters between the current dot position and the previous dot position.
						SET @sql = N'INSERT INTO ##restore_baseline_principals_' + @castedTempTableId + N'(dot_count, dot_pos, between_dot_count)
										VALUES (@dotCountIN, @dotPosIN, @betweenDotCountIN)' --Inserts the current dot count, dot position, and length of characters between dot positions into the temp table.
						EXEC sp_executesql @sql, N'@dotCountIN int, @dotPosIN int, @betweenDotCountIN int', @dotCount, @dotPos, @betweenDotCount
					COMMIT TRAN;
				END;
				ELSE --Finds the first major version number and it's length
				BEGIN
					BEGIN TRAN findFirstDotPosition

						/*
						**	This sets the @majorVersionNbr variable to the first number in the string up to the first dot in the string.  For example: given abc78.123.456
						**	the @majorVersionNbr would get set to 78 as 7 is the first numeric value and 8 is the last value before the first dot.  Technially it sets the
						**	variable up to the current dot position, but this portion of the code is only called for the first dot.
						*/
						SET @majorVersionNbr = SUBSTRING(@restoreVersionPath, (PATINDEX('%[0123456789]%', @restoreVersionPath)),(@dotPos - (PATINDEX('%[0123456789]%', @restoreVersionPath))));
						SET @majorVersionLength = LEN(@majorVersionNbr);

						SET @sql = N'INSERT INTO ##restore_baseline_principals_' + @castedTempTableId + N'(dot_count, dot_pos)
										VALUES (@dotCountIN, @dotPosIN)' --Inserts the current dot count and dot position into the temp table.
						EXEC sp_executesql @sql, N'@dotCountIN int, @dotPosIN int', @dotCount, @dotPos;
					COMMIT TRAN;
				END;
			END;
			ELSE
				SET @dotPos = @eof;
		END;
	END;

	/*
	**	We now need to find the remaining version numbers.  If no dots were found then we simply find the first number in the string and try to match that to a version
	**	number. 
	*/
	BEGIN
		
		IF @dotCount > 0 --Were dots found?
		BEGIN

			IF @dotCount > 3
				SET @dotCount = 3; --We don't care about anything after the third dot

			/*
			**	Specifies the precision of the input version based on how many dots were provided and then sets the @versionOrder string accordingly.
			*/
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

			/*
			**	Using dynamic SQL to find the the dot position based on the precision that was determined above.  @dotCount holds how precise the version provide is (major
			**	only, major + minor, full version number, etc).  The temp tables stores a relationship between where certain characters are and their dot positions based
			**	off of the dot count.
			*/
			SET @sql = N'SET @dotPosIN = (SELECT dot_pos FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count = @dotCountIN)'
			EXEC sp_executesql @sql, N'@dotPosIN int OUTPUT, @dotCountIN int', @dotPos OUTPUT, @dotCount;

			SET @patchVersionNbr = SUBSTRING(@restoreVersionPath, @dotPos + 1, LEN(@restoreVersionPath)) --Pulls the last set of characters (later refined to just numbers) after the last applicable dot.
			SET @patchNonNumberPos = PATINDEX('%[^0123456789]%', @patchVersionNbr) --Finds the first non numeric character after in the patchVersionNbr.
	
			IF @patchNonNumberPos = 0 --There are not non numeric characters in @patchVersionNbr.
				SET @patchVersionNbr = SUBSTRING(@patchVersionNbr, 1, LEN(@patchVersionNbr))
			ELSE
				SET @patchVersionNbr = SUBSTRING(@patchVersionNbr, 1, @patchNonNumberPos - 1) --Set the patchVersionNbr to the actual numeric characters in @patchVersionNbr.

			SET @patchVersionLength = LEN(@patchVersionNbr)
		END;
		ELSE --If no dots were found
			SELECT @majorVersionLength = 0
					,@patchVersionLength = 0
					,@currentVersionOrder = 1
					,@versionOrder = 'major_version_order';
	END;

	/*
	**	We find the dot count and total length of the version number and then set the actual version number.
	*/
	BEGIN

		/*
		**	This pulls the length version number between major version and patch number (a.k.a. the minor version).
		*/
		SET @sql = N'SET @restoreVersionPrecisionIN = ((SELECT SUM(between_dot_count) FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count <= 3 AND between_dot_count is not null) + @dotCountIN);';
		EXEC sp_executesql @sql, N'@restoreVersionPrecisionIN int OUTPUT, @dotCountIN int', @restoreVersionPrecision OUTPUT, @dotCount;

		IF @restoreVersionPrecision is null --Only the major version was provided, which puts a NULL value in the between_dot_count column of the temp table.  If this is the only value in the table then set @restoreVersionPrecision to 1.
			SET @restoreVersionPrecision = 1;

		SET @restoreVersionPrecision = @restoreVersionPrecision + @majorVersionLength + @patchVersionLength; --Length of the major version + length of the minor version + length of the patch number.
		SET @restoreVersionPath = SUBSTRING(@restoreVersionPath, (PATINDEX('%[0123456789]%', @restoreVersionPath)), @restoreVersionPrecision) --@restoreVersionPath is finally overwritten with the actual version.
		
		SET @printMessage = '	Trying to find version "' + @restoreVersionPath + '" in baseline database';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END;

	/*
	**	Now try to find a match in the meta database.
	*/
	BEGIN

		/*
		**	This is simply precautionary.  Resetting the @dotPos parameter to the value of the highest @dotCount.  The @dotPos parameter should already be set to this, but
		**	we are resetting it just in case.
		*/
		SET @sql = N'SET @dotPosIN = (SELECT dot_pos FROM ##restore_baseline_principals_' + @castedTempTableId + N' WHERE dot_count = @dotCountIN);';
		EXEC sp_executesql @sql, N'@dotPosIN int OUTPUT, @dotCountIN int', @dotPos OUTPUT, @dotCount;

		/*
		**	Loops at least once.  This while loop trys to find a matching version while removing the least important digit from the version.  The first iteration tries to
		**	find a match based on the entire version number provided.  It then removes a digit from the end of the version and tries again.  If it still cannot find a match
		**	it continues removing digits one-by-one.
		*/
		WHILE @versionMatch = 0
		BEGIN

			/*
			**	Now that a version number has been determined, we have to check to see if it is available for restore.  This serves two purposes: The user may have entered
			**	a nonexistent version or entered a version that is not avaiable (as not all are).  This queries the meta database to see if any records are returned from a
			**	search like the version the user provided.  It also matches the highest precision version that was given.  For example if the patch number was provided then
			**	the sp tries to match exactly on that patch number, however if it wasn't provided then it tries to match on the highest patch number available.  This dynamic
			**	SQL query can, and usually does, return multiple results.  At this point we are just checking to see if any versions match.  The actual version that is used
			**	for restore is determined later.
			*/
			SET @sql = N'IF EXISTS (SELECT 1 FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%''))
							SET @versionMatchIN = 1'
			EXEC sp_executesql @sql, N'@restoreVersionPathIN nvarchar(4000), @versionMatchIN int OUTPUT', @restoreVersionPath, @versionMatch OUTPUT;

			IF @versionMatch = 1 --A match was found
			BEGIN

				/*
				**	At this point we know a match was found now all we have to do is determine which records to pull from the list of matches.  The query below is almost
				**	identical to the one above, however this time we are specifically pulling data from the temp table, as opposed to just checking if data is returned at
				**	all, and we are only pulling the top result from the result set.  This means that we are only pulling the highest version match from the list of results.
				**	In addition to the version we return, we also return the path to the backup for that version and if it is available.
				*/
				SET @sql = N'SELECT @restoreVersionPathIN = (SELECT TOP(1) backup_path FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC)
									,@restoreVersionIN = (SELECT TOP(1) baseline_version FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC)
									,@isAvailableIN = (SELECT TOP(1) is_available FROM dbAdmin.dbo.baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'' AND ' + @versionOrder + N' = (SELECT MAX(' + @versionOrder + N') FROM baseline_versions WHERE baseline_version LIKE @restoreVersionPathIN + ''%'') ORDER BY major_version_order DESC, minor_version_order DESC, patch_version_order DESC);';
				EXEC sp_executesql @sql, N'@restoreVersionPathIN nvarchar(4000) OUTPUT, @restoreVersionIN nvarchar(64) OUTPUT, @isAvailableIN bit OUTPUT', @restoreVersionPath OUTPUT, @restoreVersion OUTPUT, @isAvailable OUTPUT;
				GOTO returnMessage;
			END;

			/*
			**	If no match was found then start removing the least important digit from the version and try again.
			*/
			SET @lastDeletedChar = SUBSTRING(@restoreVersionPath, (LEN(@restoreVersionPath)), 1); --Store the removed digit in a variable.
			SET @restoreVersionPath = SUBSTRING(@restoreVersionPath, 1, @dotPos - @count) --This is the first place @count is used, it is initially set to 1.
			SET @count = @count + 1

			IF CHARINDEX('.',@lastDeletedChar) > 0 --We couldn't find a match on the patch, minor, or major version.  Trying to find a match on the next most specific version type (major or minor)
				SET @currentVersionOrder = @currentVersionOrder - 1;

			IF @restoreVersionPath is null --Couldn't match on any number provided, immediately jump to returnMessage marker.
				GOTO returnMessage;

			IF @currentVersionOrder = 0 --Couldn't match on any number provided, immediately jump to returnMessage marker.
				GOTO returnMessage;

			SET @versionOrder = --Update the versionOrder based on the currentVersionOrder, then try searching again.
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

		returnMessage: --GOTO marker to return the correct message.
		SET @printMessage =
		CASE
			WHEN @count > 1 AND @dotCount = 3 AND @restoreVersionPath is not null AND @patchVersionLength > 0 AND @versionMatch = 1	--The entire version number was provided but a match was not found immedately.  Found a mismatched patch version number.
				THEN '	Found match with mismatched patch version number, taking highest patch version: ' + @restoreVersion
			WHEN @count > 1 AND @dotCount = 2 AND @restoreVersionPath is not null AND @versionMatch = 1								--The patch version number was not provided and a match was not found.  Found a mismatched minor version number.
				THEN '	Found match with mismatched minor version number, taking highest minor & patch version: ' + @restoreVersion
			WHEN @count > 1 AND @dotCount = 1 AND @restoreVersionPath is not null AND @versionMatch = 1								--The minor version number was not provided and a match was not found.  Found a mismatched major version number.
				THEN '	Found match with mismatched major version number, taking highest major, minor, & patch version: ' + @restoreVersion

			WHEN @count > 1 AND @currentVersionOrder = 3 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched patch version number, taking highest patch version: ' + @restoreVersion
			WHEN @count > 1 AND @currentVersionOrder = 2 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched minor version number, taking highest minor & patch version: ' + @restoreVersion
			WHEN @count > 1 AND @currentVersionOrder = 1 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match with mismatched major version number, taking highest major, minor, & patch version: ' + @restoreVersion

			WHEN @count = 1 AND @dotCount = 3 AND @restoreVersionPath is not null AND @patchVersionLength > 0 AND @versionMatch = 1	--The entire version number was provided and we immediately found a match (exact match).
				THEN '	Found match on exact version: ' + @restoreVersion
			WHEN @count = 1 AND @dotCount = 2 AND @restoreVersionPath is not null AND @versionMatch = 1								--The patch version number was not provided, but a match was found immediately.
				THEN '	Found match on exact version with patch version number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @dotCount = 1 AND @restoreVersionPath is not null AND @versionMatch = 1								--The minor version number was not provided, but a match was found immediately.
				THEN '	Found match on exact version with minor version number missing, taking highest minor & patch version: ' + @restoreVersion

			WHEN @count = 1 AND @currentVersionOrder = 3 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with patch number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @currentVersionOrder = 2 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with minor version number missing, taking highest patch version: ' + @restoreVersion
			WHEN @count = 1 AND @currentVersionOrder = 1 AND @restoreVersionPath is not null AND @versionMatch = 1
				THEN '	Found match on exact version with major version number missing, taking highest minor & patch version: ' + @restoreVersion

			ELSE '	Could not find any match.. Try harder'																			--Couldn't find any match.
		END;

		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END;

	/*
	**	This creates a common table expression that orders all the baseline_versions by one keyed field.  It then finds the next available version among the keyed fields.
	*/
	BEGIN

		IF @isAvailable = 0 --Now that a version is found that has a corresponding record in the meta database, we need to check if it is actually available.
		BEGIN

			RAISERROR('	A version was found (see above) but is not available, finding next available version', 10, 1) WITH NOWAIT;
			SET @count = 1 --Reset @count.
		END;

		WHILE @isAvailable = 0
		BEGIN

			WITH available_version_CTE (keyed_baseline, baseline_version, backup_path, is_available)
			AS (
				SELECT ROW_NUMBER() OVER (ORDER BY major_version_order, minor_version_order, patch_version_order) [keyed_baseline], baseline_version, backup_path, is_available
				FROM dbAdmin.dbo.baseline_versions --Create an ad-hoc primary key for the CTE called "keyed_baseline" then populate the other columns from the meta database.
			)

			SELECT @restoreVersionPath = (SELECT backup_path FROM available_version_CTE WHERE keyed_baseline = ((SELECT keyed_baseline FROM available_version_CTE WHERE baseline_version = @restoreVersion) + @count) AND is_available = 1) --Pulls the next available version's path.
					,@restoreVersion = (SELECT baseline_version FROM available_version_CTE WHERE keyed_baseline = ((SELECT keyed_baseline FROM available_version_CTE WHERE baseline_version = @restoreVersion) + @count) AND is_available = 1); --Pulls the next available version.

			IF @restoreVersionPath is not null --If another version was available then display a message to the user and end the loop.
			BEGIN

				SET @printMessage = '	The next available version is: ' + @restoreVersion
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

				SET @isAvailable = 1
			END;

			SET @count = @count + 1; --Increment count and try the next record from the meta database.
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
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @baselineDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_restoreBaseline sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	RAISERROR(@errorMessage, @errorSeverity, 1);
	RETURN -1;
END CATCH;
GO


