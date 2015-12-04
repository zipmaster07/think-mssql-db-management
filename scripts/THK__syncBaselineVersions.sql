/*
**	This script can be used to synchronize all the dbAdmin.dbo.baseline_versions tables across all the instances. It can only be run from the SQL11 instance.
*/
USE [dbAdmin];
GO

SET NOCOUNT ON;

/*
**	Check if the SQL11 instance has baselines that the Support instance doesn't
*/
INSERT INTO [PRVTHKDB01\SUPPORT].dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT bv.baseline_version, bv.major_version_order, bv.minor_version_order, bv.patch_version_order, bv.backup_path, bv.is_available
FROM [PRVTHKDB01\SUPPORT].dbAdmin.dbo.baseline_versions sbv
	RIGHT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = sbv.baseline_version
WHERE sbv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'SQL11', 'SUPPORT', 'SUPPORT')

/*
**	Check if the Support instance has baselines that the SQL11 instance doesn't
*/
INSERT INTO dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT sbv.baseline_version, sbv.major_version_order, sbv.minor_version_order, sbv.patch_version_order, sbv.backup_path, sbv.is_available
FROM [PRVTHKDB01\SUPPORT].dbAdmin.dbo.baseline_versions sbv
	LEFT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = sbv.baseline_version
WHERE bv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'SUPPORT', 'SQL11', 'SQL11')

/*
**	Check if the SQL11 instance has baselines that the QA instance doesn't
*/
INSERT INTO [PRVTHKDB01\QA].dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT bv.baseline_version, bv.major_version_order, bv.minor_version_order, bv.patch_version_order, bv.backup_path, bv.is_available
FROM [PRVTHKDB01\QA].dbAdmin.dbo.baseline_versions qbv
	RIGHT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = qbv.baseline_version
WHERE qbv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'SQL11', 'QA', 'QA')

/*
**	Check if the QA instance has baselines that the SQL11 instance doesn't
*/
INSERT INTO dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT qbv.baseline_version, qbv.major_version_order, qbv.minor_version_order, qbv.patch_version_order, qbv.backup_path, qbv.is_available
FROM [PRVTHKDB01\QA].dbAdmin.dbo.baseline_versions qbv
	LEFT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = qbv.baseline_version
WHERE bv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'QA', 'SQL11', 'SQL11')

/*
**	Check if the SQL11 instance has baselines that the Dev instance doesn't
*/
INSERT INTO [PRVTHKDB01\DEV].dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT bv.baseline_version, bv.major_version_order, bv.minor_version_order, bv.patch_version_order, bv.backup_path, bv.is_available
FROM [PRVTHKDB01\DEV].dbAdmin.dbo.baseline_versions dbv
	RIGHT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = dbv.baseline_version
WHERE dbv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'SQL11', 'DEV', 'DEV')

/*
**	Check if the Dev instance has baselines that the SQL11 instance doesn't
*/
INSERT INTO dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT dbv.baseline_version, dbv.major_version_order, dbv.minor_version_order, dbv.patch_version_order, dbv.backup_path, dbv.is_available
FROM [PRVTHKDB01\DEV].dbAdmin.dbo.baseline_versions dbv
	LEFT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = dbv.baseline_version
WHERE bv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'DEV', 'SQL11', 'SQL11')

/*
**	Check if the SQL11 instance has baselines that the Legacy instance doesn't
*/
INSERT INTO [PRVTHKDB01\LEGACY].dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT bv.baseline_version, bv.major_version_order, bv.minor_version_order, bv.patch_version_order, bv.backup_path, bv.is_available
FROM [PRVTHKDB01\LEGACY].dbAdmin.dbo.baseline_versions lbv
	RIGHT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = lbv.baseline_version
WHERE lbv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'SQL11', 'LEGACY', 'LEGACY')

/*
**	Check if the Legacy instance has baselines that the SQL11 instance doesn't
*/
INSERT INTO dbAdmin.dbo.baseline_versions(baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
SELECT lbv.baseline_version, lbv.major_version_order, lbv.minor_version_order, lbv.patch_version_order, lbv.backup_path, lbv.is_available
FROM [PRVTHKDB01\LEGACY].dbAdmin.dbo.baseline_versions lbv
	LEFT OUTER JOIN dbAdmin.dbo.baseline_versions bv
		ON bv.baseline_version = lbv.baseline_version
WHERE bv.baseline_version is null

IF @@ROWCOUNT > 0
	RAISERROR(90503, -1, -1, 'LEGACY', 'SQL11', 'SQL11')