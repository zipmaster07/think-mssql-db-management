/*
**	This function formats error messages that can be used in a CATCH block of a TRY...CATCH. The function returns an nvarchar.
*/
USE [dbAdmin];
GO

IF object_id (N'dbo.formatErrorMsg', N'FN') IS NOT NULL
	DROP FUNCTION [dbo].[formatErrorMsg]
GO

CREATE FUNCTION [dbo].[formatErrorMsg] (
	@messageType			bit				--The message can be a warning or an error. The message header will change depending on the messageType. 0 - warning, 1 - error
	,@formatState			int				--A user defined state.
	,@formatNumber			int				--master.sys.messages.message_id
	,@formatProcedure		nvarchar(64)	--The name of the stored procedure that the error occured in.
	,@formatLine			int				--The line number that the error occured at.
	,@langId				int				--master.sys.message.language_id
	,@debug					nchar(1) = 'n'	--Return additional information is debug is set to 'y'
)
RETURNS nvarchar(4000) WITH EXECUTE AS OWNER
AS
BEGIN

	DECLARE @formatMessage		nvarchar(4000)	--The text of the error message.
			,@formatSeverity	int				--The severity of the error message.
			,@warningHeader		nvarchar(128)	--Used to construct a message that returns a warning.
			,@errorHeader		nvarchar(128)	--Used to construct a message that returns an error.
			,@columnHeaders		nvarchar(512)	--Used to construct the messages column headers.
			,@errorBody			nvarchar(1024)	--Used to construct the message body of non debug messages.
			,@debugErrorBody	nvarchar(1024)	--Used to construct the message body of debug messages.
			,@errorFooter		nvarchar(128)	--Used to construct the message footer.
			,@printMessage		nvarchar(4000);

	SET @printMessage = NULL

	IF @langId is null
		SET @langId = (SELECT msglangid FROM sys.syslanguages WHERE name = @@language);

	SET @formatMessage = (SELECT text FROM sys.messages WHERE message_id = @formatNumber AND language_id = @langId);
	SET @formatSeverity = (SELECT severity FROM sys.messages WHERE message_id = @formatNumber AND language_id = @langId);

	/*
	**	Set all static character formatting.
	*/
	SET @warningHeader = char(13) + char(10) + N'WARNING: The system encountered a warning' + char(13) + char(10)
	SET @errorHeader = char(13) + char(10) + N'ERROR: Error encountered while processing' + char(13) + char(10)
	SET @columnHeaders = N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
						N'Error Number			Error Severity			Error Procedure				Error Line #' + char(13) + char(10) +
						N'------------------------------------------------------------------------------------------------------' + char(13) + char(10)
	SET @errorBody = @formatMessage + char(13) + char(10)
	SET @debugErrorBody = CONVERT(nvarchar(8), @formatNumber) + '					' + CONVERT(nvarchar(8), @formatSeverity) + '						' 
					+ ISNULL(CONVERT(nvarchar(32), @formatProcedure), 'NULL') + '		' + CONVERT(nvarchar(8), @formatLine) + char(13) + char(10)
					+ char(13) + char(10) + char(13) + char(10) +
					N'Error Message:		' + @formatMessage + char(13) + char(10)		
	SET @errorFooter = N'------------------------------------------------------------------------------------------------------'

	/*
	**	Construct the error message from all its components.
	*/
	IF @debug = 'y'
		SET @printMessage = @columnHeaders + @debugErrorBody + @errorFooter;
	ELSE
		SET @printMessage = @errorBody;

	IF @messageType = 0
		SET @printMessage = @warningHeader + @printMessage;
	ELSE IF @messageType = 1
		SET @printMessage = @errorHeader + @printMessage;

	RETURN(@printMessage); --Return the formatted message.
END;