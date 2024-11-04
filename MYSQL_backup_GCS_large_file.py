import os
import datetime
import logging
import configparser
import subprocess
import time
import io
from google.cloud import storage

# Configuration
BUCKET = "ti-dba-prod-sql-01"
GCS_PATH = "Backups/Current/MYSQL"
SSL_PATH = "/ssl-certs/"
SERVERS_LIST = "/backup/configs/MYSQL_servers_list.conf"
KEY_FILE = "/root/jsonfiles/ti-dba-prod-01.json"
CREDENTIALS_PATH = "/backup/configs/db_credentials.conf"

# Logging configuration
log_path = "/backup/logs/"
os.makedirs(log_path, exist_ok=True)
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(log_path, "MYSQL_backup_activity_{}.log".format(current_date))
logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')

# Load credentials
config = configparser.ConfigParser()
config.read(CREDENTIALS_PATH)
DB_USR = config['credentials']['DB_USR']
DB_PWD = config['credentials']['DB_PWD']

UPDATED_EMAIL_SCRIPT_PATH = "/backup/scripts/MYSQL_backup_error_notif.py"

def sanitize_command(command):
    """Sanitize the command by replacing sensitive information."""
    sanitized_command = [
        arg.replace(DB_USR, "*****").replace(DB_PWD, "*****") if isinstance(arg, str) else arg
        for arg in command
    ]
    return sanitized_command

def send_error_email():
    subject = "[ERROR] MYSQL CloudSQL Backup Error"
    error_lines = []

    with open(log_filename) as log_file:
        for line in log_file:
            if "ERROR" in line:
                error_lines.append(line.strip())

    body = '<br>'.join(error_lines)

    command = [
        "python3", UPDATED_EMAIL_SCRIPT_PATH, subject, body
    ]
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to send error email: {}".format(e))

def load_server_list(file_path):
    """Load the server list from a given file."""
    config = configparser.ConfigParser()
    try:
        config.read(file_path)
        return config.sections(), config
    except Exception as e:
        logging.error("Failed to load server list: {}".format(e))
        send_error_email()
        return [], None

def get_database_list(host, use_ssl, server):
    """Retrieve the list of databases from the MySQL server."""
    try:
        if not use_ssl:
            command = [
                "mysql", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", host,
                "--default-auth=mysql_native_password",
                "-B", "--silent", "-e", "SHOW DATABASES"
            ]
        else:
            command = [
                "mysql", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", host,
                "--ssl-ca=" + os.path.join(SSL_PATH, server, "server-ca.pem"),
                "--ssl-cert=" + os.path.join(SSL_PATH, server, "client-cert.pem"),
                "--ssl-key=" + os.path.join(SSL_PATH, server, "client-key.pem"),
                "--default-auth=mysql_native_password",
                "-B", "--silent", "-e", "SHOW DATABASES"
            ]
        result = subprocess.check_output(command, stderr=subprocess.STDOUT)
        db_list = result.decode("utf-8").strip().split('\n')
        valid_db_list = [
            db for db in db_list if db.isidentifier() and db not in (
                "information_schema", "performance_schema", "sys", "mysql"
            )
        ]
        return valid_db_list
    except subprocess.CalledProcessError as e:
        logging.error("Failed to get database list from {}: {} - Output: {}".format(
            host, e, e.output.decode()
        ))
        send_error_email()
        return []

def get_database_size(host, db, use_ssl, server):
    """Retrieve the size of the specified database."""
    try:
        if not use_ssl:
            command = [
                "mysql", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", host,
                "--default-auth=mysql_native_password",
                "-B", "--silent", "-e", "SELECT table_schema, SUM(data_length + index_length) / 1024 / 1024 / 1024 as 'Size (GB)' FROM information_schema.tables WHERE table_schema='{}' GROUP BY table_schema".format(db)
            ]
        else:
            command = [
                "mysql", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", host,
                "--ssl-ca=" + os.path.join(SSL_PATH, server, "server-ca.pem"),
                "--ssl-cert=" + os.path.join(SSL_PATH, server, "client-cert.pem"),
                "--ssl-key=" + os.path.join(SSL_PATH, server, "client-key.pem"),
                "--default-auth=mysql_native_password",
                "-B", "--silent", "-e", "SELECT table_schema, SUM(data_length + index_length) / 1024 / 1024 / 1024 as 'Size (GB)' FROM information_schema.tables WHERE table_schema='{}' GROUP BY table_schema".format(db)
            ]
        result = subprocess.check_output(command, stderr=subprocess.STDOUT)
        db_size = float(result.decode("utf-8").strip().split('\n')[1].split('\t')[1])
        return db_size
    except subprocess.CalledProcessError as e:
        logging.error("Failed to get database size from {}: {} - Output: {}".format(
            host, e, e.output.decode()
        ))
        send_error_email()
        return None

def stream_database_to_gcs(dump_command, gcs_path, db):
    start_time = time.time()
    try:
        sanitized_command = sanitize_command(dump_command)
        logging.info("Starting dump process: {}".format(" ".join(sanitized_command)))
        dump_proc = subprocess.Popen(dump_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        logging.info("Starting gzip process")
        gzip_proc = subprocess.Popen(["gzip"], stdin=dump_proc.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        client = storage.Client.from_service_account_json(KEY_FILE)
        bucket = client.bucket(BUCKET)
        blob = bucket.blob(gcs_path)
        logging.info("Starting GCS upload process")
        with io.BytesIO() as memfile:
            for chunk in iter(lambda: gzip_proc.stdout.read(4096), b''):
                memfile.write(chunk)
            memfile.seek(0)
            blob.upload_from_file(memfile, content_type='application/gzip')
        elapsed_time = time.time() - start_time
        logging.info("Dumped and streamed database {} to GCS successfully in {:.2f} seconds.".format(db, elapsed_time))
    except Exception as e:
        logging.error("Unexpected error streaming database {} to GCS: {}".format(db, e))
        send_error_email()

def main():
    current_date = datetime.datetime.now().strftime("%Y-%m-%d")
    sections, config = load_server_list(SERVERS_LIST)
    if not sections:
        logging.error("No servers to process. Exiting.")
        return
    logging.info("================================== {} =============================================".format(current_date))
    logging.info("==== Backup Process Started ====")
    servers = []
    for section in sections:
        try:
            host = config[section]['host']
            ssl = config[section].get('ssl', 'n')
            servers.append((section, host, ssl))
        except KeyError as e:
            logging.error("Missing configuration for server '{}': {}".format(section, e))
            send_error_email()
    for server in servers:
        SERVER, HOST, SSL = server
        use_ssl = SSL.lower() == "y"
        logging.info("DUMPING SERVER: {}".format(SERVER))
        try:
            db_list = get_database_list(HOST, use_ssl, SERVER)
            if not db_list:
                logging.warning("No databases found for server: {}".format(SERVER))
                continue
            for db in db_list:
                logging.info("Backing up database: {}".format(db))
                db_size = get_database_size(HOST, db, use_ssl, SERVER)
                if db_size is None:
                    continue
                logging.info("Database {} size: {:.2f} GB".format(db, db_size))
                if db_size >= 20:
                    logging.info("Database {} is greater than 20GB, performing backup to /backup/".format(db))
                    backup_path = os.path.join("/backup/", "{}_{}.sql.gz".format(current_date, db))
                    dump_command = [
                        "mysqldump", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", HOST, db,
                        "--set-gtid-purged=OFF", "--single-transaction", "--quick",
                        "--triggers", "--events", "--routines"
                    ]
                    if use_ssl:
                        dump_command += [
                            "--ssl-ca={}".format(os.path.join(SSL_PATH, SERVER, "server-ca.pem")),
                            "--ssl-cert={}".format(os.path.join(SSL_PATH, SERVER, "client-cert.pem")),
                            "--ssl-key={}".format(os.path.join(SSL_PATH, SERVER, "client-key.pem")),
                        ]
                    sanitized_command = sanitize_command(dump_command)
                    logging.info("Executing dump command: {}".format(" ".join(sanitized_command)))
                    with open(backup_path, "wb") as backup_file:
                        subprocess.run(dump_command, stdout=backup_file, check=True)
                    logging.info("Moving {} to GCS".format(backup_path))
                    gcs_path = os.path.join(GCS_PATH, SERVER, os.path.basename(backup_path))
                    blob = storage.Client.from_service_account_json(KEY_FILE).bucket(BUCKET).blob(gcs_path)
                    blob.upload_from_filename(backup_path)
                    os.remove(backup_path)
                else:
                    gcs_path = os.path.join(GCS_PATH, SERVER, "{}_{}.sql.gz".format(current_date, db))
                    dump_command = [
                        "mysqldump", "-u{}".format(DB_USR), "-p{}".format(DB_PWD), "-h", HOST, db,
                        "--set-gtid-purged=OFF", "--single-transaction", "--quick",
                        "--triggers", "--events", "--routines"
                    ]
                    if use_ssl:
                        dump_command += [
                            "--ssl-ca={}".format(os.path.join(SSL_PATH, SERVER, "server-ca.pem")),
                            "--ssl-cert={}".format(os.path.join(SSL_PATH, SERVER, "client-cert.pem")),
                            "--ssl-key={}".format(os.path.join(SSL_PATH, SERVER, "client-key.pem")),
                        ]
                    stream_database_to_gcs(dump_command, gcs_path, db)
        except Exception as e:
            logging.error("Error processing server {}: {}".format(SERVER, e))
            send_error_email()
    logging.info("==== Backup Process Completed ====")

if __name__ == "__main__":
    main()
