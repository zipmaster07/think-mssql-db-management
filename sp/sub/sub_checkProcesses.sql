/*
**	This stored procedure checks a target THINK Enterprise database for running processes.  At the present time it only checks if the Email/Event Queue process is running.  As
**	this process (Email/Event Queue) has the potential to email real people (even in test databases) it is stopped from running accidentially.  This sp is a sub stored
**	procedure.  It is not meant to be called directly but through a user stored procedure.  It takes the name of the THINK Enterprise database as a parameter from a USP and
**	checks that database for running processes.  Additional processes could be checked for a running state and stopped if necessary, simply add a duplicate transaction and
**	change the job_id to check for.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_checkProcesses')
	DROP PROCEDURE [dbo].[sub_checkProcesses];
GO

CREATE Procedure [dbo].[sub_checkProcesses](
	@processDbName	nvarchar(128)		--Required:	The target database where processes will be checked for a running status.
	,@tempTableId	int					--Required:	Unique ID that is appended to temporary tables.
	,@checkDebug	nchar(1) = 'n'		--Optional: When set, returns additional debugging information to diagnose errors.
)
AS
SET NOCOUNT ON 

DECLARE @processRunning		bit				--Indicates if a process on the target database is running: 0 = process is not running, 1 = process is running.
		,@castedTempTableId	nvarchar(8)		--Casts the tempTableId parameter as an nvarchar.
		,@jobColumnName		bit				--Replaces the use of the @thkVersion variables. Instead of determining the version of the database it simply checks if the job.job_status or job.status columns exist.
		,@thkVersion		numeric(2,1)	--The THINK Enterprise database version.
		,@thkVersionOUT		nvarchar(16)	--Used in dynamic SQL statements to populate the @thkVersion variable.
		,@sql				nvarchar(4000)
		,@printMessage		nvarchar(4000)
		,@errorMessage		nvarchar(4000)
		,@errorNumber		int
		,@errorSeverity		int
		,@errorLine			int
		,@errorState		int;

BEGIN TRY

	SET @castedTempTableId = CAST(@tempTableId AS nvarchar(8));

	/*
	**	Creates a temporary table that keeps track of all the job_id's that will need to be stopped and their corresponding process_id's.
	*/
	SET @sql = N'IF object_id(''tempdb..##process_principals_' + @castedTempTableId + N''') is null
				BEGIN
					CREATE TABLE ##process_principals_' + @castedTempTableId + N'(
						target_job_id	int	not null
						,process_id		int	not null

					CONSTRAINT PK_TEMP_PROCESS_PRINCIPALS PRIMARY KEY CLUSTERED (target_job_id)
					);
				END;';
	EXEC sp_executesql @sql

	SET @printMessage = 'Checking processes in a running state in the ' + @processDbName + ' database';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	/*
	**	This portion of code should not be commented out even though it is not currently used to determine if the Email/Event process is running.
	**	Instead a query is initiated against the target database to see if the job.job_status or job.status columns exist. The @thkVersion variables
	**	may still be needed/used to detect and stop other processes in the future.
	*/
	SET @sql = N'SET @thkVersionIN = (SELECT cur_vers FROM ' + @processDbName + N'.dbo.config)';
	EXEC sp_executesql @sql, N'@thkVersionIN nvarchar(16) OUTPUT', @thkVersionOUT OUTPUT; --Finds the THINK Enterprise version of the database and converts it to a numeric value.
	SET @thkVersion = CAST(SUBSTRING(@thkVersionOUT,1,3) AS numeric(2,1))

	/*
	**	Find if job has the job.status or job.job_status column.
	*/
	SET @sql = N'USE ' + QUOTENAME(@processDbName) + char(13) + char(10) +
				N'SET @jobColumnNameIN = (SELECT 1
				FROM sys.columns sc
					INNER JOIN sys.tables st
						ON st.object_id = sc.object_id
				WHERE st.name = ''job'' AND sc.name = ''status'')'
	EXEC sp_executesql @sql, N'@jobColumnNameIN bit OUTPUT', @jobColumnName OUTPUT --Finds if the job table currently uses the status column or job_status column.

	BEGIN TRANSACTION checkEmailEventQueue

		/*
		**	Checks to see if the Email/Event Queue process is currently running or attempting to be killed.  If the process is not completed or already killed then the sp
		**	will attempt to stop the process.
		*/
		IF @jobColumnName = 1
		BEGIN

			SET @sql = N'USE ' + QUOTENAME(@processDbName) + char(13) + char(10) +
						N'INSERT INTO ##process_principals_' + @castedTempTableId + N' (target_job_id, process_id)
							SELECT job_id [target_job_id], process_id
							FROM job
							WHERE process_id = 2100000007
								AND status in (0, 1, 2, 3, 5, 6)';
			EXEC sp_executesql @sql
		END
		ELSE
		BEGIN

			SET @sql = N'USE ' + QUOTENAME(@processDbName) + char(13) + char(10) +
						N'INSERT INTO ##process_principals_' + @castedTempTableId + N' (target_job_id, process_id)
							SELECT job_id [target_job_id], process_id
							FROM job
							WHERE process_id = 2100000007
								AND job_status in (2, 7, 8, 21, 22, 24)';
			EXEC sp_executesql @sql
		END
	COMMIT TRANSACTION;
	
	BEGIN TRANSACTION stopEmailEventQueue

		/*
		**	If running processes were recorded into the temp table then find out how many.  If there is at least one then continue to stop the process(es), otherwise incidate
		**	that Email/Event Queue was not running and continue.
		*/
		SET @sql = N'IF (SELECT COUNT(target_job_id) FROM ##process_principals_' + @castedTempTableId + N' WHERE process_id = 2100000007) >= 1
						SET @processRunningIN = 1;';
		EXEC sp_executesql @sql, N'@processRunningIN bit OUTPUT', @processRunning OUTPUT;

		IF @processRunning <> 1
			SET @processRunning = 0; --If @processRunning is not set then explicitly set it to 0.

		IF @processRunning = 1
		BEGIN
		
			RAISERROR('	Email/Event Queue process is currently running in target database, stopping process', 10, 1) WITH NOWAIT;

			/*
			**	Updates the running Email/Event Queue process(es) to a "Done" status.
			*/
			IF @thkVersion >= 7.1
			BEGIN
				SET @sql = N'USE ' + QUOTENAME(@processDbName) + char(13) + char(10) +
							N'UPDATE job
							SET status = 4
								,step_name = ''no step''
								,step_number = 999
							FROM job j
								INNER JOIN ##process_principals_' + @castedTempTableId + N' temp_pp
									ON temp_pp.target_job_id = j.job_id
							WHERE temp_pp.process_id = 2100000007';
				EXEC sp_executesql @sql;
			END
			ELSE
			BEGIN

				SET @sql = N'USE ' + QUOTENAME(@processDbName) + char(13) + char(10) +
							N'UPDATE job
							SET job_status = 255
							FROM job j
								INNER JOIN ##process_principals_' + @castedTempTableId + N' temp_pp
									ON temp_pp.target_job_id = j.job_id
							WHERE temp_pp.process_id = 2100000007';
				EXEC sp_executesql @sql;
			END

			RAISERROR('	Email/Event Queue process has successfully been stopped', 10, 1) WITH NOWAIT;
		END
		ELSE
			RAISERROR('	Email/Event Queue process is currently not running', 10, 1) WITH NOWAIT;
	COMMIT TRANSACTION;

	RAISERROR('All processes checked and necessary processes stopped', 10, 1) WITH NOWAIT;

	SET @sql = 'DROP TABLE ##process_principals_' + @castedTempTableId; --Drop the temp table now that we are done with it.
	EXEC sp_executesql @sql;
END TRY
BEGIN CATCH

	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @checkDebug = 'y'
	BEGIN
		
		SET @printMessage = 'An error occured in the sub_checkProcesses sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = N'IF object_id (''tempdb..##process_principals_' + @castedTempTableId + N''') is not null
					DROP TABLE ##process_principals_' + @castedTempTableId;
	EXEC (@sql);

	RAISERROR(@errorMessage, @errorSeverity, 1);
END CATCH;