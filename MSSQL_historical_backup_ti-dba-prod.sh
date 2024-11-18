#!/bin/bash

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>& 1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>& 1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }

# Database Credentials
DB_USER=trtel.backup
DB_PASS='Telus2017#'
DB_MAINTENANCE=ti_db_inventory

# Environment Variables
STORAGE=/root/cloudstorage
BUCKET=ti-dba-prod-sql-01

# Date ranges for backup logs
START_DATE="2024-11-12"
END_DATE="2024-11-17"

# SQL Query to Fetch Server Details, excluding specified projects
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type 
      FROM ti_db_inventory.servers 
      WHERE active=1 
      AND project NOT IN ('ti-verint152prod', 'tine-payroll-prod-01')
      AND type='MSSQL'
      ORDER BY location, type, os"

clear
echo "============================================================================================================"
echo "Checking backups from DATE: $START_DATE to $END_DATE"
echo "============================================================================================================"

# Fetch server details
servers=$(mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE)

# Create the storage directory if it does not exist
mkdir -p $STORAGE

# Mount the Google Cloud bucket using gcsfuse
if ! gcsfuse --key-file=/root/jsonfiles/ti-dba-prod-01.json $BUCKET $STORAGE; then
    echo "Error mounting gcsfuse. Please check if the key file path is correct and the JSON file exists."
    exit 1
fi

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

echo "============================================================================================================"
echo "Starting backup verification from DATE: $START_DATE to $END_DATE"
echo "============================================================================================================"

# Function to fetch backup files and log details into MySQL
fetch_backup_files() {
    local BACKUP_PATH="$1"
    local EXTENSION="$2"
    local FILES=""
    local START_TIMESTAMP=$(date -d "$START_DATE" +"%Y-%m-%d")
    local END_TIMESTAMP=$(date -d "$END_DATE" +"%Y-%m-%d")
    local DATE=""

    DATE="$START_TIMESTAMP"
    while [ "$DATE" != "$END_TIMESTAMP" ]; do
        FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${DATE}*${EXTENSION}" 2>/dev/null)
        DATE=$(date -I -d "$DATE + 1 day")

        for FILE in $FILES; do
            fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
            SIZE=$((SIZE + fsize))

            # Extract database name and filename from the full file path
            FILENAME=$(basename "$FILE")
            if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                DB_NAME="${BASH_REMATCH[1]}"
            fi
                
            # Insert details into the backup log
            SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath, last_update) 
                    VALUES ('$DATE', '$SERVER', $fsize, '$FILE', NOW());"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"

            endcopy=$(date +"%Y-%m-%d %H:%M:%S")
            STATE="Completed"
            if [ "$SIZE" -eq 0 ]; then
                STATE="Error"
            fi

            # Insert each file's detail into the daily log with the backup status
            DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                    VALUES ('$DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
        done
    done
}

# Fetch server details from the database and iterate over each server
echo "$servers" | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE; do
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER from DATE: $START_DATE to $END_DATE"
    echo "============================================================================================================"

    BACKUP_PATH=""
    DATABASE=""
    FILES=""
    SIZE=0

    # Determine the backup path and file extension for MSSQL
    BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
    EXTENSION=".bak"
    
    fetch_backup_files "$BACKUP_PATH" "$EXTENSION"
done

# Unmount the cloud storage
if ! fusermount -u $STORAGE; then
    echo "Error unmounting /root/cloudstorage"
    exit 1
fi

echo "Script completed successfully."
