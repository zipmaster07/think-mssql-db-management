/*
**	This stored procedure sanitizes a THINK Enterprise database for PCI compliance.  It removes all real credit card numbers, including payment gateway tokens and replaces
**	them with test values.  If affects the payment, payment_account, work_table, and work_table_payment tables.  This sp is a sub stored procedure.  It is not meant to be
**	called directly but through a user stored procedure.  It takes as input the name of a database, the THINK Enterprise version that the database is on, and an ad-hoc
**	generated ID all provided by the USP.  The sp cleans the target database based on which version it is on.  there are currently two ways to clean a database depending on
**	the version of the db.  in pre 7.3 database it was possible to place a non-encrypted number in the id_nbr fields of relavant tables and the system could read the plain-
**	text number, however in 7.3 and up the system is trying to decrypt any value in those fields, including non-encrypted numbers which will crash the system.
*/

USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_cleanDatabase')
	DROP PROCEDURE [dbo].[sub_cleanDatabase];
GO

CREATE PROCEDURE [dbo].[sub_cleanDatabase](
	@cleanDbName	nvarchar(128)		--Required:	The name of the database that is going to be sanitized.
	,@thkVersion	numeric(2,1) = 7.3	--Optional:	The THINK Enterprise version that the target database is on.
	,@tempTableId	int					--Required:	Unique ID that is appended to temporary tables.
	,@cleanDebug	nchar(1) = 'n'		--Optional: When set, returns additional debugging information to diagnose errors.
)

AS
SET NOCOUNT ON

DECLARE	@dateTimeOverride		datetime		--Get the current date (current to when the sp itself is executed) and overrides payment date fields with it.
		,@visaCcNbr				nvarchar(256)	--Replaces all Visa credit card numbers with a test number.
		,@masterCardCcNbr		nvarchar(256)	--Replaces all Mastercard credit card numbers with a test number.
		,@amexCcNbr				nvarchar(256)	--Replaces all American Express credit card numbers with a test number.
		,@discoverCcNbr			nvarchar(256)	--Replaces all Discover credit card numbers with a test number.
		,@soloCcNbr				nvarchar(256)	--Replaces all Solo credit card numbers with a test number.
		,@switchCcNbr			nvarchar(256)	--Replaces all Switch credit card numbers with a test number.
		,@valueLinkCcNbr		nvarchar(256)	--Replaces all ValueLink credit card numbers with a test number.
		,@sql					nvarchar(4000)
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorNumber			int
		,@errorSeverity			int
		,@errorLine				int
		,@errorState			int;

BEGIN TRY

	SET @printMessage = char(13) + char(10) + char(13) + char(10) + 'WELCOME TO WARP ZONE!' + char(13) + char(10) + '4	3	2' + char(13) + char(10)  + char(13) + char(10) + 'You apparently know about the clean override, so we''ll go ahead and make this database spotless' + char(13) + char(10) + char(13) + char(10) + 'Cleaning all credit card data:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	SET @dateTimeOverride = GETDATE()

	IF @thkVersion >= 7.3
	BEGIN

		/*
		**	Create a temporary table that holds all the PCI sensitive data. This will be used to cross-reference with the database to remove these records.
		*/
		SET @sql = N'CREATE TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
							cursor_id				int identity(1,1) primary key	not null
							,database_name			nvarchar(128)					not null
							,customer_id			int								null
							,payment_seq			int								null
							,credit_card_type		int								null
						);';
		EXEC sp_executesql @sql;

		/*
		**	This dyanmic SQL statement creates an INSERT statement that inserts all the PCI sensitive rows from the payment table in the temp table created above.  It finds
		**	All rows in the payment table that use a credit card.  As long as the credit card type has been created in the payment_type table than it is pushed into the temp
		**	table.
		*/
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'INSERT INTO ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, customer_id, payment_seq, credit_card_type)
					SELECT ''' + @cleanDbName + N''' [database_name], customer_id, payment_seq, pt.credit_card_type [credit_card_type]
					FROM payment p
						INNER JOIN payment_type pt
							ON pt.payment_type = p.payment_type
					WHERE pt.credit_card_type in (1,2,3,4,6,7,8)
						AND pt.payment_form = 1;';
		EXEC sp_executesql @sql;

		/*
		**	Start by removing static fields regardless of the bank definitions that have been used in the database.  These fields include auth dates, start dates, CVV's,
		**	etc.  It also updates the id_nbr_last_four fields for every credit card transaction in the payment table.
		*/
		BEGIN TRAN postUpdateStaticPmt

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr = NULL
							,auth_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
							,auth_code = 123456
							,clear_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
							,card_verification_value = NULL
							,exp_date = ''2020-12-31''
							,credit_card_info = NULL
							,credit_card_issue_id = NULL
							,credit_card_start_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq;';
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr_last_four =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''1111''
								WHEN tempcpp.credit_card_type = 2
									THEN ''4444''
								WHEN tempcpp.credit_card_type = 3
									THEN ''005''
								WHEN tempcpp.credit_card_type = 4
									THEN ''1117''
								WHEN tempcpp.credit_card_type = 6
									THEN ''''
								WHEN tempcpp.credit_card_type = 7
									THEN ''''
								WHEN tempcpp.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq;'
			EXEC sp_executesql @sql;
		COMMIT TRAN;

		/*
		**	Update CyberSource 50 credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a CyberSource 50 bank
		**	definition.
		*/
		BEGIN TRAN postUpdateCyberSrc50Pmt

			/*
			**	Setting CyberSource 50 payment variables.
			*/
			SET @visaCcNbr			= 'w0WBENNN66kBKgugwjJVhIGGls9eLhDl/UXoy2PLhZwNClqR1LUDumvvNWfwtgo+xCJ5ANYgw7pU' + char(13) + char(10) + 'iwEh3dcsomA0cdQU6MdQk3tV/lO4mW0s+4xuyE2lg1xbV63J94YoeFLwjcSf36QTHivxiqbeLQim' + char(13) + char(10) + 'Iy5jZ0yvN3smcPVY8Vo='
			SET @masterCardCcNbr	= 'PM52ZTw/8UCqq5owFMJhLYC6WuiOEDWN4F04aip1tikp4mWDbGlJ2pWeojkKtWWC+l5Fminm+kq1' + char(13) + char(10) + 'YZwCXX1Yh+OZ/l9ZYEg3UGlNQj12scE3C30pR2iO6kVTYSbQp3zDM56W+msyrWfx8taftAmTOH6w' + char(13) + char(10) + 'bEWev36ygPqVidb9zMI='
			SET @amexCcNbr			= '+vuGVLEu/QHBk4lYsu2zEmDs2LUtJq4LKlSEQmUvU5dAj9+i0zaPkqosF4vth9avIcw83cEzKgID' + char(13) + char(10) + 'pitNTTbAlAZJ4Ykjw3W0vISzGwaDFslyYY6oRcvanpA+uCuIf4Lh9PuHnKqtKBZeGZrlAxq9O6Cx' + char(13) + char(10) + 'D3ktJLjT7VeK9848gS0='
			SET @discoverCcNbr		= '1ua23D5vv3Ej+7DaIgHqZZFowkHbx2Y9npwWd7C2S2cw66y2lxA3qVC6lmK9gFNcK2ro/rWDV40s' + char(13) + char(10) + '8gyu2ps6USy0PVKSmZwwUPgPXvDtG3pmc+X9KC1KOfgU7PhkW3H5yq0Inuco9fskNFfFj+tjpqpA' + char(13) + char(10) + 'G4lFQa926ddVKygugko='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSource50.CyberSource50Sync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource 50 records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource 5.0 credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update CyberSource (old) credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a CyberSource bank
		**	definition.
		*/
		BEGIN TRAN postUpdateCyberSrcOldPmt

			/*
			**	Setting Cybersource payment variables.
			*/
			SET @visaCcNbr			= 'Mg/lIO5riRbiF9RAjbWxFauqQePzSYVPmVO4Mz9sVRxiyT591z5BVbMqoFehhKLccnwlpfF0x60U' + char(13) + char(10) + 'THIHrY31K2T0/J8YufWzkVHavYm6mLQwCRv+7TwZt7LV2NfvUUW4qbphzjREUqy00vVLP3HJmA4a' + char(13) + char(10) + 'qfSzkV9gvj44zxP/4YQ='
			SET @masterCardCcNbr	= 'FA/4KdEwzdHmPPoHHxUCBPGBrJ4E89y0tPnbidLINUyPHrBY8TetVlBX4nJhCUwFPHn3xeU5jMhU' + char(13) + char(10) + '7yZZpcR/iBz39oRTll2ij+iYVtYIZpBRj/2oTsNR1fIu14a0tA9oBF1EcLViV0VfMUBGBNJvBhwP' + char(13) + char(10) + 'Fx0E/F4oKOHUt8XYE8c='
			SET @amexCcNbr			= 'VYhFwt81IFSGOpNE2E44FEgW0sfQTlmiruv57mqYelcoqgXgHpyqYrOvjryfITaPsjhUspkn8sAL' + char(13) + char(10) + '1WEHcQo6dRZIzH7+Hv9z+rtfy0izgDaOvD48oYma6iEKAsvtxOCqGhBDDS3pLsFOgwjJtJNnz9vJ' + char(13) + char(10) + 'g3ED/hyjSp2FhPCSLmE='
			SET @discoverCcNbr		= 'dnXa3QW9ohj4qJ6xNKWyg5e/CiNM9Gr7daGcupWNlZUxbfjNRSx8UWOrFfnKLVD4yqlOTO7O8LZt' + char(13) + char(10) + '8KoA9Wfg1i7J9LLadeTIrTYrO8VpRjv3LeCCEkqgbfPhaW3EwkQVPwxPCHx3k/K3tX4pHczao9GB' + char(13) + char(10) + 'NE0wgd4kemj+1cptJcM='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE 
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSource.CyberSourceSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update CyberSource Secure credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a CyberSource Secure bank
		**	definition.
		*/
		BEGIN TRAN postUpdateCyberSoureSecurePmt

			/*
			**	Setting CyberSourceSecure payment variables.
			*/
			SET @visaCcNbr			= '3426531851040176056428||Ahj//wSRc4FdJ/RWy1DYICmrBw0ZMm7lk5T9mBLYMwBT9mBLYMzSB13ARMQyaSX+gWx6J2GBORc4FdJ/RWy1DYAAzjZI'
			SET @masterCardCcNbr	= '3426534873180176056442||Ahj//wSRc4FyoTHxHgD0ICmrFg0ZMm7hsxT9teA8OECT9teA8OHSB13ARMQyaSX+gWx6J2GEyRc4FyoTHxHgD0AA3C6b'
			SET @amexCcNbr			= '3426536079180176056470||Ahj//wSRc4F7MuV0UMEsICmrBo0ZMm7lszT9XHgByADT9XHgByDSB13ARMQyaSX+gWx6J2GDORc4F7MuV0UMEsAA2Q4s'
			SET @discoverCcNbr		= '3426536367740176056470||Ahj//wSRc4F9P8is6IEsICmrFi0ZMm7lg0T9xMbuU8ET9xMbuU/SB13ARMQyaSX+gWx6J2GBqRc4F9P8is6IEsAAggDX'
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource Secure records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update Authorize.Net credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by an Authorize.Net bank
		**	definition.
		*/
		BEGIN TRAN postUpdateAuthorizePmt

			/*
			**	Setting Authorize.Net payment variables.
			*/
			SET @visaCcNbr			= 'm9kOg4yntX05lVVJR+Y91cX274YZtqME2TnO9x0AuvleeCI1309fnn0PKYk/jMzK7th9muhPS98R' + char(13) + char(10) + '5T13mWsHR7MherCLsIZSm644HtIEQ/RpE5EtZu4+vekVdmj1TboOoA8Z578nItStwY69ONyKidj3' + char(13) + char(10) + 'AvAmhFSZKPddynNVhGU='
			SET @masterCardCcNbr	= 'RGI4rogEVL9ew0arpdxY+vHXNOJvDtuOjhwJnN5xNwl5elATWDc/mXzNj59/AYVEbeIxhK2l5Lg9' + char(13) + char(10) + 'DD4/ev9d1orFgq0wfDx4HjfiFtFmq1V2bkOGvQuWZ2yzt5tr44J4oJ75IrSrEp978paI4ER1E0qE' + char(13) + char(10) + 'LtSMmWljAKoPQFVbLrU='
			SET @amexCcNbr			= 'ufJmjplCHVQb6yelwixUENp0yCxTACIiMSL1zxWKQx0SajM4+828OFosDzC+kj1zyKiv/wWhCtZY' + char(13) + char(10) + 'Z++anZwFi8zbmHcUEZytKPe0ie1G9/jYJcpfm5n8mk3aBn9vOgwqwW52Te2167T2xk6itwU+jJHY' + char(13) + char(10) + 'Ungtded+nMQT/W1HSY0='
			SET @discoverCcNbr		= 'zmC0EDi6w+3RYCZrUqcdxX8Vd0jHSrOIMmcsWun83Jf55JmESma4d5jNrAX91azbkojKwYz0iVxV' + char(13) + char(10) + 'DECHyizHhotLCSEU2M5HPp3+jJQJU2LsMkKOmETRb6CZYzrUIx7wsakz0C3VALJ+eIicVMx1Mj+G' + char(13) + char(10) + 'mclm5E/MKMU2jkN1QsE='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcAuthorize.AuthorizeSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Authorize.Net records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Authorize.Net credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		/*
		BEGIN TRAN postUpdateNetGiroPmt --Update Netgiro credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcNetgiroSecure.NetgiroSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned NetGiro (DRWP) reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		*/

		/*
		**	Update PayFlow Pro credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a PayFlow Pro bank definition.
		*/
		BEGIN TRAN postUpdatePayFlowProPmt

			/*
			**	Setting PayFlow Pro payment variables.
			*/
			SET @visaCcNbr			= '3o3KJtWOkGWw23sgeyCz5Ypnrf8RF6SybL9sR4tvOMIKMZJFzI46bUOvuZInqciUqd4oDNZx1Jyt' + char(13) + char(10) + 'R7V5vL/Nc64yB8hOrgrDQUc75GzKIhgZGE5nIoHuD4WDSozoY5w9EEG6HSLctX0SBv5tNkUHswBH' + char(13) + char(10) + 'pGuu7X0PCzsH3nzzGs0='
			SET @masterCardCcNbr	= 'weZeFT9fjBXLrzs7Bk5RpqtJn2GkBZ7kO32m4EQj82jc91dQYb9mzFWVpQnNKKC/2Wr3DDU5O3uU' + char(13) + char(10) + '46domWkwf8U8EPz+dfW8uxcVrNtC5UvXtRxfYFDBK76iuGlwXTVk66DKbw7JMOlrRiD2J96WOuga' + char(13) + char(10) + 'ftANNZhvMYD2aWX5WM8='
			SET @amexCcNbr			= 'HMdPMfCBZ7O/i9LCb1mAKeQ8b60CoYkgNU/w/ZMLnmVslcdAgA/ridGZKFue/STofugoqdiEmBXI' + char(13) + char(10) + '2FlyJrLcQ+edwXts3IYcfdM9PorIxWSbziQoC2iYfllP7FAaPxzwleXPln+oEcGsI0Tyz03abNDz' + char(13) + char(10) + 'BWxEUBU4wLbR+MZVsAI='
			SET @discoverCcNbr		= 'zlRD64LpzQ1/rFp0ZKJEGegkR2aOiJX+wXB/0hJjSdwr9MaFgSzNzbS4BK2tvgSOE/gBTgQ2lE1i' + char(13) + char(10) + 'bqSaGS1v6eOSCIFawm+E8kwbXV0AIorsB0V3oS3a1Jq7cc+BCon4HFdNDg+6zVXnBBSOpHMTPghw' + char(13) + char(10) + 'WysYEjec6zgEI45Mi20='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPayFlowPro.PayFlowProSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any PayFlow Pro records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update PayFlow Pro Secure credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a PayFlow Pro Secure bank
		**	definition.
		*/
		BEGIN TRAN postUpdatePayFlowProSecurePmt

			/*
			**	Setting PayFlo Pro Secure payment variables.
			*/
			SET @visaCcNbr			= 'V24C2B9F395A'
			SET @masterCardCcNbr	= 'V34C2BA428E8'
			SET @amexCcNbr			= 'V25C2B9F39E1'
			SET @discoverCcNbr		= 'V34C2BA42969'
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid in (''zzcoPmtProcPayFlowProSecure.PayFlowProSecureSync'', ''zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure'');';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any PayFlow Pro Secure records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro Secure reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update Paymentech credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a Paymentech bank definition.
		*/
		BEGIN TRAN postUpdatePaymentechPmt

			/*
			**	Setting Paymentech payment variables.
			*/
			SET @visaCcNbr			= '0UAfkHCLfIqm+Y6+d03UhJy1ptLVGrVQV+WyN71HTQrFQAYruDiv000BPTvbpZ76M8aVTbJHtEIM' + char(13) + char(10) + '6vYk7rXDarYBOQLwRj7r15lRxlKHqlNuvEOfOuMFmCNahN8qEyzqNe/eVC8LvKessQMTkHDGqzSy' + char(13) + char(10) + '9X4yYdnsK6R1XpULV5c='
			SET @masterCardCcNbr	= 'HhfA5QmmTF/058bwKUKXjGcoVpGinlHXEGcIAazIwD92x1wHNSwLxx0UvOD3br42DV0k91tvXGKw' + char(13) + char(10) + 'tFz5IkAiqOYBQ/a8aCIGpYhYhsshdK19712+4k9gPqnNNLk1hKGtfLzOXrS/a/pVspJcefNrVk/0' + char(13) + char(10) + 'pxe4PzXNbZUQCuedLH8='
			SET @amexCcNbr			= 'XSKBgDsuVIrhzjLatKxEqNdpde2IARHez18LL/1lI9Vdv50/FBtNQh0L0kexYSk5niyJfnNZKc/t' + char(13) + char(10) + 'jk1+L46aji9j/U+iEq+lwT/EcjJfY6jPGwTRu8oPGpXe8hH+U9hvu6Gn+cNtr3QPBhiiB3X8R+fc' + char(13) + char(10) + 'TUS34PPNOegvPEbcmIQ='
			SET @discoverCcNbr		= 'l6qus83qSaXi+7LYtzk/UjSwiwwFO5uMVoC6pnUUw2RRRvNuVstL4SztBOFP7giwp6fjvJuy/Qgx' + char(13) + char(10) + '4ED2eBNli6K1MlDjrS1PO0+CUBW2G3GYVhqn/psfP2wXWGKpjlvsFv5zdNX1qMQTCe766asfFkkT' + char(13) + char(10) + 'HOinRh6ONIcA2EvOb1A='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPaymentech.PaymentechSync'';';
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''00000035''
								WHEN tempcpp.credit_card_type = 2
									THEN ''00000036''
								WHEN tempcpp.credit_card_type = 3
									THEN ''00000037''
								WHEN tempcpp.credit_card_type = 4
									THEN ''00000038''
								WHEN tempcpp.credit_card_type = 6
									THEN ''''
								WHEN tempcpp.credit_card_type = 7
									THEN ''''
								WHEN tempcpp.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPaymentech.PaymentechSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Paymentech records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Paymentech credit card and reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update PayPal credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a PayPal bank definition.
		*/
		BEGIN TRAN postUpdatePayPalPmt
			
			/*
			**	Setting PayPal payment variables.
			*/
			SET @visaCcNbr			= 'dpmrNR7LcwU5aMMjBpli0QgQbG14v0anHh8Kd+/afo3p/kAakEHrZQRMEIOGApHMHCHaaKrQnnng' + char(13) + char(10) + 'MiD7PrisvfVoGSav1vW4XcyD6Hdfx+pm3h/le/y4mz4+LVy3e4ygDyrfO1NfKcdkfObAy/NpBcEo' + char(13) + char(10) + '+Zp0OlbU1AdeCjDxYso='
			SET @masterCardCcNbr	= '8igQeSDweo9t4DxKMRXGdzn0CZUgHb9Km5LwKbLqeHI76fxKkQ4F/CdHFXurCBzgv9/KuNZBC6Jd' + char(13) + char(10) + 'lFE2HZcEZFPwhEDstr9cAUbH3S8EYeYdkgwRTpQxAxFiYwKYXi6FnsF13QQnW46Txl9SH/iToJyN' + char(13) + char(10) + '2ZTeQmurnK72ioTY/jE='
			SET @amexCcNbr			= 'pQY+Zm/EHQexPQv6byIbJ3pgyWdSs1qy+U6QfSx9x6n6o4kN8f+13nEPA/Ar0OZo+TKMkLAagniZ' + char(13) + char(10) + 'ToqQ+wwh95K5dN7pAEnCcl/kIHgiHC1DCGNa80aHQUBBSxbeGTZ9bmbVzoLNhXOdJZ3DqU7XtjPy' + char(13) + char(10) + 'H2LK+MTuzyMGUTL8/nI='
			SET @discoverCcNbr		= 'lCuJESzDPen+hVVpb5enaN/H53vp8iUl2O7+LiiF0sk1g4dvdQfZOLngv0DCY58IJ3t9Wa6Zjnky' + char(13) + char(10) + 'KAXH+RWLee+zB1QM7R9O6XlE/q5XwOnI6N3fdeicwb45Pn3Z3NCjahS3X7zZsFCv6sRQT3F/6gMe' + char(13) + char(10) + '4M4mMisES3N/sxkOFmw='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPayPal.PayPalSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any PayPal records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned PayPal credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update CyberSource Secure SOAP credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a CyberSource
		**	Secure SOAP bank definition.
		*/
		BEGIN TRAN postUpdateCyberSrcSOAPPmt

			/*
			**	Setting CyberSourceSecureSOAP payment variables.
			*/
			SET @visaCcNbr			= '3426536567430176056442||Ahj//wSRc4F+qwST8Ej0ICmrBo0ZMm7ls2T9XHgB04BT9XHgB07SB13ARMQyaSX+gWx6J2GBORc4F+qwST8Ej0AAfC3s'
			SET @masterCardCcNbr	= '3426536719750176056442||Ahj//wSRc4F/wBYa7Ej0ICmrFg0ZMm7hs0T9teA8W0CT9teA8W3SB13ARMQyaSX+gWx6J2GEyRc4F/wBYa7Ej0AAyiYX'
			SET @amexCcNbr			= '3426536825890176056428||Ahj//wSRc4GAgSdk6njYICmrBq0ZMm7ZuyT9a16z7UDT9a16z7XSB13ARMQyaSX+gWx6J2GDORc4GAgSdk6njYAA1y+7'
			SET @discoverCcNbr		= '3426536911230176056470||Ahj//wSRc4GBHGLtr6ksICmrBy0ZMm7hs3T9pvmJpEET9pvmJpHSB13ARMQyaSX+gWx6J2GBqRc4GBHGLtr6ksAAowDZ'
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource Secure SOAP records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure (SOAP) reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update Litle credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a Litle bank definition.
		*/
		BEGIN TRAN postUpdateLitlePmt

			/*
			**	Setting Litle payment variables.
			*/
			SET @visaCcNbr			= 'pnIYfabMi/BM43bC+SE+RBBtg8shDi0wpMhVcNnfVhukJjtEXB9gvnWbrd38p+zfCuefxoC1fOTq' + char(13) + char(10) + '4fVSVqgTXNSuKfn+RGxkd5Mqo/Q2J1vYK9/ziN00GnGbdrR0jwZ3D4XpWOOfJGUEDJ1iG2ItUVbf' + char(13) + char(10) + 'q8tgplmiABXtCRN7SrY='
			SET @masterCardCcNbr	= '8ymyoVdZiLkVgtzSlyzMlSAYNeU6HaCC8skJjZa2GIRY1QK0Yb6kpRxdfqeA6O8O3cBtr+ffPbF/' + char(13) + char(10) + 'FWTnCfC5yas76O7WbaZtjMDdmxbsfh6iyINloRKyhzoYfOLtb5lbdyoOGb2EvgAhiqyVKJ71anvD' + char(13) + char(10) + 'MEg7+UYjSUJgrxnfsKQ='
			SET @amexCcNbr			= '/f6Kr7aWQB8MlYGfj38oxsgX022TUzk+1VjGH0U0g8oEh0Wl8yI4H4quo/DAASMIpvV1EAdBOMow' + char(13) + char(10) + 'RqQ7+nTh4T8UrkTLyseQZssFK5XxoN5VyrzpM6HQO++glXlzUl7c1GgLNuBzruXqhKozGYLYnpXT' + char(13) + char(10) + 'XB1+chDao7m5svZg2Q0='
			SET @discoverCcNbr		= 'pcPei8J+80wZIgk9XjkXciRHC5uho7tBtpI8O0F1iwUCS2B64B3RrsgVv+NtJopTu9ZHWlHYgBwJ' + char(13) + char(10) + 'ystjkaFVo+koLjhvlXfhp84YoZExRRuSzWobN9DZEc+fGnhgu5+y8nkq3B+1QrA2Kvd7/ERStgFN' + char(13) + char(10) + 'adx3J2yFPSIQG4E/4Do='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcLitle.zzcoPmtProcLitle'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Litle records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Litle reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update Optimal credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by an Optimal bank definition.
		*/
		BEGIN TRAN postUpdateOptimalPmt

			/*
			**	Setting Optimal payment variables.
			*/
			SET @visaCcNbr			= ''
			SET @masterCardCcNbr	= ''
			SET @amexCcNbr			= ''
			SET @discoverCcNbr		= ''
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcOptimal.Optimal'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Optimal records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Optimal reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update Westpac credit card numbers for all records in the payment table that have been auth, settled, or auth and settled by a Westpac bank definition.
		*/
		BEGIN TRAN postUpdateWestpacPmt

			/*
			**	Setting Westpac payment variables.
			*/
			SET @visaCcNbr			= 'PFX-55'
			SET @masterCardCcNbr	= 'PFX-57'
			SET @amexCcNbr			= 'PFX-60'
			SET @discoverCcNbr		= 'PFX-62'
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcWestpac.zzcoPmtProcWestpac'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Westpac records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Westpac reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		SET @sql = N'DROP TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20));
		EXEC sp_executesql @sql;
	END;
END TRY
BEGIN CATCH
	
	IF @@ROWCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorNumber = ERROR_NUMBER()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @cleanDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_cleanDatabase sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = N'IF object_id(''tempdb..##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;

	RAISERROR(@errorMessage,@errorSeverity, 1)
END CATCH

/*
**	Now that we have changed values in the payment table Let's change the values in the payment_account table.  It is basically a repeat of what we did for the payment
**	table.  It should be noted that Westpac does not support payment accounts.
*/
BEGIN TRY

	IF @thkVersion >= 7.3
	BEGIN

		/*
		**	Create a temporary table that holds all the PCI sensitive data. This will be used to cross-reference with the database to remove these records.
		*/
		SET @sql = N'CREATE TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
						cursor_id				int identity(1,1) primary key	not null
						,database_name			nvarchar(128)					not null
						,customer_id			int								null
						,payment_account_seq	int								null
						,credit_card_type		int								null
					);';
		EXEC sp_executesql @sql;

		/*
		**	This dyanmic SQL statement creates an INSERT statement that inserts all the PCI sensitive rows from the payment_account table in the temp table created above.
		**	It finds all rows in the payment_account table that use a credit card.  As long as the credit card type has been created in the payment_type table than it is
		**	pushed into the temp table.
		*/
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'INSERT INTO ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, customer_id, payment_account_seq, credit_card_type)
					SELECT ''' + @cleanDbName + ''', customer_id, payment_account_seq, pt.credit_card_type [credit_card_type]
					FROM payment_account pa
						INNER JOIN payment_type pt
							ON pt.payment_type = pa.payment_type
					WHERE pt.credit_card_type in (1,2,3,4,6,7,8)'
		EXEC sp_executesql @sql;

		/*
		**	Start by removing static fields regardless of the bank definitions that have been used in the database.  These fields include CVV's, expire dates, start dates,
		**	etc.  It also updates the id_nbr_last_four fields for every credit card transaction in the payment table.
		*/
		BEGIN TRAN postUpdateStaticPmtAcct

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr = NULL
							,card_verification_value = NULL
							,credit_card_expire = ''2020-12-31''
							,credit_card_start_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq'
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr_last_four = 
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''1111''
								WHEN tempcpap.credit_card_type = 2
									THEN ''4444''
								WHEN tempcpap.credit_card_type = 3
									THEN ''005''
								WHEN tempcpap.credit_card_type = 4
									THEN ''117''
								WHEN tempcpap.credit_card_type = 6
									THEN ''''
								WHEN tempcpap.credit_card_type = 7
									THEN ''''
								WHEN tempcpap.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq;';
			EXEC sp_executesql @sql;
		COMMIT TRAN;

		/*
		**	Update all non-tokenized payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN postUpdateNonTokenizedPmtAcct

			/*
			**	Setting Non-Tokenized payment account variables.
			*/
			SET @visaCcNbr			= 'UpKQySzbHS2ape3/2GXtfJ1+AhO2yJd7/oC32amAGsREsHtL4QVDGkJ7ezRW7wfrwAwhrC87FQiK' + char(13) + char(10) + 'wpASfwaNkdiP3NwtXdh/GV4eefml9bzjWdu91Y1TUBCL8GCTj7yovh0j1t8RXWP0wF6EA96roJY9' + char(13) + char(10) + '2VWZ4rnK8chw2mRTBM8='		
			SET @masterCardCcNbr	= 'pWd/vGMM+/+V4tk3FCstUB4IkdFWfFx5e6U8ejyVz5TaxuDOF4oqdBWccBr8WIgpIUGzoAJXNW10' + char(13) + char(10) + '/QKIg9oPlZoSVm/mCprXs7r3wNSh0oGUzI7y5oa58odzwQL8HuAtSP59xcXOoOghMLm6D/M8RNvT' + char(13) + char(10) + '/7Z7QpfIYn1k5Sl2pr8='
			SET @amexCcNbr			= '7mPgoYR88xnf9ZzjvfbwcVGfSBMTTaSp/Wj88xnR+1Fb3scnNs1ls9EfJJYlgTPCgX0reA9zr7EF' + char(13) + char(10) + 'WojIKTRCYDI0jweidv3J85K61mV/i175/UvqEqSnbZhWpZvyNsxFAlK87PsI3WphWr1q1ErIztWX' + char(13) + char(10) + 'uPKKxIrBxzbulzlHYww='
			SET @discoverCcNbr		= 'uJpCYnhOrjZdK6U1LFMbHMOgY7c+6BNORyRdWcmZUM80ivy3YEDWAJ/2N35auSi6xmqAh1FJKp/U' + char(13) + char(10) + 'vjqQpSWcue0axFVqdWespjHjeJufSMPnE3RIounveRQ7Ftf/QiNi3TL372KoJJHsAEJm8wrj+vQ/' + char(13) + char(10) + 'CLA+fBjgV7MvwGyRQmA='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE 
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
						WHERE secure_bank_def_id is null;';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any non-tokenized records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned All Non-Tokenized payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
 		COMMIT TRAN;

		/*
		**	Update all CyberSource Secure payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN postUpdateCyberSrcSecurePmtAcct

			/*
			**	Setting CyberSourceSecure payment account variables.
			*/
			SET @visaCcNbr			= 'jqrnGM9ySScEshFoDnaOqSUme3mwPDxjzCvzvbrA2Dmi529snWHjX0tbJQDg2ICQ+ZvQcyo1M7K0' + char(13) + char(10) + 'SMLMN9Ej6Ryw1eT6vKbfT5sHQtVWmHmX/05qIMK2OLOoRynnVYDu1mYZR9cgTLTlUCnmIr/iBwRq' + char(13) + char(10) + '1nGdA+FA0Lr/1KoAvXs='
			SET @masterCardCcNbr	= 'KMb2JrknE32HphY0mcQwAb8oU7igJAQrZPuRqnne5/9gDgFHQEweG/vSYkLItLJsr39Zt0qozmon' + char(13) + char(10) + 'ZFaW6YdFSJMsPNdC23vTXkZeSQosg8nNYMDQUc8i63MI0dwrmZ52wJ53lx5x9YQv4AULwtW5dGUA' + char(13) + char(10) + 'WF57n7e3QmTx1B7Kahk='
			SET @amexCcNbr			= 'TEGgYS/b+VlSqro9WkOlHiembv4Z3QwGxiFpShOipX8coTir/Na9s1L3q6t2yczmgk3d6ZJCqM+v' + char(13) + char(10) + 'R1u2xvHw2fK2M8wMsx0+sTMueQ7YE1lzGhFhLFZxUNGUU8MPSR8ulyp+3jeTWnJDQCQGIhF408uH' + char(13) + char(10) + 'KCEV/pSr98CmIDJTqzk='
			SET @discoverCcNbr		= 'lvQl+BZrQ0mbDrzFfp9RpSNkcGDSF+MpaYm1RDAShOxRX1S26l6nJ4u6YDIH3R3lygjFZ4vpiHn/' + char(13) + char(10) + 'epQ/Y1PyhEa3J9TWx/CVii/sxVmbFBwkuzpHytM6u1tdM8qx53tnG6C38yGg2i8us4919ucxEQMl' + char(13) + char(10) + '7zMCilDZecg3F7DkEDA='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource Secure records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		/*
		BEGIN TRAN postUpdateNetGiroPmtAcct --Update NetGiro payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcNetgiroSecure.NetgiroSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned NetGiro (DRWP) payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		*/

		/*
		**	Update all PayFlow Pro Secure payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN postUpdatePayFlowProSecurPmtAcct

			/*
			**	Setting PayFlow Pro Secure payment account variables.
			*/
			SET @visaCcNbr			= 'b/m3ftL2vUXxAe6322htC1ScyhMp6xY/InZdPeWg2liE01VvCC3cRB104RZTC/xXRUldJhQXuy0Z' + char(13) + char(10) + 'fIor4j8X0Sqm1gKUuvPUN8w5YYo78EC2a2LBkVBsilN08pxrxzrzs5th3HKUcYQDkuTeZtaBNtmG' + char(13) + char(10) + 'e7BYhguYEWdJfi8B67w='
			SET @masterCardCcNbr	= 'rvRDyPKAaqjq6JmjnUzOs98ULL1lZUQP0S+u+m15ccJBDLNGLZyyWVtk0E8v5+aOz/FgdjxIM1xc' + char(13) + char(10) + '79fb/Chgud/wKawbQbUx1Xliqqr0UhUCyzQEDIbK1LVa6/9PdfX0Sg+O7Cku7h1CS+bXskSSb90e' + char(13) + char(10) + 'BugKHhynjlct2XwT0mM='
			SET @amexCcNbr			= '02mOi9FLfslAvsCtjWupvN7HPWEPO4R1y3R4c1coRu/bKBrIlIN1bFbJqoneqZoWCeXDbbJzoexT' + char(13) + char(10) + 'aoT4CR4fHTgrzm6gK3JMFyc8THjyEwnZcGElrcPYVRWUnq2MOS1/RMbuPE7KwQRBMiL90+8cVhrB' + char(13) + char(10) + 'NJU5OU/4/uRoxwofDEU='
			SET @discoverCcNbr		= 'q1DQg52sr5at9VcWR0cn9TwxvHXchjDzfnTwGLEFzwcx+i0a5isdIY7h5aP8K/zS0MUagtv79nKk' + char(13) + char(10) + 'uC3adEo9kJdhT2/rBVcqggqy196KRmkctBEVR97tZDNVvN7nDQOtuoCB0VUrGjSkv17hB8nO7BGb' + char(13) + char(10) + '+ZYHWN9KnmoFboUakzE='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid in (''zzcoPmtProcPayFlowProSecure.PayFlowProSecureSync'', ''zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure'');';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any PayFlow Pro Secure records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro Secure payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update all CyberSource Secure SOAP payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN postUpdateCyberSrcSOAPPmtAcct

			/*
			**	Setting CyberSourceSecureSOAP payment account variables.
			*/
			SET @visaCcNbr			= 'HYRJTStfRf9ABcs3kuC4Pu3wxLqG8kpxkVFm4XE3HpcLmuGIaZth6vgoqx/Uu1rd6tI/+fvyFhpn' + char(13) + char(10) + '6XPYO7OXENPJFhl1ybB52wJgw3ajMDKmGeYhscG7mejMLszMGxN5BI6Z3YghgSdygRNe0urvezVz' + char(13) + char(10) + 'RUuIJqdzPrJ4pDJUaEw='
			SET @masterCardCcNbr	= 'MVxdpPr/C1w0mC6U8/vc85EcGD12quQ4TjN8YgBjthwKySDu2oKNlFG6Ktu2k46CaM3Izhvx5uW9' + char(13) + char(10) + 'PkeVLOcjgIFVg3OUQwG6knl593hTdzBWOlH8xX3DdvsxxOJywvOujZfpNbEyv6k9zZdT77JfmgKZ' + char(13) + char(10) + '2M353h/xuZ1ggj44ajs='
			SET @amexCcNbr			= 'FEQHw9Q0SQNNECm3YSG1b04B87EiDgm8fLb0LXTVZ8idpc1I7CnO+rJ9F/lgSA4kJmjK5q6TQEqy' + char(13) + char(10) + 'BwIoamXQ4tz0acipPqkM0viybAOEgLEqKnFOpu234Bd+Rr1Ay28XMJQzKdFJDFyJFTJdQ2+lgwOC' + char(13) + char(10) + 'OohQ0aBNvXtRjILDzzM='
			SET @discoverCcNbr		= 'wsgQNpK/K0a0dO3Qdz0M9xNK5Gbb7ZVcS3VXAGjBrHs3/dLxkRYHNYJut/kGU0WQWmIzW2ouS/KB' + char(13) + char(10) + '0hRueWLO1FDFiaiwBDICC/w5woBamjBA+zY3i64rWFvNoGKrnRsxkTfWGvo2vUXJhnsAdHA7+TJ0' + char(13) + char(10) + 'MqH/QLzlcKs0paYIjKo='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any CyberSource Secure SOAP records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure (SOAP) payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update all Litle payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN postUpdateLitlePmtAcct

			/*
			**	Setting Litle payment account variables.
			*/
			SET @visaCcNbr			= 'QEHI9IJsJCN8/rMR0+gUi6AOdtscPCorD6TrS3QNf10tOSnckRifSLyeP02iinLnf/r4Px1IxeT/' + char(13) + char(10) + '4GxADD/6Xe0H0XppRdLlWq2AmpyyYvYhLlyMbvgdP4A4d76ysjX706g0OjShGKQ1ji6QJDxv/ccc' + char(13) + char(10) + 'bGfG52d3hZaMVrHe124='
			SET @masterCardCcNbr	= 'nsjP6REOLBhnLgf2z3nJiZI5TpggMDbLtZnIEHf5BqDvdyhjbV4Ns2lNhrkVBF+fYHiQGPXdvpaW' + char(13) + char(10) + 'HBPiD+9eHlrfeNAF2o1Jur1VRt0pSCHcReXD2wJdALMYz56MdvkG/DlIFY+8w8saAn7j309LDODj' + char(13) + char(10) + 'EYh5XCbcMkpsS97NqWc='
			SET @amexCcNbr			= 'Lb9h5q1oYsZ6HRMdP1dCCcU8y3mUlD64ti/vDEyoDhsYtolOJ50uM5qtwn/TAbJgkIxDyFmw1nG+' + char(13) + char(10) + '8XUzPfceAxowb1VGmfTIDl+WMLIRgcxA5ZME4lTxmQQ+x5xzmro9ZW5V1oa99dJSoN0u0DlLrXkW' + char(13) + char(10) + 'w36d4B/LLHZTjqyfW1I='
			SET @discoverCcNbr		= 'jM1c+F/iHdS46s2XbFS/yyPP7zNnUagfH+qx/9rdUuenEPK/o4qvpCa0liOp4HXL73sm7DxXo1ZN' + char(13) + char(10) + 'CY6WOoXOpkcfWwOZ5T2KBl9ACUVQm57ZC7nE3BAb112kR/du3Ru57PGCSV2JCtN3CyVFY7rsf2uA' + char(13) + char(10) + 'IIRosT/W0c8tncxg3EI='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= ''
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcLitle.zzcoPmtProcLitle'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Litle records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Litle payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		/*
		**	Update all Optimal payment accounts for all records in the payment_account table that use a valid credit card
		*/
		BEGIN TRAN  updateOptimalPmtAcct

			/*
			**	Setting Optimal payment account variables.
			*/
			SET @visaCcNbr			= 'b+WTyUllt/9EEPWsoAZzTTE7i/GssGSQDTZ1gv3mYJdG6jM8AeqrPemoNte9vy+f2LWZdUXKmHeu' + char(13) + char(10) + 'gsxeskrvnKBPFxR9XeBKZH2YN7OaGTyOlRJwFxSVprfYi3n6HDyELGjzU8cF1T3X+2TniZB2zNOU' + char(13) + char(10) + 'VmuuGGLLAPXRkNGAISw='
			SET @masterCardCcNbr	= 'm3IuOpiHy6CepZj5uYa9e8nDcXkXaP5IhViZ8jxAv9ppEs1vlwDMrINL77h7ZsDNfaGpCn18qFuS' + char(13) + char(10) + 'Bnl/AZNjhd28Y7mDSdzHi1TD6H6IP/MUZxnyak2O5f0whZ2WDNBsODdS2Pm3RRbsTmmEHZnaxa5N' + char(13) + char(10) + '+xTiRUB+w1IVaTYtgZQ='
			SET @amexCcNbr			= 'PXPbg6Nmsk/pND2vug3SXN0KFKcqzO/adqct9JLbD4E55LCYyFcG2QuT/s5/DWuGdPFzwSTKoood' + char(13) + char(10) + 'UkrORShLeiUPav3C7ot7Z09ki5Ypz93ewZdaVxYDjZGZEBAf9HmCAVAGM86KaHC5/xk9fkHsM4QK' + char(13) + char(10) + 'TH59ZV7e0zt4ANE6b0k='
			SET @discoverCcNbr		= 'ZpLDLU9NzhSVN6KVMlozb9N85mARZ60O1h7nfGfvCgx9NWr5pjEjptURL0gom4JKaOY7gWIk+i9g' + char(13) + char(10) + 'pqdVYwxRaSA8k1625rdCFxD/8uZZBwWPTJvWO5e7G6CPRYbp57sVIj5JE0GlQ12FQTpgzM2xwCha' + char(13) + char(10) + 'FXKRl8izlLnLpKOBpag='
			SET @soloCcNbr			= ''
			SET @switchCcNbr		= '0GPCQLTbOslwmwGgvXuYOQJa98kEHcOOzxkhdcpkqc/7BofJwDqzqf6dMW+yUNApj27pVgVFNvz5' + char(13) + char(10) + 'JZvcZvBMqAxdRhLg+dhCzLT/9Dp8++nW3gum9bgR4dSJ0Xac7WrI7CSGtiwjiIGuUIRdnqbJcrDa' + char(13) + char(10) + 'QHQ7g/wpjkZwh5969DE='
			SET @valueLinkCcNbr		= ''

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @visaCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @masterCardCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @amexCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @discoverCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @soloCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @switchCcNbr + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @valueLinkCcNbr + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcOptimal.Optimal'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0 --If any Optimal records were updated than report it to the user.
			BEGIN
				SET @printMessage =  '	Cleaned Optimal payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		SET @sql = N'DROP TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20));
		EXEC sp_executesql @sql;
	END;
END TRY
BEGIN CATCH

	IF @@ROWCOUNT > 0
		ROLLBACK

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorNumber = ERROR_NUMBER()
			,@errorSeverity = ERROR_SEVERITY()
			,@errorLine = ERROR_LINE()
			,@errorState = ERROR_STATE();

	IF @cleanDebug = 'y'
	BEGIN

		SET @printMessage = 'An error occured in the sub_cleanDatabase sp at line ' + CAST(ISNULL(@errorLine, 0) AS nvarchar(8)) + char(13) + char(10) + char(13) + char(10);
		RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
	END

	SET @sql = N'IF object_id(''tempdb..##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;

	RAISERROR(@errorMessage,@errorSeverity, 1)
END CATCH;

/*
**	Now that we have change values in the payment table and the payment_account table, we need to clean out the work_table_payment table and the work_table table.
*/
BEGIN TRAN postUpdateWorkTable

	IF @thkVersion >= 7.3
	BEGIN
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE work_table_payment
					SET pay_exp_month = 1
						,pay_exp_year = NULL
						,pay_id_number = NULL
						,pay_ref_number = NULL
						,pay_auth_code = NULL
						,dd_account_number = NULL
						--,dd_account_number_plain = NULL
					WHERE pay_exp_year is not null
						OR pay_id_number is not null
						OR pay_ref_number is not null
						OR pay_auth_code is not null
						OR dd_account_number is not null
						--OR dd_account_number_plain is not null'
		EXEC sp_executesql @sql;
	
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) + 
					N'UPDATE work_table
					SET pay_exp_date = NULL
						,pay_id_nbr = NULL
						,pay_ref_nbr = NULL
						,pay_auth_code = NULL
					WHERE pay_exp_date is not null
						OR pay_id_nbr is not null
						OR pay_ref_nbr is not null
						OR pay_auth_code is not null'
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned work_table and work_table_payment payment related fields'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
	END;
COMMIT TRAN;

/*
**	Update payment table for all pre 7.3 versions
*/
BEGIN TRAN preUpdatePaymentTable

	IF @thkVersion < 7.3
	BEGIN

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE payment
					SET id_nbr =
						CASE payment_type
							WHEN ''VS''
								THEN ''4111111111111111''
							WHEN ''MC''
								THEN ''5454545454545454''
							WHEN ''AX''
								THEN ''378282246310005''
							WHEN ''DS''
								THEN ''6011111111111117''
							ELSE NULL
						END
						,credit_card_info = ''name_on_credit_card'';';
		EXEC (@sql);

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned payment table';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE payment_account
					SET id_nbr =
						CASE payment_type
							WHEN ''VS''
								THEN ''4111111111111111''
							WHEN ''MC''
								THEN ''5454545454545454''
							WHEN ''AX''
								THEN ''340000000000041''
							WHEN ''DS''
								THEN ''6011000000000004''
							ELSE NULL
						END	
						,id_nbr_last_four =
						CASE payment_type
							WHEN ''VS''
								THEN ''1111''
							WHEN ''MC''
								THEN ''5454''
							WHEN ''AX''	
								THEN ''005''
							WHEN ''DS''
								THEN ''0007''
							ELSE NULL
						END
						,card_verification_value = NULL
						,credit_card_expire = ''2020-12-31''
						,credit_card_info = NULL
						,credit_card_issue_id = NULL
						,credit_card_start_date = ''2008-02-05''
						,dd_bank_description = NULL
						,dd_sorting_code = NULL
						,dd_state = NULL
						,description = NULL
						,bank_account_type = NULL;';
		EXEC (@sql);

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned payment_account table';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
	END;
COMMIT TRAN;

SET @printMessage =  'All credit card data has been cleaned.  Shall we warp to level 8 now?' + char(13) + char(10) + char(13) + char(10);
RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
