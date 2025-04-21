#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="ti_db_inventory"
REPORT_DATE=$(date '+%Y-%m-%d')  # Today's date for report title
YESTERDAY_DATE=$(date -d '-1 day' '+%Y-%m-%d')  # Set the report date to yesterday
DIR="backup"

# Create Directory if not exists
mkdir -p "${DIR}"

# Debug logs file
LOG_FILE="${DIR}/debug_screen.log"
: > "${LOG_FILE}" # Clear log file

# Function to print section to the screen with table-style output
printSectionToScreen() {
    local title="${1}"
    local query="${2}"

    echo "Processing section: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    echo ""
    echo "======================================================"
    echo "                 ${title}"
    echo "======================================================"
    echo ""

    mysql -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r Server size size_name Location DB_engine OS backup_date; do
        # Determine error status based on the size
        local error="No"
        if [[ "$size" == "0.00" && "$size_name" == "B" ]]; then
            error="Yes"
        fi

        printf "Server: %s\nSize: %s %s\nLocation: %s\nDB Engine: %s\nOS: %s\nError: %s\nBackup Date: %s\n" \
            "$Server" "$size" "$size_name" "$Location" "$DB_engine" "$OS" "$error" "$backup_date"
        echo "------------------------------------------------------"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Query execution failed for section: ${title}" >> "${LOG_FILE}"
        echo "Error: Query execution failed for section: ${title}" >&2
    else
        echo "Query executed successfully for section: ${title}" >> "${LOG_FILE}"
    fi
}

# Clear the terminal screen
clear

# Generate Queries with ORDER BY clause
queryMySQL="SELECT Server, size, size_name, Location, DB_engine, OS, backup_date FROM daily_backup_report WHERE DB_engine='MYSQL' AND Location='GCP' AND backup_date = '${YESTERDAY_DATE}' ORDER BY Server ASC;"
queryPGSQL="SELECT Server, size, size_name, Location, DB_engine, OS, backup_date FROM daily_backup_report WHERE DB_engine='PGSQL' AND Location='GCP' AND backup_date = '${YESTERDAY_DATE}' ORDER BY Server ASC;"
queryMSSQL="SELECT Server, size, size_name, Location, DB_engine, OS, backup_date FROM daily_backup_report WHERE DB_engine='MSSQL' AND Location='GCP' AND backup_date = '${YESTERDAY_DATE}' ORDER BY Server ASC;"

# Log the generated queries
echo "Generated Queries:" >> "${LOG_FILE}"
echo "${queryMySQL}" >> "${LOG_FILE}"
echo "${queryPGSQL}" >> "${LOG_FILE}"
echo "${queryMSSQL}" >> "${LOG_FILE}"

# Print sections to the screen for analysis
printSectionToScreen "GCP Backup Information - MySQL" "${queryMySQL}"
printSectionToScreen "GCP Backup Information - PostgreSQL" "${queryPGSQL}"
printSectionToScreen "GCP Backup Information - MSSQL" "${queryMSSQL}"

echo ""
echo "======================================================"
echo "       Backup Logs Output Completed"
echo "======================================================"
echo ""

# Print any debug information to the screen
echo ""
echo "Debug logs saved to: ${LOG_FILE}"
echo "Debug log content:"
cat "${LOG_FILE}"
