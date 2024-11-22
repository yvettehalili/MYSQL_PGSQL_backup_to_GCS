import pyodbc
import os
import datetime
import logging
from google.cloud import storage

# Configuration
CONFIG_FILE = "/backup/configs/MSSQL_database_list.conf"
BACKUP_DIR = "/backup/dumps"
LOG_DIR = "/backup/logs"
SERVER = '34.78.106.8,1433'  # Replace with your SQL Server instance IP
USERNAME = 'genbackupuser'
PASSWORD = 'genbackupuser'
INSTANCE_NAME = 'ti-aiprod-ms-primary-01'  # Change as per your instance name
GCS_BUCKET_NAME = "ti-dba-prod-sql-01"  # Replace with your GCS bucket name

# Setup logging
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(LOG_DIR, f"MSSQL_backup_activity_{current_date}.log")
logging.basicConfig(filename=log_filename, level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

def log_info(message):
    logging.info(message)
    print(message)

def read_database_list(config_file):
    databases = []
    with open(config_file, 'r') as file:
        for line in file:
            db = line.strip()
            if db:
                databases.append(db)
    return databases

def upload_to_gcs(local_file_path, bucket_name, destination_blob_name):
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(destination_blob_name)
    blob.upload_from_filename(local_file_path)
    log_info(f"Uploaded {local_file_path} to gs://{bucket_name}/{destination_blob_name}")

def backup_database(connection, database_name):
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file_local = os.path.join(BACKUP_DIR, f"{INSTANCE_NAME}_{database_name}_FULL_{timestamp}.bak")
    backup_command = f"BACKUP DATABASE [{database_name}] TO DISK = N'{backup_file_local}' WITH NOFORMAT, NOINIT, NAME = N'{database_name}-Full Database Backup', SKIP, NOREWIND, NOUNLOAD, STATS = 10"

    log_info(f"Backing up database: {database_name}")
    log_info(f"Backup command: {backup_command.replace(PASSWORD, '****')}")

    start_time = datetime.datetime.now()

    # Use autocommit for the backup command
    connection.autocommit = True
    cursor = connection.cursor()
    cursor.execute(backup_command)
    cursor.commit()
    connection.autocommit = False

    end_time = datetime.datetime.now()

    duration = (end_time - start_time).total_seconds()
    log_info(f"Backup Completed for database {database_name} to {backup_file_local} successfully in {duration:.2f} seconds.")

    # Construct GCS path
    gcs_path = f"Backups/Current/MSSQL/{INSTANCE_NAME}/{database_name}/FULL/{os.path.basename(backup_file_local)}"
    upload_to_gcs(backup_file_local, GCS_BUCKET_NAME, gcs_path)

def main():
    log_info("================================== {} ============================================".format(current_date))
    log_info("==== Backup Process Started ====")
    log_info(f"Backing up SERVER: {SERVER}")

    databases = read_database_list(CONFIG_FILE)

    connection = pyodbc.connect(f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER=tcp:{SERVER};UID={USERNAME};PWD={PASSWORD}")

    for database in databases:
        try:
            backup_database(connection, database)
        except Exception as e:
            log_info(f"Error while backing up database {database}: {str(e)}")

    connection.close()
    log_info("==== Backup Process Completed ====")

if __name__ == "__main__":
    main()
