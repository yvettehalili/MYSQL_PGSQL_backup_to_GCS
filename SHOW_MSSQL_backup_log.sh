#!/bin/bash

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>& 1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>& 1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }
command -v mysql >/dev/null 2>& 1 || { echo >&2 "mysql command not found. Please install mysql client."; exit 1; }
command -v gsutil >/dev/null 2>& 1 || { echo >&2 "gsutil command not found. Please install gsutil."; exit 1; }

# Database Credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MNT="ti_db_inventory"

# Environment Variables
STORAGE="/root/cloudstorage"
BUCKET="ti-dba-prod-sql-01"
KEY_FILE="/root/jsonfiles/ti-dba-prod-01.json"

# Current Date
TEST_DATE=$(date +"%Y-%m-%d")
TEST_DATE2=$(date -d "$TEST_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$TEST_DATE" +"%d-%m-%Y")

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type 
       FROM $DB_MNT.servers 
       WHERE active = 1 
         AND type = 'MSSQL' 
         AND project NOT IN ('tine-payroll-prod-01', 'ti-verint152prod') 
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
echo "START DATE: $TEST_DATE ....................................................................................."
echo "============================================================================================================"

# Fetch and iterate over server details from the database
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MNT | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE
do
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $TEST_DATE"

    BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
    echo "Backup path being checked: gs://$BUCKET/$BACKUP_PATH"

    SIZE=0
    FILENAMES=()
    STATE="Completed"

    echo "Listing all subdirectories (databases) under gs://$BUCKET/$BACKUP_PATH"
    DB_FOLDERS=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH/" 2>/dev/null | grep '/$')
    
    if [[ -z "$DB_FOLDERS" ]]; then
        echo "No database folders found under gs://$BUCKET/$BACKUP_PATH"
        continue
    fi
    
    for DB_FOLDER in $DB_FOLDERS; do
        DB_NAME=$(basename "$DB_FOLDER")
        DB_FULL_PATH="gs://$BUCKET/$DB_FOLDER/FULL/"
        DB_DIFF_PATH="gs://$BUCKET/$DB_FOLDER/DIFF/"
        echo "Checking FULL directory: ${DB_FULL_PATH}"
        echo "Checking DIFF directory: ${DB_DIFF_PATH}"

        for DATE in "$TEST_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
            # Aggregate file lists from FULL and DIFF directories
            FULL_FILES=$(gsutil ls "${DB_FULL_PATH}*${DATE}*.bak" 2>/dev/null)
            DIFF_FILES=$(gsutil ls "${DB_DIFF_PATH}*${DATE}*.bak" 2>/dev/null)

            if [[ -n "$FULL_FILES" || -n "$DIFF_FILES" ]]; then
                FILES="$FULL_FILES $DIFF_FILES"
                echo "Found backup files: $FILES"

                for FILE in $FILES; do
                    fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                    SIZE=$((SIZE + fsize))

                    # Extract filename from the full file path
                    FILENAME=$(basename "$FILE")
                    FILENAMES+=("$FILENAME")

                    echo "Backup details - Server: $SERVER, Database: $DB_NAME, Filename: $FILENAME, Filesize: $fsize, Path: $FILE"
                done
                STATE="Completed"
                break
            else
                echo "No backup files found for date: $DATE in ${DB_FULL_PATH} and ${DB_DIFF_PATH}"
                STATE="Error"
            fi
        done
    done
done

echo "Unmounting storage"
fusermount -u "$STORAGE" || { echo "Error unmounting $STORAGE"; exit 1; }

echo "Script completed successfully."
