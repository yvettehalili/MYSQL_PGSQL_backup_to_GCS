import os
import datetime
import logging
import subprocess

# Configuration
CONFIG_FILE = "/backup/configs/MSSQL_database_list.conf"
LOG_DIR = "/backup/logs"
INSTANCE_NAME = 'ti-aiprod-ms-primary-01'  # Replace with your instance name
GCS_BUCKET_NAME = "ti-dba-prod-sql-01"  # Replace with your GCS bucket name
BACKUP_PATH_TEMPLATE = "Backups/Current/MSSQL/{instance_name}/{database_name}"  # Template for backup path

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

def export_to_gcs(instance_name, database_name, bucket_name):
    # Build the dynamic backup path
    backup_path = BACKUP_PATH_TEMPLATE.format(instance_name=instance_name, database_name=database_name)
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file_name = f"{database_name}_FULL_{timestamp}.bak"
    gcs_path = f"gs://{bucket_name}/{backup_path}/{backup_file_name}"

    log_info(f"Exporting database: {database_name} to GCS path: {gcs_path}")
    export_command = [
        "gcloud", "sql", "export", "bak", instance_name,
        gcs_path,
        "--database", database_name
    ]

    log_info(f"Running command: {' '.join(export_command)}")
    start_time = datetime.datetime.now()

    try:
        result = subprocess.run(export_command, check=True, text=True, capture_output=True)
        end_time = datetime.datetime.now()
        duration = (end_time - start_time).total_seconds()
        log_info(f"Export completed for database {database_name} successfully in {duration:.2f} seconds.")
        log_info(result.stdout)
    except subprocess.CalledProcessError as e:
        log_info(f"Error while exporting database {database_name}: {e.stderr}")
        raise

def main():
    log_info("================================== {} ============================================".format(current_date))
    log_info("==== Backup Process Started ====")
    log_info(f"Backing up CloudSQL Instance: {INSTANCE_NAME}")

    try:
        databases = read_database_list(CONFIG_FILE)
        for database in databases:
            try:
                export_to_gcs(INSTANCE_NAME, database, GCS_BUCKET_NAME)
            except Exception as e:
                log_info(f"Error while backing up database {database}: {str(e)}")
    except FileNotFoundError:
        log_info(f"Error: Configuration file not found at {CONFIG_FILE}")
    except Exception as e:
        log_info(f"Unexpected error occurred: {str(e)}")

    log_info("==== Backup Process Completed ====")

if __name__ == "__main__":
    main()
