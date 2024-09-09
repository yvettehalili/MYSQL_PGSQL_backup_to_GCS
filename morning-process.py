#!/usr/bin/python3.5

import subprocess

def run_command(command, stdout_file, stderr_file, append=False):
    """Runs a command and writes the output and errors to specified files."""
    mode = 'a' if append else 'w'
    with open(stdout_file, mode) as out, open(stderr_file, mode) as err:
        process = subprocess.run(command, shell=True, stdout=out, stderr=err)
    return process.returncode

# Define commands
mysql_command = "/usr/bin/python3 /backup/scripts/MYSQL_cloudsql_backup_to_GCS.py"
pgsql_command = "/usr/bin/python3 /backup/scripts/PGSQL_cloudsql_backup_to_GCS.py"

# Define log files
database_bk_output_log = "/backup/cronlog/database_bk_output.log"
database_bk_error_log = "/backup/cronlog/database_bk_error.log"

# Run commands sequentially
run_command(mysql_command, database_bk_output_log, database_bk_error_log)
run_command(pgsql_command, database_bk_output_log, database_bk_error_log, append=True)
