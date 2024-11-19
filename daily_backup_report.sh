#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="ti_db_inventory"
REPORT_DATE=$(date '+%Y-%m-%d')  # Automatically set the report date to the current date
DIR="backup"

# Create Directory if not exists
mkdir -p "${DIR}"

# Define the function to generate queries
function generateQuery {
    local serverType="${1}"
    local locationConstraint="${2}"

    local queryStr="SELECT @rownum := @rownum + 1 AS No, b.server AS Server, "
    queryStr+="(CASE WHEN (TRUNCATE((SUM(b.size) / 1024), 0) > 0) THEN "
    queryStr+="(CASE WHEN (TRUNCATE(((SUM(b.size) / 1024) / 1024), 0) > 0) THEN "
    queryStr+="TRUNCATE(((SUM(b.size) / 1024) / 1024), 2) "
    queryStr+="ELSE TRUNCATE((SUM(b.size) / 1024), 2) END) "
    queryStr+="ELSE SUM(b.size) END) AS size, "
    queryStr+="(CASE WHEN (TRUNCATE((SUM(b.size) / 1024), 0) > 0) THEN "
    queryStr+="(CASE WHEN (TRUNCATE(((SUM(b.size) / 1024) / 1024), 0) > 0) "
    queryStr+="THEN 'MB' ELSE 'KB' END) ELSE 'B' END) AS size_name, "
    queryStr+="s.location AS Location, s.type AS DB_engine, s.os AS OS, "
    queryStr+="CASE WHEN SUM(b.size) > 0 THEN 'No' ELSE 'Yes' END AS Error "
    queryStr+="FROM daily_log b "
    queryStr+="JOIN servers s ON s.name = b.server, "
    queryStr+="(SELECT @rownum := 0) r "
    queryStr+="WHERE b.backup_date = '${REPORT_DATE}' ${locationConstraint} AND s.type='${serverType}' "
    queryStr+="GROUP BY b.server, s.location, s.type, s.os "
    queryStr+="ORDER BY s.type DESC; "

    echo "${queryStr}"
}

# Function to append section to email content with graphical chart
appendSection() {
    local title="${1}"
    local query="${2}"
    {
        echo "    <h2>${title}</h2>"
        mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -u"${DB_USER}" -p"${DB_PASS}" -e "${query}" --batch --skip-column-names | while IFS=$'\t' read -r No Server size size_name Location DB_engine OS Error; do
            if [[ "${size_name}" == "MB" ]]; then
                sizeValue="$(echo ${size} | awk '{print $1*1}')"
            elif [[ "${size_name}" == "KB" ]]; then
                sizeValue="$(echo ${size} | awk '{print $1/1024}')"
            else
                sizeValue="$(echo ${size} | awk '{print $1/(1024*1024)}')"
            fi

            # Set maximum size for scaling (assuming MSSQL has the largest size for demonstration)
            maxSize_MB=24837.58
            # Scale size to percentage for the chart
            percentage="$(echo "${sizeValue}" | awk -v maxSize_MB="${maxSize_MB}" '{print ($1 / maxSize_MB) * 100}')"
            echo "    <div class='chart'>"
            echo "      <div class='label'>${Server}</div>"
            echo "      <div class='bar'>"
            echo "        <div class='bar-fill' style='width: ${percentage}%;'><span>${size} ${size_name}</span></div>"
            echo "      </div>"
            echo "    </div>"
        done
    } >> "${emailFile}"
}

# Clear the terminal screen
clear

# Generate Queries
queryMySQL=$(generateQuery "MYSQL" "AND s.location='GCP'")
queryPGSQL=$(generateQuery "PGSQL" "AND s.location='GCP'")
queryMSSQL=$(generateQuery "MSSQL" "AND s.location='GCP'")

# Email Content
emailFile="${DIR}/yvette_email_notification.html"
{
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: [Test - susweyak17] Daily Backup Report - ${REPORT_DATE}"

    echo "<!DOCTYPE html>"
    echo "<html lang='en'>"
    echo "<head>"
    echo "  <meta charset='UTF-8'>"
    echo "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
    echo "  <title>Daily Backup Data Overview</title>"
    echo "  <link rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Poppins:wght@600&display=swap'>"
    echo "  <style>"
    echo "    body {"
    echo "      font-family: 'Segoe UI', Arial, sans-serif;"
    echo "      background-color: #f4f4f4;"
    echo "      color: #333;"
    echo "      margin: 0;"
    echo "      padding: 20px;"
    echo "    }"
    echo "    .container {"
    echo "      max-width: 1000px;"
    echo "      margin: 0 auto;"
    echo "      padding: 20px;"
    echo "      background-color: #fff;"
    echo "      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);"
    echo "      border-radius: 15px;"
    echo "      border: 1px solid #ddd;"
    echo "    }"
    echo "    h1, h2 {"
    echo "      font-family: 'Poppins', sans-serif;"
    echo "      margin-bottom: 20px;"
    echo "    }"
    echo "    h1 {"
    echo "      color: #4B286D;"
    echo "      text-align: center;"
    echo "      border-bottom: 2px solid #4B286D;"
    echo "      padding-bottom: 10px;"
    echo "    }"
    echo "    h2 {"
    echo "      margin-top: 40px;"
    echo "      border-bottom: 1px solid #4B286D;"
    echo "      padding-bottom: 10px;"
    echo "      color: #00C853;"
    echo "    }"
    echo "    .chart {"
    echo "      display: flex;"
    echo "      align-items: center;"
    echo "      margin-bottom: 20px;"
    echo "    }"
    echo "    .label {"
    echo "      flex: 1;"
    echo "      margin-right: 10px;"
    echo "      font-weight: bold;"
    echo "      color: #4B286D;"
    echo "    }"
    echo "    .bar {"
    echo "      width: 100%;"
    echo "      max-width: 600px;"
    echo "      height: 30px;"
    echo "      background-color: #ddd;"
    echo "      border-radius: 10px;"
    echo "      overflow: hidden;"
    echo "      border: 1px solid #00C853;"
    echo "      position: relative;"
    echo "    }"
    echo "    .bar .bar-fill {"
    echo "      height: 100%;"
    echo "      border-radius: 10px;"
    echo "      padding: 0 10px;"
    echo "      color: white;"
    echo "      line-height: 30px;"
    echo "      transition: width 0.3s;"
    echo "      display: flex;"
    echo "      align-items: center;"
    echo "      justify-content: flex-end;"
    echo "      font-weight: bold;"
    echo "      background-color: #4B286D;"
    echo "    }"
    echo "    .bar .bar-fill span {"
    echo "      position: absolute;"
    echo "      right: 10px;"
    echo "    }"
    echo "    .footer {"
    echo "      text-align: center;"
    echo "      padding: 20px;"
    echo "      color: #4B286D;"
    echo "      border-top: 1px solid #ddd;"
    echo "      margin-top: 40px;"
    echo "    }"
    echo "    .footer a {"
    echo "      color: #4B286D;"
    echo "      text-decoration: none;"
    echo "      transition: color 0.3s;"
    echo "    }"
    echo "    .footer a:hover {"
    echo "      color: #00C853;"
    echo "    }"
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

# Send Email
/usr/sbin/ssmtp yvette.halili@telusinternational.com < "${emailFile}"
