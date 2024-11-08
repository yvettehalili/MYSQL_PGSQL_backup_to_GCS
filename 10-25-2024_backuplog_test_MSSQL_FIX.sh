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
KEY_DIR=/root/jsonfiles

# Fixed Date Variables for Testing (simulating "2024-10-25")
TEST_DATE="2024-10-25"
TEST_DATE2=$(date -d "$TEST_DATE" +"%Y%m%d")
TEST_DATE3=$(date -d "$TEST_DATE" +"%d-%m-%Y")

# Execute Setup Query
mysql -u"$DB_USER" -p"$DB_PASS" -e "$setup_query"

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type, bucket, project FROM ti_db_inventory.servers WHERE active=1 ORDER BY location, type, os"

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
        IFS= read -r "$1" <<< "${input%%[$IFS]*}"
        input="${input#*[$IFS]}"
        shift
    done
    IFS= read -r "$1" <<< "$input"
}

# Fetch server details from the database and iterate over each server
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' myread SERVER SERVERIP WUSER WUSERP OS FREQUENCY SAVE_PATH LOCATION TYPE BUCKET PROJECT;
do
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION - $BUCKET - $PROJECT"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $TEST_DATE"

    BACKUP_PATH=""
    DATABASE=""
    FILES=""

    # Determine the correct key file based on the project
    case "$PROJECT" in
        "tine-payroll-prod-01")
            KEY_FILE="$KEY_DIR/tine-payroll-prod-01.json"
            ;;
        "ti-verint152prod")
            KEY_FILE="$KEY_DIR/ti-verint152prod-4ba9008f4ef8.json"
            ;;
        *)
            KEY_FILE="$KEY_DIR/ti-dba-prod-01.json"
            ;;
    esac

    # Mount the Google Cloud bucket using gcsfuse
    echo "Mounting bucket $BUCKET with key file $KEY_FILE"
    if ! gcsfuse --key-file=$KEY_FILE "$BUCKET" "$STORAGE"; then
        echo "Error mounting gcsfuse. Please check if the key file path is correct and the JSON file exists."
        exit 1
    fi

    case "$TYPE" in
        MYSQL)
            BACKUP_PATH="$SAVE_PATH$SERVER/"
            EXTENSION="*.sql.gz"
            ;;
        PGSQL)
            BACKUP_PATH="$SAVE_PATH$SERVER/"
            EXTENSION="*.dump"
            ;;
        MSSQL)
            BACKUP_PATH="$SAVE_PATH$SERVER/"
            ;;
        *)
            echo "Unsupported database type: $TYPE"
            fusermount -u $STORAGE
            continue
            ;;
    esac

    if [[ "$TYPE" == "MSSQL" ]]; then
        SIZE=0
        for DATE in "$TEST_DATE" "$TEST_DATE2" "$TEST_DATE3"; do
            for DB_PATH in $(gsutil ls "gs://$BUCKET/$BACKUP_PATH*/" 2>/dev/null); do
                DB_FOLDER=$(basename $DB_PATH)
                echo "Checking path: gs://$BUCKET/$BACKUP_PATH$DB_FOLDER/DIFF/*${DATE}*.bak"
                FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH$DB_FOLDER/DIFF/*${DATE}*.bak" 2>/dev/null)
                echo "Checking path: gs://$BUCKET/$BACKUP_PATH$DB_FOLDER/FULL/*${DATE}*.bak"
                FILES+=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH$DB_FOLDER/FULL/*${DATE}*.bak" 2>/dev/null)
                if [[ -n "$FILES" ]]; then
                    break
                fi
            done
            if [[ -n "$FILES" ]]; then
                break
            fi
        done

        FILENAMES=()
        for FILE in $FILES; do
            fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
            SIZE=$((SIZE + fsize))
            FILENAME=$(basename "$FILE")
            FILENAMES+=("$FILENAME")
            DB_NAME=$(basename $(dirname "$FILE"))

            # Echo details to be inserted into backup_log
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

            # Echo details to be inserted into daily_log
            echo "Would insert into daily_log: (date: $TEST_DATE, server: $SERVER, database: $DB_NAME, size: $fsize, state: $STATE, file: $FILENAME)"

            DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                    VALUES ('$TEST_DATE', '$SERVER', '$DB_NAME', $fsize, '$STATE', '$endcopy', '$FILENAME');"
            echo "DQUERY: $DQUERY"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
        done
    else
        SIZE=0
        FILENAMES=()
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

            # Echo details to be inserted into backup_log
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

            # Echo details to be inserted into daily_log
            echo "Would insert into daily_log: (date: $TEST_DATE, server: $SERVER, database: $DATABASE, size: $fsize, state: $STATE, file: $FILENAME)"

            DQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update, fileName) 
                    VALUES ('$TEST_DATE', '$SERVER', '$DATABASE', $fsize, '$STATE', '$endcopy', '$FILENAME');"
            echo "DQUERY: $DQUERY"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$DQUERY"
        done
    fi
    
    # Unmount the cloud storage
    if mountpoint -q $STORAGE; then
        fusermount -u $STORAGE
        echo "Successfully unmounted $STORAGE"
    fi
done

if mountpoint -q $STORAGE; then
    if ! fusermount -u $STORAGE; then
        echo "Error unmounting /root/cloudstorage"
        exit 1
    else
        echo "Successfully unmounted /root/cloudstorage"
    fi
fi

printf "done\n"

