USE [dbAdmin]
GO

/****** Object:  StoredProcedure [dbo].[CommandExecute]    Script Date: 10/2/2012 1:32:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[CommandExecute]

@Command nvarchar(max),
@Comment nvarchar(max),
@Mode int,
@Execute nvarchar(max)

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  SET LOCK_TIMEOUT 3600000

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @StartTime datetime
  DECLARE @EndTime datetime

  DECLARE @Error int

  SET @Error = 0

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @Command IS NULL OR @Command = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Command is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Comment IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Comment is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Mode NOT IN(1,2) OR @Mode IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Mode is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO ReturnCode

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartTime = CONVERT(datetime,CONVERT(varchar,GETDATE(),120),120)

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,@StartTime,120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Command: ' + @Command
  IF @Comment <> '' SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10) + 'Comment: ' + @Comment
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Execute command                                                                            //--
  ----------------------------------------------------------------------------------------------------

  IF @Mode = 1 AND @Execute = 'Y'
  BEGIN
    EXECUTE(@Command)
    SET @Error = @@ERROR
  END

  IF @Mode = 2 AND @Execute = 'Y'
  BEGIN
    BEGIN TRY
      EXECUTE(@Command)
    END TRY
    BEGIN CATCH
      SET @Error = ERROR_NUMBER()
      SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
      RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    END CATCH
  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  SET @EndTime = CONVERT(datetime,CONVERT(varchar,GETDATE(),120),120)

  SET @EndMessage = 'Outcome: ' + CASE WHEN @Execute = 'N' THEN 'Not Executed' WHEN @Error = 0 THEN 'Succeeded' ELSE 'Failed' END + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'Duration: ' + CASE WHEN DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) > 0 THEN CAST(DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) AS nvarchar) + '.' ELSE '' END + CONVERT(nvarchar,@EndTime - @StartTime,108) + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'DateTime: ' + CONVERT(nvarchar,@EndTime,120) + CHAR(13) + CHAR(10)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Return code                                                                                //--
  ----------------------------------------------------------------------------------------------------

  ReturnCode:

  RETURN @Error

  ----------------------------------------------------------------------------------------------------

END



GO


