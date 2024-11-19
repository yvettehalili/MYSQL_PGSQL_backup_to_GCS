#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="ti_db_inventory"
REPORT_DATE=$(date '+%Y-%m-%d')  # Automatically set to the current date
DIR="backup"
MAX_SIZE_MB=30720  # Maximum size in MB for scaling (30GB)

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
    queryStr+="ELSE SUM(b.size) END) AS size_MB, "
    queryStr+="s.location AS Location, s.type AS DB_engine, s.os AS OS "
    queryStr+="FROM daily_log b "
    queryStr+="JOIN servers s ON s.name = b.server "
    queryStr+="WHERE b.backup_date = '${REPORT_DATE}' ${locationConstraint} AND s.type='${serverType}' "
    queryStr+="GROUP BY b.server, s.location, s.type, s.os;"

    echo "${queryStr}"
}

# Function to fetch data and return as JavaScript array
fetchData() {
    local title="${1}"
    local query="${2}"
    local dataVarName="${3}"

    echo "Fetching data: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    echo "var ${dataVarName} = google.visualization.arrayToDataTable([" >> "${emailFile}";
    echo "  ['Instance', 'Backup Size (MB)']," >> "${emailFile}";
    mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r Server size_MB Location DB_engine OS; do
        sizeValue="$(echo ${size_MB} | awk '{print $1}')"
        echo "  ['${Server}', ${sizeValue}]," >> "${emailFile}"
    done
    echo "]);" >> "${emailFile}"

    if [[ $? -ne 0 ]]; then
        echo "Query execution failed for: ${title}" >> "${LOG_FILE}"
    else
        echo "Query executed successfully for: ${title}" >> "${LOG_FILE}"
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
    echo "To: yvette.halili@telusinternational.com"
    echo "From: no-reply@telusinternational.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=utf-8"
    echo "Subject: Daily Backup Report - ${REPORT_DATE}"
    echo ""
    echo "<!DOCTYPE html>"
    echo "<html lang='en'>"
    echo "<head>"
    echo "    <style>"
    echo "        body { font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }"
    echo "        h1, h2 { margin: 0 0 10px; padding-bottom: 5px; border-bottom: 2px solid #4B286D; }"
    echo "        h1 { color: #4B286D; } /* Telus Purple */"
    echo "        h2 { color: #6C77A1; } /* Telus Secondary Purple */"
    echo "        .chart-container { display: flex; justify-content: space-around; flex-wrap: wrap; }"
    echo "        .chart { width: 45%; min-width: 300px; height: 400px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); background-color: #fff; padding: 20px; border-radius: 10px; }"
    echo "    </style>"
    echo "    <script type='text/javascript' src='https://www.gstatic.com/charts/loader.js'></script>"
    echo "    <script type='text/javascript'>"
    echo "        google.charts.load('current', {'packages':['corechart']});"
    echo "        google.charts.setOnLoadCallback(drawCharts);"
    echo ""
    echo "        function drawCharts() {"
    echo "            drawMySQLChart();"
    echo "            drawPGSQLChart();"
    echo "            drawMSSQLChart();"
    echo "        }"
    echo ""
    echo "        function drawMySQLChart() {"
    echo "            $(dataMySQL)"
    echo "            var options = {"
    echo "                title: 'Total Size of Backups per Instance (MySQL)',"
    echo "                colors: ['#4B286D'],"
    echo "                backgroundColor: '#ffffff',"
    echo "                titleTextStyle: { color: '#6C77A1' },"
    echo "                legend: { position: 'bottom' },"
    echo "                hAxis: { title: 'Instance', textStyle: { color: '#4B286D' }, slantedText: true, slantedTextAngle: 45 },"
    echo "                vAxis: { title: 'Backup Size (MB)', textStyle: { color: '#4B286D' }, viewWindowMode: 'explicit', viewWindow: { max: ${MAX_SIZE_MB} } }"
    echo "            };"
    echo "            var chart = new google.visualization.ColumnChart(document.getElementById('chart_mysql'));"
    echo "            chart.draw(dataMySQL, options);"
    echo "        }"
    echo ""
    echo "        function drawPGSQLChart() {"
    echo "            $(dataPGSQL)"
    echo "            var options = {"
    echo "                title: 'Total Size of Backups per Instance (PostgreSQL)',"
    echo "                colors: ['#4B286D'],"
    echo "                backgroundColor: '#ffffff',"
    echo "                titleTextStyle: { color: '#6C77A1' },"
    echo "                legend: { position: 'bottom' },"
    echo "                hAxis: { title: 'Instance', textStyle: { color: '#4B286D' }, slantedText: true, slantedTextAngle: 45 },"
    echo "                vAxis: { title: 'Backup Size (MB)', textStyle: { color: '#4B286D' }, viewWindowMode: 'explicit', viewWindow: { max: ${MAX_SIZE_MB} } }"
    echo "            };"
    echo "            var chart = new google.visualization.ColumnChart(document.getElementById('chart_pgsql'));"
    echo "            chart.draw(dataPGSQL, options);"
    echo "        }"
    echo ""
    echo "        function drawMSSQLChart() {"
    echo "            $(dataMSSQL)"
    echo "            var options = {"
    echo "                title: 'Total Size of Backups per Instance (MSSQL)',"
    echo "                colors: ['#4B286D'],"
    echo "                backgroundColor: '#ffffff',"
    echo "                titleTextStyle: { color: '#6C77A1' },"
    echo "                legend: { position: 'bottom' },"
    echo "                hAxis: { title: 'Instance', textStyle: { color: '#4B286D' }, slantedText: true, slantedTextAngle: 45 },"
    echo "                vAxis: { title: 'Backup Size (MB)', textStyle: { color: '#4B286D' }, viewWindowMode: 'explicit', viewWindow: { max: ${MAX_SIZE_MB} } }"
    echo "            };"
    echo "            var chart = new google.visualization.ColumnChart(document.getElementById('chart_mssql'));"
    echo "            chart.draw(dataMSSQL, options);"
    echo "        }"
    echo "    </script>"
} > "${emailFile}"

# Fetch data and create JavaScript data variables
fetchData "GCP Backup Information - MySQL" "${queryMySQL}" "dataMySQL"
fetchData "GCP Backup Information - PostgreSQL" "${queryPGSQL}" "dataPGSQL"
fetchData "GCP Backup Information - MSSQL" "${queryMSSQL}" "dataMSSQL"

# Close Email Content
{
    echo "</head>"
    echo "<body>"
    echo "<h1 align='center'>Daily Backup Report - ${REPORT_DATE}</h1>"
    echo "<p>This report provides an overview of the backup activities for the date ${REPORT_DATE}.</p>"
    echo "<div class='chart-container'>"
    echo "    <div id='chart_mysql' class='chart'></div>"
    echo "    <div id='chart_pgsql' class='chart'></div>"
    echo "    <div id='chart_mssql' class='chart'></div>"
    echo "</div>"
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

