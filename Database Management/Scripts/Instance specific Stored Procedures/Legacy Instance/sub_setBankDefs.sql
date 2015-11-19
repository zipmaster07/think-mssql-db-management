USE [dbAdmin];
GO

IF EXISTS(SELECT 1 FROM sys.procedures WHERE name = 'sub_setBankDefs')
	DROP PROCEDURE [dbo].[sub_setBankDefs]
GO

CREATE PROCEDURE [dbo].[sub_setBankDefs] (
	@icsDbName			nvarchar(128)
	,@retainBankDefInfo	bit = 1
)
AS
SET NOCOUNT ON


/*
**	Who is restoring the database and how is it being restored? When the database is being restored for the
**	first time (meaning it just came from a customers site) or is specifically being restored as dirty we
**	change additional values that are specific to THINK such as merchant ID, username and password, etc.
**	If the database is not being restored for the first time (a.k.a it is already clean or it isn't a
**	customers database to being with - most applicable to QA and Dev), then we don't want to change the
**	current values in these fields, so the sp simply checks to make sure the bank def is pointing to its
**	payment gateway's test servers as opposed to the production servers.
*/

------------------------------------
-- Variables for the Cyber Source --
------------------------------------
DECLARE	@sql			nvarchar(4000)
		,@count			int
		,@rowcount		bit
		,@printMessage	nvarchar(4000)
		,@errorMessage	nvarchar(4000)
		,@errorSeverity	int
		,@errorNumber	int;

SET @count = 0;

declare   @CS_sync_processor_progid varchar(80),
		  @CS_send_to_production varchar(20),
		  @CS_server_URL varchar(80),
		  @CS_merchant_id varchar(30),
		  @CS_server_host varchar(20),
		  @CS_server_port varchar(10);

set @CS_sync_processor_progid = 'zzcoPmtProcCyberSource.CyberSourceSync';
set @CS_send_to_production = 'false';
set @CS_server_URL = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor/';
set @CS_merchant_id = 'prussell';
set @CS_server_host = 'ics2test.ic3.com';
set @CS_server_port = '80';

---------------------------------------
-- Variables for the Cyber Source 50 --
---------------------------------------
declare	  @CS_50_sync_processor_progid varchar(80),
		  @CS_50_send_to_production varchar(20),
		  @CS_50_server_URL varchar(80),
		  @CS_50_merchant_id varchar(30);

set @CS_50_sync_processor_progid = 'zzcoPmtProcCyberSource50.CyberSource50Sync';
set @CS_50_send_to_production = 'false';
set @CS_50_server_URL = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor/';
set @CS_50_merchant_id = 'test';
		  
-------------------------------------------
-- Variables for the Cyber Source Secure --
-------------------------------------------
declare	  @CS_Secure_sync_processor_progid varchar(80),
		  @CS_Secure_send_to_production varchar(20),
		  @CS_Secure_merchant_id varchar(30);

set @CS_Secure_sync_processor_progid = 'zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync';
set @CS_Secure_send_to_production = 'false';
set @CS_Secure_merchant_id = 'think_subscription';

-----------------------------------------------
-- Variables for the Cyber Source Secure SOAP--
-----------------------------------------------
declare	  @CS_Secure_Soap_sync_processor_progid varchar(80),
		  @CS_Secure_Soap_send_to_production varchar(20),
		  @CS_Secure_Soap_merchant_id varchar(30);

set @CS_Secure_Soap_sync_processor_progid = 'zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap';
set @CS_Secure_Soap_send_to_production = 'false';
set @CS_Secure_Soap_merchant_id = 'think_subscription';

-------------------------------
-- Variables for the NetGiro --
-------------------------------
declare	  @NG_sync_processor_progid varchar(80),
		  @NG_proxyport varchar(20),
		  @NG_merchant_id varchar(30);

set @NG_sync_processor_progid = 'zzcoPmtProcNetgiroSecure.NetgiroSecureSync';
set @NG_proxyport = '2828';
set @NG_merchant_id = '1699590972';

-----------------------------
-- Variables for the Litle --
-----------------------------
declare	  @Ltl_sync_processor_progid varchar(80),
		  @Ltl_testmode varchar(20),
		  @Ltl_username varchar(30),
		  @Ltl_password varchar(30),
		  @Ltl_merchantid varchar (20),
		  @Ltl_billing_descriptor varchar(40),
		  @Ltl_report_group varchar (40);

set @Ltl_sync_processor_progid = 'zzcoPmtProcLitle.zzcoPmtProcLitle';
set @Ltl_testmode = 'true';
set @Ltl_username = 'thnktkn';
set @Ltl_password = 'cert76PfM';
set @Ltl_merchantid = '029629';
set @Ltl_billing_descriptor = 'IPM*InvestorPlaceMedia';
set @Ltl_report_group = 'THKNKDEV';

---------------------------------
-- Variables for Authorize.net --
---------------------------------
declare	  @An_sync_processor_progid varchar(80),
		  @An_server_host varchar(20),
		  @An_x_login varchar(40),
		  @An_x_tran_key varchar(40);

set @An_sync_processor_progid = 'zzcoPmtProcAuthorize.AuthorizeSync';
set @An_server_host = 'test.authorize.net';
set @An_x_login = 'cnpdev4564';
set @An_x_tran_key = 'yourTranKey';

-----------------------------------
-- Variables for the PayFlowPro  --
-----------------------------------
declare	@PFP_sync_processor_progid varchar(80),
		@PFP_PWD varchar(20),
		@PFP_SENDTOPRODUCTION varchar(10),
		@PFP_USER varchar(40),
		@PFP_VENDOR varchar(40),
		@PFP_PARTNER varchar(40);
		
set @PFP_sync_processor_progid = 'zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure';
set	@PFP_PWD = 'th1nk12';
set @PFP_SENDTOPRODUCTION = 'false';
set	@PFP_USER = 'thinksubscription';
set	@PFP_VENDOR = 'thinksubscription';
set	@PFP_PARTNER = 'PayPal';

-------------------------------------------
-- Variables for the Paymentech (Online) --
-------------------------------------------
declare	@PTo_sync_processor_progid varchar(80),
		@PTo_divison_number varchar(10),
		@PTo_server_host varchar(20),
		@PTo_server_port varchar(10),
		@PTo_socks_proxy_host varchar(10),
		@PTo_socks_proxy_port varchar(10),
		@PTo_restrict_log varchar(10),
		@PTo_ignore_call varchar(10);
		
set @PTo_sync_processor_progid = 'zzcoPmtProcPaymentech.PaymentechSync';
set @PTo_divison_number  = 'test';
set @PTo_server_host = 'localhost';
set @PTo_server_port = '77';
set @PTo_socks_proxy_host = 'n/a';
set @PTo_socks_proxy_port = '1080';
set @PTo_restrict_log = 'false';
set @PTo_ignore_call = 'false';

-------------------------------------------
-- Variables for the Paymentech (Batch) --
-------------------------------------------
declare	@PTb_sync_processor_progid varchar(80),
		@PTb_divison_number varchar(10),
		@PTb_ignore_call varchar(10),
		@PTb_presenter_id varchar(10),
		@PTb_presenter_password varchar(10),
		@PTb_server_host varchar(20),
		@PTb_server_port varchar(10),
		@PTb_socks_proxy_host varchar(10),
		@PTb_socks_proxy_port varchar(10),
		@PTb_restrict_log varchar(10),
		@PTb_submitter_id varchar(10),
		@PTb_submitter_password varchar(10);

set @PTb_sync_processor_progid = 'zzcoPmtProcPaymentech.PaymentechBatch';
set @PTb_divison_number  = '123456';
set @PTb_ignore_call = 'false';
set @PTb_presenter_id = 'test';
set @PTb_presenter_password = 'test';
set @PTb_server_host = 'localhost';
set @PTb_server_port = '78';
set @PTb_socks_proxy_host = 'n/a';
set @PTb_socks_proxy_port = '1080';
set @PTb_restrict_log = 'false';
set @PTb_submitter_id = 'test';
set @PTb_submitter_password = 'test';

------------------------------
-- Variables for the PayPal --
------------------------------
declare	  @PP_sync_processor_progid varchar(80),
		  @PP_server_URL varchar(80),
		  @PP_server_express_URL varchar(80),
		  @PP_api_username varchar(80),
		  @PP_api_password varchar(80);

set @PP_sync_processor_progid = 'zzcoPmtProcPayPal.PayPalSync';
set @PP_server_URL = 'api.sandbox.paypal.com';
set @PP_server_express_URL = 'api-aa.sandbox.paypal.com';
set @PP_api_username = 'think1_api1.thinksubscription.com';
set @PP_api_password = 'think1api1';

-------------------------------
-- Variables for the Optimal --
-------------------------------
declare	  @Opt_sync_processor_progid varchar(80),
		  @Opt_testmode varchar(20),
		  @Opt_merchant_number varchar(30),
		  @Opt_merchant_password varchar(30),
		  @Opt_merchant_store_id varchar (30),
		  @Opt_ref_num_prefix varchar(40);

set @Opt_sync_processor_progid = 'zzcoPmtProcOptimal.Optimal';
set @Opt_testmode = 'true';
set @Opt_merchant_number = '89991911';
set @Opt_merchant_password = 'test';
set @Opt_merchant_store_id = 'tst';
set @Opt_ref_num_prefix = 'PFX-USD-';

-------------------------------
-- Variables for the Westpac --
-------------------------------
declare	  @WP_sync_processor_progid varchar(80),
		  @WP_testmode varchar(20),
		  @WP_merchant_number varchar(30),
		  @WP_password varchar(30),
		  @WP_username varchar (30),
		  @WP_ref_num_prefix varchar(40);

set @WP_sync_processor_progid = 'zzcoPmtProcWestpac.zzcoPmtProcWestpac';
set @WP_testmode = 'true';
set @WP_merchant_number = 'FMG_FRG';
set @WP_username = 'FAIRFAX';
set @WP_password = 'FAIRFAX';
set @WP_ref_num_prefix = 'PFX';

-------------------------------------------------------------
-------------------- End of Declarations --------------------
-------------------------------------------------------------

BEGIN TRY

	SET @printMessage =  char(13) + char(10) + 'Finding Bank Defs:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF @retainBankDefInfo = 1
		SET @printMessage = '	Set to retain bank definition info, checking for production values only.  No other bank definition settings will be changed'
	ELSE
		SET @printMessage = '	Set to remove all bank definition info, checking all values.'

	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	BEGIN TRAN updateCyberSrcBankDef --Is it a CyberSource definition?

		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_server_URL +
						N''' FROM ics_name_value inv
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_sync_processor_progid +
						N''' and ics_name = ''serverURL'''
			EXEC sp_executesql @sql;
			
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_merchant_id +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_sync_processor_progid +
						N''' and ics_name = ''merchant_id'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_server_host +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_sync_processor_progid +
						N''' and ics_name = ''server_host'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_server_port +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_sync_processor_progid +
						N''' and ics_name = ''server_port'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @CS_send_to_production +
					N''' FROM ics_name_value inv
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = inv.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''' + @CS_sync_processor_progid +
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

		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_50_server_URL +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_50_sync_processor_progid +
					N''' and ics_name = ''serverURL'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +			
						N'update ics_name_value set ics_value = ''' + @CS_50_merchant_id +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_50_sync_processor_progid +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		end

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found CyberSource 50'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
	COMMIT TRAN;

	BEGIN TRAN updateCyberSrcSecureBankDef --Is it a CyberSource Secure definition?
		
		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @CS_Secure_send_to_production +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_Secure_sync_processor_progid +
					N''' and ics_name = ''sendToProduction'''
		EXEC sp_executesql @sql;
		
		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_Secure_merchant_id +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_Secure_sync_processor_progid +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @CS_50_send_to_production +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_50_sync_processor_progid +
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
		
		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @CS_Secure_Soap_merchant_id +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_Secure_Soap_sync_processor_progid +
					N'''and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @CS_Secure_Soap_send_to_production +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @CS_Secure_Soap_sync_processor_progid +
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
		
		IF @retainBankDefInfo = 0
		BEGIN

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @NG_proxyport +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @NG_sync_processor_progid +
						N''' and ics_name = ''proxyport'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @NG_merchant_id +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @NG_sync_processor_progid +
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
		
		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Ltl_username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
					N''' and ics_name = ''username'''

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Ltl_password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
					N''' and ics_name = ''password'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Ltl_merchantid +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
					N''' and ics_name = ''merchantid'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Ltl_billing_descriptor +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
					N''' and ics_name = ''billingdescriptor'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Ltl_report_group +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
					N''' and ics_name = ''reportgroup'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @Ltl_testmode +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Ltl_sync_processor_progid +
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

		IF @retainBankDefInfo = 0
		BEGIN
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @An_x_login +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @An_sync_processor_progid +
						N''' and ics_name = ''x_login'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @An_x_tran_key +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @An_sync_processor_progid +
						N''' and ics_name = ''x_tran_key'''
			EXEC sp_executesql @sql;
		END;

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @An_server_host +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @An_sync_processor_progid +
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

		IF @retainBankDefInfo = 0
		BEGIN
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PFP_PWD +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PFP_sync_processor_progid +
						N''' and ics_name = ''PWD'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PFP_USER +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PFP_sync_processor_progid +
						N''' and ics_name = ''USER'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PFP_VENDOR +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PFP_sync_processor_progid +
						N''' and ics_name = ''VENDOR'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PFP_PARTNER +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PFP_sync_processor_progid +
						N''' and ics_name = ''PARTNER'''
			EXEC sp_executesql @sql;
		END;

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @PFP_SENDTOPRODUCTION +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @PFP_sync_processor_progid +
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

		IF @retainBankDefInfo = 0
		BEGIN
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_divison_number +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''division_number'''
			EXEC sp_executesql @sql;
		
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_server_host +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''server_host'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_server_port +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''server_port'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_socks_proxy_host +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''socks_proxy_host'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_socks_proxy_port +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''socks_proxy_port'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_restrict_log +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''restrict_log'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PTo_ignore_call +
						N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.sync_processor_progid = ''' + @PTo_sync_processor_progid +
						N''' and ics_name = ''ignore_call'''
			EXEC sp_executesql @sql;
		END

		IF @@ROWCOUNT > 0
		BEGIN
			SET @count = @count + 1;
			SET @printMessage =  '	Found Paymentech Online'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END
		
		--Check if we also have a Batch Processor
		BEGIN TRAN updatePaymentBatchBankDef
			
			IF @retainBankDefInfo = 0
			BEGIN
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_divison_number +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''division_number'''
				EXEC sp_executesql @sql;
			
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
							N'update ics_name_value_batch set ics_value = ''' + @PTb_ignore_call +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''ignore_call'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_presenter_id +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''presenter_id'''
				EXEC sp_executesql @sql;
			
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_presenter_password +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''presenter_password'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_server_host +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''server_host'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_server_port +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''server_port'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_socks_proxy_host +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''socks_proxy_host'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_socks_proxy_port +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''socks_proxy_port'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTo_restrict_log +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''restrict_log'''
				EXEC sp_executesql @sql;

				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_submitter_id +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
						N''' and inv.ics_name = ''submitter_id'''
				EXEC sp_executesql @sql;
		
				SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) + 
							N'update ics_name_value_batch set ics_value = ''' + @PTb_submitter_password +
							N''' FROM ics_name_value inv
									INNER JOIN ics_bank_def ibd
										ON ibd.ics_bank_def_id = inv.ics_bank_def_id
								WHERE ibd.batch_processor_progid = ''' + @PTb_sync_processor_progid +
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

		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PP_api_username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @PP_sync_processor_progid +
					N''' and ics_name = ''api_username'''

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @PP_api_password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @PP_sync_processor_progid +
					N''' and ics_name = ''api_password'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +			
					N'update ics_name_value set ics_value = ''' + @PP_server_express_URL +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @PP_sync_processor_progid +
					N''' and ics_name = ''server_host_express'''
		EXEC sp_executesql @sql;

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @PP_server_URL +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @PP_sync_processor_progid +
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

		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Opt_merchant_number +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Opt_sync_processor_progid +
					N''' and ics_name = ''MERCHANTNUMBER'''

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Opt_merchant_password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Opt_sync_processor_progid +
					N''' and ics_name = ''MERCHANTPASSWORD'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Opt_merchant_store_id +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Opt_sync_processor_progid +
					N''' and ics_name = ''MERCHANTSTOREID'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @Opt_ref_num_prefix +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Opt_sync_processor_progid +
					N''' and ics_name = ''REFNUMPREFIX'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @Opt_testmode +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @Opt_sync_processor_progid +
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

		if (@retainBankDefInfo = 0) begin
			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @WP_merchant_number +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @WP_sync_processor_progid +
					N''' and ics_name = ''MERCHANTNUMBER'''

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @WP_password +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @WP_sync_processor_progid +
					N''' and ics_name = ''PASSWORD'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @WP_username +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @WP_sync_processor_progid +
					N''' and ics_name = ''USERNAME'''
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
						N'update ics_name_value set ics_value = ''' + @WP_ref_num_prefix +
						N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @WP_sync_processor_progid +
					N''' and ics_name = ''REFNUMPREFIX'''
			EXEC sp_executesql @sql;
		end

		SET @sql = N'USE ' + QUOTENAME(@icsDbName) + char(13) + char(10) +
					N'update ics_name_value set ics_value = ''' + @WP_testmode +
					N''' FROM ics_name_value inv
								INNER JOIN ics_bank_def ibd
									ON ibd.ics_bank_def_id = inv.ics_bank_def_id
							WHERE ibd.sync_processor_progid = ''' + @WP_sync_processor_progid +
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
		,@errorNumber = ERROR_NUMBER();

	RAISERROR(@errorMessage, @errorSeverity, 1)
END CATCH;
