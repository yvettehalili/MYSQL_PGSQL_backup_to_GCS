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
BUCKET=ti-dba-prod-sql-01

# Current Date Variables
CUR_DATE=$(date +"%Y-%m-%d")
CUR_DATE2=$(date -d "$CUR_DATE" +"%Y%m%d")
CUR_DATE3=$(date -d "$CUR_DATE" +"%d-%m-%Y")
CUR_DATE4=$(date -d "$CUR_DATE" +"%Y%m%d_%H%M%S")

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, save_path, location, type FROM ti_db_inventory.servers WHERE active=1 ORDER BY location, type, os"

clear

echo "============================================================================================================"
echo "START DATE: $CUR_DATE ....................................................................................."
echo "============================================================================================================"

# Create the storage directory if it does not exist
mkdir -p $STORAGE

# Mount the Google Cloud bucket using gcsfuse
if ! gcsfuse --key-file=/root/jsonfiles/ti-dba-prod-01.json $BUCKET $STORAGE; then
    echo "Error mounting gcsfuse. Please check if the key file path is correct and the JSON file exists."
    exit 1
fi

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
mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' myread SERVER SERVERIP WUSER WUSERP OS SAVEPATH LOCATION TYPE;
do
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVEPATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $CUR_DATE"

    BACKUP_PATH=""

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
            EXTENSION="*.bak"
            ;;
        *)
            echo "Unsupported database type: $TYPE"
            continue
            ;;
    esac

    SIZE=0
    DATABASE=""

    # Check for files with CUR_DATE
    FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE2}_${CUR_DATE4}${EXTENSION}" 2>/dev/null)
    if [[ -z "$FILES" ]]; then
        # Check for files with CUR_DATE2
        FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE2}${EXTENSION}" 2>/dev/null)
    fi
    if [[ -z "$FILES" ]]; then
        # Check for files with CUR_DATE3
        FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE3}${EXTENSION}" 2>/dev/null)
    fi

    for FILE in $FILES; do
        fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
        SIZE=$((SIZE + fsize))

        # Extract database name from the file name based on the type
        FILENAME=$(basename "$FILE")
        case "$TYPE" in
            MYSQL)
                if [[ "$FILENAME" =~ ^(${CUR_DATE}|${CUR_DATE2}|${CUR_DATE3})_(.*)\.sql\.gz$ ]]; then
                    DATABASE="${BASH_REMATCH[2]}"
                fi
                ;;
            PGSQL)
                if [[ "$FILENAME" =~ ^(${CUR_DATE}|${CUR_DATE2}|${CUR_DATE3})_(.*)\.dump$ ]]; then
                    DATABASE="${BASH_REMATCH[2]}"
                fi
                ;;
            MSSQL)
                if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                    DATABASE="${BASH_REMATCH[1]}"
                fi
                ;;
        esac
    done

    endcopy=$(date +"%Y-%m-%d %H:%M:%S")
    STATE="Completed"
    if [ "$SIZE" -eq 0 ]; then
        STATE="Error"
    fi

    # Insert or update the daily log with the backup status
    IQUERY="INSERT INTO daily_log (backup_date, server, \`database\`, size, state, last_update) 
            VALUES ('$CUR_DATE', '$SERVER', '$DATABASE', $SIZE, '$STATE', '$endcopy') 
            ON DUPLICATE KEY UPDATE size=$SIZE, state='$STATE', last_update='$endcopy';"
    mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$IQUERY"

    # Insert details into the backup log
    for FILE in $FILES; do
        fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
        SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath) 
                VALUES ('$CUR_DATE','$SERVER',$fsize,'$FILE')
                ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize;"
        mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"
    done
done

# Unmount the cloud storage
if ! fusermount -u $STORAGE; then
    echo "Error unmounting /root/cloudstorage"
    exit 1
fi

printf "done\n"
