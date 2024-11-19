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
    local locationConstraint="${1}"

    local queryStr="SELECT s.type AS DBType, b.server AS Server, "
    queryStr+="(CASE WHEN (TRUNCATE((SUM(b.size) / 1024), 0) > 0) THEN "
    queryStr+="(CASE WHEN (TRUNCATE(((SUM(b.size) / 1024) / 1024), 0) > 0) THEN "
    queryStr+="TRUNCATE(((SUM(b.size) / 1024) / 1024), 2) "
    queryStr+="ELSE TRUNCATE((SUM(b.size) / 1024), 2) END) "
    queryStr+="ELSE SUM(b.size) END) AS size_MB "
    queryStr+="FROM daily_log b "
    queryStr+="JOIN servers s ON s.name = b.server "
    queryStr+="WHERE b.backup_date = '${REPORT_DATE}' ${locationConstraint} "
    queryStr+="GROUP BY s.type, b.server;"

    echo "${queryStr}"
}

# Function to fetch data and return as JavaScript array
fetchData() {
    local title="${1}"
    local query="${2}"
    local dataVarName="${3}"

    echo "Fetching data: ${title}" >> "${LOG_FILE}"
    echo "Query: ${query}" >> "${LOG_FILE}"

    servers=()
    mysqlSizes=()
    pgsqlSizes=()
    mssqlSizes=()

    mysql --defaults-file=/etc/mysql/my.cnf --defaults-group-suffix=bk -u"${DB_USER}" -p"${DB_PASS}" -D"${DB_NAME}" -e "${query}" --batch --skip-column-names 2>>"${LOG_FILE}" | while IFS=$'\t' read -r DBType Server size_MB; do
        if [[ ! " ${servers[@]} " =~ " ${Server} " ]]; then
            servers+=("${Server}")
            mysqlSizes+=(0)
            pgsqlSizes+=(0)
            mssqlSizes+=(0)
        fi

        index=$(printf '%s\n' "${servers[@]}" | grep -nx "${Server}" | cut -d: -f1 | head -n1)
        index=$((index-1))

        if [[ "${DBType}" == "MYSQL" ]]; then
            mysqlSizes[${index}]=${size_MB}
        elif [[ "${DBType}" == "PGSQL" ]]; then
            pgsqlSizes[${index}]=${size_MB}
        elif [[ "${DBType}" == "MSSQL" ]]; then
            mssqlSizes[${index}]=${size_MB}
        fi
    done

    echo "var ${dataVarName} = google.visualization.arrayToDataTable([" >> "${emailFile}"
    echo "  ['Server', 'MySQL', 'PostgreSQL', 'MSSQL']," >> "${emailFile}"
    for ((i=0; i<${#servers[@]}; i++)); do
        echo "  ['${servers[i]}', ${mysqlSizes[i]}, ${pgsqlSizes[i]}, ${mssqlSizes[i]}]," >> "${emailFile}"
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

# Define the query
query=$(generateQuery "AND s.location='GCP'")

# Log the generated query
echo "Generated Query:" >> "${LOG_FILE}"
echo "${query}" >> "${LOG_FILE}"

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
    echo "        .chart { width: 90%; min-width: 300px; height: 500px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); background-color: #fff; padding: 20px; border-radius: 10px; }"
    echo "    </style>"
    echo "    <script type='text/javascript' src='https://www.gstatic.com/charts/loader.js'></script>"
    echo "    <script type='text/javascript'>"
    echo "        google.charts.load('current', {'packages':['corechart', 'bar']});"
    echo "        google.charts.setOnLoadCallback(drawStacked);"
    echo ""
    echo "        function drawStacked() {"
    echo "            var data = google.visualization.arrayToDataTable([" >> "${emailFile}"

    # Fetch data for the stacked bar chart
    fetchData "Backup Sizes" "${query}" "data"
    
    echo "            ]);"
    echo "            var options = {"
    echo "                title : 'Backup Sizes by Server',"
    echo "                isStacked: true,"
    echo "                height: 500,"
    echo "                legend: {position: 'top', maxLines: 3},"
    echo "                vAxis: {title: 'Server', minValue: 0},"
    echo "                hAxis: {title: 'Backup Size (MB)'},"
    echo "                colors: ['#4B286D', '#6C77A1', '#63A74A'],"
    echo "            };"
    echo "            var chart = new google.visualization.BarChart(document.getElementById('stacked_chart'));"
    echo "            chart.draw(data, options);"
    echo "        }"
    echo "    </script>"
} >> "${emailFile}"

# Close Email Content
{
    echo "</head>"
    echo "<body>"
    echo "<h1 align='center'>Daily Backup Report - ${REPORT_DATE}</h1>"
    echo "<p>This report provides an overview of the backup activities for the date ${REPORT_DATE}.</p>"
    echo "<div class='chart-container'>"
    echo "    <div id='stacked_chart' class='chart'></div>"
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
