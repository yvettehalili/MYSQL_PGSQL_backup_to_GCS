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

# Get the current date
TODAY=$(date +"%Y-%m-%d")
TODAY2=$(date -d "$TODAY" +"%Y%m%d")
TODAY3=$(date -d "$TODAY" +"%d-%m-%Y")

# SQL Query to Fetch Server Details, excluding specified projects
query="SELECT name, ip, user, pwd, os, frequency, save_path, location, type 
      FROM ti_db_inventory.servers 
      WHERE active=1 
      AND project NOT IN ('ti-verint152prod', 'tine-payroll-prod-01')
      ORDER BY location, type, os"

clear
echo "============================================================================================================"
echo "Fetching active servers on DATE: $TODAY"
echo "============================================================================================================"

# Fetch and print server details to ensure they are being fetched correctly
servers=$(mysql -u"$DB_USER" -p"$DB_PASS" --batch -se "$query" $DB_MAINTENANCE)
echo "Fetched Servers:"
echo "$servers"
echo "============================================================================================================"

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
echo "START DATE: $TODAY .........................................................................................."
echo "============================================================================================================"

# Function to fetch backup files and echo details
fetch_backup_files() {
  local BACKUP_PATH="$1"
  local EXTENSION="$2"

  FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TODAY}*${EXTENSION}" 2>/dev/null)
  if [[ -z "$FILES" ]]; then
      FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TODAY2}*${EXTENSION}" 2>/dev/null)
  fi
  if [[ -z "$FILES" ]]; then
      FILES=$(gsutil ls "gs://$BUCKET/$BACKUP_PATH*${TODAY3}*${EXTENSION}" 2>/dev/null)
  fi

  for FILE in $FILES; do
      fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
      SIZE=$((SIZE + fsize))

      # Extract database name and filename from the full file path
      FILENAME=$(basename "$FILE")
      case "$TYPE" in
          MYSQL)
              if [[ "$FILENAME" =~ ^(${TODAY}|${TODAY2}|${TODAY3})_(db_.*)\.sql\.gz$ ]]; then
                  DATABASE="${BASH_REMATCH[2]}"
              elif [[ "$FILENAME" =~ ^(${TODAY}|${TODAY2}|${TODAY3})_(.*)\.sql\.gz$ ]]; then
                  DATABASE="${BASH_REMATCH[2]}"
              fi
              ;;
          PGSQL)
              if [[ "$FILENAME" =~ ^(${TODAY}|${TODAY2}|${TODAY3})_(.*)\.dump$ ]]; then
                  DATABASE="${BASH_REMATCH[2]}"
              fi
              ;;
      esac

      # Echo details instead of logging
      echo "Found backup: (date: $TODAY, server: $SERVER, size: $fsize, file: $FILE, database: $DATABASE)"
  done
}

# Fetch server details from the database and iterate over each server
echo "$servers" | while IFS=$'\t' read_fields SERVER SERVERIP WUSER WUSERP OS SAVE_PATH LOCATION TYPE_EXTRA; do
    # Extract the actual TYPE from the TYPE_EXTRA (assume TYPE_EXTRA is the last field)
    TYPE=$(echo "$TYPE_EXTRA" | awk '{print $NF}')
    
    echo "============================================================================================================"
    echo "SERVER: $SERVER - $SERVERIP - $OS - $TYPE - $SAVE_PATH - $LOCATION"
    echo "============================================================================================================"
    echo "Checking backups for SERVER: $SERVER on DATE: $TODAY"

    BACKUP_PATH=""
    DATABASE=""
    FILES=""

    # Determine the backup path and file extension based on the type of database
    case "$TYPE" in
        MYSQL)
            BACKUP_PATH="Backups/Current/MYSQL/$SERVER/"
            EXTENSION=".sql.gz"
            fetch_backup_files "$BACKUP_PATH" "$EXTENSION"
            ;;
        PGSQL)
            BACKUP_PATH="Backups/Current/POSTGRESQL/$SERVER/"
            EXTENSION=".dump"
            fetch_backup_files "$BACKUP_PATH" "$EXTENSION"
            ;;
        MSSQL)
            BACKUP_PATH="Backups/Current/MSSQL/$SERVER/"
            EXTENSION=".bak"
            
            SIZE=0

            # Check for files with TODAY variants
            for DATE in "$TODAY" "$TODAY2" "$TODAY3"; do
                FILES=$(gsutil ls "gs://$BUCKET/${BACKUP_PATH}*/DIFF/*${DATE}*.bak" 2>/dev/null)
                FILES+=$(gsutil ls "gs://$BUCKET/${BACKUP_PATH}*/FULL/*${DATE}*.bak" 2>/dev/null)

                if [[ -n "$FILES" ]]; then
                    break
                fi
            done

            for FILE in $FILES; do
                fsize=$(gsutil du -s "$FILE" | awk '{print $1}')
                SIZE=$((SIZE + fsize))

                # Extract database name and filename from the full file path
                FILENAME=$(basename "$FILE")

                if [[ "$FILENAME" =~ ^${SERVER}_(.*)_(DIFF|FULL)_(.*)\.bak$ ]]; then
                    DB_NAME="${BASH_REMATCH[1]}"
                fi
                
                # Echo details instead of logging
                echo "Found backup: (date: $TODAY, server: $SERVER, size: $fsize, file: $FILE, database: $DB_NAME)"
            done
            ;;
        *)
            echo "Unsupported database type: $TYPE"
            continue
            ;;
    esac
done

# Unmount the cloud storage
if ! fusermount -u $STORAGE; then
    echo "Error unmounting /root/cloudstorage"
    exit 1
fi

echo "Script completed successfully."
