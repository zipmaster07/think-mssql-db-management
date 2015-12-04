/*
**	This stored procedure formats error messages that can be used in a CATCH block of a TRY...CATCH. This is a sub sp, it should be called
**	from a usp. The sp uses the formatErrorMsg function to actually format the error message text.
*/

USE [dbAdmin];
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_formatErrorMsg')
	DROP PROCEDURE [dbo].[sub_formatErrorMsg]
GO

CREATE PROCEDURE [dbo].[sub_formatErrorMsg] (
	@formatSpName	nvarchar(64) = null		--Optional:	The name of the stored procedure that threw the error message. If not provided then the sp will attempt to figure out the stored procedure.
	,@errorSeverity	int OUTPUT				--Output:	Stores the ERROR_SEVERITY(). The severity is output to the calling stored procedure to indicate whether it should continue processing or abort.
	,@formatDebug	char(1) = 'n'			--Optional:	If debug is set to 'y' then additional information is returned.
	,@stringData0	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData1	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData2	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData3	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData4	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData5	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData6	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData7	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData8	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@stringData9	nvarchar(1024) = null	--Optional:	Can be used to provide additional string (%s) information when the message requires it.
	,@intData0		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData1		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData2		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData3		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData4		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData5		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData6		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData7		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData8		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
	,@intData9		int = null				--Optional:	Can be used to provide additional numeric (%d) information when the message requires it.
)WITH EXECUTE AS OWNER
AS

DECLARE @printMessage			nvarchar(4000)	--Used to format all the message components.
		,@errorMessage			nvarchar(4000)	--Stores the value of ERROR_MESSAGE().
		,@errorNumber			int				--Stores the value of ERROR_NUMBER().
		,@errorState			int				--Stores the value of ERROR_STATE().
		,@errorProcedure		nvarchar(128)	--Stores the value of ERROR_PROCEDURE(). This value can be overridden by a user defined value.
		,@errorLine				int;			--Stores the value of ERROR_LINE().

/*
**	Select the current error message, severity, number, and line, then format the data.
*/
SELECT @errorMessage = ERROR_MESSAGE()
		,@errorSeverity = ERROR_SEVERITY()
		,@errorNumber = ERROR_NUMBER()
		,@errorState = ERROR_STATE()
		,@errorProcedure = COALESCE(@formatSpName, ERROR_PROCEDURE(), NULL)
		,@errorLine = ERROR_LINE();

/*
**	Provide custom error messages based on what the system returns.
*/
BEGIN

	IF @errorNumber = 1802 --Database could not be created because the same filename already exists on the database server.
	BEGIN

		IF @intData0 < 10
		BEGIN

			SET @errorNumber = 70501;
			SET @errorSeverity = 10
		
			SET @printMessage = dbAdmin.dbo.formatErrorMsg(0, @errorState, @errorNumber, @errorProcedure, @errorLine, 1033, @formatDebug);
			RAISERROR(@printMessage, @errorSeverity, @errorState, @stringData0, @stringData1, @stringData2)
			RETURN (1) --Running the message with additional data, so the end RAISERROR should not be called.
		END;
	END

	IF @errorNumber = 5069 --Failed to alter the database
	BEGIN

		IF @formatDebug = 'y'
		BEGIN

			SET @errorNumber = 87002;
			SET @errorSeverity = 11;

			SET @printMessage = dbAdmin.dbo.formatErrorMsg(0, @errorState, @errorNumber, @errorProcedure, @errorLine, 1033, @formatDebug);
		END;
		ELSE
		BEGIN
			
			SET @errorNumber = 80501;
			SET @errorSeverity = 10;

			SET @printMessage = dbAdmin.dbo.formatErrorMsg(0, @errorState, @errorNumber, @errorProcedure, @errorLine, 1033, @formatDebug);
		END;
	END;
	ELSE
	BEGIN

		IF @formatDebug = 'y'
			SET @printMessage = char(13) + char(10) +
								N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
								N'Error Number			Error Severity			Error Procedure				Error Line #' + char(13) + char(10) +
								N'------------------------------------------------------------------------------------------------------' + char(13) + char(10) +
								CONVERT(nvarchar(8), @errorNumber) + '					' + CONVERT(nvarchar(8), @errorSeverity) + '						'
								+ ISNULL(CONVERT(nvarchar(32), @errorProcedure), 'NULL') + '		' + CONVERT(nvarchar(8), @errorLine) + char(13) + char(10)
								+ char(13) + char(10) + char(13) + char(10) +
								N'Error Message:		' + @errorMessage + char(13) + char(10) +
								N'------------------------------------------------------------------------------------------------------';
		ELSE
		BEGIN

			RAISERROR(@errorMessage, -1, -1)
			RETURN (1)
		END;
	END;

	RAISERROR(@printMessage, @errorSeverity, @errorState)
END;