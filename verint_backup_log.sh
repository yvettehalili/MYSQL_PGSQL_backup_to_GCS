#!/bin/bash

# Script to check backup logs for ti-verint152prod

# Ensure required commands are available
command -v gcsfuse >/dev/null 2>&1 || { echo >&2 "gcsfuse command not found. Please install gcsfuse."; exit 1; }
command -v fusermount >/dev/null 2>&1 || { echo >&2 "fusermount command not found. Please install fuse."; exit 1; }

# Database Credentials
DB_USER=trtel.backup
DB_PASS='Telus2017#'
DB_MAINTENANCE=ti_db_inventory

# Environment Variables
STORAGE=/root/cloudstorage
BUCKET=ticxwfo-dbbackup

# Date Calculation
CURRENT_SATURDAY=$(date +"%Y-%m-%d")
START_DATE=$(date -d "$CURRENT_SATURDAY -6 days" +"%Y-%m-%d")
END_DATE=$(date -d "$CURRENT_SATURDAY -1 days" +"%Y-%m-%d")

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type FROM ti_db_inventory.servers WHERE active = 1 AND project = 'ti-verint152prod' ORDER BY location, type, os;"

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

# Mount storage for ti-verint152prod
echo "Mounting bucket for project ti-verint152prod"
gcsfuse --key-file=/root/jsonfiles/ti-verint152prod-4ba9008f4ef8.json $BUCKET $STORAGE || { echo "Error mounting gcsfuse for ti-verint152prod"; exit 1; }

echo "============================================================================================================"
echo "CHECKING DATE RANGE: $START_DATE to $END_DATE"
echo "============================================================================================================"

# Fetch and iterate over server details from the database
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE_EXTRA
do
    # Extract the actual TYPE from the TYPE_EXTRA (assume TYPE_EXTRA is the last field)
    TYPE=$(echo "$TYPE_EXTRA" | awk '{print $NF}')

    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER from DATE: $START_DATE to $END_DATE"

    BACKUP_PATH="V152_Backups/$SERVER"
    echo "Backup path being checked: $BACKUP_PATH"

    SIZE=0
    FILENAMES=()

    # Handle MSSQL separately due to different backup structure
    if [[ "$TYPE" == "MSSQL" ]]; then
        for DAY in {0..6}; do
            TARGET_DATE=$(date -d "$START_DATE +$DAY days" +"%Y-%m-%d")
            DATE_FORMATTED1=$(date -d "$TARGET_DATE" +"%Y%m%d")
            DATE_FORMATTED2=$(date -d "$TARGET_DATE" +"%d-%m-%Y")
            
            for DATE in "$TARGET_DATE" "$DATE_FORMATTED1" "$DATE_FORMATTED2"; do
                # List all database directories under the server
                for DB_FOLDER in $(gsutil ls "gs://$BUCKET/$BACKUP_PATH/" | grep '/$'); do
                    DB_FULL_PATH="${DB_FOLDER}FULL/"
                    DB_DIFF_PATH="${DB_FOLDER}DIFF/"
                    echo "Checking FULL directory: ${DB_FULL_PATH}"
                    echo "Checking DIFF directory: ${DB_DIFF_PATH}"

                    # Aggregate file lists from FULL and DIFF directories
                    FILES=$(gsutil ls "${DB_FULL_PATH}*${DATE}*.bak" 2>/dev/null)
                    FILES+=$(gsutil ls "${DB_DIFF_PATH}*${DATE}*.bak" 2>/dev/null)

                    if [[ -n "$FILES" ]]; then
                        echo "Found backup files: $FILES"

                        for FILE in $FILES; do
                            fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                            SIZE=$((SIZE + fsize))

                            # Extract database name and filename from the full file path
                            FILENAME=$(basename "$FILE")
                            FILENAMES+=("$FILENAME")

                            if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                                DB_NAME="${BASH_REMATCH[1]}"
                            fi

                            echo "Backup details - Server: $SERVER, Database: $DB_NAME, Filename: $FILENAME, Filesize: $fsize, Path: $FILE"

                            # Insert details into the backup log
                            SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath, last_update) 
                                    VALUES ('$TARGET_DATE','$SERVER',$fsize,'$FILE', NOW())
                                    ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize;"
                            echo "Inserting into backup_log: \"$SQUERY\""
                            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"

                            endcopy=$(date +"%Y-%m-%d %H:%M:%S")
                            STATE="Completed"

                            if [ "$SIZE" -eq 0 ]; then
                                STATE="Error"
                            fi

                            # Insert each file's detail into the daily log with the backup status
                            DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                                    VALUES ('$TARGET_DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
                            echo "Inserting into daily_log: \"$DQUERY\""
                            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
                        done
                    else
                        echo "No backup files found for date: $DATE in ${DB_FULL_PATH} and ${DB_DIFF_PATH}"
                    fi
                done
                if [[ -n "$FILES" ]]; then
                    break
                fi
            done
        done
    else
        echo "Skipping non-MSSQL server: $SERVER"
    fi
done

echo "Unmounting storage for ti-verint152prod"
fusermount -u $STORAGE || { echo "Error unmounting $STORAGE"; exit 1; }

echo "ti-verint152prod script completed successfully."
