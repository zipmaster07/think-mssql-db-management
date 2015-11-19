/*
**	This stored procedure changes bank definition settings.  This sp is a sub stored procedure.  It is not meant to be called directly but through a user stored procedure.
**	The sp takes the name of a database and a binary value provided by the USP.  What exactly is changed in the bank definition(s) are determined by who is restoring the
**	database and how is it being restored.  When the database is being restored for the first time (meaning it just came from a customers site) or is specifically being
**	restored as dirty we change additional values that are specific to THINK such as merchant ID, username and password, etc.  If the database is not being restored for the
**	first time (a.k.a it is already clean or it isn't a customers database to begin with - most applicable to QA and Dev), then we don't want to change the current values
**	in these fields, so the sp simply checks to make sure the bank def is pointing to its payment gateway's test servers as opposed to the production servers.
*/

USE [dbAdmin];
GO

IF EXISTS(SELECT 1 FROM sys.procedures WHERE name = 'sub_setBankDefs')
	DROP PROCEDURE [dbo].[sub_setBankDefs]
GO

CREATE PROCEDURE [dbo].[sub_setBankDefs] (
	@icsDbName			nvarchar(128)	--Required:	The name of the database whose bank definition(s) will be changed.
	,@retainBankDefInfo	bit = 1			--Required:	Sets whether or not to retain the current bank definitions and just check for production values, or to completely overwrite the bank def: 0 = do not retain, 1 = retain.
	,@bankDebug			nchar(1) = 'n'	--Optional: When set, returns additional debugging information to diagnose errors.
)
AS
SET NOCOUNT ON

DECLARE	@syncProcessorProgId	nvarchar(128)	--The sync_processor_progid in the THINK Enterprise database.
		,@sendToProduction		nvarchar(8)		--Specifies if the payment requests should go to the payment processors production or test servers.  Doubles as: Litle's "testmode", Optimal's "testmode", Westpac's "testmode".
		,@serverUrl				nvarchar(256)	--Payment processors API endpoint.
		,@serverExpressUrl		nvarchar(256)	--PayPal's express API endpoint.
		,@merchantId			nvarchar(64)	--The merchant ID passed to the payment processor.  Doubles as Paymentech's "divisionNumber".
		,@storeId				nvarchar(32)	--Optimal's merchant store ID.  Is not equivalent to Optimal's merchant ID.
		,@username				nvarchar(128)	--Gateway's username.  Doubles as: Authorize.Net's "x_login".
		,@password				nvarchar(128)	--Gateway's password.  Doubles as: Authorize.Net's "x_tran_key".
		,@socksProxyPort		nvarchar(8)		--Port number for a SOCKS proxy.  Used for Paymentech only.
		,@socksProxyHost		nvarchar(128)	--Host name for a SOCKS proxy.  Used for Paymentech only.
		,@proxyPort				nvarchar(8)		--Send transactions to a proxy server before sending to the actual gateway using the specified port number.
		,@serverHost			nvarchar(256)	--The host name of the gateway.
		,@serverPort			nvarchar(8)		--The port number to connect to the gateway.
		,@billingDescriptor		nvarchar(64)	--A billing description for the Litle payment processor.
		,@reportGroup			nvarchar(64)	--A reporting group for the Litle payment processor.
		,@vendor				nvarchar(64)	--The vendor name for the PayFlow Pro payment processor.
		,@partner				nvarchar(64)	--The partner name for the PayFlow Pro payment processor.
		,@restrictLog			nvarchar(8)		--Sets whether to restrict the log.  Used for Paymentech only.
		,@ignoreCall			nvarchar(8)		--Paymentech setting.
		,@presenterId			nvarchar(64)	--Additional ID used for sending Paymentech batch transactions.
		,@submitterId			nvarchar(64)	--Additional ID used for sending Paymentech batch transactions.
		,@key					nvarchar(1024)	--The xaction_key or any other bank definition key used for contacting/authenticating to the payment gateway.
		,@refNbrPrefix			nvarchar(64)	--A prefix identifier used for Optimal and Westpac payment processor.
		,@count					int = 0			--Counter for any arbitrary number of operations.
		,@rowcount				bit				--Used to determine if a bank definition was actually found and the values changed.
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorSeverity			int
		,@errorNumber			int
		,@errorLine				int
		,@errorState			int;

BEGIN TRY

	SET @printMessage =  char(13) + char(10) + 'Finding Bank Defs:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF @retainBankDefInfo = 1
		SET @printMessage = '	Set to retain bank definition info, checking for production values only.  No other bank definition settings will be changed'
	ELSE
		SET @printMessage = '	Set to remove all bank definition info, checking all values.'

	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	/*
	**	Increase the ics_value column's max size.  This is necessary because of CyberSource Secure SOAP.  Even if there is no match to a CyberSource Secure SOAP bank
	**	definition the system will still throw a truncation error if the ics_value column isn't long enough.
	*/
	SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
				N'ALTER TABLE ics_name_value ALTER COLUMN ics_value varchar(1024) not null;';
	EXEC sp_executesql @sql;

	BEGIN TRAN updateCyberSrcBankDef --Is it a CyberSource definition?

		/*
		**	Setting variables for CyberSource.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcCyberSource.CyberSourceSync';
		SET @sendToProduction = 'false';
		SET @serverUrl = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor/';
		SET @merchantId = 'prussell';
		SET @serverHost = 'ics2test.ic3.com';
		SET @serverPort = '80';

		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set CyberSource server URL.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverUrl +
						N''' FROM ics_name_value inv
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''serverURL'''
			EXEC sp_executesql @sql;
			
			/*
			**	Set CyberSource merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''merchant_id'''
			EXEC sp_executesql @sql;

			/*
			**	Set CyberSource server host.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverHost +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''server_host'''
			EXEC sp_executesql @sql;

			/*
			**	Set CyberSource server port.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverPort +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''server_port'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set CyberSource @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = inv.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''sendToProduction'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found CyberSource';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateCyberSrc50BankDef --Is it a CyberSource 50 definition?

		/*
		**	Setting variables for CyberSource50.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcCyberSource50.CyberSource50Sync';
		SET @sendToProduction = 'false';
		SET @serverUrl = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor/';
		SET @merchantId = 'test';

		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set CyberSource 50 server URL.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverUrl +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''serverURL'''
			EXEC sp_executesql @sql;
		
			/*
			**	Set CyberSource 50 merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +			
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set CyberSource 50 @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = inv.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''sendToProduction'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found CyberSource 50'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateCyberSrcSecureBankDef --Is it a CyberSource Secure definition?

		/*
		**	Setting variables for CyberSourceSecure.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync';
		SET @sendToProduction = 'false';
		SET @merchantId = 'think_subscription';
		
		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set CyberSourceSecure merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set CyberSourceSecure @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''sendToProduction'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found CyberSource Secure'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateCyberSrcSecureSOAPBankDef --Is it a CyberSource Secure Soap definition?

		/*
		**	Setting variables for CyberSourceSecureSOAP.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap';
		SET @sendToProduction = 'false';
		SET @merchantId = 'think_subscription'
		SET @key = 'v7jCn8f/WuukKi1KdD3tFI97i3LkmXglp/LKKTvt2qWs8mxZynKCleh52VFP260XKv+t3Oxd1f29NsryOdjGIeRpuDr48D41LzZvbIjqOIqHm5VxfaJsXwjr8tD6dvtAhM0oT9Wj9YbTQcX/Rfqu0blBEHwAZ13TP4IyOsNoRwTdAUdbM6Jt2IFLdwIbr9bPz4AghYrlt4ybb7QImY4e8L/PTam/HQKhzxmuVgaFGhr6o/kVt2dL3aZzbG5LqbCFJbFaf954+VNR9+gnzxkjAD7d3n1pfPlfCD+MVXOiuLTtx+28VEfB+2k6c7Hy8juwldBdC3wYVcskAzsAJr3aAQ==';
		
		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set CyberSourceSecureSOAP merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N'''and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;

			/*
			**	Set CyberSourceSecureSOAP xaction_key.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @key +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N'''and ics_name = ''xaction_key'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set CyberSourceSecureSOAP @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N'''and ics_name = ''sendToProduction'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found CyberSource Secure Soap'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateNetGiroBankDef --Is it a NetGiro definition?
		
		/*
		**	Setting variables for NetGiro.  Netgiro has not indication of pointing to a test or production server.  Settings are only ever changed if restoring as clean or
		**	dirty.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcNetgiroSecure.NetgiroSecureSync';
		SET @proxyPort = '2828';
		SET @merchantId = '1699590972';

		IF @retainBankDefInfo = 0
		BEGIN

			/*
			**	Set Netgiro proxy port number.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @proxyPort +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''proxyport'''
			EXEC sp_executesql @sql;
			
			/*
			**	Set Netgiro merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		END;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found NetGiro'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateLitleBankDef --Is it a Litle definition?

		/*
		**	Setting variables for Litle.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcLitle.zzcoPmtProcLitle';
		SET @sendToProduction = 'true';
		SET @username = 'thnktkn';
		SET @password = 'cert76PfM';
		SET @merchantId = '029629';
		SET @billingDescriptor = 'IPM*InvestorPlaceMedia';
		SET @reportGroup = 'THKNKDEV';
		
		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set Litle merchant username.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''username'''
			EXEC sp_executesql @sql;

			/*
			**	Set Litle merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''password'''
			EXEC sp_executesql @sql;

			/*
			**	Set Litle merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;

			/*
			**	Set Litle billing descriptor.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @billingDescriptor +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''billingdescriptor'''
			EXEC sp_executesql @sql;

			/*
			**	Set Litle reporting group.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @reportGroup +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''reportgroup'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set Litle @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''testmode''';
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Litle'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateAuthorizeBankDef --Is it a Authorize.net definition?

		/*
		**	Setting variables for Authorize.net.  Authorize.Net's production settings are specified in the server host.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcAuthorize.AuthorizeSync';
		SET @serverHost = 'test.authorize.net';
		SET @username = 'cnpdev4564';
		SET @password = 'yourTranKey';

		IF @retainBankDefInfo = 0
		BEGIN

			/*
			**	Set Authorize.Net merchant username.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @username +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''x_login'''
			EXEC sp_executesql @sql;
		
			/*
			**	Set Authorize.Net merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''x_tran_key'''
			EXEC sp_executesql @sql;
		END;

		/*
		**	Set Authorize.Net @serverHost value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @serverHost +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''server_host'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Authorize.net'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updatePayFlowProSecureBankDef --Is it a PayFlowPro Secure definition?

		/*
		**	Setting variables for PayFlowPro.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure';
		SET	@password = 'th1nk12';
		SET @sendToProduction = 'false';
		SET	@username = 'thinksubscription';
		SET	@vendor = 'thinksubscription';
		SET	@partner = 'PayPal';

		IF @retainBankDefInfo = 0
		BEGIN

			/*
			**	Set PayFlow Pro merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''PWD'''
			EXEC sp_executesql @sql;
		
			/*
			**	Set PayFlow Pro merchant username.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @username +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''USER'''
			EXEC sp_executesql @sql;
		
			/*
			**	Set PayFlow Pro vendor.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @vendor +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''VENDOR'''
			EXEC sp_executesql @sql;

			/*
			**	Set PayFlow Pro partner.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @partner +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''PARTNER'''
			EXEC sp_executesql @sql;
		END;

		/*
		**	Set PayFlow Pro @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''SENDTOPRODUCTION'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found PayFlowPro v4'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;
	
	BEGIN TRAN updatePaymentechOnlineBankDef --Is it a Paymentech definition?

		/*
		**	Setting variables for Paymentech (Online).  Paymentech bank definitions are only ever changed when restoring as clean or dirty.  All original values are kept if
		**	restoring otherwise.
		*/

		SET @syncProcessorProgId = 'zzcoPmtProcPaymentech.PaymentechSync';
		SET @merchantId  = 'test';
		SET @serverHost = 'localhost';
		SET @serverPort = '77';
		SET @socksProxyHost = 'n/a';
		SET @socksProxyPort = '1080';
		SET @restrictLog = 'false';
		SET @ignoreCall = 'false';

		IF @retainBankDefInfo = 0
		BEGIN

			/*
			**	Set Paymentech online division number.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''division_number'''
			EXEC sp_executesql @sql;
		
			/*
			**	Set Paymentech online server host.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverHost +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''server_host'''
			EXEC sp_executesql @sql;

			/*
			**	Set Paymentech online server port.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @serverPort +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''server_port'''
			EXEC sp_executesql @sql;

			/*
			**	Set Paymentech online SOCKS proxy host.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @socksProxyHost +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''socks_proxy_host'''
			EXEC sp_executesql @sql;

			/*
			**	Set Paymentech online SOCKS proxy port number.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @socksProxyPort +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''socks_proxy_port'''
			EXEC sp_executesql @sql;

			/*
			**	Set Paymentech online restrict log setting.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @restrictLog +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''restrict_log'''
			EXEC sp_executesql @sql;

			/*
			**	Set Paymentech online ignore call setting.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @ignoreCall +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
						N''' and ics_name = ''ignore_call'''
			EXEC sp_executesql @sql;
		END

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Paymentech Online'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
		
		BEGIN TRAN updatePaymentBatchBankDef --Check if we also have a Batch Processor.

			/*
			**	Setting variables for Paymentech (Batch).  Paymentech bank definitions are only ever changed when restoring as clean or dirty.  All original values are kept
			**	if restoring otherwise.
			*/
			SET @syncProcessorProgId = 'zzcoPmtProcPaymentech.PaymentechBatch';
			SET @merchantId  = '123456';
			SET @ignoreCall = 'false';
			SET @presenterId = 'test';
			SET @serverHost = 'localhost';
			SET @serverPort = '78';
			SET @socksProxyHost = 'n/a';
			SET @socksProxyPort = '1080';
			SET @restrictLog = 'false';
			SET @submitterId = 'test';
			SET @password = 'test';
			
			IF @retainBankDefInfo = 0
			BEGIN

				/*
				**	Set Paymentech batch division number.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @merchantId +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''division_number'''
				EXEC sp_executesql @sql;
				
				/*
				**	Set Paymentech batch ignore call setting.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
							N'update ics_name_value_batch SET ics_value = ''' + @ignoreCall +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''ignore_call'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch presenter ID.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @presenterId +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''presenter_id'''
				EXEC sp_executesql @sql;
			
				/*
				**	Set Paymentech batch present ID password.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @password +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''presenter_password'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch server host.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @serverHost +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''server_host'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @serverPort +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''server_port'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch SOCKS proxy host.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @socksProxyHost +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''socks_proxy_host'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch SOCKS proxy port.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @socksProxyPort +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''socks_proxy_port'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch restrict log setting.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @restrictLog +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''restrict_log'''
				EXEC sp_executesql @sql;

				/*
				**	Set Paymentech batch submitter ID.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @submitterId +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''submitter_id'''
				EXEC sp_executesql @sql;
		
				/*
				**	Set Paymentech batch submitter ID password.
				*/
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch SET ics_value = ''' + @password +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @syncProcessorProgId +
						N''' and inv.ics_name = ''submitter_password'''
				EXEC sp_executesql @sql;
			END;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @count = @count + 1;
				SET @printMessage =  '		Found Paymentech Batch'
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END
		COMMIT TRAN;
	COMMIT TRAN;
	
	BEGIN TRAN updatePayPalBankDef --Is it a PayPal definition?

		/*
		**	Setting variables for PayPal.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcPayPal.PayPalSync';
		SET @serverUrl = 'api.sandbox.paypal.com';
		SET @serverExpressUrl = 'api-aa.sandbox.paypal.com';
		SET @username = 'think1_api1.thinksubscription.com';
		SET @password = 'think1api1';

		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set PayPal merchant username.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''api_username'''
			EXEC sp_executesql @sql;

			/*
			**	Set PayPal merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''api_password'''
			EXEC sp_executesql @sql;
		END


		/*
		**	Set PayPal @serverExpressUrl value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +			
					N'update ics_name_value SET ics_value = ''' + @serverExpressUrl +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''server_host_express'''
		EXEC sp_executesql @sql;

		/*
		**	Set PayPal @serverUrl value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @serverUrl +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''server_host'''
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found PayPal'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateOptimalBankDef --Is it a Optimal definition?

		/*
		**	Setting variables for Optimal.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcOptimal.Optimal';
		SET @sendToProduction = 'true';
		SET @merchantId = '89991911';
		SET @password = 'test';
		SET @storeId = 'tst';
		SET @refNbrPrefix = 'PFX-USD-';

		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set Optimal merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''MERCHANTNUMBER'''
			EXEC sp_executesql @sql;

			/*
			**	Set Optimal merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''MERCHANTPASSWORD'''
			EXEC sp_executesql @sql;

			/*
			**	Set Optimal store ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @storeId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''MERCHANTSTOREID'''
			EXEC sp_executesql @sql;

			/*
			**	Set Optimal reference number prefix.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @refNbrPrefix +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''REFNUMPREFIX'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set Optimal @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''testmode''';
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Optimal'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;
		
	BEGIN TRAN updateWestpacBankDef --Is it a Westpac definition?

		/*
		**	Setting variables for Westpac.
		*/
		SET @syncProcessorProgId = 'zzcoPmtProcWestpac.zzcoPmtProcWestpac';
		SET @sendToProduction = 'true';
		SET @merchantId = 'FMG_FRG';
		SET @username = 'FAIRFAX';
		SET @password = 'FAIRFAX';
		SET @refNbrPrefix = 'PFX';

		IF (@retainBankDefInfo = 0)
		BEGIN

			/*
			**	Set Westpac merchant ID.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @merchantId +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''MERCHANTNUMBER'''
			EXEC sp_executesql @sql;
			
			/*
			**	Set Westpac merchant password.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''PASSWORD'''
			EXEC sp_executesql @sql;

			/*
			**	Set Westpac merchant username.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''USERNAME'''
			EXEC sp_executesql @sql;

			/*
			**	Set Westpac reference number prefix.
			*/
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value SET ics_value = ''' + @refNbrPrefix +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''REFNUMPREFIX'''
			EXEC sp_executesql @sql;
		END

		/*
		**	Set Westpac @sendToProduction value.  Always changed if a bank definition is found.
		*/
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value SET ics_value = ''' + @sendToProduction +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @syncProcessorProgId +
					N''' and ics_name = ''testmode''';
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Westpac'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	IF @count = 0
		SET @printMessage =  '	No bank defs where found.  You ain''t makin'' any $' + char(13) + char(10);
	ELSE
		SET @printMessage =  'All bank defs found' + char(13) + char(10);

	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
END TRY
BEGIN CATCH
	
	IF @@TRANCOUNT > 0
		ROLLBACK;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorNumber = ERROR_NUMBER()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @bankDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_setBankDefs sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	RAISERROR(@errorMessage, @errorSeverity, 1)
END CATCH;
