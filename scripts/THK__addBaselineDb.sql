/*
**	Use this script to create new baseline databases for the usp_THKRestoreDb stored procedure.  After running the below script you can call
**	the sp with the special "##" command in the @setBackupFile parameter (see sp documentation for more information).  Replace path/filename
**	in the RESTORE DATABASE & BACKUP DATABASE commands as well as the values in the INSERT INTO command.
**	
**	The following has to be changed to import a new baseline:
**	1.	Under the RESTORE DATABASE command change the value under the FROM DISK parameter.
**	2.	Under the BACKUP DATABASE command change the value under the TO DISK parameter.
**	3.	Under the BACKUP DATABASE command change the value under the NAME parameter.
**	4.	Under the INSERT INTO command change the values for the baseline_version, major_version_order, minor_version_order, patch_version_order, and backup_path columns.
*/

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'newBaselineDb')
	DROP DATABASE [newBaselineDb];

CREATE DATABASE [newBaselineDb] ON  PRIMARY 
( NAME = N'newBaselineDb', FILENAME = N'R:\MSSQL10_50.SUPPORT\MSSQL\Data\newBaselineDb.mdf' , SIZE = 3072KB , FILEGROWTH = 1024KB )
 LOG ON 
( NAME = N'newBaselineDb_log', FILENAME = N'S:\MSSQL10_50.SUPPORT\MSSQL\Logs\newBaselineDb_log.ldf' , SIZE = 1024KB , FILEGROWTH = 10%)
GO
ALTER DATABASE [newBaselineDb] SET COMPATIBILITY_LEVEL = 100
ALTER DATABASE [newBaselineDb] SET ANSI_NULL_DEFAULT OFF 
ALTER DATABASE [newBaselineDb] SET ANSI_NULLS OFF 
ALTER DATABASE [newBaselineDb] SET ANSI_PADDING OFF 
ALTER DATABASE [newBaselineDb] SET ANSI_WARNINGS OFF 
ALTER DATABASE [newBaselineDb] SET ARITHABORT OFF 
ALTER DATABASE [newBaselineDb] SET AUTO_CLOSE OFF 
ALTER DATABASE [newBaselineDb] SET AUTO_CREATE_STATISTICS ON 
ALTER DATABASE [newBaselineDb] SET AUTO_SHRINK OFF 
ALTER DATABASE [newBaselineDb] SET AUTO_UPDATE_STATISTICS ON 
ALTER DATABASE [newBaselineDb] SET CURSOR_CLOSE_ON_COMMIT OFF 
ALTER DATABASE [newBaselineDb] SET CURSOR_DEFAULT  GLOBAL 
ALTER DATABASE [newBaselineDb] SET CONCAT_NULL_YIELDS_NULL OFF 
ALTER DATABASE [newBaselineDb] SET NUMERIC_ROUNDABORT OFF 
ALTER DATABASE [newBaselineDb] SET QUOTED_IDENTIFIER OFF 
ALTER DATABASE [newBaselineDb] SET RECURSIVE_TRIGGERS OFF 
ALTER DATABASE [newBaselineDb] SET DISABLE_BROKER 
ALTER DATABASE [newBaselineDb] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
ALTER DATABASE [newBaselineDb] SET DATE_CORRELATION_OPTIMIZATION OFF 
ALTER DATABASE [newBaselineDb] SET PARAMETERIZATION SIMPLE 
ALTER DATABASE [newBaselineDb] SET READ_COMMITTED_SNAPSHOT OFF 
ALTER DATABASE [newBaselineDb] SET READ_WRITE 
ALTER DATABASE [newBaselineDb] SET RECOVERY FULL 
ALTER DATABASE [newBaselineDb] SET MULTI_USER 
ALTER DATABASE [newBaselineDb] SET PAGE_VERIFY CHECKSUM
GO
USE [newBaselineDb]
GO
IF NOT EXISTS (SELECT name FROM sys.filegroups WHERE is_default=1 AND name = N'PRIMARY') ALTER DATABASE [newBaselineDb] MODIFY FILEGROUP [PRIMARY] DEFAULT
GO

USE [master]
RESTORE DATABASE [newBaselineDb] FROM DISK = N'U:\DIRTY\baseline_sql05_74110.bak' WITH FILE = 1
	,MOVE N'e4_2_2_0_baseline_data' TO N'R:\MSSQL10_50.SUPPORT\MSSQL\Data\newBaselineDb.mdf'
	,MOVE N'e4_2_2_0_baseline_log' TO N'S:\MSSQL10_50.SUPPORT\MSSQL\Logs\newBaselineDb_log.ldf'
	,NOUNLOAD
	,REPLACE
	,STATS = 5
GO

USE [newBaselineDb]
GO
DROP SCHEMA [dev]
GO
USE [newBaselineDb]
GO
DROP USER [dev]
GO

USE [newBaselineDb]
GO
DROP SCHEMA [sfoster]
GO
USE [newBaselineDb]
GO
DROP USER [sfoster]
GO

USE [master]
GO
ALTER DATABASE [newBaselineDb] SET COMPATIBILITY_LEVEL = 100
GO

BACKUP DATABASE [newBaselineDb] TO DISK = N'U:\MSSQL10_50.SUPPORT\MSSQL\Backup\baseline_sql08_74110.bak' WITH FORMAT
	,INIT
	,NAME = N'THINK Enterprise baseline: Version 7.4.1.10 - Full'
	,SKIP
	,NOREWIND
	,NOUNLOAD
	,STATS = 5
GO

INSERT INTO dbAdmin.dbo.baseline_versions (baseline_version, major_version_order, minor_version_order, patch_version_order, backup_path, is_available)
	VALUES ('7.4.1.10', 5, 2, 4, '\\PRVTHKDB01\BASELINES\baseline_sql08_74110.bak', 1)
GO

DROP DATABASE [newBaselineDb];