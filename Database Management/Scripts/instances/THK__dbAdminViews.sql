USE [dbAdmin];
GO

/*
**	CREATE VIEW statements
*/
CREATE VIEW [dbo].[available_stored_procedures]
AS
SELECT stored_proc [Stored Procedure]
FROM dbAdmin.dbo.db_stored_proc_rights
WHERE is_applicable = 1;
GO

CREATE VIEW [dbo].[recent_restore_history]
AS
SELECT TOP(25) rh.restore_id [ID], rh.database_name [Database Name], rh.restore_start_date [Start Datetime],
		rh.restore_end_date [Stop Datetime], rh.user_name [Restored By]
		,CASE
			WHEN rhf.filename LIKE '\\PRVTHKDB01\BASELINES\%'
				THEN 'From baseline repository'
			ELSE rhf.filename
		END [Restored From File]			
		,CASE rhf.filetype
			WHEN 'l'
				THEN 'litespeed'
			WHEN 'n'
				THEN 'native'
			ELSE 'unknown'
		END [Backup Type]
FROM restore_history rh
	INNER JOIN restore_history_file rhf
		ON rhf.restore_id = rh.restore_id
ORDER BY rh.restore_id DESC;
GO