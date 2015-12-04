/*
**	This script is used to add custom SQL messages to sys.messages. These messages are used to report the status, errors, and warnings of processes that occur
**	throughout usp, sub, and adm stored procedures. the following conventions should be used:
**		-	All custom messages ID's should start above 60000.
**		-	Messages for user stored procedures (usp's) should start at 60001.
**		-	Messages for sub stored procedures (sub's) should start at 70000.
**		-	Messages for adm stored procedures (adm's) should start at 80000.
**		-	Information and error messages that are called outside of CATCH blocks that are used across all types of stored procedures should start at 90000.
**	All debug messages should start halfway through the message range. For example debug messages for usp's will start at 65000 while debug messages for sub's
**	will start at 75000. The following guidelines should be used when creating messages:
**		-	Messages with a severity of 0 - 9 should occupy the first 500 messages of a range.
**		-	Messages with a severity of 10 should occupy the next 1500 messages of a range.
**		-	Messages with a severity of 11 should occupy the next 250 messages of a range.
**		-	Messages with a severity of 13 should occupy the next 100 messages of a range.
**		-	Messages with a severity of 14 should occupy the next 250 messages of a range.
**		-	Messages with a severity of 15 should occupy the next 500 messages of a range.
**		-	Messages with a severity of 16 should occupy the next 1000 messages of a range.
**		-	Messages with a severity of 17 - 19 occupy the next 100 messages of a range.
**		-	The next 600 messages of a range can be used for special cases.
**		-	The last 200 (or so) messages of a range should not be used, but reserved as a buffer unless absolutely necessary.
**
**	Messages should be called in the sub_formatErrorMsg sp not the procedure that the error actually occured in.
*/

/*
OLD MESSAGES (TEMPORARY)
60001	1033	16	0	Unable to find personnel using the values provided  First Name: (%s)  Last Name: (%s)
60002	1033	10	0	The name provided returned more than one personnel, defaulting to choosing the first record returned.  If this is not the correct personnel then disambiguate the name.
60003	1033	16	0	The THINK Enterprise version "%s" does not exist, aborting process
90000	1033	16	1	Log shipping copy for %s are more than %s Minute(s) behind
90001	1033	16	1	Log shipping Restores for %s are more than %s Minute(s) behind
*/

USE [master];
GO

DECLARE @printMessage nvarchar(4000)

/*
**	The user defined message ID of 60000 is a THINK Subscription reserved ID. All custom messages start after 60000.
*/
IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000 AND language_id = 1033)
	EXEC sp_addmessage @msgnum = 60000 --Reserved custom message
		,@severity = 1
		,@msgtext = 'Custom Message for the THINK Subscription stored procedures.'
		,@lang = 'english'
		,@with_log = 'FALSE'
ELSE
	RAISERROR('Message ID 60000 already exists, skipping.', 10, 1) WITH NOWAIT;

/*
**	All usp sp custom messages. Message ID's from 60001 - 69999.
**	For reference:
**	|-------------------------------------------------------|
**	|	Severity	|				  Range					|
**	|-------------------------------------------------------|
**	|///////////////|	  Non Debug		|		Debug		|
**	|---------------|-------------------|-------------------|
**	|	   0-9		|	60001 - 60501	|	65001 - 65501	|
**	|	   10		|	60502 - 62002	|	65502 - 67002	|
**	|	   11		|	62003 - 62253	|	67003 - 67253	|
**	|	   13		|	62254 - 62354	|	67254 - 67354	|
**	|	   14		|	62355 - 62605	|	67355 - 67605	|
**	|	   15		|	62606 - 63106	|	67606 - 68106	|
**	|	   16		|	63107 - 64107	|	68107 - 69107	|
**	|	  17-19		|	64108 - 64208	|	69108 - 69208	|
**	|  special case |	64209 - 64809	|	69209 - 69809	|
**	|	reserved	|	64810 - 64999	|	69810 - 69999	|
**	|-------------------------------------------------------|
*/

/*
**	All sub sp custom messages. Message ID's from 70000 - 79999.
**	For reference:
**	|-------------------------------------------------------|
**	|	Severity	|				  Range					|
**	|-------------------------------------------------------|
**	|///////////////|	  Non Debug		|		Debug		|
**	|---------------|-------------------|-------------------|
**	|	   0-9		|	70000 - 70500	|	75000 - 75500	|
**	|	   10		|	70501 - 72001	|	75501 - 77001	|
**	|	   11		|	72002 - 72252	|	77002 - 77252	|
**	|	   13		|	72253 - 72353	|	77253 - 77353	|
**	|	   14		|	72354 - 72604	|	77354 - 77604	|
**	|	   15		|	72605 - 73105	|	77605 - 78105	|
**	|	   16		|	73106 - 74106	|	78106 - 79106	|
**	|	  17-19		|	74107 - 74207	|	79107 - 79207	|
**	|  special case |	74208 - 74808	|	79208 - 79808	|
**	|	reserved	|	74809 - 74999	|	79809 - 79999	|
**	|-------------------------------------------------------|
*/
BEGIN
	
	SET @printMessage = 'Filename: "%s" and/or "%s" already exists for the %s' + char(13) + char(10) + 'database, alerting filename structure'
	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 70501 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 70501
			,@severity = 10
			,@msgtext = @printMessage
			,@lang = 'english'
			,@with_log = 'FALSE';
	ELSE
		RAISERROR('Message ID 70501 already exists, skipping.', 10, 1) WITH NOWAIT;
END;

/*
**	All adm sp custom messages. Message ID's from 80000 - 89999.
**	For reference:
**	|-------------------------------------------------------|
**	|	Severity	|				  Range					|
**	|-------------------------------------------------------|
**	|///////////////|	  Non Debug		|		Debug		|
**	|---------------|-------------------|-------------------|
**	|	   0-9		|	80000 - 80500	|	85000 - 85500	|
**	|	   10		|	80501 - 82001	|	85501 - 87001	|
**	|	   11		|	82002 - 82252	|	87002 - 87252	|
**	|	   13		|	82253 - 82353	|	87253 - 87353	|
**	|	   14		|	82354 - 82604	|	87354 - 87604	|
**	|	   15		|	82605 - 83105	|	87605 - 88105	|
**	|	   16		|	83106 - 84106	|	88106 - 89106	|
**	|	  17-19		|	84107 - 84207	|	89107 - 89207	|
**	|  special case |	84208 - 84808	|	89208 - 89808	|
**	|	reserved	|	84809 - 84999	|	89809 - 89999	|
**	|-------------------------------------------------------|
*/
BEGIN


	SET @printMessage = N'The database engine returned an "ALTER DATABASE statement failed" which could' + char(13) + char(10) +
						N'indicate that the database doesn''t exist or is unavailable. Processing will continue but it is' + char(13) + char(10) +
						N'likely that additional errors may occur.'
	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 87002 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 87002
			,@severity = 11
			,@msgtext = @printMessage
			,@lang = 'english'
			,@with_log = 'TRUE';
	ELSE
		RAISERROR('Message ID 87002 already exists, skipping.', 10, 1) WITH NOWAIT;

	SET @printMessage = N'The database engine was unable to effect a database change. Processing will continue but additional errors may occur.'
	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 80501 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 80501
			,@severity = 10
			,@msgtext = @printMessage
			,@lang = 'english'
			,@with_log = 'FALSE';
	ELSE
		RAISERROR('Message ID 80501 already exists, skipping.', 10, 1) WITH NOWAIT;
END;

/*
**	All information and error messages that are used across all sp's. Message ID's from 90000 - 99999.
**	For reference:
**	|-------------------------------------------------------|
**	|	Severity	|				  Range					|
**	|-------------------------------------------------------|
**	|///////////////|	  Non Debug		|		Debug		|
**	|---------------|-------------------|-------------------|
**	|	   0-9		|	90000 - 90500	|	95000 - 95500	|
**	|	   10		|	90501 - 92001	|	95501 - 97001	|
**	|	   11		|	92002 - 92252	|	97002 - 97252	|
**	|	   13		|	92253 - 92353	|	97253 - 97353	|
**	|	   14		|	92354 - 92604	|	97354 - 97604	|
**	|	   15		|	92605 - 93105	|	97605 - 98105	|
**	|	   16		|	93106 - 94106	|	98106 - 99106	|
**	|	  17-19		|	94107 - 94207	|	99107 - 99207	|
**	|  special case |	94208 - 94808	|	99208 - 99808	|
**	|	reserved	|	94809 - 94999	|	99809 - 99999	|
**	|-------------------------------------------------------|
*/
BEGIN

	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 90501 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 90501
			,@severity = 10
			,@msgtext = 'The database was successfully dropped.'
			,@lang = 'english'
			,@with_log = 'FALSE';
	ELSE
		RAISERROR('Message ID 90501 already exists, skipping.', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 90502 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 90502
			,@severity = 10
			,@msgtext = 'Only members of the sysadmin and securityadmin fixed server roles may view debug statements.  No debug statements will be printed.'
			,@lang = 'english'
			,@with_log = 'FALSE';
	ELSE
		RAISERROR('Message ID 90502 already exists, skipping.', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 90503 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 90503
			,@severity = 10
			,@msgtext = 'Found baseline_versions in the %s instance not in %s. Updating baselines in the %s instance'
			,@lang = 'english'
			,@with_log = 'FALSE';
	ELSE
		RAISERROR('Message ID 90503 already exists, skipping.', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 93106 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 93106
			,@severity = 16
			,@msgtext = 'Value for parameter @baselineFile cannot be empty when adding an available baseline to the meta database.'
			,@lang = 'english'
			,@with_log = 'TRUE';
	ELSE
		RAISERROR('Message ID 93106 already exists, skipping.', 10, 1) WITH NOWAIT;

	IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 93107 AND language_id = 1033)
		EXEC sp_addmessage @msgnum = 93107
			,@severity = 16
			,@msgtext = 'You must provide the THINK Enterprise version when adding an unavailable baseline to the meta database.'
			,@lang = 'english'
			,@with_log = 'TRUE';
	ELSE
		RAISERROR('Message ID 93107 already exists, skipping.', 10, 1) WITH NOWAIT;
END;