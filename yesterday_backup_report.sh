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
LOG_FILE="${DIR}/debug_yesterday.log"
: > "${LOG_FILE}" # Clear log file

# Function to append section to email content with table
appendSectionWithTable() {
    local title="${1}"
    local query="${2}"

    echo "Appending section: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    {
        echo "<h2 style='color: #4B286D; text-align: center;'>${title}</h2>"
        echo "<table style='width: 100%; border-collapse: collapse; margin: 20px 0; border: 1px solid #ddd;'>"
        echo "  <thead>"
        echo "    <tr style='background-color: #4B286D; color: white;'>"
        echo "      <th style='padding: 10px; text-align: left;'>No</th>"
        echo "      <th style='padding: 10px; text-align: left;'>Server</th>"
        echo "      <th style='padding: 10px; text-align: left;'>Size</th>"
        echo "      <th style='padding: 10px; text-align: left;'>Size Name</th>"
        echo "      <th style='padding: 10px; text-align: left;'>Location</th>"
        echo "      <th style='padding: 10px; text-align: left;'>DB Engine</th>"
        echo "      <th style='padding: 10px; text-align: left;'>OS</th>"
        echo "      <th style='padding: 10px; text-align: left;'>Error</th>"
        echo "    </tr>"
        echo "  </thead>"
        echo "  <tbody>"

        local counter=1
        mysql -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r Server size size_name Location DB_engine OS backup_date; do
            # Determine error status based on the size
            local error="No"
            if [[ "$size" == "0.00" && "$size_name" == "B" ]]; then
                error="Yes"
            fi

            echo "    <tr style='border-bottom: 1px solid #ddd;'>"
            echo "      <td style='padding: 8px;'>${counter}</td>"
            echo "      <td style='padding: 8px;'>${Server}</td>"
            echo "      <td style='padding: 8px;'>${size}</td>"
            echo "      <td style='padding: 8px;'>${size_name}</td>"
            echo "      <td style='padding: 8px;'>${Location}</td>"
            echo "      <td style='padding: 8px;'>${DB_engine}</td>"
            echo "      <td style='padding: 8px;'>${OS}</td>"
            echo "      <td style='padding: 8px;'>${error}</td>"
            echo "    </tr>"
            ((counter++))
        done

        echo "  </tbody>"
        echo "</table>"
    } >> "${emailFile}"

    if [[ $? -ne 0 ]]; then
        echo "Query execution failed for section: ${title}" >> "${LOG_FILE}"
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

# Email Content
emailFile="${DIR}/yesterday_backup_report.html"
{
    echo "<!DOCTYPE html>"
    echo "<html lang='en'>"
    echo "<head>"
    echo "  <meta charset='UTF-8'>"
    echo "  <style>"
    echo "    body { font-family: 'Helvetica Neue', Arial, sans-serif; background-color: #f4f4f4; color: #333; margin: 0; padding: 20px; }"
    echo "    .container { max-width: 800px; margin: 0 auto; padding: 20px; background-color: #fff; border: 1px solid #ddd; border-radius: 10px; }"
    echo "    h1 { color: #4B286D; text-align: center; margin-bottom: 20px; }"
    echo "    h2 { color: #4B286D; text-align: center; margin-top: 40px; }"
    echo "    table { width: 100%; border-collapse: collapse; margin: 20px 0; border: 1px solid #ddd; }"
    echo "    th { background-color: #4B286D; color: white; padding: 10px; text-align: left; }"
    echo "    td { padding: 10px; text-align: left; }"
    echo "    tr:nth-child(even) { background-color: #f9f9f9; }"
    echo "    tr:hover { background-color: #f1f1f1; }"
    echo "    .footer { text-align: center; padding: 20px; color: #4B286D; border-top: 1px solid #ddd; }"
    echo "  </style>"
    echo "</head>"
    echo "<body>"
    echo "  <div class='container'>"
    echo "    <h1>Backup Report - ${YESTERDAY_DATE}</h1>"
} > "${emailFile}"

# Append sections to the email content
appendSectionWithTable "GCP Backup Information - MySQL" "${queryMySQL}"
appendSectionWithTable "GCP Backup Information - PostgreSQL" "${queryPGSQL}"
appendSectionWithTable "GCP Backup Information - MSSQL" "${queryMSSQL}"

# Close HTML Tags
{
    echo "    <div class='footer'>"
    echo "      <p>Report generated by Database Engineering</p>"
    echo "    </div>"
    echo "  </div>"
    echo "</body>"
    echo "</html>"
} >> "${emailFile}"

# Send Email via sendmail
{
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: Backup Log Report - ${YESTERDAY_DATE}"
    echo ""
    cat "${emailFile}"
} | /usr/sbin/sendmail -t

echo "Backup log email sent to yvette.halili@telusinternational.com"
