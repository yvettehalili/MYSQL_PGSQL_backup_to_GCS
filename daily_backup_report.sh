#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="ti_db_inventory"
REPORT_DATE=$(date '+%Y-%m-%d')  # Automatically set the report date to the current date
DIR="backup"
MAX_SIZE_MB=30720  # 30GB in MB

# Create Directory if not exists
mkdir -p "${DIR}"

# Debug logs file
LOG_FILE="${DIR}/debug.log"
: > "${LOG_FILE}" # Clear log file

# Define the function to generate queries
function generateQuery() {
    local serverType="${1}"
    local locationConstraint="${2}"

    local queryStr="SELECT b.server AS Server, "
    queryStr+="(CASE WHEN (TRUNCATE((SUM(b.size) / 1024), 0) > 0) THEN "
    queryStr+="(CASE WHEN (TRUNCATE(((SUM(b.size) / 1024) / 1024), 0) > 0) THEN "
    queryStr+="TRUNCATE(((SUM(b.size) / 1024) / 1024), 2) "
    queryStr+="ELSE TRUNCATE((SUM(b.size) / 1024), 2) END) "
    queryStr+="ELSE SUM(b.size) END) AS size_MB "
    queryStr+="FROM daily_log b "
    queryStr+="JOIN servers s ON s.name = b.server "
    queryStr+="WHERE b.backup_date = '${REPORT_DATE}' ${locationConstraint} AND s.type='${serverType}' "
    queryStr+="GROUP BY b.server;"

    echo "${queryStr}"
}

# Function to append section to email content with vertical bar graph
appendSection() {
    local title="${1}"
    local query="${2}"

    echo "Appending section: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    {
        echo "<h2 style='color: #00C853; text-align: center;'>${title}</h2>"
        echo "<div style='display: flex; align-items: flex-end; justify-content: center; height: 300px; border: 1px solid #ddd; padding: 10px;'>"
        echo "  <div style='text-align: right; padding-right: 10px;'>"
        echo "    <div style='height: 100%; display: flex; flex-direction: column; justify-content: space-between;'>"
        echo "      <span>30GB</span>"
        echo "      <span>20GB</span>"
        echo "      <span>10GB</span>"
        echo "      <span>0GB</span>"
        echo "    </div>"
        echo "  </div>"
        echo "  <div style='flex-grow: 1; display: flex; align-items: flex-end; justify-content: center;' >"
        mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r Server size_MB; do
            # Set maximum size for scaling (30GB in MB is 30720MB)
            percentage=$(echo "${size_MB}" | awk -v maxSize_MB="${MAX_SIZE_MB}" '{print ($1 / maxSize_MB) * 100}')
            
            echo "    <div style='flex: 1; margin: 0 10px; text-align: center; width: 50px;'>"
            echo "      <div style='height: ${percentage}%; width: 100%; background-color: #4B286D; margin-bottom: 10px; position: relative;'>"
            echo "        <span style='position: absolute; bottom: 100%; left: 50%; transform: translateX(-50%); color: #4B286D; font-size: 12px;'>${size_MB} MB</span>"
            echo "      </div>"
            echo "      <div style='writing-mode: vertical-rl; text-orientation: mixed; color: #4B286D; font-size: 14px;'>${Server}</div>"
            echo "    </div>"
        done
        echo "  </div>"
        echo "</div>"
    } >> "${emailFile}"

    if [[ $? -ne 0 ]]; then
        echo "Query execution failed for section: ${title}" >> "${LOG_FILE}"
    else
        echo "Query executed successfully for section: ${title}" >> "${LOG_FILE}"
    fi
}

# Clear the terminal screen
clear

# Generate Queries
queryMySQL=$(generateQuery "MYSQL" "AND s.location='GCP'")
queryPGSQL=$(generateQuery "PGSQL" "AND s.location='GCP'")
queryMSSQL=$(generateQuery "MSSQL" "AND s.location='GCP'")

# Log the generated queries
echo "Generated Queries:" >> "${LOG_FILE}"
echo "${queryMySQL}" >> "${LOG_FILE}"
echo "${queryPGSQL}" >> "${LOG_FILE}"
echo "${queryMSSQL}" >> "${LOG_FILE}"

# Email Content
emailFile="${DIR}/yvette_email_notification.html"
{
    echo "<!DOCTYPE html>"
    echo "<html lang='en'>"
    echo "<head>"
    echo "  <meta charset='UTF-8'>"
    echo "  <style>"
    echo "    body { font-family: Arial, sans-serif; background-color: #f4f4f4; color: #333; margin: 0; padding: 20px; }"
    echo "    .container { max-width: 800px; margin: 0 auto; padding: 20px; background-color: #fff; border: 1px solid #ddd; border-radius: 10px; }"
    echo "    h1 { color: #4B286D; text-align: center; }"
    echo "    h2 { color: #4B286D; text-align: center; margin-top: 40px; }"
    echo "    .footer { text-align: center; padding: 20px; color: #4B286D; border-top: 1px solid #ddd; margin-top: 20px; }"
    echo "  </style>"
    echo "</head>"
    echo "<body>"
    echo "  <div class='container'>"
    echo "    <h1>Daily Backup Data Overview - ${REPORT_DATE}</h1>"
} > "${emailFile}"

# Append sections to the email content
appendSection "GCP Backup Information - MySQL" "${queryMySQL}"
appendSection "GCP Backup Information - PostgreSQL" "${queryPGSQL}"
appendSection "GCP Backup Information - MSSQL" "${queryMSSQL}"

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
    echo "Subject: Daily Backup Report - ${REPORT_DATE}"
    echo ""
    cat "${emailFile}"
} | /usr/sbin/sendmail -t

echo "Email sent to yvette.halili@telusinternational.com"
