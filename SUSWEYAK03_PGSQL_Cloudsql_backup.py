import os
import subprocess
import datetime
import configparser
import time
import logging
from google.cloud import storage

# Constants and paths
BUCKET = "ti-sql-02"
GCS_PATH = "Backups/Current"
SSL_PATH = "/ssl-certs/"
KEY_FILE = "/root/jsonfiles/ti-dba-prod-01.json"
EMAIL_SCRIPT_PATH = "/backup/scripts/POSTGRESQL_backup_error_notif.py"
CREDENTIALS_PATH = "/backup/configs/db_credentials.conf"
LOG_PATH = "/backup/logs/"
DB_ROLES = {
    "db_datti": "GenBackupUser",
    "db_gtt_historic_data": "GenBackupUser"
}

# Configure logging
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(LOG_PATH, "PGSQL_backup_activity_{}.log".format(current_date))
os.makedirs(LOG_PATH, exist_ok=True)
logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')

# Read database credentials
config = configparser.ConfigParser()
config.read(CREDENTIALS_PATH)
DB_USR = config['credentials']['DB_USR']
DB_PWD = config['credentials']['DB_PWD']

# Set environment variable for PostgreSQL password
os.environ["PGPASSWORD"] = DB_PWD

def sanitize_command(command):
    """Sanitize the command by replacing sensitive information."""
    return [arg.replace(DB_USR, "*****").replace(DB_PWD, "*****") if isinstance(arg, str) else arg for arg in command]

def send_error_email():
    subject = "[ERROR] PostgreSQL Backup Error"
    error_lines = []

    with open(log_filename) as log_file:
        for line in log_file:
            if "ERROR" in line:
                error_lines.append(line.strip())

    body = '<br>'.join(error_lines)
    command = ["python3", EMAIL_SCRIPT_PATH, subject, body]

    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to send error email: {}".format(e))

def log_to_file(message):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_filename, "a") as log_file:
        log_file.write("{}: {}\n".format(timestamp, message))

def run_command(command, env=None):
    try:
        subprocess.check_call(command, shell=True, env=env or os.environ)
        return True
    except subprocess.CalledProcessError as e:
        log_to_file("Command failed: {}\nError message: {}".format(sanitize_command(command), e))
        send_error_email()
        return False

def stream_database_to_gcs(dump_command, gcs_path, db):
    start_time = time.time()

    try:
        sanitized_command = sanitize_command(dump_command)
        logging.info("Starting dump process: {}".format(" ".join(sanitized_command)))

        # Start the dump process
        dump_proc = subprocess.Popen(dump_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Initialize Google Cloud Storage client
        client = storage.Client.from_service_account_json(KEY_FILE)
        bucket = client.bucket(BUCKET)
        blob = bucket.blob(gcs_path)

        logging.info("Starting GCS upload process")

        with blob.open("wb") as f:
            while True:
                chunk = dump_proc.stdout.read(4096)
                if not chunk:
                    break
                f.write(chunk)

        stderr_output = dump_proc.stderr.read().decode('utf-8')
        dump_proc.wait()
        elapsed_time = time.time() - start_time

        if dump_proc.returncode != 0:
            logging.error("Command failed with return code {}: {}".format(dump_proc.returncode, stderr_output))
            log_to_file("Error details: {}".format(stderr_output))
            send_error_email()
            return False

        logging.info("Dumped and streamed database {} to GCS successfully in {:.2f} seconds.".format(db, elapsed_time))
        return True

    except Exception as e:
        logging.error("Unexpected error streaming database {} to GCS: {}".format(db, e))
        send_error_email()
        return False

def main():
    server_config = configparser.ConfigParser()
    server_config.read('/backup/configs/PGSQL_servers_list.conf')

    logging.info("================================== {} =============================================".format(current_date))
    logging.info("==== Backup Process Started ====")

    servers = [(section, server_config.get(section, 'host'), server_config.get(section, 'ssl')) for section in server_config.sections()]

    for SERVER, HOST, SSL in servers:
        DB_HOST = HOST
        log_to_file("DUMPING SERVER: {}".format(SERVER))

        if SSL == 'n':
            dbs_command = "psql -h {host} -U {user} -d postgres -t -c 'SELECT datname FROM pg_database WHERE datistemplate = false;'".format(host=DB_HOST, user=DB_USR)
        else:
            dbs_command = (
                "psql \"sslmode=verify-ca sslrootcert={ssl}{server}/server-ca.pem sslcert={ssl}{server}/client-cert.pem "
                "sslkey={ssl}{server}/client-key.pem hostaddr={host} user={user} dbname=postgres\" "
                "-t -c 'SELECT datname FROM pg_database WHERE datistemplate = false;'"
            ).format(ssl=SSL_PATH, server=SERVER, host=DB_HOST, user=DB_USR)

        try:
            log_to_file("Running database listing command: {}".format(dbs_command))
            dbs_output = subprocess.check_output(dbs_command, shell=True, env=os.environ, stderr=subprocess.STDOUT).decode().splitlines()
            dbs_output = [db.strip() for db in dbs_output if db.strip()]
            log_to_file("Successfully fetched databases from server {}: {}".format(SERVER, dbs_output))

        except subprocess.CalledProcessError as e:
            error_output = e.output.decode()
            log_to_file("Error fetching databases from server {}: {}\n{}".format(SERVER, e, error_output))
            send_error_email()
            continue

        for DB in dbs_output:
            if DB not in ["template0", "template1", "restore", "postgres", "cloudsqladmin"]:
                log_to_file("Dumping DB {}".format(DB))

                role = DB_ROLES.get(DB, "postgres")

                if SSL == 'y':
                    pg_dump_command = [
                        "pg_dump",
                        "sslmode=verify-ca user={user} hostaddr={host} sslrootcert={sslrt} sslcert={sslc} sslkey={sslk} dbname={db}".format(
                            user=DB_USR,
                            host=DB_HOST,
                            sslrt=os.path.join(SSL_PATH, SERVER, 'server-ca.pem'),
                            sslc=os.path.join(SSL_PATH, SERVER, 'client-cert.pem'),
                            sslk=os.path.join(SSL_PATH, SERVER, 'client-key.pem'),
                            db=DB
                        ),
                        "--role=postgres",
                        "--no-owner",
                        "--no-acl",
                        "-Fc"
                    ]
                else:
                    pg_dump_command = [
                        "pg_dump",
                        "postgresql://{user}@{host}:5432/{db}".format(user=DB_USR, host=DB_HOST, db=DB),
                        "--role=postgres",
                        "--no-owner",
                        "--no-acl",
                        "-Fc"
                    ]

                gcs_path = "{gcs}/{server}/{date}_{db}.dump".format(gcs=GCS_PATH, server=SERVER, date=current_date, db=DB)
                if stream_database_to_gcs(pg_dump_command, gcs_path, DB):
                    log_to_file("Successfully backed up and streamed {} from server {} to GCS".format(DB, SERVER))
                else:
                    log_to_file("Failed to backup and stream {} from server {}".format(DB, SERVER))
                    send_error_email()

    logging.info("==== Backup Process Completed ====")
    logging.info("============================================================================================")

if __name__ == "__main__":
    main()
