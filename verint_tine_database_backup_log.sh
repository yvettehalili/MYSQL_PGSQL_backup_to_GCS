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

# Date Range Variables for Checking Backups
START_DATE="2024-09-07"
END_DATE="2024-11-09"

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type FROM ti_db_inventory.servers WHERE active = 1 AND project IN ('ti-verint152prod', 'tine-payroll-prod-01') ORDER BY location, type, os;"

clear

# Create the storage directory if it does not exist
mkdir -p $STORAGE

# Function to mount the appropriate bucket storage based on the project
mount_storage() {
    local project=$1
    case $project in
        tine-payroll-prod-01)
            gcsfuse --key-file=/root/jsonfiles/tine-payroll-prod-01.json tine-payroll-eu-prod-01-db-backups $STORAGE || { echo "Error mounting gcsfuse for tine-payroll-prod-01"; exit 1; }
            ;;
        ti-verint152prod)
            gcsfuse --key-file=/root/jsonfiles/ti-verint152prod-4ba9008f4ef8.json ticxwfo-dbbackup $STORAGE || { echo "Error mounting gcsfuse for ti-verint152prod"; exit 1; }
            ;;
        *)
            echo "Unsupported project: $project"
            exit 1
            ;;
    esac
}

# Function to unmount the storage
unmount_storage() {
    fusermount -u $STORAGE || { echo "Error unmounting $STORAGE"; exit 1; }
}

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

# Iterate over each date in the range
current_date=$START_DATE
while [[ "$current_date" < "$END_DATE" || "$current_date" == "$END_DATE" ]]; do
    TEST_DATE=$current_date
    TEST_DATE2=$(date -d "$TEST_DATE" +"%Y%m%d")
    TEST_DATE3=$(date -d "$TEST_DATE" +"%d-%m-%Y")

    echo "============================================================================================================"
    echo "START DATE: $TEST_DATE ....................................................................................."
    echo "============================================================================================================"

    # Fetch server details from the database and iterate over each server
    mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE_EXTRA;
    do
        # Extract the actual TYPE from the TYPE_EXTRA (assume TYPE_EXTRA is the last field)
        TYPE=$(echo "$TYPE_EXTRA" | awk '{print $NF}')
        
        echo "============================================================================================================"
        echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE"
        echo "============================================================================================================"
        echo "Checking backups for SERVER: $SERVER on DATE: $TEST_DATE"

        BACKUP_PATH=""
        FILES=""

        # Determine the project and mount the appropriate storage
        case "$LOCATION" in
            tine-payroll-eu-prod-01)
                PROJECT="tine-payroll-prod-01"
                mount_storage $PROJECT
                ;;
            ticxwfo)
                PROJECT="ti-verint152prod"
                mount_storage $PROJECT
                ;;
            *)
                echo "Unsupported location: $LOCATION"
                continue
                ;;
        esac

        # Determine backup path based on server name
        case "$LOCATION" in
            tine-payroll-eu-prod-01)
                BACKUP_PATH="$STORAGE/Backups/Current/$SERVER"
                ;;
            ticxwfo)
                BACKUP_PATH="$STORAGE/V152_Backups/$SERVER"
                ;;
            *)
                echo "Unsupported location: $LOCATION"
                continue
                ;;
        esac

        # Process files based on backup path
        SIZE=0
        FILENAMES=()

        # Check for files with TEST_DATE variants
        for DATE in "$TEST_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
            FILES=$(gsutil ls "$BACKUP_PATH/DIFF/*${DATE}*.bak" 2>/dev/null)
            FILES+=$(gsutil ls "$BACKUP_PATH/FULL/*${DATE}*.bak" 2>/dev/null)
            if [[ -n "$FILES" ]]; then
                break
            fi
        done

        for FILE in $FILES; do
            fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
            SIZE=$((SIZE + fsize))

            # Extract database name and filename from the full file path
            FILENAME=$(basename "$FILE")
            FILENAMES+=("$FILENAME")

            if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                DB_NAME="${BASH_REMATCH[1]}"
            fi
            
            # Insert details into the backup log
            echo "Would insert into backup_log: (date: $TEST_DATE, server: $SERVER, size: $fsize, file: $FILE)"
            SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath, last_update) 
                    VALUES ('$TEST_DATE','$SERVER',$fsize,'$FILE', NOW())
                    ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize;"
            echo "SQUERY: $SQUERY"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"

            endcopy=$(date +"%Y-%m-%d %H:%M:%S")
            STATE="Completed"
            if [ "$SIZE" -eq 0 ]; then
                STATE="Error"
            fi

            # Insert each file's detail into the daily log with the backup status
            echo "Would insert into daily_log: (date: $TEST_DATE, server: $SERVER, database: $DB_NAME, size: $fsize, state: $STATE, file: $FILENAME)"
            DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                    VALUES ('$TEST_DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
            echo "DQUERY: $DQUERY"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
        done

        # Unmount storage after processing each server
        unmount_storage

    done
    
    # Increment the date by one day
    current_date=$(date -I -d "$current_date + 1 day")
done

echo "Script completed successfully."
