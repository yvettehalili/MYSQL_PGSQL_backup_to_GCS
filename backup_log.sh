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

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frecuency, domain, save_path, location, type FROM ti_db_inventory.servers WHERE srv_active = 1 ORDER BY location, type, os"

clear

echo "============================================================================================================"
echo "START DATE: $CUR_DATE ....................................................................................."
echo "============================================================================================================"

# Create the storage directory if it does not exist
mkdir -p $STORAGE

# Mount the Google Cloud bucket
gcsfuse --key-file=/root/jsonfiles/ti-dba-prod-01.json $BUCKET $STORAGE

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

mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE | while IFS=$'\t' myread SERVER SERVERIP WUSER WUSERP OS FRECUENCY DOMAIN SAVEPATH LOCATION TYPE;
do
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVEPATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $CUR_DATE"

    BACKUP_PATH=""

    case "$TYPE" in
        MYSQL)
            BACKUP_PATH="Backups/Current/MYSQL/$SERVER/"
            ;;
        POSQL)
            BACKUP_PATH="Backups/Current/POSTGRESQL/$SERVER/"
            ;;
        MSSQL)
            BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
            ;;
        *)
            echo "Unsupported database type: $TYPE"
            continue
            ;;
    esac

    if [ -n "$BACKUP_PATH" ]; then
        SIZE=$(gsutil du -s "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE}*" | awk '{print $1}')
        if [[ $SIZE =~ ^[[:space:]]*$ ]] || [ "$SIZE" -eq 0 ]; then
            SIZE=$(gsutil du -s "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE2}*" | awk '{print $1}')
        fi
        if [[ $SIZE =~ ^[[:space:]]*$ ]] || [ "$SIZE" -eq 0 ]; then
            SIZE=$(gsutil du -s "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE3}*" | awk '{print $1}')
        fi
    fi

    if [[ $SIZE =~ ^[[:space:]]*$ ]]; then
        SIZE=0
    fi

    endcopy=$(date +"%Y-%m-%d %H:%M:%S")
    IQUERY="INSERT INTO daily_log (backup_date, server, size) VALUES ('$CUR_DATE', '$SERVER', $SIZE) ON DUPLICATE KEY UPDATE size=$SIZE;"
    mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$IQUERY"
    
    if [ "$SIZE" -gt 0 ]; then
        gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE}*" > "/backup/cronlog/$SERVER.txt" 2>/dev/null
        gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE2}*" >> "/backup/cronlog/$SERVER.txt" 2>/dev/null
        gsutil ls "gs://$BUCKET/$BACKUP_PATH*${CUR_DATE3}*" >> "/backup/cronlog/$SERVER.txt" 2>/dev/null

        while read -r line; do
            fsize=$(gsutil du -s "$line" | awk '{print $1}')
            file=$(basename "$line")
            SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath) 
                    VALUES ('$CUR_DATE','$SERVER',$fsize,'$line')
                    ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize, state=CASE WHEN $fsize > 0 THEN 'Completed' ELSE 'Error' END;"
            mysql -u"$DB_USER" -p"$DB_PASS" $DB_MAINTENANCE -e "$SQUERY"
        done < "/backup/cronlog/$SERVER.txt"
    fi
done

# Unmount the cloud storage
fusermount -uz $STORAGE

printf "done\n"
