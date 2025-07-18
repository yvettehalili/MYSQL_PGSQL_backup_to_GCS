##############################################
# Develop by: Database Engineering Team      #
# ############################################

#!/bin/bash

# Script to check backup logs for tine-payroll-prod-01 for the current day
# This script mounts a Google Cloud Storage bucket, checks for MSSQL backup files, and logs backup information into a MySQL database.

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>&1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>&1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }
command -v mysql >/dev/null 2>&1 || { echo >&2 "mysql command not found. Please install mysql client."; exit 1; }
command -v gsutil >/dev/null 2>&1 || { echo >&2 "gsutil command not found. Please install gsutil."; exit 1; }

# Database Credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="ti_db_inventory"

# Environment Variables
STORAGE="/root/cloudstorage"
BUCKET="ti-dba-prod-sql-03-eu"
KEY_FILE="/root/jsonfiles/ti-dba-prod-01.json"

# Current Date
CURRENT_DATE=$(date +"%Y-%m-%d")
TEST_DATE2=$(date -d "$CURRENT_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$CURRENT_DATE" +"%d-%m-%Y")

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type 
       FROM ti_db_inventory.servers 
       WHERE active = 1 
         AND project = 'tine-payroll-prod-01' 
       ORDER BY location, type, os;"

clear

# Create the storage directory if it does not exist
mkdir -p "$STORAGE"

# Function to read and prevent collapsing of empty fields
read_fields() {
    local input
    IFS= read -r input || return $?
    while (( $# > 1 )); do
        IFS= read -r "$1" <<< "${input%%[$IFS]*}"
        input="${input#*[$IFS]}"
        shift
    done
    IFS= read -r "$1" <<< "$input"
}

# Mount storage
echo "Mounting bucket"
gcsfuse --key-file="$KEY_FILE" "$BUCKET" "$STORAGE" || { echo "Error mounting gcsfuse"; exit 1; }

echo "============================================================================================================"
echo "START DATE: $CURRENT_DATE .................................................................................."
echo "============================================================================================================"

# Fetch and iterate over server details from the database
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS FREQUENCY SAVE_PATH LOCATION TYPE
do
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $FREQUENCY - $SAVE_PATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $CURRENT_DATE"

    SERVER_BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
    echo "Backup path being checked: gs://$BUCKET/$SERVER_BACKUP_PATH"

    SIZE=0
    FILENAMES=()
    STATE="Completed"
    BACKUP_FOUND=false

    # List all database directories under the server
    DB_FOLDERS=$(gsutil ls "gs://$BUCKET/$SERVER_BACKUP_PATH" | grep '/$')

    if [[ -z "$DB_FOLDERS" ]]; then
        echo "No database folders found under gs://$BUCKET/$SERVER_BACKUP_PATH"
        continue
    fi

    for DB_FOLDER in $DB_FOLDERS; do
        DB_NAME=$(basename "$DB_FOLDER")

        for DATE in "$CURRENT_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
            for TYPE in "FULL" "DIFF"; do
                DB_PATH="${DB_FOLDER}${TYPE}/"
                echo "Checking ${TYPE} directory: ${DB_PATH}"

                # Aggregate file lists from FULL and DIFF directories
                FILES=$(gsutil ls "${DB_PATH}*${DATE}*.bak" 2>/dev/null)

                if [[ -n "$FILES" ]]; then
                    echo "Found backup files in ${TYPE} directory: $FILES"
                    BACKUP_FOUND=true

                    for FILE in $FILES; do
                        fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                        SIZE=$((SIZE + fsize))

                        # Extract filename from the full file path
                        FILENAME=$(basename "$FILE")
                        FILENAMES+=("$FILENAME")

                        echo "Backup details - Server: $SERVER, Database: $DB_NAME, Filename: $FILENAME, Filesize: $fsize, Path: $FILE"

                        # Insert details into the backup log
                        SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath, last_update) 
                                VALUES ('$CURRENT_DATE','$SERVER',$fsize,'$FILE', NOW())
                                ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize;"
                        mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"

                        endcopy=$(date +"%Y-%m-%d %H:%M:%S")
                        STATE="Completed"
                        if [[ "$SIZE" -eq 0 ]]; then
                            STATE="Error"
                        fi

                        # Insert each file's detail into the daily log with the backup status
                        DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                                VALUES ('$CURRENT_DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
                        mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
                    done
                else
                    echo "No backup files found for date: $DATE in ${DB_PATH}"
                fi
            done
        done
    done

    if [ "$BACKUP_FOUND" = false ]; then
        echo "No backup files found for SERVER: $SERVER on DATE: $CURRENT_DATE"
    fi
done

echo "Unmounting storage"
fusermount -u "$STORAGE" || { echo "Error unmounting $STORAGE"; exit 1; }

echo "Script completed successfully."
