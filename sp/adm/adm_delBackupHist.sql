USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'adm_delBackupHist')
	DROP PROCEDURE [dbo].[adm_delBackupHist];
GO

CREATE PROCEDURE [dbo].[adm_delBackupHist]

AS
SET NOCOUNT ON;
BEGIN

	DECLARE @retentionDays	varchar(5)
			,@today			datetime;
	
	DECLARE @BackupID TABLE (
		backupId int
	);	

	SET @today = GETDATE(); --Should be coalesced
	 
	SELECT @retentionDays = p_value --Should be coalesced
	FROM dbo.params
	WHERE p_key = 'BackupHistoryRetention';

	INSERT INTO @BackupID (BackupID)
		SELECT backup_id
		FROM dbo.backup_history
		WHERE DATEDIFF(dd, backup_start_date, @today) > @retentionDays

	DELETE FROM backup_history
	WHERE backup_id
		IN (SELECT BackupID FROM @BackupID);

	DELETE FROM	backup_history_file
	WHERE backup_id
		IN (SELECT BackupID FROM @BackupID);
END
GO


