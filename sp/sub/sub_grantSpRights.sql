/*
**	This stored procedure grants rights to THINK Enterprise stored procedures to SQL users in a given database.  This sp is a sub stored procedure.  It is not meant to be
**	called directly but through a user stored procedure.  The sp takes the name of a database and an ad-hoc generated ID provided by the USP.  It grants rights to the users
**	in the provided database.  
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_grantSpRights')
	DROP PROCEDURE [dbo].[sub_grantSpRights];
GO

CREATE PROCEDURE [dbo].[sub_grantSpRights](
	@spGrantDbName		nvarchar(128)	--Required:	The name of the database where sp rights will be modified.  This must be a THINK Enterprise database.
	,@tempTableId		int				--Required:	Unique ID that is appended to temporary tables.
	,@spGrantDebug		nchar(1) = 'n'	--Optional: When set, returns additional debugging information to diagnose errors.
)

AS
SET NOCOUNT ON;

DECLARE @dbProcName		sysname	--Name of the stored procedure that a set of users will be granted access to.
		,@sqlOUT		nvarchar(max)
		,@sql			nvarchar(4000)
		,@printMessage	nvarchar(4000)
		,@errorMessage	nvarchar(4000)
		,@errorSeverity	int
		,@errorNumber	int
		,@errorLine		int
		,@errorState	int;

BEGIN TRY

	/*
	**	Creates a temporary table that will list all the users that will be granted rights to the stored procedures.
	*/
	SET @sql = N'CREATE TABLE ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
					cursor_id		int identity(1,1) primary key	not null
					,database_name	nvarchar(128)					not null
					,user_name		nvarchar(256)					not null
				);';
	EXEC sp_executesql @sql;

	/*
	**	This dynamic SQL statement creates several INSERT statements that inserts data into the temp table created above.  The data inserted is a list of users pulled from
	**	the sys.database_principals system table and cross referenced with the sys.server_principals system table.  This means that only SQL users that have associated
	**	server logins will be granted rights to the stored procedures.
	*/
	SET @sql = N'USE ' + QUOTENAME(@spGrantDbName) + ';' + char(13) + char(10) +
				N'INSERT INTO ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, user_name)
					SELECT ''' + @spGrantDbName + N''' [database_name], dp.name [user_name]
					FROM sys.database_principals dp
						INNER JOIN sys.server_principals sp
							ON dp.sid = sp.sid
					WHERE dp.name not in (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
						AND sp.name != ''thkapp'';';
	EXEC sp_executesql @sql;

	BEGIN TRAN resetStoredProcRights

		/*
		**	db_stored_proc_rights is a table in the meta database that houses the list of THINK Enterprise stored procedures.  The database lists stored procedures
		**	that are not necessarily available in every THINK Enterprise version.  The is_applicable column is used to set which stored procedures are applicable to the
		**	particular database being affected.  However, before this is done, any previous changes to the column are wiped out to start fresh.
		*/
		UPDATE db_stored_proc_rights
		SET is_applicable = null;

		/*
		**	Match the stored procedures that are available in the database with stored procedures that are available in the meta database by cross referencing the
		**	sys.procedures system table with the meta database.
		*/
		SET @sql = N'UPDATE db_stored_proc_rights
					SET is_applicable = 1
					FROM dbAdmin..db_stored_proc_rights dspr
						INNER JOIN ' + QUOTENAME(@spGrantDbName) + N'.sys.procedures sp
							ON sp.name COLLATE SQL_Latin1_General_CP850_CI_AS = dspr.stored_proc;'
		EXEC sp_executesql @sql;
	COMMIT TRAN;

	BEGIN TRAN alterSpRights

		/*
		**	This dynamic SQL statement creates several GRANT EXECUTE and GRANT VIEW DEFINITION statements (all held in @sqlOUT).  A GRANT EXECUTE and GRANT VIEW DEFINITION
		**	statements are used to actually grant rights to the stored procedures in the database.
		*/
		SET @sql = N'SET @sqlIN = ''''

					SELECT @sqlIN = @sqlIN + N''GRANT EXECUTE ON [dbo].['' + dspr.stored_proc + N''] TO ['' + tempgsr.user_name + N''];'' + char(13) + char(10)
					FROM dbAdmin..db_stored_proc_rights dspr, ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempgsr
					WHERE dspr.is_applicable = 1
					ORDER BY tempgsr.user_name;

					SELECT @sqlIN = @sqlIN + N''GRANT VIEW DEFINITION ON [dbo].['' + dspr.stored_proc + N''] TO ['' + tempgsr.user_name + N''];'' + char(13) + char(10)
					FROM dbAdmin..db_stored_proc_rights dspr, ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempgsr
					WHERE dspr.is_applicable = 1
					ORDER BY tempgsr.user_name;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(MAX) OUTPUT', @sqlOUT OUTPUT;

		SET @sqlOUT = N'USE ' + QUOTENAME(@spGrantDbName) + char(13) + char(10) + @sqlOUT; --Pad the @sqlOUT variable with proper syntax.
		EXEC sp_executesql @sqlOUT;
	COMMIT TRAN;

	SET @sql = N'DROP TABLE ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @spGrantDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_grantSpRights sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = 'IF object_id(''tempdb..##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##grant_sp_rights_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;