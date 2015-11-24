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
    -R, --recovery      Sets WITH RECOVERY or NORECOVERY options on the database being restored.
    -C, --create        Create a new database or use an existing database.
    -U, --user_rights   Sets how users should be kept/restored to the original and restored database.
    
The module classes consist of:
"""

__author__  = "Joshua Schaeffer"
__date__    = "$Nov 23, 2015 3:53:23 PM$"
__version__ = '1.0'

import argparse

parser = argparse.ArgumentParser(description="")
parser.add_argument("command", help="Runs the dbo.usp_THKBackup stored procedure", choices=["backup", "restore"])
parser.add_argument("-v", "--verbose", help="outputs verbose messages", action="store_true")
args = parser.parse_args()

if __name__ == "__main__":
    if args.verbose:
       print "verbose logging is on"
    else:
        print "verbose logging is off"
