USE [dbAdmin];
GO

ALTER DATABASE [dbAdmin] SET TRUSTWORTHY ON;
GO

SET NOCOUNT ON;

DECLARE @printMessage	nvarchar(4000)
		,@errorMessage	nvarchar(4000)
		,@errorSeverity	int
		,@errorNumber	int

SET @printMessage = 'Setting up dbAdmin database for sql11 instance:' + char(13) + char(10);
RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

BEGIN TRY
	/*
	**	CREATE TABLE statements
	*/
	SET @printMessage = char(13) + char(10) + 'Creating tables:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'backup_history')
	BEGIN

		CREATE TABLE backup_history (
			backup_id			int identity(1000,1)	not null
			,database_name		nvarchar(128)			not null
			,backup_start_date	datetime				null
			,backup_end_date	datetime				null
			,type				char(1)					not null
			,backup_status		char(1)					not null
			,backup_errcode		int						null
			,error_message		nvarchar(2048)			null
			,clean_status		nvarchar(16)			null
			,owner				nvarchar(64)			null
			,dept				nvarchar(64)			null
			,thkVersion			nvarchar(32)			null
			,dbType				nchar(2)				null
			,problem_num		nchar(5)				null
			,client				nvarchar(128)			null
			,days_to_save		int						not null

			,CONSTRAINT PK_BACKUP_HISTORY PRIMARY KEY CLUSTERED(
				backup_id
			)
		)

		ALTER TABLE backup_history ADD CONSTRAINT DF_backup_history_days_to_save DEFAULT (30) FOR days_to_save
		ALTER TABLE backup_history WITH CHECK ADD CONSTRAINT chk_backup_status CHECK (backup_status='i' OR backup_status='f' OR backup_status='s')
		ALTER TABLE backup_history WITH CHECK ADD CONSTRAINT chk_backup_type CHECK (type='l' OR type='d' OR type='f' OR type='n')

		RAISERROR('	Table created successfully: backup_history', 10, 1) WITH NOWAIT;
	END
	ELSE
		RAISERROR('	Table "backup_history" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'backup_history_file')
	BEGIN

		CREATE TABLE backup_history_file (
			backup_id		int		not null
			,file_number	tinyint	not null
			,filename		sysname	not null
			,deleted		char(1)	not null

			,CONSTRAINT PK_BACKUP_HISTORY_FILE PRIMARY KEY CLUSTERED(
				backup_id
				,file_number
			)
			,UNIQUE NONCLUSTERED(
				filename
			)
		)

		ALTER TABLE backup_history_file ADD CONSTRAINT DFLT_DELETED DEFAULT 'n' FOR deleted
		ALTER TABLE backup_history_file WITH CHECK ADD CONSTRAINT fk_backup_history_backup_id FOREIGN KEY (backup_id) REFERENCES backup_history (backup_id)
			ON DELETE CASCADE
		ALTER TABLE backup_history_file CHECK CONSTRAINT [fk_backup_history_backup_id]
		ALTER TABLE backup_history_file WITH CHECK ADD  CONSTRAINT [chk_deleted] CHECK  (([deleted]='n' OR [deleted]='y'))
		ALTER TABLE backup_history_file CHECK CONSTRAINT [chk_deleted]

		RAISERROR('	Table created successfully: backup_history_file', 10, 1) WITH NOWAIT;
	END
	ELSE
		RAISERROR('	Table "backup_history_file" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'db_stored_proc_rights')
	BEGIN

		CREATE TABLE db_stored_proc_rights (
			sp_id			int identity (1000,1)	not null
			,stored_proc	varchar(255)			not null
			,is_applicable	tinyint					null

			,CONSTRAINT PK_DB_STORED_PROC_RIGHTS PRIMARY KEY CLUSTERED(
				sp_id
			)
		);

		ALTER TABLE db_stored_proc_rights ADD CONSTRAINT DF_STORED_PROC UNIQUE (stored_proc)

		RAISERROR('	Table created successfully: db_stored_proc_rights', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "db_stored_proc_rights" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'error_handling')
	BEGIN

		CREATE TABLE error_handling (
			error_handling_id	int identity(1000,1)	not null
			,step_number		int						not null
			,error_description	nvarchar(512)			null

			CONSTRAINT PK_ERROR_HANDLING PRIMARY KEY CLUSTERED(
				error_handling_id
			)
		);

		RAISERROR('	Table created successfully: error_handling', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "error_handling" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'params')
	BEGIN

		CREATE TABLE params(
			p_key		varchar(64)		not null
			,p_value	varchar(2048)	not null

			,CONSTRAINT P_KEY PRIMARY KEY CLUSTERED(
				p_key
			)
		);

		RAISERROR('	Table created successfully: params', 10, 1) WITH NOWAIT;
	END
	ELSE
		RAISERROR('	Table "params" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'restore_history')
	BEGIN

		CREATE TABLE restore_history (
			restore_id			int identity(7000,1)	not null
			,database_name		varchar(128)			null		--Name of the database that was restored
			,restore_start_date	datetime				null
			,restore_end_date	datetime				null
			,user_name			nvarchar(256)			null		--The user who restored the database
			,err_nbr			int						null		--Any SQL error messages that are encountered
			,problem_nbr		int						null		--Undocumented.  Null by default.  Required when restoring a dirty backup

			,CONSTRAINT PK_RESTORE_HISTORY PRIMARY KEY CLUSTERED(
				restore_id
			)
		);

		RAISERROR('	Table created successfully: restore_history', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "restore_history" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'restore_history_file')
	BEGIN

		CREATE TABLE restore_history_file (
			restore_id	int				not null
			,filename	nvarchar(1000)	not null		--Name and location of the backup file(s) used to perform the restore
			,filetype	varchar(2)		not null		--If the backup was in native or litespeed format

			,FOREIGN KEY (restore_id) REFERENCES restore_history(restore_id)
		);

		RAISERROR('	Table created successfully: restore_history_file', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "restore_history_file" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'statistics_maint_hist')
	BEGIN

		CREATE TABLE statistics_maint_hist(
			stats_maint_id		int identity(1000,1)	not null
			,db_name			nvarchar(128)			null
			,object_name		nvarchar(128)			null
			,schema_name		nvarchar(128)			null
			,index_name			nvarchar(128)			null
			,object_id			int						null
			,index_id			smallint				null
			,statistics_date	datetime				null
			,updated_date		datetime				null

			,CONSTRAINT PK_STATISTICS_MAINT_HIST PRIMARY KEY CLUSTERED(
				stats_maint_id
			)
		);

		RAISERROR('	Table created successfully: statistics_maint_hist', 10, 1) WITH NOWAIT;
	END
	ELSE
		RAISERROR('	Table "statistics_maint_hist" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'user_mappings')
	BEGIN

		CREATE TABLE user_mappings (
			user_id			int identity (1000,1)	not null
			,domain_name	varchar(80)				not null
			,user_name		varchar(80)				not null
			,dept_name		varchar(80)				not null

			,CONSTRAINT PK_USER_MAPPINGS PRIMARY KEY CLUSTERED(
				user_id
			)
		);

		ALTER TABLE user_mappings ADD CONSTRAINT DF_USER_NAME UNIQUE (user_name)

		RAISERROR('	Table created successfully: user_mappings', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "user_mappings" already exists, skipping...', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'baseline_versions')
	BEGIN

		CREATE TABLE baseline_versions(
			baseline_version		nvarchar(16)	not null
			,major_version_order	tinyint			not null
			,minor_version_order	tinyint			not null
			,patch_version_order	tinyint			not null
			,backup_path			nvarchar(512)	not null
			,is_available			bit				not null

			,CONSTRAINT PK_BASELINE_VERSIONS PRIMARY KEY CLUSTERED(
				baseline_version
				,major_version_order
				,minor_version_order
				,patch_version_order
			)
		);

		RAISERROR('	Table created successfully: baseline_versions', 10, 1) WITH NOWAIT;
	END;
	ELSE
		RAISERROR('	Table "baseline_versions" already exists, skipping...', 10, 1) WITH NOWAIT;

	RAISERROR('Done creating tables', 10, 1) WITH NOWAIT;

	/*
	**	INSERT statements
	**
	**	All values are checked to see if they already exists in the current table.  If they are then a
	**	begin try is used to avoid race conditions, deadlocks, and non-deterministric errors.  If not
	**	exists are still used to avoid logging/error implications or performance hits.
	*/
	BEGIN TRAN insertStmts
		
		SET @printMessage = char(13) + char(10) + 'Inserting into db_stored_proc_rights:'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM db_stored_proc_rights WHERE stored_proc = 'sl_DeleteCustProsp')
		BEGIN TRY

			INSERT INTO db_stored_proc_rights (stored_proc)
				VALUES ('sl_DeleteCustProsp');

			RAISERROR ('	Stored procedure added successfully: sl_DeleteCustProsp', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Stored procedure "sl_DeleteCustProsp" already inserted, skipping...', 10, 1) WITH NOWAIT;
		
		IF NOT EXISTS (SELECT 1 FROM db_stored_proc_rights WHERE stored_proc = 'sl_GetDemographicResponse')
		BEGIN TRY

			INSERT INTO db_stored_proc_rights (stored_proc)
				VALUES ('sl_GetDemographicResponse');

			RAISERROR('	Stored procedure added successfully: sl_GetDemographicResponse', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH
		
			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Stored procedure "sl_GetDemographicResponse" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM db_stored_proc_rights WHERE stored_proc = 'zz_dbver')
		BEGIN TRY

			INSERT INTO db_stored_proc_rights (stored_proc)
				VALUES ('zz_dbver');

			RAISERROR ('	Stored procedure added successfully: zz_dbver', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Stored procedure "zz_dbver" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM db_stored_proc_rights WHERE stored_proc = 'zz_helpdomain')
		BEGIN TRY
		INSERT INTO db_stored_proc_rights (stored_proc)
			VALUES ('zz_helpdomain');

			RAISERROR ('	Stored procedure added successfully: zz_helpdomain', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Stored procedure "zz_helpdomain" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM db_stored_proc_rights WHERE stored_proc = 'sl_refreshallviews')
		BEGIN TRY

			INSERT INTO db_stored_proc_rights (stored_proc)
				VALUES ('sl_refreshallviews');

			RAISERROR ('	Stored procedure added successfully: sl_refreshallviews', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Stored procedure "sl_refreshallviews" already inserted, skipping...', 10, 1) WITH NOWAIT;

		RAISERROR('Done inserting into db_stored_proc_rights', 10, 1) WITH NOWAIT;

		SET @printMessage = char(13) + char(10) + 'Inserting into params:';
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'AdhocBackupRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('AdhocBackupRetention', '14');

			RAISERROR ('	Values added successfully: AdhocBackupRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "AdhocBackupRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'BackupHistoryRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('BackupHistoryRetention', '90');

			RAISERROR ('	Values added successfully: BackupHistoryRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "BackupHistoryRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DailyBackupControl')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DailyBackupControl', 'fnnnnnn');

			RAISERROR ('	Values added successfully: DailyBackupControl', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DailyBackupControl" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'Dedicated Admin Port')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('Dedicated Admin Port', '53807');

			RAISERROR ('	Values added successfully: Dedicated Admin Port', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "Dedicated Admin Port" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DefaultBackupDirectory')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DefaultBackupDirectory', 'U:\MSSQL11.SQL11\MSSQL\Backup');

			RAISERROR ('	Values added successfully: DefaultBackupDirectory', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DefaultBackupDirectory" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DefaultBackupMethod')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DefaultBackupMethod', 'litespeed');

			RAISERROR ('	Values added successfully: DefaultBackupMethod', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DefaultBackupMethod" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DefaultDataDirectory')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DefaultDataDirectory', 'R:\MSSQL11.SQL11\MSSQL\Data');

			RAISERROR ('	Values added successfully: DefaultDataDirectory', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DefaultDataDirectory" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DefaultLogDirectory')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DefaultLogDirectory', 'S:\MSSQL11.SQL11\MSSQL\Logs');

			RAISERROR ('	Values added successfully: DefaultLogDirectory', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DefaultLogDirectory" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'DiffBackupRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('DiffBackupRetention', '0');

			RAISERROR ('	Values added successfully: DiffBackupRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "DiffBackupRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'FileCountThreshold')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('FileCountThreshold', '100');

			RAISERROR ('	Values added successfully: FileCountThreshold', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "FileCountThreshold" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'FullBackupRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('FullBackupRetention', '7');

			RAISERROR ('	Values added successfully: FullBackupRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "FullBackupRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'InfrastructureVersion')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('InfrastructureVersion', '1.06');

			RAISERROR ('	Values added successfully: InfrastructureVersion', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "InfrastructureVersion" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'PowershellScriptPath')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('PowershellScriptPath', '');

			RAISERROR ('	Values added successfully: PowershellScriptPath', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "PowershellScriptPath" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'StatsHistoryRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('StatsHistoryRetention', '90');

			RAISERROR ('	Values added successfully: StatsHistoryRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "StatsHistoryRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'StatsMaintLimit')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('StatsMaintLimit', '15');

			RAISERROR ('	Values added successfully: StatsMaintLimit', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "StatsMaintLimit" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'ProblemNumber')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('ProblemNumber','00000');

			RAISERROR ('	Values added successfully: ProblemNumber', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "ProblemNumber" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'thkVersion')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('thkVersion','???');

			RAISERROR ('	Values added successfully: thkVersion', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "thkVersion" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'tempTableId')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('tempTableId', '0');

			RAISERROR ('	Values added successfully: tempTableId', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "tempTableId" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'StatsRebuildAge')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('StatsRebuildAge','7');

			RAISERROR ('	Values added successfully: StatsRebuildAge', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "StatsRebuildAge" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM params WHERE p_key = 'TlogBackupRetention')
		BEGIN TRY

			INSERT INTO params (p_key, p_value)
				VALUES ('TlogBackupRetention','2');

			RAISERROR ('	Values added successfully: TlogBackupRetention', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "TlogBackupRetention" already inserted, skipping...', 10, 1) WITH NOWAIT;

		RAISERROR('Done inserting into params', 10, 1) WITH NOWAIT;

		SET @printMessage = char(13) + char(10) + 'Inserting into user_mappings:'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'jschaeffer')
		BEGIN TRY
	
			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\jschaeffer','jschaeffer','support');

			RAISERROR ('	Values added successfully: jschaeffer', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "jschaeffer" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'akennedy')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\akennedy','akennedy','dev');

			RAISERROR ('	Values added successfully: akennedy', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "akennedy" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'lzibetti')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\lzibetti','lzibetti','support');

			RAISERROR ('	Values added successfully: lzibetti', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "lzibetti" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'mheil')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\mheil','mheil','dev');

			RAISERROR ('	Values added successfully: mheil', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "mheil" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'rwalgren')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\rwalgren','rwalgren','qa');

			RAISERROR ('	Values added successfully: rwalgren', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "rwalgren" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'shokanson')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\shokanson','shokanson','dev');

			RAISERROR ('	Values added successfully: shokanson', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "shokanson" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM user_mappings WHERE user_name = 'cjenkins')
		BEGIN TRY

			INSERT INTO user_mappings (domain_name, user_name, dept_name)
				VALUES ('MPLS\cjenkins','cjenkins','impl');

			RAISERROR ('	Values added successfully: cjenkins', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR ('	Values "cjenkins" already inserted, skipping...', 10, 1) WITH NOWAIT;

		RAISERROR('Done inserting into user_mappings', 10, 1) WITH NOWAIT;

		SET @printMessage = char(13) + char(10) + 'Inserting into baseline_versions:'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.0.13.48')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.0.13.48', 1, 1, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_701348.bak', 1)

			RAISERROR('	Values added successfully: 7.0.13.48', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.0.13.48" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.0.13.49')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.0.13.49', 1, 1, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_701349.bak', 1)

			RAISERROR('	Values added successfully: 7.0.13.49', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.0.13.49" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.0.13.50')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.0.13.50', 1, 1, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_701350.bak', 0)

			RAISERROR('	Values added successfully: 7.0.13.50', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.0.13.50" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.0.14.25')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.0.14.25', 1, 2, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_701425.bak', 1)

			RAISERROR('	Values added successfully: 7.0.14.25', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.0.14.25" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.0.15.30')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.0.15.30', 1, 3, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_701530.bak', 1)

			RAISERROR('	Values added successfully: 7.0.15.30', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.0.15.30" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.5.4')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.5.4', 2, 1, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_7154.bak', 0)

			RAISERROR('	Values added successfully: 7.1.5.4', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.5.4" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.6.35')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.6.35', 2, 2, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_71635.bak', 0)

			RAISERROR('	Values added successfully: 7.1.6.35', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.6.35" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.6.36')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.6.36', 2, 2, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_71636.bak', 1)

			RAISERROR('	Values added successfully: 7.1.6.36', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.6.36" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.8.8')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.8.8', 2, 3, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_7188.bak', 1)

			RAISERROR('	Values added successfully: 7.1.8.8', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.8.8" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.8.11')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.8.11', 2, 3, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_71811.bak', 0)

			RAISERROR('	Values added successfully: 7.1.8.11', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.8.11" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.8.13')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.8.13', 2, 3, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_71813.bak', 1)

			RAISERROR('	Values added successfully: 7.1.8.13', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.8.13" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.9.53')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.9.53', 2, 4, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_71953.bak', 1)

			RAISERROR('	Values added successfully: 7.1.9.53', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.9.53" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.9.56')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.9.56', 2, 4, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_71956.bak', 0)

			RAISERROR('	Values added successfully: 7.1.9.56', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.9.56" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.9.58')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.9.58', 2, 4, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_71958.bak', 1)

			RAISERROR('	Values added successfully: 7.1.9.58', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.9.58" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.10.21')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.10.21', 2, 5, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_711021.bak', 1)

			RAISERROR('	Values added successfully: 7.1.10.21', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.10.21" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.11.19')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.11.19', 2, 6, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_711119.bak', 0)

			RAISERROR('	Values added successfully: 7.1.11.19', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.11.19" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.11.22')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.11.22', 2, 6, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_711122.bak', 0)

			RAISERROR('	Values added successfully: 7.1.11.22', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.11.22" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.11.26')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.11.26', 2, 6, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_711126.bak', 1)

			RAISERROR('	Values added successfully: 7.1.11.26', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.11.26" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.11.31')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.11.31', 2, 6, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_711131.bak', 1)

			RAISERROR('	Values added successfully: 7.1.11.31', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.11.31" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.11.34')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.11.34', 2, 6, 5, '\\PRVTHKDB01\BASELINES\baseline_sql08_711134.bak', 1)

			RAISERROR('	Values added successfully: 7.1.11.34', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.11.34" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.12.29')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.12.29', 2, 7, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_711229.bak', 1)

			RAISERROR('	Values added successfully: 7.1.12.29', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.12.29" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.1.12.32')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.1.12.32', 2, 7, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_711232.bak', 1)

			RAISERROR('	Values added successfully: 7.1.12.32', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.1.12.32" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.1.29')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.1.29', 3, 1, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_72129.bak', 0)

			RAISERROR('	Values added successfully: 7.2.1.29', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.1.29" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.2.26')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.2.26', 3, 2, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_72226.bak', 0)

			RAISERROR('	Values added successfully: 7.2.2.26', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.2.26" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.2.30')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.2.30', 3, 2, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_72230.bak', 1)

			RAISERROR('	Values added successfully: 7.2.2.30', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.2.30" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.2.31')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.2.31', 3, 2, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_72231.bak', 1)

			RAISERROR('	Values added successfully: 7.2.2.31', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.2.31" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.3.7')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.3.7', 3, 3, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_7237.bak', 1)

			RAISERROR('	Values added successfully: 7.2.3.7', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.3.7" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.3.9')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.3.9', 3, 3, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_7239.bak', 1)

			RAISERROR('	Values added successfully: 7.2.3.9', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.3.9" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.4.33')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.4.33', 3, 4, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_72433.bak', 1)

			RAISERROR('	Values added successfully: 7.2.4.33', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.4.33" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.5.62')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.5.62', 3, 5, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_72562.bak', 1)

			RAISERROR('	Values added successfully: 7.2.5.62', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.5.62" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.5.64')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.5.64', 3, 5, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_72564.bak', 1)

			RAISERROR('	Values added successfully: 7.2.5.64', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.5.64" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.5.65')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.5.65', 3, 5, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_72565.bak', 0)

			RAISERROR('	Values added successfully: 7.2.5.65', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.5.65" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.6.94')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.6.94', 3, 6, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_72694.bak', 1)

			RAISERROR('	Values added successfully: 7.2.6.94', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.6.94" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.6.95')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.6.95', 3, 6, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_72695.bak', 1)

			RAISERROR('	Values added successfully: 7.2.6.95', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.6.95" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.2.6.96')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.2.6.96', 3, 6, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_72696.bak', 1)

			RAISERROR('	Values added successfully: 7.2.6.96', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.2.6.96" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.0.41')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.0.41', 4, 1, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_73041.bak', 1)

			RAISERROR('	Values added successfully: 7.3.0.41', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.0.41" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.0.45')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.0.45', 4, 1, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_73045.bak', 1)

			RAISERROR('	Values added successfully: 7.3.0.45', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.0.45" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.1.40')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.1.40', 4, 2, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_73140.bak', 1)

			RAISERROR('	Values added successfully: 7.3.1.40', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.1.40" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.1.53')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.1.53', 4, 2, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_73153.bak', 1)

			RAISERROR('	Values added successfully: 7.3.1.53', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.1.53" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.1.54')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.1.54', 4, 2, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_73154.bak', 1)

			RAISERROR('	Values added successfully: 7.3.1.54', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.1.54" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.2.43')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.2.43', 4, 3, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_73243.bak', 1)

			RAISERROR('	Values added successfully: 7.3.2.43', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.2.43" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.2.50')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.2.50', 4, 3, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_73250.bak', 0)

			RAISERROR('	Values added successfully: 7.3.2.50', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.2.50" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.2.51')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.2.51', 4, 3, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_73251.bak', 1)

			RAISERROR('	Values added successfully: 7.3.2.51', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.2.51" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.2.53')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.2.53', 4, 3, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_73253.bak', 1)

			RAISERROR('	Values added successfully: 7.3.2.53', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.2.53" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.4.47')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.4.47', 4, 4, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_73447.bak', 1)

			RAISERROR('	Values added successfully: 7.3.4.47', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.4.47" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.4.49')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.4.49', 4, 4, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_73449.bak', 1)

			RAISERROR('	Values added successfully: 7.3.4.49', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.4.49" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.4.51')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.4.51', 4, 4, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_73451.bak', 1)

			RAISERROR('	Values added successfully: 7.3.4.51', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.4.51" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.4.52')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.4.52', 4, 4, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_73452.bak', 1)

			RAISERROR('	Values added successfully: 7.3.4.52', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.4.52" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.4.53')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.4.53', 4, 4, 5, '\\PRVTHKDB01\BASELINES\baseline_sql08_73453.bak', 1)

			RAISERROR('	Values added successfully: 7.3.4.53', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.4.53" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.5.129')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.5.129', 4, 5, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_735129.bak', 1)

			RAISERROR('	Values added successfully: 7.3.5.129', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.5.129" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.5.131')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.5.131', 4, 5, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_735131.bak', 1)

			RAISERROR('	Values added successfully: 7.3.5.131', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.5.131" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.5.134')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.5.134', 4, 5, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_735134.bak', 1)

			RAISERROR('	Values added successfully: 7.3.5.134', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.5.134" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.3.5.141')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.3.5.141', 4, 5, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_735141.bak', 1)

			RAISERROR('	Values added successfully: 7.3.5.141', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.3.5.141" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.4.0.113')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.4.0.113', 5, 1, 1, '\\PRVTHKDB01\BASELINES\baseline_sql08_740113.bak', 1)

			RAISERROR('	Values added successfully: 7.4.0.113', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.4.0.113" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.4.0.119')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.4.0.119', 5, 1, 2, '\\PRVTHKDB01\BASELINES\baseline_sql08_740119.bak', 1)

			RAISERROR('	Values added successfully: 7.4.0.119', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.4.0.119" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.4.0.125')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.4.0.125', 5, 1, 3, '\\PRVTHKDB01\BASELINES\baseline_sql08_740125.bak', 0)

			RAISERROR('	Values added successfully: 7.4.0.125', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.4.0.125" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.4.0.126')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.4.0.126', 5, 1, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_740126.bak', 1)

			RAISERROR('	Values added successfully: 7.4.0.126', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.4.0.126" already inserted, skipping...', 10, 1) WITH NOWAIT;

		IF NOT EXISTS (SELECT 1 FROM baseline_versions WHERE baseline_version = '7.4.0.130')
		BEGIN TRY

			INSERT INTO baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
				VALUES ('7.4.0.130', 5, 1, 5, '\\PRVTHKDB01\BASELINES\baseline_sql08_740130.bak', 1)

			RAISERROR('	Values added successfully: 7.4.0.130', 10, 1) WITH NOWAIT;
		END TRY
		BEGIN CATCH

			SELECT @errorMessage = ERROR_MESSAGE()
					,@errorSeverity = ERROR_SEVERITY()
					,@errorNumber = ERROR_NUMBER();

			RAISERROR(@errorMessage, @errorSeverity, 1);
		END CATCH;
		ELSE
			RAISERROR('	Values "7.4.0.130" already inserted, skipping...', 10, 1) WITH NOWAIT;

		SET @printMessage = 'Done inserting into baseline_versions' + char(13) + char(10) + char(13) + char(10) + 'dbAdmin database is now setup for the sql11 instance'
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	COMMIT TRAN;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER();

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;