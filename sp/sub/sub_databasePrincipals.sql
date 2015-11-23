/*
**	This stored procedure adds and removes database principals including SQL users, roles, other stored procedures, schemas, views, etc.  This sp is a sub stored procedure.
**	It is not meant to be called directly but through a user stored procedure.  The sp takes the name of a database, a user defined value, and an ad-hoc generated ID passed
**	by a USP.  The database name is used to connect to the database to modify and view all of its principals.  The user defined value must be set to a specific value.
**	This value is not checked here, but in the calling procedure.  The value determines specific portions of code that run in the sp.  Depending on the code that is passed
**	The sp may delete current database principals, store them in a temporary table, or create principals based off of a template stored in the meta database.  The
**	ah-hoc ID is used to create unique temporary tables.
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_databasePrincipals')
	DROP PROCEDURE [dbo].[sub_databasePrincipals];
GO

CREATE PROCEDURE [dbo].[sub_databasePrincipals] (
	@principalDbName	nvarchar(128)	--Required:	The name of the database whose principals will be deleted/modifed/stored/created in/etc.
	,@gatherUsers		tinyint			--Required:	Value to specify which portion of code needs to run under the sp.  0 = find and store current principals in a temp table, 1 = delete all principals, 2 = add principals from template, 3 = add principals from a previously generated temp table.
	,@tempTableId		int				--Required: Unique ID that is appended to temporary tables.
	,@principalDebug	nchar(1) = 'n'	--Optional: When set, returns additional debugging information to diagnose errors.
)
AS
SET NOCOUNT ON

DECLARE @rowModified	int				--Used to stored the @@rowcount variable after a DML statment.
		,@sql			nvarchar(4000)
		,@sqlOUT		nvarchar(max)
		,@printMessage	nvarchar(4000)
		,@errorMessage	nvarchar(4000)
		,@errorSeverity	int
		,@errorNumber	int
		,@errorLine		int
		,@errorState	int;

BEGIN TRY

	/*
	**	create a temporary table called db_principals_00 where "00" is replaced by the tempTableId.  The temporary table is populated with various data from the database
	**	that is passed to the sp.
	*/
	SET @sql = N'IF object_id (''tempdb..##db_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is null
				BEGIN
					CREATE TABLE ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N'(
						cursor_id			int identity(1,1) primary key	not null
						,database_name		nvarchar(128)					not null
						,login_name			nvarchar(256)					null
						,user_name			nvarchar(256)					null
						,principal_type		nvarchar(2)						null
						,default_schema		nvarchar(256)					null
						,gather_users		tinyint							null
						,clear_users		tinyint							null
						,add_users_gathered	tinyint							null
						,add_users_std		tinyint							null
					);
				END;';
	EXEC sp_executesql @sql;

	/*
	**	This portion of the code is used to find users and other database principals in the original database (before restoring over it), and stores them in the temp table.
	**	When this portion is run the USP should call this sp again after forcefully changing the @gatherUsers parameter to 3.  This will Then restore the users gathered
	**	here to the restored database.
	*/
	IF @gatherUsers = 0
	BEGIN

		SET @printMessage = 'Gathering users before database is restored over';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		/*
		**	This statement populates the prevously created temporary table with data from the sys.database_principals and sys.server_principals database system tables.
		**	It specifically pulls SQL users from the database.  It does not pull schemas or roles, this information is lost.  It also avoids pulling system generated
		**	users (dbo, guest, sys, etc).
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + ';' + char(13) + char(10) +
					N'INSERT INTO ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, login_name, user_name, principal_type, add_users_gathered)
					SELECT ''' + @principalDbName + N''' [database_name], sp.name [login_name], dp.name [user_name], sp.type [principal_type], 1 [add_users_gathered]
					FROM sys.database_principals dp
						INNER JOIN sys.server_principals sp
							ON dp.sid = sp.sid
					WHERE dp.name not in (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')';
		EXEC sp_executesql @sql;
	END
	/*
	**	This portion of the code is used to wipe out all users and other database principals from the restored database, regardless of which users had access (a.k.a.
	**	starting fresh).  This portion should never be called if @gatherUsers is set to 0, it should be entirely skipped over (the two portions are mutually exlusive). It
	**	is common to have the calling sp call this sub sp again after forcefully changing the @gatherUsers parameter to 2.  Although this is a typical use case it is
	**	not required.  This portion of the code can be used to simply wipe the database of any principals and leave it in a "cleaned" state.
	*/
	ELSE IF @gatherUsers = 1
	BEGIN
		
		SET @printMessage =  'Cleaning SQL Users from restored database:'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		/*
		**	This statement populates the previously created temporary table with data from the sys.database_principals and sys.schemas database system tables.  It
		**	specifically pulls SQL users, their types, and their associated schemas.  It does not directly pull user roles, althought his information is determined later
		**	on by cross querying these results with other system tables.  The statement avoids pulling system generated users (dbo, guest, sys, etc) and other non users
		**	that have fixed roles (db_accessadmin, db_datareader, etc).
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'INSERT INTO ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, user_name, principal_type, default_schema, clear_users)
					SELECT ''' + @principalDbName + N''' [database_name], dp.name [user_name], dp.type [principal_type], s.name [default_schema], 1 [clear_users]
					FROM sys.database_principals dp
						LEFT OUTER JOIN sys.schemas s
							ON dp.principal_id = s.principal_id
					WHERE dp.type in (''S'', ''U'', ''R'', ''G'')
						AND dp.name not in (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'', ''public'')
						AND dp.is_fixed_role = 0
					ORDER BY type;';
		EXEC sp_executesql @sql;

		/*
		**	Start by dropping the associated schema views of non THINK Enterprise schemas.
		**	
		**	This dynamic SQL statement creates several INSERT statements (all contained in the @sqlOUT variable).  The INSERT statement inserts data into the temporary
		**	table.  The data it inserts is pulled from the previous SQL statement.  It pulls data from the temp table, uses that data to determine what are non THINK
		**	Enterprise views, and then inserts the new data into the same temp table.
		*/
		SET @sql = 'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '''''' + default_schema + N'''''' AND TABLE_TYPE = ''''VIEW'''')
									BEGIN
									INSERT INTO ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, default_schema, gather_users)
										VALUES (''''' + @principalDbName + N''''', '''''' + default_schema + N'''''', 1);
									END;'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE default_schema is not null
						AND default_schema != ''dbo''
						AND clear_users = 1
					ORDER BY user_name;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT

		SET @sqlOUT = 'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the INSERT statements with proper SQL syntax.
		EXEC (@sqlOUT);
		SET @rowModified = @@ROWCOUNT

		IF @rowModified > 0 --Tell the user if any any associated views were found.
		BEGIN
			SET @printMessage =  '	Collecting dependant schema views to drop';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several DROP VIEW statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross referencing
		**	data from the temp table with data in the actual database.  The temp table already holds all the non THINK Enterprise views.
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''DROP VIEW ['' + default_schema COLLATE SQL_Latin1_General_CP850_CI_AS + N''].['' + ist.TABLE_NAME + N''];'' + char(13) + char(10)
					FROM INFORMATION_SCHEMA.TABLES ist
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = ist.TABLE_SCHEMA COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE dbp.gather_users = 1
						AND ist.TABLE_TYPE = ''VIEW''
					ORDER BY dbp.default_schema, ist.TABLE_NAME;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP VIEW statements with proper SQL syntax.

		BEGIN TRAN dropAssociatedSchemaViews

			EXEC (@sqlOUT);
			SET @rowModified = @@ROWCOUNT
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any views were actually dropped.
		BEGIN
			SET @printMessage =  '	Views dropped, making temp table ready to collect tables' + char(13) + char(10) + char(13) + char(10);
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
		
		/*
		**	With the views dropped, now non THINK Enterprise tables can be dropped.
		*/

		SET @sql = N'DELETE FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE gather_users = 1;'; --Clean the temp table of previous, view related, data.
		EXEC (@sql)

		/*
		**	This dynamic SQL statement creates several INSERT statements (all contained in the @sqlOUT variable).  The INSERT statement inserts data into the temporary
		**	table.  The data it inserts is pulled from the previous SQL statement.  It pulls data from the temp table, uses that data to determine what are non THINK
		**	Enterprise tables, and then inserts the new data into the same temp table.
		*/
		SET @sql = 'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '''''' + default_schema + N'''''' AND TABLE_TYPE = ''''BASE TABLE'''')
									BEGIN
									INSERT INTO ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, default_schema, gather_users)
										VALUES (''''' + @principalDbName + N''''', '''''' + default_schema + N'''''', 1);
									END;'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE default_schema is not null
						AND default_schema != ''dbo''
						AND clear_users = 1
					ORDER BY user_name;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT
			
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the INSERT statements with proper SQL syntax.
		EXEC (@sqlOUT);
		SET @rowModified = @@ROWCOUNT;

		IF @rowModified > 0 --Tell the user if any associated tables were found.
		BEGIN
			SET @printMessage =  '	Collecting dependant schema base tables';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several DROP TABLE statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross
		**	referencing data from the temp table with data in the actual database.  The temp table already holds all the non THINK Enterprise tables.
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''DROP TABLE ['' + default_schema COLLATE SQL_Latin1_General_CP850_CI_AS + N''].['' + ist.TABLE_NAME + N''];'' + char(13) + char(10)
					FROM INFORMATION_SCHEMA.TABLES ist
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = ist.TABLE_SCHEMA COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE dbp.gather_users = 1
						AND ist.TABLE_TYPE = ''BASE TABLE''
					ORDER BY dbp.default_schema, ist.TABLE_NAME;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP TABLE statements with proper SQL syntax.

		BEGIN TRAN dropAssociatedSchemaTables 

			EXEC (@sqlOUT);
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any tables were actually dropped.
		BEGIN
			SET @printMessage =  '	Tables dropped, making temp table ready to collect stored procedures' + char(13) + char(10) + char(13) + char(10);
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
		
		/*
		**	Move on to dropping non THINK Enterprise procedures.  These are procedures in the target database, none of these deal with usp, sub, or
		**	THINK Enterprise sp's.
		*/
		
		SET @sql = N'DELETE FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE gather_users = 1;'; --Clean the temp table of previous, table related, data.
		EXEC sp_executesql @sql;

		/*
		**	This dynamic SQL statement creates several INSERT statements (all contained in the @sqlOUT variable).  The INSERT statement inserts data into the temporary
		**	table.  The data it inserts is pulled from the previous SQL statement.  It pulls data from the temp table, uses that data to determine what are non THINK
		**	Enterprise stored procedures, and then inserts the new data into the same temp table.
		*/
		SET @sql = 'SET @sqlIN = '''';
					SELECT @sqlIN = @sqlIN + N''IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = '''''' + default_schema + N'''''' AND ROUTINE_TYPE = ''''PROCEDURE'''')
									BEGIN
									INSERT INTO ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, default_schema, gather_users)
										VALUES (''''' + @principalDbName + N''''', '''''' + default_schema + N'''''', 1);
									END;'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE default_schema is not null
						AND default_schema != ''dbo''
						AND clear_users = 1
					ORDER BY user_name;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
			
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the INSERT statements with proper SQL syntax.
		EXEC (@sqlOUT);
		SET @rowModified = @@ROWCOUNT;

		IF @rowModified > 0 --Tell the user if any associated stored procedures were found.
		BEGIN
			SET @printMessage =  '	Collecting dependant schema stored procedures';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several DROP PROCEDURE statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross
		**	referencing data from the temp table with data in the actual database.  The temp table already holds all the non THINK Enterprise stored procedues.
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''DROP PROCEDURE ['' + default_schema COLLATE SQL_Latin1_General_CP850_CI_AS + N''].['' + isr.ROUTINE_NAME + N''];'' + char(13) + char(10)
					FROM INFORMATION_SCHEMA.ROUTINES isr
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = isr.ROUTINE_SCHEMA COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE dbp.gather_users = 1
						AND isr.ROUTINE_TYPE = ''PROCEDURE''
					ORDER BY dbp.default_schema, isr.ROUTINE_NAME;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP PROCEDURE statements with proper SQL syntax.
		BEGIN TRAN dropAssociatedProcedures

			EXEC (@sqlOUT);
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any stored procedures were actually dropped.
		BEGIN
			SET @printMessage =  '	Stored procedures dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	Find any rules that belong to non THINK Enterprise schemas on any database tables or columns, unbind the rules and rebind them using the dbo
		**	schema.
		*/

		SET @sql = N'DELETE FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE gather_users = 1;'; --Clean the temp table of previous, table related, data.
		EXEC sp_executesql @sql;

		/*
		**	This dynamic SQL statement creates several INSERT statements (all contained in the @sqlOUT variable).  The INSERT statement inserts data into the temporary
		**	table.  The data it inserts is pulled from the previous SQL statement.  It pulls data from the temp table, uses that data to determine what rules belong to
		**	non THINK Enterprise schemas, and then inserts the new data into the same temp table.
		*/
		SET @sql = 'SET @sqlIN = '''';
					SELECT @sqlIN = @sqlIN + N''IF EXISTS (SELECT 1 FROM sys.columns c INNER JOIN sys.objects o1 ON o1.object_id = c.rule_object_id INNER JOIN sys.objects o2 ON o2.object_id = c.object_id INNER JOIN sys.schemas s ON s.schema_id = o1.schema_id WHERE s.name = '''''' + default_schema + N'''''')
									BEGIN
						
										INSERT INTO ##db_principals_' + CAST(@tempTableId AS nvarchar(8)) + N' (database_name, default_schema, gather_users)
											VALUES (''''' + @principalDbName + N''''', '''''' + default_schema + N'''''', 1);
									END;'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS nvarchar(8)) + char(13) + char(10) +
					N'WHERE default_schema is not null
						AND default_schema != ''dbo''
						AND clear_users = 1
					ORDER BY user_name;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the INSERT statements with proper SQL syntax.
		EXEC sp_executesql @sqlOUT;
		SET @rowModified = @@ROWCOUNT;

		IF @rowModified > 0 --Tell the user if any rules that belong to non THINK Enterprise schemas were found.
		BEGIN
			SET @printMessage =  '	Collecting dependant schema rules';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several EXEC sys.sp_unbindrule statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross
		**	referencing data from the temp table with data in the actual database.  The temp table already holds all the non THINK Enterprise rules.
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + ''EXEC sys.sp_unbindrule '''''' + o2.name + ''.'' + c.name + '''''';'' + char(13) + char(10)
					FROM sys.columns c
						INNER JOIN sys.objects o1
							ON o1.object_id = c.rule_object_id
						INNER JOIN sys.objects o2
							ON o2.object_id = c.object_id
						INNER JOIN sys.schemas s
							ON s.schema_id = o1.schema_id
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = s.name COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE s.name = '''' + default_schema COLLATE SQL_Latin1_General_CP850_CI_AS + ''''
						AND dbp.gather_users = 1
					ORDER BY dbp.default_schema;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the EXEC sys.sp_unbindrule statements with proper SQL syntax.
		BEGIN TRAN unbindAssociatedRules

			EXEC sp_executesql @sqlOUT;
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any rules that belong to non THINK Enterprise schemas were unbound.
		BEGIN
			SET @printMessage =  '	Unbinding dependant schema rules';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several EXEC sys.sp_bindrule statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross
		**	referencing data from the temp table with data in the actual database.  The temp table already holds all the non THINK Enterprise rules.
		*/
		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + ''EXEC sys.sp_bindrule '''' + o1.name + ''''], [dbo].['' + o2.name + ''].['' + c.name + ''];'' + char(13) + char(10)
					FROM sys.columns c
						INNER JOIN sys.objects o1
							ON o1.object_id = c.rule_object_id
						INNER JOIN sys.objects o2
							ON o2.object_id = c.object_id
						INNER JOIN sys.schemas s
							ON s.schema_id = o1.schema_id
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = s.name COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE s.name = '''' + default_schema COLLATE SQL_Latin1_General_CP850_CI_AS + ''''
						AND dbp.gather_users = 1
					ORDER BY dbp.default_schema;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the EXEC sys.sp_bindrule statements with proper SQL syntax.
		BEGIN TRAN bindAssociatedRules

			EXEC (@sqlOUT);
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any objects were rebound to dbo
		BEGIN
			SET @printMessage =  '	Rebinding objects to dbo schema';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	Now that all the non THINK enterprise rules are unbound and have been rebound using dbo, delete the rule
		*/

		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + ''DROP RULE ['' + s.name + ''].['' + o.name + '']'' + char(13) + char(10)
					FROM sys.objects o
						INNER JOIN sys.schemas s
							ON s.schema_id = o.schema_id
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = s.name COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE s.name = default_schema COLLATE SQL_Latin1_General_CP850_CI_AS
						AND o.type = ''R''
					ORDER BY dbp.default_schema;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP RULE statements with proper SQL syntax.
		BEGIN TRAN dropAssociatedRules
			
			EXEC sp_executesql @sqlOUT;
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any rules were rebound to the dbo schema.
		BEGIN
			SET @printMessage =  '	Rules dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	Before dropping the schema, check to see if any functions are currently bound to the schema and drop the functions.
		*/

		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + ''DROP FUNCTION ['' + s.name + ''].['' + o.name + '']'' + char(13) + char(10)
					FROM sys.objects o
						INNER JOIN sys.schemas s
							ON s.schema_id = o.schema_id
						INNER JOIN ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' dbp
							ON dbp.default_schema = s.name COLLATE SQL_Latin1_General_CP850_CI_AS
					WHERE s.name = default_schema COLLATE SQL_Latin1_General_CP850_CI_AS
						AND o.type in (''AF'', ''FN'', ''FS'', ''FT'', ''IF'', ''TF'')
					ORDER BY dbp.default_schema;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP FUNCTION statements with proper SQL syntax.
		BEGIN TRAN dropAssociatedFunctions
			
			EXEC sp_executesql @sqlOUT;
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any functions were dropped.
		BEGIN
			SET @printMessage =  '	Functions dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	With all the principals that depend on the non THINK Enterprise schemas dropped, the actual schemas and then finally the users can be removed.
		*/

		SET @sql = N'DELETE FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE gather_users = 1;'; --Clean the temp table of previous, stored procedure related, data.
		EXEC (@sql);

		/*
		**	This dynamic SQL statement creates several DROP SCHEMA statements (all contained in the @sqlOUT variable).  The SQL statements are created by cross
		**	referencing the data from the temp table with the data in the actual database.  The temp table originally held all the non THINK Enterprise users and their
		**	associated schemas.  Data has since been added and removed from this temp table but the users and it's associated information remain.
		*/
		SET @sql = N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''DROP SCHEMA ['' + default_schema + N'']'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
					WHERE tempdbp.default_schema is not null
						AND tempdbp.default_schema != ''dbo''
						AND tempdbp.clear_users = 1;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
			
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP SCHEMA statements with proper SQL syntax.
		EXEC (@sqlOUT);
		SET @rowModified = @@ROWCOUNT;

		IF @rowModified > 0 --Tell the user if any schemas were actually dropped.
		BEGIN
			SET @printMessage =  char(13) + char(10) + '	Schema''s dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	Look for non THINK Enterprise roles, drop any users associated with that/those roles, and then drop the role itself. The mechanism to drop a member from a role changed
		**	between SQL versions 10 and 11. We must therefore detect which version of the db server we are running in before forming the SQL statement to drop members from a role.
		*/

		SET @sql =
			CASE
				WHEN SERVERPROPERTY('ProductVersion') >= '11'
					THEN N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
						N'SET @sqlIN = '''';
						WITH role_members_CTE (role_principal_id, member_principal_id, member_name)
						AS (
							SELECT drm.role_principal_id, drm.member_principal_id, dp1.name
							FROM sys.database_role_members drm
								INNER JOIN sys.database_principals dp1
									ON dp1.principal_id = drm.member_principal_id
							WHERE drm.role_principal_id in (SELECT principal_id FROM sys.database_principals dp WHERE type = ''R'' AND is_fixed_role = 0 AND name != ''public'')
						)
						SELECT @sqlIN = @sqlIN + ''ALTER ROLE ['' + dp.name + ''] DROP MEMBER ['' + rmc.member_name + ''];'' + char(13) + char(10)
						FROM role_members_CTE rmc
							INNER JOIN sys.database_principals dp
								ON dp.principal_id = rmc.role_principal_id;'
				WHEN SERVERPROPERTY('ProductVersion') < '11'
					THEN N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
						N'SET @sqlIN = '''';
						WITH role_members_CTE (role_principal_id, member_principal_id, member_name)
						AS (
							SELECT drm.role_principal_id, drm.member_principal_id, dp1.name
							FROM sys.database_role_members drm
								INNER JOIN sys.database_principals dp1
									ON dp1.principal_id = drm.member_principal_id
							WHERE drm.role_principal_id in (SELECT principal_id FROM sys.database_principals dp WHERE type = ''R'' AND is_fixed_role = 0 AND name != ''public'')
						)
						SELECT @sqlIN = @sqlIN + ''EXEC sp_droprolemember N'''''' + dp.name + '''''', N'''''' + rmc.member_name + '''''''' + char(13) + char(10)
						FROM role_members_CTE rmc
							INNER JOIN sys.database_principals dp
								ON dp.principal_id = rmc.role_principal_id;'
			END;

		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT --Pad the DROP MEMBER statements with proper SQL syntax.	
			
		BEGIN TRAN dropRoleMembers
			EXEC sp_executesql @sqlOUT;
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any role members were dropped.
		BEGIN
			SET @printMessage = '	Role members dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) +
					N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + ''DROP ROLE ['' + dp.name + '']'' + char(13) + char(10)
					FROM sys.database_principals dp
					WHERE type = ''R''
						AND is_fixed_role = 0
						AND name != ''public''';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP ROLE statements with proper SQL syntax.
		BEGIN TRAN dropRoles
			
			EXEC sp_executesql @sqlOUT;
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any roles were dropped.
		BEGIN
			SET @printMessage =  '	Roles dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		/*
		**	This dynamic SQL statement creates several DROP USER statements (all contained in the @sqlOUT variable).  The SQL statements are created in the same way
		**	that the DROP SCHEMA statements are created.
		*/
		SET @sql = N'SET @sqlIN = ''''
					SELECT @sqlIN = @sqlIN + N''DROP USER ['' + user_name + N'']'' + char(13) + char(10)
					FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
					WHERE tempdbp.principal_type in (''S'', ''U'', ''G'')
						AND tempdbp.clear_users = 1;';
		EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;
		
		SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the DROP USER statements with proper SQL syntax.

		BEGIN TRAN dropSchemaAndUser

			EXEC (@sqlOUT);
			SET @rowModified = @@ROWCOUNT;
		COMMIT TRAN;

		IF @rowModified > 0 --Tell the user if any users were actually dropped.
		BEGIN
			SET @printMessage =  '	Users''s dropped';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		SET @sql = 'DELETE FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + char(13) + char(10) +
					N'WHERE clear_users = 1;'; --Clear the temp table of all user related data.
		EXEC (@sql);

		SET @printMessage =  'All Non-THINK related SQL Users/Schemas/Stored procedures have been cleared';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END;
	/*
	**	This portion of the code is used to add a standard list of users and database principals to the restored database, regardless of what is already there.  This portion
	**	is typically called under two use case scenarios.  The first, and more likely, is that the database was wiped of all its previous users in order to start fresh.
	**	Now that the database's principals have been "cleaned" the user can then add principals based off of a standard template pulled from the meta database.  The second
	**	scenario is that the user simply wants to add the standard template but doesn't know or care what is already in the database.  this can be potentially dangerous
	**	as a principal added from the template may already exist in the database and cause errors to occur.
	*/
	ELSE IF @gatherUsers = 2
	BEGIN
		BEGIN TRAN addUserPrincipals
			
			/*
			**	Create users in the target database by creating a dynamic SQL statement directly from the meta database.  As each instance holds its own meta database the
			**	user information that is/can be pulled is instance dependent.
			*/
			SET @sql = '';
			SELECT @sql = @sql + N'CREATE USER [' + domain_name + N'] FROM LOGIN [' + domain_name + N']
							ALTER USER [' + domain_name + N'] WITH DEFAULT_SCHEMA = [dbo];' + char(13) + char(10)
			FROM user_mappings;

			SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sql;
			EXEC (@sql)

			/*
			**	Add the db_datareader role to the new users that were added.
			*/
			SET @sql = '';
			SELECT @sql = @sql + N'EXEC sp_addrolemember N''db_datareader'', N''' + domain_name + N'''' + char(13) + char(10)
			FROM user_mappings;

			SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sql;
			EXEC (@sql)

			/*
			**	Add the db_datawriter role to the new users that were added.
			*/
			SET @sql = '';
			SELECT @sql = @sql + N'EXEC sp_addrolemember N''db_datawriter'', N''' + domain_name + N'''' + char(13) + char(10)
			FROM user_mappings;

			SET @sql = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sql;
			EXEC (@sql);
		COMMIT TRAN;
	END;
	/*
	**	This portion of the code is used to add the list of users that was generated when @gatherUsers was set to 0.  This portion is usually only invoked statically.  A
	**	USP will typically change the @gatherUser parameter forcefully (with or without the user's knowledge) and call this sub sp on its own.  It is not usually invoked
	**	directly by the user.
	*/
	ELSE IF @gatherUsers = 3
	BEGIN
		BEGIN TRAN addGatheredUsers
		
			/*
			**	This dynamic SQL statement creates several CREATE USER statements (all stored in the @sqlOUT variable).  In order to successfully add a stored user back
			**	to the restored database a SQL Login must already exists, of which this sub sp does not add itself.  The login must have the same name that was used to link
			**	the SQL user in the original database.
			*/
			SET @sql = N'SET @sqlIN = ''''
							SELECT @sqlIN = @sqlIN + N''CREATE USER ['' + user_name + N''] FOR LOGIN ['' + login_name + N'']
											ALTER USER ['' + user_name + N''] WITH DEFAULT_SCHEMA = [dbo];'' + char(13) + char(10)
							FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
							WHERE tempdbp.add_users_gathered = 1;';
			EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

			SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the CREATE USER statements with proper SQL syntax.
			EXEC (@sqlOUT);

			/*
			**	After creating the users in the restored database we automatically give them the db_datareader role.  If this role is not desired then it has to be removed
			**	manually.
			*/
			SET @sql = N'SET @sqlIN = ''''
						SELECT @sqlIN = @sqlIN + N''EXEC sp_addrolemember N''''db_datareader'''', N'''''' + user_name + N'''''''' + char(13) + char(10)
						FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
						WHERE tempdbp.add_users_gathered = 1
							AND tempdbp.login_name != ''thkapp'';';
			EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

			SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the EXEC statements with proper SQL syntax.
			EXEC (@sqlOUT);

			/*
			**	In addtion to the db_datareader role, we also automatically give the new user(s) the db_datawriter role.  If this role is not desired then it has to be
			**	removed manually.
			*/
			SET @sql = N'SET @sqlIN = ''''
						SELECT @sqlIN = @sqlIN + N''EXEC sp_addrolemember N''''db_datawriter'''', N'''''' + user_name + N'''''''' + char(13) + char(10)
						FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
						WHERE tempdbp.gather_users = 1
							AND tempdbp.login_name != ''thkapp'';';
			EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

			SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the EXEC statements with proper SQL syntax.
			EXEC (@sqlOUT);

			/*
			**	In addition to the db_datareader and db_datawriter roles, we also automatically give the new user(s) the db_owner role.  If this role is not desired then
			**	it has to be removed manually.
			*/
			SET @sql = N'IF EXISTS (SELECT 1 FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' WHERE login_name = ''thkapp'')
						BEGIN

							SET @sqlIN = ''''
							SELECT @sqlIN = @sqlIN + N''EXEC sp_addrolemember N''''db_owner'''', N'''''' + user_name + N'''''''' + char(13) + char(10)
							FROM ##db_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempdbp
							WHERE tempdbp.gather_users = 1
								AND tempdbp.login_name = ''thkapp'';
						END;';
			EXEC sp_executesql @sql, N'@sqlIN nvarchar(max) OUTPUT', @sqlOUT OUTPUT;

			SET @sqlOUT = N'USE ' + QUOTENAME(@principalDbName) + char(13) + char(10) + @sqlOUT; --Pad the EXEC statements with proper SQL syntax.
			EXEC (@sqlOUT);
		COMMIT TRAN;

		SET @sql = 'DROP TABLE ##db_principals_' + CAST(@tempTableId AS varchar(20)); --Regardless of which portion of the code is run, in the end we drop the temp table.
		EXEC (@sql);
	END;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @principalDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_databasePrincipals sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = N'IF object_id (''tempdb..##db_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##db_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC (@sql);

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;