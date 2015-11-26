"""Command line MSSQL stored procedure automation tool.

This module runs MSSQL stored procedures from the command line. It is mainly designed to automate the running of stored
procedures.

It takes arguments that correspond to the following stored procedures:

    -   dbo.usp_THKBackupDb
    -   dbo.usp_THKRestoreDb
    
Below is an example of how to run the command line utility:

    automate.py backup -s localhost\\myinstance -p 1433 -d mydb -u login -a password -c client -P default -t full \\
        -m native -T production -r 14 -M "media set" -n
    
    automate.py restore -s localhost\\myinstance -p 1433 -d mydb -u login -a password -c client -P "C:\\Temp\\backup.bak"
        -R -C -U 1 -T production
        
The following parameters can be passed to the cli tool:

    -s, --server        Name of the MSSQL server and instance. Can be set in the config file.
    -p, --port          Port number that the MSSQL server and instance is listening on. Can be set in the config file.
    -d, --database      Name of the database on the MSSQL server and instance. Can be set in the config file.
    -D, --dsn           Name of the DSN on the local machine that can connect to the database. When specified the server, database, and port should
                        not be specified.
    -u, --username      MSSQL login used to access the database. Can be set in the config file.
    -a, --password      Password associated to the MSSQL login. Can be set in the config file.
    -c, --client        The name of the client, program, or database that is being backed up or restored.
    -P, --path          For backups: Which location the database should be backed up to: "default", "customer first",
                        "db changes". For restores: Backup path and filename that is being used to restore the database.
    -t, --backup_type   Type of backup being taken: "full", "diff", "log".
    -m, --method        How the backup should be performed: "native", "litespeed".
    -T, --database_type Type of database being backed up: "test", "live", "staging", "conversion", "qa", "dev", "other".
    -r, --retention     How long the backup should be kept.
    -M, --media_set     The name of the media set/family to backup or create.
    -n, --new_media     Sets if a new media set/family should be created or to use an existing one.
    -f, --filename      The full path and filename of the database backup to use for restoring.
    -R, --recovery      Sets WITH RECOVERY or NORECOVERY options on the database being restored.
    -C, --create        Create a new database or use an existing database.
    -U, --user_rights   Sets how users should be kept/restored to the original and restored database.
    
The module classes consist of:
"""

__author__  = "Joshua Schaeffer"
__date__    = "$Nov 23, 2015 3:53:23 PM$"
__version__ = '1.0'

import argparse
import sqlalchemy

ENGINE_STRING = "mssql+pyodbc://guest:password@localhost/tempdb"

'''Common arguments for the automation program. The arguments are used in both the backup and restore subcommands.'''
parent_parser = argparse.ArgumentParser(prog="automate.py", prefix_chars="-/"
    ,description="Common parameters to both the backup and restore stored procedures.")
parent_parser.add_argument("-u", "--username", help="MSSQL login used to access the database. Can be set in the config file.") #If a login is not supplied then the program will use the user's current credentials.
parent_parser.add_argument("-a", "--password", help="Password associated to the MSSQL login. Can be set in the config file.")
parent_parser.add_argument("-c", "--client", help="The name of the client, program, or database that is being backed up or restored.")
parent_parser.add_argument("--version", action="version", version=__version__, help="Prints the current version and exits.")
subparser = parent_parser.add_subparsers(description="Command help-text", help="Sub-commands")
hostname_group = parent_parser.add_argument_group(title="Hostname args", description="Arguments required when providing a hostname based connection.")
dsn_group = parent_parser.add_argument_group(title="DSN args", description="Arguments required when providing a DSN based connection.")

hostname_group.add_argument("-s", "--server", nargs="?", default="localhost"
    ,help="Name of the MSSQL server and instance. Can be set in the config file.")
hostname_group.add_argument("-d", "--database", nargs="?", default="tempdb"
    ,help="Name of the database on the MSSQL server and instance. Can be set in the config file.")
hostname_group.add_argument("-p", "--port", type=int, default=1433
    ,help="Port number that the MSSQL server and instance is listening on. Can be set in the config file.")
dsn_group.add_argument("-D", "--dsn", nargs="?", default="localhost", help="Name of the dsn used to connect to the server and database.")

'''Arguments used for the backup subcommand'''
backup_parser = subparser.add_parser("backup", help="Runs the dbo.usp_THKBackupDb stored procedure")
backup_parser.add_argument("-P", "--path", default="default"
    ,help="Which location the database should be backed up to: 'default', 'customer first', 'db changes'. For restores: Backup path and filename that is being used to restore the database.")
backup_parser.add_argument("-t", "--backup_type", default="full", choices=["full", "diff", "log"]
    ,help="Type of backup being taken: 'full', 'diff', 'log'.")
backup_parser.add_argument("-m", "--method", default="native", help="How the backup should be performed: 'native', 'litespeed'.")
backup_parser.add_argument("-T", "--database_type", default="L", choices=["L", "T", "S", "C", "Q", "D", "O"]
    ,help="Type of database being backed up: 'test', 'live', 'staging', 'conversion', 'qa', 'dev', 'other'.")
backup_parser.add_argument("-r", "--retention", type=int, default=90, help="How long the backup should be kept.")
backup_parser.add_argument("-M", "--media_set", help="The name of the media set/family to backup or create.")
backup_parser.add_argument("-n", "--new_media", action="store_false"
    ,help="Sets if a new media set/family should be created or to use an existing one.")

'''Arguments used for the restore subcommand'''
restore_parser = subparser.add_parser("restore", help="Runs the dbo.usp_THKRestoreDb stored procedure")
restore_parser.add_argument("-f", "--filename", required=True, help="The full path and filename of the database backup to use for restoring.")
restore_parser.add_argument("-R", "--Recovery", action="store_true"
    ,help="Sets WITH RECOVERY or NORECOVERY options on the database being restored.")
restore_parser.add_argument("-C", "--create", action="store_true", help="Create a new database or use an existing database.")
restore_parser.add_argument("-U", "--user_rights", type=int, default=1
    ,help="Sets how users should be kept/restored to the original and restored database.")

args = parent_parser.parse_args()

if args.password is None:
    args.password = ""
if args.username is None:
    args.username = ""
if args.client is None:
    args.client = args.database
if args.media_set is None:
    args.media_set = "NULL"

ENGINE_STRING = "mssql+pyodbc://%s:%s@%s:%d/%s?driver=SQL+Server+Native+Client+10.0" % (args.username, args.password, args.server, args.port, args.database)
engine = sqlalchemy.create_engine(ENGINE_STRING)

connection = engine.raw_connection()
try:
    cursor = connection.cursor()
    cursor.callproc("dbo.usp_THKBackupDb", [args.database, args.client, args.path, args.backup_type, args.method, args.database_type, args.retention, args.media_set, args.new_media])
    results = list(cursor.fetchall())
    cursor.close()
    connection.commit()
finally:
    connection.close

class Automate(object):
    pass

class Backup(Automate):
    pass

class Restore(Automate):
    pass

if __name__ == "__main__":
    pass
