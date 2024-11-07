#!/bin/bash

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>&1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>&1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }

# Database Credentials
DB_USER=trtel.backup
DB_PASS='Telus2017#'
DB_MAINTENANCE=ti_db_inventory

# Environment Variables
STORAGE=/root/cloudstorage

# Fixed Date Variables for Testing (simulating "2024-10-25")
TEST_DATE="2024-10-25"
TEST_DATE2=$(date -d "$TEST_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$TEST_DATE" +"%d-%m-%Y")

# Execute Setup Query
mysql -u"$DB_USER" -p"$DB_PASS" -e "$setup_query"

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type, bucket FROM ti_db_inventory.servers WHERE active=1 ORDER BY location, type, os"

clear

echo "============================================================================================================"
echo "START DATE: $TEST_DATE ....................................................................................."
echo "============================================================================================================"

# Create the storage directory if it does not exist
mkdir -p $STORAGE

# Function to Prevent Collapsing of Empty Fields
myread() {
    local input
    IFS= read -r input || return $?
    while (( $# > 1 )); do
        IFS= read -r "$1" <<< "${input%%[$IFS false
IFS=$'\n'

# Fetch server details from the database and iterate over each server
servers=$(mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE)
IFS=$'\n'
for line in $servers; do
    read -a server_details <<< "$line"
    SERVER="${server_details[0]}"
    SERVERIP="${server_details[1]}"
    WUSER="${server_details[2]}"
    WUSERP="${server_details[3]}"
    OS="${server_details[4]}"
    FREQUENCY="${server_details[5]}"
    - PATH: Path to the backups directory

    Returns:
        None
    """
    SIZE = 0

    # Check for files with TEST_DATE variants
    for DATE in [TEST_DATE, TEST_DATE2, TEST_DATE3]:
        FILES = run_ls(f"gs://{BUCKET}/{SAVE_PATH}*/DIFF/*{DATE}*.bak")
        FILES += run_ls(f"gs://{BUCKET}/{SAVE_PATH}*/FULL/*{DATE}*.bak")

        if FILES:
            break

    FILENAMES = []

    for FILE in FILES:
        fsize = run_du(FILE)
        SIZE += fsize

        # Extract database name and filename from the full file path
        FILENAME = os.path.basename(FILE)
        FILENAMES.append(FILENAME)

        if re.match(rf"^{SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$", FILENAME):
            DB_NAME = re.match(rf"^{SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$", FILENAME).group(1)

        # Insert details into the backup log
        SQUERY = f"""
            INSERT INTO backup_log (backup_date, server, size, filepath, last_update)
            VALUES ('{TEST_DATE}','{SERVER}',{fsize},'{FILE}', NOW())
            ON DUPLICATE KEY UPDATE last_update=NOW(), size={fsize};
        """
        run_mysql(SQUERY)

        endcopy = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        STATE = "Completed"
        if SIZE == 0:
            STATE = "Error"

        # Insert each file's detail into the daily log with the backup status
        DQUERY = f"""
            INSERT INTO daily_log (backup_date, server, `database`, size, state, last_update, fileName)
            VALUES ('{TEST_DATE}', '{SERVER}', '{DB_NAME}', {fsize}, '{STATE}', '{endcopy}', '{FILENAME}');
        """
        run_mysql(DQUERY)


def main():
    """
    Main function to orchestrate the tasks for checking backups and logging to the database.
    """
    # Create the storage directory if it does not exist
    os.makedirs(STORAGE, exist_ok=True)

    # Initialize the SQL query for server details
    query = "SELECT name, ip, user, pwd, os, frequency, save_path, location, type, bucket FROM ti_db_inventory.servers WHERE active=1 ORDER BY location, type, os"

    # Fetch server details from the MySQL database
    for SERVER, SERVERIP, WUSER, WUSERP, OS, FREQUENCY, SAVE_PATH, LOCATION, TYPE, BUCKET in run_mysql(query):
        print("=" * 100)
        print(f"SERVER: {SERVER} - {SERVERIP} - {OS} - {TYPE} - {SAVE_PATH} - {LOCATION} - {BUCKET}")
        print("=" * 100)
        print(f"Checking backups for SERVER: {SERVER} on DATE: {TEST_DATE}")

        BACKUP_PATH = SAVE_PATH

        if TYPE == "MSSQL":
            # Ensure the storage directory is clean and ready for mount
            if os.path.ismount(STORAGE):
                subprocess.run(["fusermount", "-u", STORAGE], check=True)

            # Mount the Google Cloud bucket using gcsfuse
            print(f"Mounting bucket {BUCKET}")
            if not gcsfuse_mounted(BUCKET):
                gcsfuse_mount(BUCKET, STORAGE)

            process_mssql_backups(BUCKET, BACKUP_PATH, SERVER)

            # Unmount the bucket storage after checking MSSQL backups
            if os.path.ismount(STORAGE):
                subprocess.run(["fusermount", "-u", STORAGE], check=True)
                print(f"Successfully unmounted {STORAGE}")

        elif TYPE in ["MYSQL", "PGSQL"]:
            EXTENSION = "*.sql.gz" if TYPE == "MYSQL" else "*.dump"
            SIZE = 0
            FILENAMES = []

            for DATE in [TEST_DATE, TEST_DATE2, TEST_DATE3]:
                FILES = run_ls(f"gs://{BUCKET}/{BACKUP_PATH}*{DATE}*.{EXTENSION.split('.')[1]}")

                if FILES:
                    break

            for FILE in FILES:
                fsize = run_du(FILE)
                SIZE += fsize

                # Extract database name and filename from the full file path
                FILENAME = os.path.basename(FILE)
                FILENAMES.append(FILENAME)
                db_match = re.match(rf"^({TEST_DATE}|{TEST_DATE2}|{TEST_DATE3})_(.*)\.{EXTENSION.split('.')[1]}$", FILENAME)
                if db_match:
                    DATABASE = db_match.group(2)

                # Insert details into the backup log
                SQUERY = f"""
                    INSERT INTO backup_log (backup_date, server, size, filepath, last_update)
                    VALUES ('{TEST_DATE}','{SERVER}',{fsize},'{FILE}', NOW())
                    ON DUPLICATE KEY UPDATE last_update=NOW(), size={fsize};
                """
                run_mysql(SQUERY)

                endcopy = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                STATE = "Completed"
                if SIZE == 0:
                    STATE = "Error"

                # Insert each file's detail into the daily log with the backup status
                DQUERY = f"""
                    INSERT INTO daily_log (backup_date, server, `database`, size, state, last_update, fileName)
                    VALUES ('{TEST_DATE}', '{SERVER}', '{DATABASE}', {fsize}, '{STATE}', '{endcopy}', '{FILENAME}');
                """
                run_mysql(DQUERY)

    # Unmount the cloud storage if it remains mounted
    if os.path.ismount(STORAGE):
        if not subprocess.run(["fusermount", "-u", STORAGE], check=True):
            print("Error unmounting /root/cloudstorage")
            exit(1)
        else:
            print("Successfully unmounted /root/cloudstorage")

    print("done")


if __name__ == "__main__":
    main()
