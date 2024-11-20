#!/bin/bash

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>& 1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>& 1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }
command -v gsutil >/dev/null 2>& 1 || { echo >&2 "gsutil command not found. Please install gsutil."; exit 1; }

# Environment Variables
STORAGE="/root/cloudstorage"
BUCKET="ti-dba-prod-sql-01"
KEY_FILE="/root/jsonfiles/ti-dba-prod-01.json"

# Current Date
TEST_DATE=$(date +"%Y-%m-%d")
TEST_DATE2=$(date -d "$TEST_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$TEST_DATE" +"%d-%m-%Y")

# Specific Server Details
SERVER="SDEFRYAK01"
SERVERIP="10.87.9.13"
OS="WINDOWS"
TYPE="GCP MSSQL"
SAVE_PATH="/Backups/Current/MSSQL/"
LOCATION=""

clear

# Create the storage directory if it does not exist
mkdir -p "$STORAGE"

# Mount storage
echo "Mounting bucket"
gcsfuse --key-file="$KEY_FILE" "$BUCKET" "$STORAGE" || { echo "Error mounting gcsfuse"; exit 1; }

echo "============================================================================================================"
echo "START DATE: $TEST_DATE ....................................................................................."
echo "============================================================================================================"

echo "============================================================================================================"
echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
echo "============================================================================================================"
echo "Checking backups for SERVER: $SERVER on DATE: $TEST_DATE"

SERVER_BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
echo "Backup path being checked: gs://$BUCKET/$SERVER_BACKUP_PATH"

SIZE=0
FILENAMES=()
STATE="Completed"

# List all database directories under the server
echo "Listing all subdirectories (databases) under gs://$BUCKET/$SERVER_BACKUP_PATH"
DB_FOLDERS=$(gsutil ls "gs://$BUCKET/$SERVER_BACKUP_PATH" 2>&1)

if echo "$DB_FOLDERS" | grep -q 'CommandException'; then
    echo "$DB_FOLDERS"
    echo "No database folders found under gs://$BUCKET/$SERVER_BACKUP_PATH"
else
    DB_FOLDERS=$(echo "$DB_FOLDERS" | grep '/$')

    if [[ -z "$DB_FOLDERS" ]]; then
        echo "No database folders found under gs://$BUCKET/$SERVER_BACKUP_PATH"
    else
        for DB_FOLDER in $DB_FOLDERS; do
            DB_NAME=$(basename "$DB_FOLDER")
            DB_FULL_PATH="gs://${BUCKET}/${SERVER_BACKUP_PATH}${DB_NAME}/FULL"

            for DATE in "$TEST_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
                echo "Checking FULL directory: ${DB_FULL_PATH}"

                # Aggregate file lists from FULL directory
                FULL_FILES=$(gsutil ls "${DB_FULL_PATH}/*${DATE}*.bak" 2>/dev/null)

                if [[ -n "$FULL_FILES" ]]; then
                    echo "Found backup files: $FULL_FILES"

                    for FILE in $FULL_FILES; do
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
                    echo "No backup files found for date: $DATE in ${DB_FULL_PATH}"
                    STATE="Error"
                fi
            done
        done
    fi
fi

echo "Unmounting storage"
fusermount -u "$STORAGE" || { echo "Error unmounting $STORAGE"; exit 1; }

echo "Script completed successfully."
