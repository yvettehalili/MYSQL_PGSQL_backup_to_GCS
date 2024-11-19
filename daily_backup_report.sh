#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="ti_db_inventory"
REPORT_DATE=$(date '+%Y-%m-%d')  # Automatically set the report date to the current date
DIR="backup"

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
    queryStr+="ELSE SUM(b.size) END) AS size, "
    queryStr+="(CASE WHEN (TRUNCATE((SUM(b.size) / 1024), 0) > 0) THEN "
    queryStr+="(CASE WHEN (TRUNCATE(((SUM(b.size) / 1024) / 1024), 0) > 0) "
    queryStr+="THEN 'MB' ELSE 'KB' END) ELSE 'B' END) AS size_name, "
    queryStr+="s.location AS Location, s.type AS DB_engine, s.os AS OS "
    queryStr+="FROM daily_log b "
    queryStr+="JOIN servers s ON s.name = b.server "
    queryStr+="WHERE b.backup_date = '${REPORT_DATE}' ${locationConstraint} AND s.type='${serverType}' "
    queryStr+="GROUP BY b.server, s.location, s.type, s.os;"

    echo "${queryStr}"
}

# Function to append section to email content with graphical chart
appendSection() {
    local title="${1}"
    local query="${2}"

    echo "Appending section: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    {
        echo "    <h2 style='margin-top: 40px; border-bottom: 1px solid #4B286D; padding-bottom: 10px; color: #00C853;'>${title}</h2>"
        mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r Server size size_name Location DB_engine OS; do
            sizeValue=0
            unit="B"
            if [[ "${size_name}" == "MB" ]]; then
                sizeValue="$(echo ${size} | awk '{print $1}')"
                unit="MB"
            elif [[ "${size_name}" == "KB" ]]; then
                sizeValue="$(echo ${size} | awk '{print $1/1024}')"
                unit="KB"
            fi

            # Set maximum size for scaling (assuming MSSQL has the largest size for demonstration)
            maxSize_MB=24837.58
            percentage=$(echo "${sizeValue}" | awk -v maxSize_MB="${maxSize_MB}" '{print ($1 / maxSize_MB) * 100}')
            
            echo "    <div style='display: flex; align-items: center; margin-bottom: 20px;'>"
            echo "      <div style='flex: 1; margin-right: 10px; font-weight: bold; color: #4B286D;'>${Server}</div>"
            echo "      <div style='width: 100%; max-width: 600px; height: 30px; background-color: #ddd; border-radius: 10px; overflow: hidden; border: 1px solid #00C853; position: relative;'>"
            echo "        <div style='height: 100%; border-radius: 10px; padding: 0 10px; color: white; line-height: 30px; transition: width 0.3s; display: flex; align-items: center; justify-content: flex-end; font-weight: bold; background-color: #4B286D; width: ${percentage}%;'><span style='position: absolute; right: 10px;'>${sizeValue} ${unit}</span></div>"
            echo "      </div>"
            echo "    </div>"
        done
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
    echo "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
    echo "  <title>Daily Backup Data Overview</title>"
    echo "  <style>"
    echo "    body { font-family: Arial, sans-serif; background-color: #f4f4f4; color: #333; margin: 0; padding: 20px; }"
    echo "    .container { max-width: 800px; margin: 0 auto; padding: 20px; background-color: #fff; border: 1px solid #ddd; border-radius: 10px; }"
    echo "    h1 { color: #4B286D; text-align: center; }"
    echo "    h2 { color: #4B286D; }"
    echo "    .footer { text-align: center; padding: 20px; color: #4B286D; border-top: 1px solid #ddd; margin-top: 20px; }"
    echo "  </style>"
    echo "</head>"
    echo "<body>"
    echo "  <div class='container'>"
    echo "    <h1>Daily Backup Data Overview - ${REPORT_DATE}</h1>"
} > "${emailFile}"

# Append sections to the email content
appendSection "GCP Backup Information - MYSQL" "${queryMySQL}"
appendSection "GCP Backup Information - PGSQL" "${queryPGSQL}"
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

# Display Email Content File's Path for Debug
echo "Email content generated at: ${emailFile}"
echo "Log file generated at: ${LOG_FILE}"

# Send Email via sendmail
{
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: [Test - susweyak17] Daily Backup Report - ${REPORT_DATE}"
    echo ""
    Report generated by Database Engineering</p>"
    echo "    </div>"
    echo "  </div>"
    echo "</body>"
    echo "</html>"
} >> "${emailFile}"

# Display Email Content File's Path for Debug
echo "Email content generated at: ${emailFile}"
echo "Log file generated at: ${LOG_FILE}"

# Send Email via sendmail
{
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: [Test - susweyak17] Daily Backup Report - ${REPORT_DATE}"
    echo ""
    cat "${emailFile}"
} | /usr/sbin/sendmail -t

echo "Email sent to yvette.halili@telusinternational.com"

# Uncomment to print email file for debugging
# cat "${emailFile}"
