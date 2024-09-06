#!/usr/bin/python3.5

import os
import subprocess
import datetime
import logging
from google.cloud import storage
import configparser

# Backup and log path
BUCKET = "ti-dba-prod-sql-01"
GCS_PATH = "temp"
SSL_PATH = "/ssl-certs/"
DB_USR = "GenBackupUser"
DB_PWD = "DBB@ckuPU53r*"
TMP_PATH = "/backup/dumps/" # Temporary directory to store dumps before uploading to GCS

# Backup and log paths
log_path = "/backup/logs/"
if not os.path.exists(log_path):
    os.makedirs(log_path)
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(log_path, "MYSQL_backup_activity_{}.log".format(current_date))
logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')

def dump_database_to_tmp(server, host, db, use_ssl):
    """
    Dump the database to a temporary gzipped file.
    """
    current_date = datetime.datetime.now().strftime("%Y-%m-%d")
    tmp_file_path = os.path.join(TMP_PATH, "{}_{}.sql.gz".format(current_date, db))

    try:
        dump_command = [
            "mysqldump", "-u" + DB_USR, "-p" + DB_PWD, "--set-gtid-purged=OFF",
            "--single-transaction", "--lock-tables=false", "--quick", "--triggers", "--events", "--routines",
            "-h", host, db
        ]
        if use_ssl:
            dump_command.extend([
                "--ssl-ca=" + os.path.join(SSL_PATH, server, "server-ca.pem"),
                "--ssl-cert=" + os.path.join(SSL_PATH, server, "client-cert.pem"),
                "--ssl-key=" + os.path.join(SSL_PATH, server, "client-key.pem")
            ])

        dump_command_str = ' '.join(dump_command)
        logging.info("Dump command: {}".format(dump_command_str))

# Dump the database to a temporary file and compress it using gzip

        with open(tmp_file_path, "wb") as temp_file:
            dump_proc = subprocess.Popen(dump_command, stdout=subprocess.PIPE)
            gzip_proc = subprocess.Popen(["gzip"], stdin=dump_proc.stdout, stdout=temp_file)
            dump_proc.stdout.close()
            gzip_proc.communicate()

        logging.info("Dumped database {} to temporary file {}".format(db, tmp_file_path))
        return tmp_file_path

    except subprocess.CalledProcessError as e:
        logging.error("Failed to dump database {}: {}".format(db, e))
        return None
    except Exception as e:
        logging.error("Unexpected error dumping database {}: {}".format(db, e))
        return None

def move_to_gcs(tmp_file_path, server, db):
    """
    Use gsutil command to move the temporary file to Google Cloud Storage.
    """
    try:
        current_date = datetime.datetime.now().strftime("%Y-%m-%d")
        gcs_path = "gs://{}/{}/{}/{}_{}.sql.gz".format(BUCKET, GCS_PATH, server, current_date, db)
        gsutil_command = "gsutil -m -o GSUtil:parallel_composite_upload_threshold=150MB mv {} {}".format(tmp_file_path, gcs_path)
        logging.info("Executing: {}".format(gsutil_command))
        subprocess.check_call(gsutil_command, shell=True)
        logging.info("File {} moved to GCS successfully.".format(tmp_file_path))
    except subprocess.CalledProcessError as e:
        logging.error("Failed to move file to GCS: {}".format(e))

def main():
    """
    Main function to execute the backup process.
    """
    current_date = datetime.datetime.now().strftime("%Y-%m-%d")
# Define the parameters directly
    SERVERS = [
        {
            "name": "ti-mysql-us-we-13",
            "host": "172.19.225.197",
            "ssl": "n",
            "databases": ["db_gleat"]
        }
    ]

    logging.info("================================== {} =============================================".format(current_date))
    logging.info("==== Backup Process Started ====")

    for server_data in SERVERS:
        SERVER = server_data["name"]
        HOST = server_data["host"]
        SSL = server_data["ssl"]
        DATABASES = server_data["databases"]

        logging.info("DUMPING SERVER: {}".format(SERVER))

        try:
            for db in DATABASES:  # Looping through declared databases
                logging.info("Backing up database: {}".format(db.strip()))
                tmp_file_path = dump_database_to_tmp(SERVER, HOST, db.strip(), SSL.upper() == "Y")

                if tmp_file_path:
                    move_to_gcs(tmp_file_path, SERVER, db.strip())

        except Exception as e:
            logging.error("Error processing server {}: {}".format(SERVER, e))

    logging.info("==== Backup Process Completed ====")


if __name__ == "__main__":
    main()
