#!/bin/bash

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>& 1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>& 1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }
command -v gsutil >/dev/null 2>& 1 || { echo >&2 "gsutil command not found. Please install gsutil."; exit 1; }

# Database Credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="ti_db_inventory"

# Environment Variables
STORAGE="/root/cloudstorage"
BUCKET="ti-dba-prod-sql-01"
KEY_FILE="/root/jsonfiles/ti-dba-prod-01.json"

# Specific Server Details
SERVER="sdefryak01"
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
echo "CHECKING ALL AVAILABLE BACKUPS ............................................................................"
echo "============================================================================================================"

echo "============================================================================================================"
echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
echo "============================================================================================================"

SERVER_BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
echo "Backup path being checked: gs://$BUCKET/$SERVER_BACKUP_PATH"

SIZE=0
FILENAMES=()
STATE="Completed"

# Fetch the current date
CURRENT_DATE=$(date +"%Y-%m-%d")

# List all database directories under the server
echo "Listing all subdirectories (databases) under gs://$BUCKET/$SERVER_BACKUP_PATH"
DB_FOLDERS=$(gsutil ls "gs://$BUCKET/$SERVER_BACKUP_PATH" 2>&1)
echo "gsutil ls output: $DB_FOLDERS"

if echo "$DB_FOLDERS" | grep -q 'CommandException'; then
    echo "$DB_FOLDERS"
    echo "No database folders found under gs://$BUCKET/$SERVER_BACKUP_PATH"
else
    DB_FOLDERS=$(echo "$DB_FOLDERS" | grep '/$')
    echo "Database folders found: $DB_FOLDERS"

    if [[ -z "$DB_FOLDERS" ]]; then
        echo "No database folders found under gs://$BUCKET/$SERVER_BACKUP_PATH"
    else    
        for DB_FOLDER in $DB_FOLDERS; do
            DB_NAME=$(basename "$DB_FOLDER")
            DB_FULL_PATH="gs://${BUCKET}/${SERVER_BACKUP_PATH}${DB_NAME}/FULL/"

            echo "Checking FULL directory: ${DB_FULL_PATH}"

            # Aggregate file lists from FULL directory
            FULL_FILES=$(gsutil ls "${DB_FULL_PATH}*.bak" 2>/dev/null)
            echo "FULL_FILES output: $FULL_FILES"

            if [[ -n "$FULL_FILES" ]]; then
                echo "Found backup files: $FULL_FILES"

                for FILE in $FULL_FILES; do
                    fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                    SIZE=$((SIZE + fsize))

                    # Extract filename from the full file path
                    FILENAME=$(basename "$FILE")
                    FILENAMES+=("$FILENAME")

                    # Extract database name from filename
                    if [[ "$FILENAME" =~ ^sinch-db-cluster\.ti\.ads\$SinchAG.*_(.*)_FULL_.*\.bak$ ]]; then
                        DB_NAME="${BASH_REMATCH[1]}"
                    fi

                    echo "Backup details - Server: $SERVER, Database: $DB_NAME, Filename: $FILENAME, Filesize: $fsize, Path: $FILE"

                    # Insert details into the backup log
                    SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath, last_update) 
                            VALUES ('$CURRENT_DATE','$SERVER',$fsize,'$FILE', NOW())
                            ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize;"
                    echo "Inserting into backup_log: \"$SQUERY\""
                    mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"

                    endcopy=$(date +"%Y-%m-%d %H:%M:%S")
                    STATE="Completed"
                    if [[ "$SIZE" -eq 0 ]]; then
                        STATE="Error"
                    fi

                    # Insert each file's detail into the daily log with the backup status
                    DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                            VALUES ('$CURRENT_DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
                    echo "Inserting into daily_log: \"$DQUERY\""
                    mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
                done
                STATE="Completed"
            else
                echo "No backup files found in ${DB_FULL_PATH}"
                STATE="Error"
            fi
        done
    fi
fi

echo "Unmounting storage"
fusermount -u "$STORAGE" || { echo "Error unmounting $STORAGE"; exit 1; }

echo "Script completed successfully."
