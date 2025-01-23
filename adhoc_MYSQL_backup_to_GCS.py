#!/usr/bin/python3.5

"""
MySQL Database Backup Script with Google Cloud Storage Integration

This script performs automated backups of MySQL databases and uploads them to Google Cloud Storage.
It supports SSL connections, compression, and maintains detailed logging of all operations.

Key Features:
- MySQL database backup using mysqldump
- Compression using gzip
- SSL support for secure connections
- Google Cloud Storage integration
- Detailed logging
- Error handling and reporting

Requirements:
- Python 3.5+
- Google Cloud Storage client library
- MySQL client tools
- Access to Google Cloud Storage bucket
- Appropriate MySQL user permissions
"""

import os
import subprocess
import datetime
import logging
from google.cloud import storage
import configparser

# Configuration Constants
# TODO: Move these to a secure configuration file or environment variables
BUCKET = "ti-dba-prod-sql-01"
GCS_PATH = "Decommissioned"
SSL_PATH = "/ssl-certs/"
DB_USR = "GenBackupUser"
DB_PWD = "DBB@ckuPU53r*"
TMP_PATH = "/backup/dumps/"  # Temporary directory for database dumps

# Setup logging configuration
log_path = "/backup/logs/"
if not os.path.exists(log_path):
    os.makedirs(log_path)
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(log_path, "MYSQL_backup_activity_{}.log".format(current_date))
logging.basicConfig(
    filename=log_filename,
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)

def dump_database_to_tmp(server, host, db, use_ssl):
    """
    Creates a compressed dump of a MySQL database.

    Args:
        server (str): The name of the database server
        host (str): The hostname or IP address of the database server
        db (str): The name of the database to backup
        use_ssl (bool): Whether to use SSL for the connection

    Returns:
        str: Path to the temporary backup file if successful, None otherwise

    The function uses mysqldump with the following features:
    - Single transaction mode for consistency
    - No table locking to minimize impact on production
    - Quick option for large tables
    - Includes triggers, events, and routines
    - GTID purging disabled
    - Compression using gzip
    """
    current_date = datetime.datetime.now().strftime("%Y-%m-%d")
    tmp_file_path = os.path.join(TMP_PATH, "{}_{}.sql.gz".format(current_date, db))

    try:
        # Construct the mysqldump command with all necessary options
        dump_command = [
            "mysqldump",
            "-u" + DB_USR,
            "-p" + DB_PWD,
            "--set-gtid-purged=OFF",  # Prevents GTID-related issues in replication
            "--single-transaction",    # Consistent backup without locking tables
            "--lock-tables=false",     # Prevents blocking other connections
            "--quick",                 # Reduces memory usage for large tables
            "--triggers",              # Include trigger definitions
            "--events",               # Include event definitions
            "--routines",             # Include stored procedures and functions
            "-h", host,
            db
        ]

        # Add SSL parameters if SSL is enabled
        if use_ssl:
            dump_command.extend([
                "--ssl-ca=" + os.path.join(SSL_PATH, server, "server-ca.pem"),
                "--ssl-cert=" + os.path.join(SSL_PATH, server, "client-cert.pem"),
                "--ssl-key=" + os.path.join(SSL_PATH, server, "client-key.pem")
            ])

        # Log the command for debugging purposes (excluding password)
        safe_command = ' '.join(dump_command).replace(DB_PWD, "****")
        logging.info("Executing dump command: {}".format(safe_command))
		
        # Create a pipeline: mysqldump -> gzip -> output file
        with open(tmp_file_path, "wb") as temp_file:
            # Start mysqldump process
            dump_proc = subprocess.Popen(dump_command, stdout=subprocess.PIPE)
            # Pipe mysqldump output through gzip
            gzip_proc = subprocess.Popen(["gzip"], stdin=dump_proc.stdout, stdout=temp_file)
            
            # Close mysqldump stdout to signal EOF to gzip
            dump_proc.stdout.close()
            # Wait for gzip to complete
            gzip_proc.communicate()

        logging.info("Successfully dumped database {} to temporary file {}".format(db, tmp_file_path))
        return tmp_file_path

    except subprocess.CalledProcessError as e:
        logging.error("mysqldump process failed for database {}: {}".format(db, e))
        return None
    except Exception as e:
        logging.error("Unexpected error during database dump {}: {}".format(db, e))
        return None

def move_to_gcs(tmp_file_path, server, db):
    """
    Transfers a backup file to Google Cloud Storage.

    Args:
        tmp_file_path (str): Path to the local backup file
        server (str): Name of the source server
        db (str): Name of the database

    This function:
    - Constructs the GCS destination path
    - Uses gsutil for efficient file transfer
    - Enables parallel composite uploads for large files
    - Handles transfer errors and logging
    """
    try:
        current_date = datetime.datetime.now().strftime("%Y-%m-%d")
        # Construct GCS destination path
        gcs_path = "gs://{}/{}/{}/{}_{}.sql.gz".format(
            BUCKET,
            GCS_PATH,
            server,
            current_date,
            db
        )

        # Construct gsutil command with parallel upload optimization
        gsutil_command = "gsutil -m -o GSUtil:parallel_composite_upload_threshold=150MB mv {} {}".format(
            tmp_file_path,
            gcs_path
        )
        
        logging.info("Starting GCS transfer: {}".format(gsutil_command))
        subprocess.check_call(gsutil_command, shell=True)
        logging.info("Successfully transferred {} to GCS".format(tmp_file_path))

    except subprocess.CalledProcessError as e:
        logging.error("GCS transfer failed: {}".format(e))

def main():
    """
    Main execution function for the backup process.

    This function:
    1. Initializes the backup process
    2. Iterates through configured servers and databases
    3. Orchestrates the backup and upload process
    4. Handles errors and maintains logging
    """
    current_date = datetime.datetime.now().strftime("%Y-%m-%d")

    # Server configuration
    # ENSURE TO UPDATE THIS PART
    SERVERS = [
        {
            "name": "ti-mysql-us-we-13",
            "host": "172.19.225.197",
            "ssl": "n",
            "databases": ["db_osticket_security_global"]
        }
    ]

    # Log backup process start
    logging.info("=" * 80)
    logging.info("Backup Process Started - {}".format(current_date))
    logging.info("=" * 80)

    # Process each server
    for server_data in SERVERS:
        SERVER = server_data["name"]
        HOST = server_data["host"]
        SSL = server_data["ssl"]
        DATABASES = server_data["databases"]

        logging.info("Processing server: {}".format(SERVER))

        try:
            # Process each database for the current server
            for db in DATABASES:
                db = db.strip()
                logging.info("Starting backup of database: {}".format(db))
                
                # Step 1: Create the database dump
                tmp_file_path = dump_database_to_tmp(
                    SERVER,
                    HOST,
                    db,
                    SSL.upper() == "Y"
                )

                # Step 2: Upload to GCS if dump was successful
                if tmp_file_path:
                    move_to_gcs(tmp_file_path, SERVER, db)
                else:
                    logging.error("Skipping GCS upload for {} due to dump failure".format(db))

        except Exception as e:
            logging.error("Failed to process server {}: {}".format(SERVER, e))

    logging.info("=" * 80)
    logging.info("Backup Process Completed - {}".format(current_date))
    logging.info("=" * 80)

if __name__ == "__main__":
    main()
