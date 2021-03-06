USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'adm_cleanAllLogs')
	DROP PROCEDURE [dbo].[adm_cleanAllLogs]
GO

CREATE PROCEDURE [dbo].[adm_cleanAllLogs] (
	@truncateDbName	nvarchar(128) = null
	,@targetSize	int = 0
) WITH EXECUTE AS OWNER
AS

DECLARE @filename				nvarchar(1024)
		,@definedTempTableId	int
		,@castedTempTableId		varchar(16)
		,@sql					nvarchar(4000)
		,@sqlOUT				nvarchar(max)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorNumber			int;

SET NOCOUNT ON;

BEGIN TRY

	/*
	**	Step 1: pull temp table ID
	*/
	BEGIN
		BEGIN TRAN

			SELECT @definedTempTableId = CAST((SELECT p_value FROM params WITH (ROWLOCK, HOLDLOCK) WHERE p_key = 'tempTableId') AS int);
			SET @definedTempTableId = @definedTempTableId + 1;

			UPDATE params WITH (ROWLOCK, HOLDLOCK)
			SET p_value = CAST(@definedTempTableId AS varchar(20))
			WHERE p_key = 'tempTableId'
		COMMIT TRAN;

		SET @castedTempTableId = CAST(@definedTempTableId AS varchar(16))
	END;

	/*
	**	Step 2: Create temp table and insert all THINK Enterprise databases into the table
	*/
	BEGIN

		SET @sql = N'CREATE TABLE ##all_database_admin_' + @castedTempTableId + N' (
						truncate_id		int identity(1000,1)	not null
						,database_id	int						not null
						,database_name	sysname					not null
						,filename		nvarchar(1024)			not null
						
						,CONSTRAINT PK_TEMP_ALL_DATABASE_ADMIN_' + @castedTempTableId + N' PRIMARY KEY CLUSTERED (
							truncate_id
						)
					);';
		EXEC sp_executesql @sql;

		SET @sql = N'INSERT INTO ##all_database_admin_' + @castedTempTableId + N' (database_id, database_name, filename)
						SELECT d.database_id, d.name [database_name], mf.name [filename]
								FROM sys.databases d
									INNER JOIN sys.master_files mf
										ON mf.database_id = d.database_id
								WHERE d.name not in (''master'', ''tempdb'', ''model'', ''msdb'', ''dbAdmin'', ''ReportServer$SUPPORT'', ''ReportServer$SUPPORTTempDB'')
									AND mf.type_desc = ''LOG''
									AND d.state = 0;';
		EXEC sp_executesql @sql;
	END;

	/*
	**	Step 3: Truncate log files
	*/
	BEGIN

		IF @truncateDbName is not null --A database name was provided, truncating log file of that database only
		BEGIN

			SET @filename = (SELECT TOP(1) mf.name FROM sys.master_files mf INNER JOIN sys.databases d ON d.database_id = mf.database_id WHERE d.name = @truncateDbName AND mf.type_desc = 'LOG')

			SET @sql = N'USE [master]
						ALTER DATABASE [' + @truncateDbName + '] SET RECOVERY SIMPLE WITH NO_WAIT;
						
						USE ' + QUOTENAME(@truncateDbName) + char(13) + char(10) +
						N'DBCC SHRINKFILE(N''' + @filename + ''', ' + CAST(@targetSize AS varchar(8)) + N');
						
						USE [master]
						ALTER DATABASE [' + @truncateDbName + '] SET RECOVERY FULL WITH NO_WAIT;'
			EXEC sp_executesql @sql
		END;
		ELSE
		BEGIN

			SET @sql = N'SET @sqlIN = ''''
						SELECT @sqlIN = @sqlIN + N''USE [master]
										ALTER DATABASE ['' + database_name + ''] SET RECOVERY SIMPLE WITH NO_WAIT;

										USE ['' + database_name + '']
										DBCC SHRINKFILE (N'''''' + filename + '''''', '' + CAST(@targetSizeIN AS varchar(8)) + '');

										USE [master]
										ALTER DATABASE ['' + database_name + ''] SET RECOVERY FULL WITH NO_WAIT;'' + char(13) + char(10) + char(13) + char(10)
						FROM ##all_database_admin_' + @castedTempTableId
			EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT, @targetSizeIN int', @sqlOUT OUTPUT, @targetSize
			EXEC sp_executesql @sqlOUT;
		END;
	END;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SET @sql = N'IF object_id (''tempdb..##all_database_admin_' + @castedTempTableId + N''') is not null
					DROP TABLE ##all_database_admin_' + @castedTempTableId
	EXEC sp_executesql @sql;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER();

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;