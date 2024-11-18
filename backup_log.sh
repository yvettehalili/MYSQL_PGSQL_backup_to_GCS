#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="ti_db_inventory"
REPORT_DATE="2024-11-17"
DIR="/backup"

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

# Clear the terminal screen
clear

# Generate Queries
queryMySQL=$(generateQuery "MYSQL" "AND s.location='GCP'")
queryPGSQL=$(generateQuery "PGSQL" "AND s.location='GCP'")
queryMSSQL=$(generateQuery "MSSQL" "AND s.location='GCP'")

# Email Content
emailFile="${DIR}/yvette_email_notification.txt"
{
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: Daily Backup Report - ${REPORT_DATE}"

    echo "<!DOCTYPE html>"
    echo "<html lang='en'>"
    echo "<head>"
    echo "  <meta charset='UTF-8'>"
    echo "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
    echo "  <title>Daily Backup Report</title>"
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
    echo "      box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);"
    echo "      border-radius: 10px;"
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
    echo "      color: #6C77A1;"
    echo "    }"
    echo "    table {"
    echo "      width: 100%;"
    echo "      border-collapse: collapse;"
    echo "      margin-bottom: 20px;"
    echo "      border-radius: 8px;"
    echo "      overflow: hidden;"
    echo "    }"
    echo "    th {"
    echo "      background-color: #4B286D;"
    echo "      color: #ffffff;"
    echo "      padding: 10px 15px;"
    echo "      text-align: left;"
    echo "      text-transform: uppercase;"
    echo "    }"
    echo "    td {"
    echo "      padding: 10px 15px;"
    echo "      text-align: left;"
    echo "      border-bottom: 1px solid #ddd;"
    echo "      transition: background-color 0.3s;"
    echo "    }"
    echo "    tr:nth-child(even) {"
    echo "      background-color: #f9f9f9;"
    echo "    }"
    echo "    tr:hover {"
    echo "      background-color: #e1e1e1;"
    echo "    }"
    echo "    .footer {"
    echo "      text-align: center;"
    echo "      padding: 10px;"
    echo "      color: #4B286D;"
    echo "      border-top: 1px solid #ddd;"
    echo "      margin-top: 20px;"
    echo "    }"
    echo "    .footer a {"
    echo "      color: #4B286D;"
    echo "      text-decoration: none;"
    echo "      transition: color 0.3s;"
    echo "    }"
    echo "    .footer a:hover {"
    echo "      color: #6C77A1;"
    echo "    }"
    echo "  </style>"
    echo "</head>"
    echo "<body>"
    echo "  <div class='container'>"
    echo "    <h1>Daily Backup Report ${REPORT_DATE}</h1>"
} > "${emailFile}"

# GCP Backup Information - MYSQL
{
    echo "    <h2>GCP Backup Information - MYSQL</h2>"
    echo "    <table>"
    echo "      <tr><th>No</th><th>Server</th><th>Size</th><th>Size Name</th><th>Location</th><th>DB Engine</th><th>OS</th><th>Error</th></tr>"
    mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryMySQL}" | sed '1d; s/$/ <\/tr>/; s/<tr>/\<tr\>\<td>/g; s/<\/td>/<\/td><td>/g; s/<td><\/td>//g'
    echo "    </table>"
} >> "${emailFile}"

# GCP Backup Information - POSTGRES
{
    echo "    <h2>GCP Backup Information - PGSQL</h2>"
    echo "    <table>"
    echo "      <tr><th>No</th><th>Server</th><th>Size</th><th>Size Name</th><th>Location</th><th>DB Engine</th><th>OS</th><th>Error</th></tr>"
    mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryPGSQL}" | sed '1d; s/$/ <\/tr>/; s/<tr>/\<tr\>\<td>/g; s/<\/td>/<\/td><td>/g; s/<td><\/td>//g'
    echo "    </table>"
} >> "${emailFile}"

# GCP Backup Information - MSSQL
{
    echo "    <h2>GCP Backup Information - MSSQL</h2>"
    echo "    <table>"
    echo "      <tr><th>No</th><th>Server</th><th>Size</th><th>Size Name</th><th>Location</th><th>DB Engine</th><th>OS</th><th>Error</th></tr>"
    mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryMSSQL}" | sed '1d; s/$/ <\/tr>/; s/<tr>/\<tr\>\<td>/g; s/<\/td>/<\/td><td>/g; s/<td><\/td>//g'
    echo "    </table>"
    echo "    <div class='footer'>"
    echo "      <p>Report generated by Database Engineering Team</p>"
    echo "    </div>"
    echo "  </div>"
    echo "</body>"
    echo "</html>"
} >> "${emailFile}"

# Send Email
/usr/sbin/ssmtp -t < "${emailFile}"
