#!/bin/bash

# Maintenance Access
DB_MAINTENANCE="ti_db_inventory"
CUR_DATE=$(date +"%Y-%m-%d")
DIR="backup"

# Create Directory if not exists
mkdir -p "${DIR}"

# Define the function to generate queries
function generateQuery {
        local serverType="${1}"
        local locationConstraint="${2}"

        local queryStr="SELECT @rownum := @rownum + 1 AS No, server AS Server, "
        queryStr+="(CASE WHEN (TRUNCATE((size / 1024), 0) > 0) THEN "
        queryStr+="(CASE WHEN (TRUNCATE(((size / 1024) / 1024), 0) > 0) THEN "
        queryStr+="TRUNCATE(((size / 1024) / 1024), 2) "
        queryStr+="ELSE TRUNCATE((size / 1024), 2) END) "
        queryStr+="ELSE size END) AS size, "
        queryStr+="(CASE WHEN (TRUNCATE((size / 1024), 0) > 0) THEN "
        queryStr+="(CASE WHEN (TRUNCATE(((size / 1024) / 1024), 0) > 0) "
        queryStr+="THEN 'MB' ELSE 'KB' END) ELSE 'B' END) AS size_name, "
        queryStr+="s.location AS Location, s.type AS DB_engine, s.os AS OS, "
        queryStr+="CASE WHEN size > 0 THEN 'No' ELSE 'Yes' END AS Error "
        queryStr+="FROM daily_log b "
        queryStr+="JOIN servers s ON s.name = b.server, "
        queryStr+="(SELECT @rownum := 0) r "
        queryStr+="WHERE backup_date = CAST(NOW() AS DATE) ${locationConstraint} AND s.type='${serverType}'"
        queryStr+="ORDER BY s.type DESC; "

        echo "${queryStr}"
}

# Clear the terminal screen
clear

# Generate Queries
queryMySQL=$(generateQuery "MYSQL" "AND location='GCP'")
queryPOSQL=$(generateQuery "POSQL" "AND location='GCP'")
queryMSSQL=$(generateQuery "MSSQL" "AND location='GCP'")

# Email Content
emailFile="${DIR}/yvette_email_notification.txt"
{
        echo "To: yvette.halili@telusinternational.com"
        echo "From: no-reply@telusinternational.com"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=utf-8"
        echo "Subject: Daily Backup Report - ${CUR_DATE}"

        echo "<!DOCTYPE html>"
        echo "<html lang='en'>"
        echo "<head>"
        echo "<style>"

        echo "body {"
        echo "  font-family: 'Segoe UI', Arial, sans-serif;"
        echo "  background-color: #f4f4f4;"
        echo "  margin: 0;"
        echo "  padding: 20px;"
        echo "}"

        echo "h1, h2 {"
        echo "  margin: 0 0 10px;"
        echo "  padding-bottom: 5px;"
        echo "  border-bottom: 2px solid #4B286D;" # Telus Purple
        echo "}"

        echo "h1 { color: #4B286D; }" # Telus Purple
        echo "h2 { color: #6C77A1; }" # Telus Secondary Purple

        echo "table {"
        echo "  width: 100%;"
        echo "  border-collapse: collapse;"
        echo "  background-color: #fff;"
        echo "  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
        echo "  margin-bottom: 20px;"
        echo "}"

        echo "th {"
        echo "  background-color: #4B286D;"
        echo "  color: #ffffff;"
        echo "  padding: 15px;"
        echo "  font-weight: normal;"
        echo "  text-transform: uppercase;"
        echo "}"

        echo "td {"
        echo "  padding: 10px;"
        echo "  text-align: left;"
        echo "  border-bottom: 1px solid #ddd;"
        echo "  transition: background-color 0.3s;"
        echo "}"

        echo "tr:nth-child(even) {"
        echo "  background-color: #f9f9f9;" # Very light grey for even rows
        echo "}"

        echo "tr:hover {"
        echo "  background-color: #e1e1e1;" # A more pronounced grey for row hover
        echo "}"

        echo "</style>"
        echo "</head>"
        echo "<body>"
} > "${emailFile}"

# Header
echo " <h1 align=\"center\">Daily Backup Report ${CUR_DATE}</h1>" >> "${emailFile}"

# GCP Backup Information - MYSQL
echo "<h1>GCP Backup Information - MYSQL</h1>" >> "${emailFile}"
mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryMySQL}" >> "${emailFile}"

# GCP Backup Information - POSTGRES
echo "<h1>GCP Backup Information - POSTGRES</h1>" >> "${emailFile}"
mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryPOSQL}" >> "${emailFile}"

# GCP Backup Information - MSSQL
echo "<h1>GCP Backup Information - MSSQL</h1>" >> "${emailFile}"
mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -H -e "${queryMSSQL}" >> "${emailFile}"

# Close HTML Tags
echo "</body></html>" >> "${emailFile}"

# Send Email
/usr/sbin/ssmtp -t < "${emailFile}"
