import os
import subprocess
import datetime
import configparser
import io
import time
import logging
from google.cloud import storage

# Constants and paths
BUCKET = "ti-dba-prod-sql-01"
GCS_PATH = "Backups/Current/POSTGRESQL"
SSL_PATH = "/ssl-certs/"
KEY_FILE = "/root/jsonfiles/ti-dba-prod-01.json"
EMAIL_SCRIPT_PATH = "/backup/scripts/POSTGRESQL_backup_error_notif.py"

# Define the path for the database credentials and load them
CREDENTIALS_PATH = "/backup/configs/db_credentials.conf"
config = configparser.ConfigParser()
config.read(CREDENTIALS_PATH)
DB_USR = config['credentials']['DB_USR']
DB_PWD = config['credentials']['DB_PWD']

# Set environment variable for PostgreSQL password
os.environ["PGPASSWORD"] = DB_PWD

# Logging Configuration
log_path = "/backup/logs/"
os.makedirs(log_path, exist_ok=True)
current_date = datetime.datetime.now().strftime("%Y-%m-%d")
log_filename = os.path.join(log_path, "PGSQL_backup_activity_{}.log".format(current_date))
logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')

# Specific database roles
DB_ROLES = {
    "db_datti": "GenBackupUser",
    "db_gtt_historic_data": "GenBackupUser"
}

def sanitize_command(command):
    """Sanitize the command by replacing sensitive information."""
    sanitized_command = [
        arg.replace(DB_USR, "*****").replace(DB_PWD, "*****") if isinstance(arg, str) else arg
        for arg in command
    ]
    return sanitized_command

def send_error_email():
    subject = "[ERROR] PostgreSQL Backup Error"
    error_lines = []

    # Read the log file and capture lines containing "ERROR"
    with open(log_filename) as log_file:
        for line in log_file:
            if "ERROR" in line:
                error_lines.append(line.strip())

    # Join the error lines into a single string with HTML line breaks
    body = '<br>'.join(error_lines)

    command = [
        "python3", EMAIL_SCRIPT_PATH, subject, body
    ]
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to send error email: {}".format(e))

def log_to_file(message):
    """Write messages to the log file with a timestamp."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_filename, "a") as log_file:
        log_file.write("{}: {}\n".format(timestamp, message))

def run_command(command, env=None):
    """Run a command and return its success."""
    try:
        subprocess.check_call(command, shell=True, env=env or os.environ)
        return True
    except subprocess.CalledProcessError as e:
        log_to_file("Command failed: {}\nError message: {}".format(command, e))
        send_error_email()
        return False

def run_command_capture(command, env=None):
    """Run a command and capture its output and error messages."""
    try:
        output = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT, env=env or os.environ)
        return True, output.decode()
    except subprocess.CalledProcessError as e:
        return False, e.output.decode()

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
        with io.BytesIO() as memfile:
            while True:
                chunk = dump_proc.stdout.read(4096)
                if not chunk:
                    break
                memfile.write(chunk)

            memfile.seek(0)
            blob.upload_from_file(memfile, content_type='application/octet-stream')

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
    # Initialize the configuration parser and load the server configurations
    server_config = configparser.ConfigParser()
    server_config.read('/backup/configs/PGSQL_servers_list.conf')

    logging.info("================================== {} =============================================".format(current_date))
    logging.info("==== Backup Process Started ====")

    # Read server configurations into a list of tuples
    servers = []
    for section in server_config.sections():
        SERVER = section
        HOST = server_config.get(section, 'host')
        SSL = server_config.get(section, 'ssl')
        servers.append((SERVER, HOST, SSL))

    for server in servers:
        SERVER, HOST, SSL = server
        DB_HOST = HOST

        log_to_file("DUMPING SERVER: {}".format(SERVER))

        if SSL == 'n':
            dbs_command = f"""psql -h {DB_HOST} -U {DB_USR} -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" """
        else:
            dbs_command = (
                "psql \"sslmode=verify-ca sslrootcert={}{}{} sslcert={}{}{} sslkey={}{}{} hostaddr={} user={} dbname=postgres\" "
                "-t -c 'SELECT datname FROM pg_database WHERE datistemplate = false;'"
            ).format(SSL_PATH, SERVER, "/server-ca.pem", SSL_PATH, SERVER, "/client-cert.pem",
                    SSL_PATH, SERVER, "/client-key.pem", DB_HOST, DB_USR)

        try:
            log_to_file("Running database listing command: {}".format(dbs_command))
            dbs_output = subprocess.check_output(dbs_command, shell=True, env=os.environ, stderr=subprocess.STDOUT).decode().splitlines()
            dbs_output = [db.strip() for db in dbs_output if db.strip()]
            log_to_file("Successfully fetched databases from server {}: {}".format(SERVER, dbs_output))

        except subprocess.CalledProcessError as e:
            error_output = e.output.decode()  # Capture and decode the error output
            log_to_file("Error fetching databases from server {}: {}\n{}".format(SERVER, e, error_output))
            send_error_email()
            continue

        for DB in dbs_output:
            if DB not in ["template0", "template1", "restore", "postgres", "cloudsqladmin"]:
                log_to_file("Dumping DB {}".format(DB))

                # Determine the role for the specific database
                role = DB_ROLES.get(DB, "postgres")

                # Construct the pg_dump command based on SSL status
                if SSL == 'y':
                    pg_dump_command = [
                        "pg_dump",
                        "sslmode=verify-ca user={} hostaddr={} sslrootcert={} sslcert={} sslkey={} dbname={}".format(
                            DB_USR,
                            DB_HOST,
                            os.path.join(SSL_PATH, SERVER, "server-ca.pem"),
                            os.path.join(SSL_PATH, SERVER, "client-cert.pem"),
                            os.path.join(SSL_PATH, SERVER, "client-key.pem"),
                            DB
                        ),
                        "--role=postgres",
                        "--no-owner",
                        "--no-acl",
                        "-Fc"
                    ]
                else:
                    pg_dump_command = [
                        "pg_dump",
                        "postgresql://{}@{}:5432/{}".format(DB_USR, DB_HOST, DB),
                        "--role=postgres",
                        "--no-owner",
                        "--no-acl",
                        "-Fc"
                    ]

                gcs_path = "{}/{}/{}_{}.dump".format(GCS_PATH, SERVER, current_date, DB)
                if stream_database_to_gcs(pg_dump_command, gcs_path, DB):
                    log_to_file("Successfully backed up and streamed {} from server {} to GCS".format(DB, SERVER))
                else:
                    log_to_file("Failed to backup and stream {} from server {}".format(DB, SERVER))
                    send_error_email()
                    
    logging.info("==== Backup Process Completed ====")
    logging.info("============================================================================================")

if __name__ == "__main__":
    main()
