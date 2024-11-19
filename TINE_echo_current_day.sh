#!/bin/bash

# Script to check backup logs for tine-payroll-prod-01 for the current day

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>&1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>&1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }

# Database Credentials
DB_USER=trtel.backup
DB_PASS='Telus2017#'
DB_MAINTENANCE=ti_db_inventory

# Environment Variables
STORAGE=/root/cloudstorage
BUCKET=tine-payroll-eu-prod-01-db-backups

# Get the current date
CURRENT_DATE=$(date +"%Y-%m-%d")
TEST_DATE2=$(date -d "$CURRENT_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$CURRENT_DATE" +"%d-%m-%Y")

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type FROM ti_db_inventory.servers WHERE active = 1 AND project = 'tine-payroll-prod-01' ORDER BY location, type, os;"

clear

# Create the storage directory if it does not exist
mkdir -p $STORAGE

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

# Mount storage for tine-payroll-prod-01
echo "Mounting bucket for project tine-payroll-prod-01"
gcsfuse --key-file=/root/jsonfiles/tine-payroll-prod-01.json $BUCKET $STORAGE || { echo "Error mounting gcsfuse for tine-payroll-prod-01"; exit 1; }

echo "============================================================================================================"
echo "START DATE: $CURRENT_DATE .................................................................................."
echo "============================================================================================================"

# Fetch and iterate over server details from the database
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE_EXTRA
do
    # Extract the actual TYPE from the TYPE_EXTRA (assume TYPE_EXTRA is the last field)
    TYPE=$(echo "$TYPE_EXTRA" | awk '{print $NF}')

    echo "============================================================================================================"

    if [[ "$OS" == "Windows" ]]; then
        DB_FULL_PATH="${SAVE_PATH}/FULL/"
        DB_DIFF_PATH="${SAVE_PATH}/DIFF/"
        SIZE=0
        FILENAMES=()
        
        # Aggregate file lists from FULL and DIFF directories
        FILES=$(gsutil ls "${DB_FULL_PATH}*${TEST_DATE2}*.bak" 2>/dev/null)
        FILES+=$(gsutil ls "${DB_DIFF_PATH}*${TEST_DATE2}*.bak" 2>/dev/null)

        if [[ -n "$FILES" ]]; then
            echo "Found backup files: $FILES"

            for FILE in $FILES; do
                fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                SIZE=$((SIZE + fsize))
                FILENAME=$(basename "$FILE")
                FILENAMES+=("$FILENAME")

                if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                    DB_NAME="${BASH_REMATCH[1]}"
                fi

                echo "Backup details - Server: $SERVER, Database: $DB_NAME, Filename: $FILENAME, Filesize: $fsize, Path: $FILE"
            done
        else
            echo "No backup files found for date: $CURRENT_DATE in ${DB_FULL_PATH} and ${DB_DIFF_PATH}"
        fi
    else
        echo "Skipping non-MSSQL server: $SERVER"
    fi
done

echo "Unmounting storage for tine-payroll-prod-01"
fusermount -u $STORAGE || { echo "Error unmounting $STORAGE"; exit 1; }

echo "tine-payroll-prod-01 script completed successfully."
