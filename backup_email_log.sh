#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="ti_db_inventory"
CUR_DATE=$(date +"%Y-%m-%d")
DIR="backup"

function generateQuery {
        local serverType="${1}"
        local locationConstraint="${2}"

        local queryStr="select @rownum := @rownum + 1 AS No, server as Server, "
        queryStr+="(case when (truncate((size / 1024),0) > 0) then "
        queryStr+="(case when (truncate(((size / 1024) / 1024),0) > 0) then "
        queryStr+="truncate(((size / 1024) / 1024),2) "
        queryStr+="else truncate((size / 1024),2) end) "
        queryStr+="else size end) AS size, "
        queryStr+="(case when (truncate((sizee / 1024),0) > 0) then "
        queryStr+="(case when (truncate(((size / 1024) / 1024),0) > 0) "
        queryStr+="then 'MB' else 'KB' end) else 'B' end) AS size_name, "
        queryStr+="s.location Location, s.type DB_engine, s.os OS, "
        queryStr+="case when size > 0 then 'No' else 'Yes' end as Error "
        queryStr+="from daily_log b "
        queryStr+="join servers s on s.name = b.server, "
        queryStr+="(SELECT @rownum := 0) r "
        queryStr+="where backup_date = cast(now() as date) ${locationConstraint} and s.type='${serverType}'"
        queryStr+="order by s.type desc; "

        echo "${queryStr}"
}
# Clear the screen
clear

# Generate Queries

queryMySQL=$(generateQuery "MYSQL" "and location='GCP'")
queryPOSQL=$(generateQuery "POSQL" "and location='GCP'")
queryMSSQL=$(generateQuery "MSSQL" "and location='GCP'")

# Email Content
emailFile="/${DIR}/yvette_email_notification.txt"
{
        echo "To: yvette.halili@telusinternational.com"
        echo "From: no-reply@telusinternational.com"
        echo "MIME-Version: 1.0"
        echo "Content-type: text/html; charset=utf-8"
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

        echo "h1 {color: #4B286D;}" # Telus Purple
        echo "h2 {color: #6C77A1;}" # Telus Secondary Purple

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
echo " <h1 align="center">Daily Backup Report ${CUR_DATE}</h1>" >> "${emailFile}"

# GCP Backup Information - MYSQL
echo "<h1>GCP Backup Information - MYSQL</h1>" >> "${emailFile}"
/usr/bin/mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryMySQL}" >> "${emailFile}"
#mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryMySQL}" >> "${emailFile}"

# GCP Backup Information - POSTGRES
echo "<h1>GCP Backup Information - POSTGRES</h1>" >> "${emailFile}"
/usr/bin/mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryPOSQL}" >> "${emailFile}"
#mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryPOSQL}" >> "${emailFile}"

# GCP Backup Information - MSSQL
echo "<h1>GCP Backup Information - MSSQL</h1>" >> "${emailFile}"
/usr/bin/mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryMSSQL}" >> "${emailFile}"
#mysql --defaults-group-suffix=bk ${DB_MAINTENANCE} -H -e "${queryMSSQL}" >> "${emailFile}"

# Close HTML Tags
echo "</body></html>" >> "${emailFile}"
# Send Email
#ssmtp -t < "${emailFile}"
/usr/sbin/ssmtp -t < "${emailFile}"
