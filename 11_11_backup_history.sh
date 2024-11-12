
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

# Date Range Variables for Checking Backups
START_DATE="2024-11-01"
END_DATE="2024-11-11"

# Execute Setup Query (if any)
mysql -u"$DB_USER" -p"$DB_PASS" -e "$setup_query"

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type FROM ti_db_inventory.servers WHERE active=1 ORDER BY location, type, os"

clear

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
        echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
        echo "============================================================================================================"
        echo "Checking backups for SERVER: $SERVER on DATE: $TEST_DATE"

        BACKUP_PATH=""
        DATABASE=""
        FILES=""

        # Determine the backup path and file extension based on the type of database
        case "$TYPE" in
            MYSQL)
                BACKUP_PATH="Backups/Current/MYSQL/$SERVER/"
                EXTENSION="*.sql.gz"
                ;;
            PGSQL)
                BACKUP_PATH="Backups/Current/POSTGRESQL/$SERVER/"
                EXTENSION="*.dump"
                ;;
            MSSQL)
                BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
                ;;
            *)
                echo "Unsupported database type: $TYPE"
                continue
                ;;
        esac

        # Handle MSSQL separately due to different backup structure
        if [[ "$TYPE" == "MSSQL" ]]; then
            SIZE=0

            # Check for files with TEST_DATE variants
            for DATE in "$TEST_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
                FILES=$(gsutil ls "gs://$BUCKET/${BACKUP_PATH}*/DIFF/*${DATE}*.bak" 2>/dev/null)
                FILES+=$(gsutil ls "gs://$BUCKET/${BACKUP_PATH}*/FULL/*${DATE}*.bak" 2>/dev/null)

                if [[ -n "$FILES" ]]; then
                    break
                fi
            done

            FILENAMES=()

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

        else
            SIZE=0
            FILENAMES=()

            # Check for files with TEST_DATE variants
            FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TEST_DATE}*.${EXTENSION##*.}" 2>/dev/null)
            if [[ -z "$FILES" ]]; then
                FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TEST_DATE2}*.${EXTENSION##*.}" 2>/dev/null)
            fi
            if [[ -z "$FILES" ]]; then
                FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TEST_DATE3}*.${EXTENSION##*.}" 2>/dev/null)
            fi

            for FILE in $FILES; do
                fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                SIZE=$((SIZE + fsize))

                # Extract database name and filename from the full file path
                FILENAME=$(basename "$FILE")
                FILENAMES+=("$FILENAME")
                case "$TYPE" in
                    MYSQL)
                        if [[ "$FILENAME" =~ ^(${TEST_DATE}|${TEST_DATE2}|${TEST_DATE3})_(db_.*)\.sql\.gz$ ]]; then
                            DATABASE="${BASH_REMATCH[2]}"
                        elif [[ "$FILENAME" =~ ^(${TEST_DATE}|${TEST_DATE2}|${TEST_DATE3})_(.*)\.sql\.gz$ ]]; then
                            DATABASE="${BASH_REMATCH[2]}"
                        fi
                        ;;
                    PGSQL)
                        if [[ "$FILENAME" =~ ^(${TEST_DATE}|${TEST_DATE2}|${TEST_DATE3})_(.*)\.dump$ ]]; then
                            DATABASE="${BASH_REMATCH[2]}"
                        fi
                        ;;
                esac

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
                echo "Would insert into daily_log: (date: $TEST_DATE, server: $SERVER, database: $DATABASE, size: $fsize, state: $STATE, file: $FILENAME)"
                DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                        VALUES ('$TEST_DATE', '$SERVER', '$DATABASE', $fsize, '$STATE', '$endcopy', '$FILENAME');"
                echo "DQUERY: $DQUERY"
                mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
            done
        fi
    done
    
    # Increment the date by one day
    current_date=$(date -I -d "$current_date + 1 day")
done

# Unmount the cloud storage
if ! fusermount -u $STORAGE; then
    echo "Error unmounting /root/cloudstorage"
    exit 1
fi

echo "Script completed successfully."
