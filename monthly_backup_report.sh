#!/bin/bash

# Database credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="db_legacy_maintenance"

# Date configurations
CUR_DATE=$(date +"%Y-%m-%d")
CUR_MONTH=$(date +"%Y-%m")

# File paths
BACKUP_DIR="/backup"
ACTIVE_SERVERS_FILE="${BACKUP_DIR}/active_servers.txt"
BACKUP_LOGS_FILE="${BACKUP_DIR}/backup_logs.txt"
REPORT_OUTPUT="${BACKUP_DIR}/${CUR_MONTH}_backup_report.html"

# SQL Queries
ACTIVE_SERVERS_QUERY="SELECT srv_name, srv_os, srv_frecuency, srv_location, srv_type FROM lgm_servers WHERE srv_active = 1;"
BACKUP_LOGS_QUERY="SELECT lbl_date, lbl_server, lbl_size_byte, lbl_filename FROM lgm_backups_log WHERE lbl_date LIKE '${CUR_MONTH}%';"

# Extract data to files
mysql -u$DB_USER -p$DB_PASS -e "$ACTIVE_SERVERS_QUERY" $DB_NAME > $ACTIVE_SERVERS_FILE
mysql -u$DB_USER -p$DB_PASS -e "$BACKUP_LOGS_QUERY" $DB_NAME > $BACKUP_LOGS_FILE

# Initialize data aggregation variables
data_growth=""
backup_frequency=""
error_rate=""
successful_count=0
failed_count=0
week_counts=()

# Initialize HTML report content
HTML_HEAD="
<!DOCTYPE html>
<html lang='en'>
<head>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            background-color: #f4f4f4;
            margin: 0;
            padding: 20px;
        }
        h1, h2 {
            margin: 0 0 10px;
            padding-bottom: 5px;
            border-bottom: 2px solid #4B286D;
        }
        h1 { color: #4B286D; }
        h2 { color: #6C77A1; }
        table {
            width: 100%;
            border-collapse: collapse;
            background-color: #fff;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #4B286D;
            color: #ffffff;
            text-transform: uppercase;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:hover {
            background-color: #e1e1e1;
        }
        .chart-container {
            display: flex;
            justify-content: space-around;
            flex-wrap: wrap;
        }
        .chart {
            width: 45%;
            min-width: 300px;
            height: 400px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            background-color: #fff;
            padding: 20px;
            border-radius: 10px;
        }
    </style>
    <script type='text/javascript' src='https://www.gstatic.com/charts/loader.js'></script>
    <script type='text/javascript'>
        google.charts.load('current', {'packages':['corechart']});
        google.charts.setOnLoadCallback(drawCharts);

        function drawCharts() {
            drawBackupStatusOverviewChart();
            drawDataGrowthOverTimeChart();
            drawBackupFrequencyChart();
            drawErrorRateChart();
        }

        function drawBackupStatusOverviewChart() {
            var data = google.visualization.arrayToDataTable([
                ['Status', 'Count'],
                ['Successful', $successful_count],
                ['Failed', $failed_count]
            ]);
            var options = {
                title: 'Backup Status Overview',
                colors: ['#4B286D', '#E74C3C'], /* Purple for successful, red for failed */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' }
            };
            var chart = new google.visualization.PieChart(document.getElementById('backup_status_overview_chart'));
            chart.draw(data, options);
        }

        function drawDataGrowthOverTimeChart() {
            var data = google.visualization.arrayToDataTable([
                ['Date', 'Data Growth'],
                $data_growth
            ]);
            var options = {
                title: 'Data Growth Over Time',
                colors: ['#63A74A'], /* Light green for data growth */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                hAxis: { title: 'Date', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Size (MB)', textStyle: { color: '#4B286D' } }
            };
            var chart = new google.visualization.LineChart(document.getElementById('data_growth_over_time_chart'));
            chart.draw(data, options);
        }

        function drawBackupFrequencyChart() {
            var data = google.visualization.arrayToDataTable([
                ['Week', 'Backups'],
                $backup_frequency
            ]);
            var options = {
                title: 'Backup Frequency',
                colors: ['#4B286D'],
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                hAxis: { title: 'Week', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Number of Backups', textStyle: { color: '#4B286D' } },
                bar: { groupWidth: '75%' }
            };
            var chart = new google.visualization.ColumnChart(document.getElementById('backup_frequency_chart'));
            chart.draw(data, options);
        }

        function drawErrorRateChart() {
            var data = google.visualization.arrayToDataTable([
                ['Date', 'Errors'],
                $error_rate
            ]);
            var options = {
                title: 'Error Rate',
                colors: ['#E74C3C'], /* Red for errors */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                hAxis: { title: 'Date', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Number of Errors', textStyle: { color: '#4B286D' } },
                isStacked: true
            };
            var chart = new google.visualization.ColumnChart(document.getElementById('error_rate_chart'));
            chart.draw(data, options);
        }
    </script>
</head>
<body>
<h1 align='center'>Monthly Backup Report - ${CUR_MONTH}</h1>
<p>This report provides an overview of the backup activities for the month of ${CUR_MONTH}.</p>

<div class='chart-container'>
    <div id='backup_status_overview_chart' class='chart'></div>
    <div id='data_growth_over_time_chart' class='chart'></div>
    <div id='backup_frequency_chart' class='chart'></div>
    <div id='error_rate_chart' class='chart'></div>
</div>

<table border='1'>
    <tr>
        <th>No</th>
        <th>Server</th>
        <th>OS</th>
        <th>Frequency</th>
        <th>Location</th>
        <th>DB Engine</th>
        <th>Size (Bytes)</th>
        <th>Date</th>
        <th>Filename</th>
        <th>Error</th>
    </tr>"

HTML_BODY_CONTENTS=""

# Read data from extracted files and compile report data
count=1

while IFS= read -r SERVER_NAME OS FREQUENCY LOCATION TYPE; do
    grep "$SERVER_NAME" $BACKUP_LOGS_FILE | while IFS=$'\t' read -r DATE SERVER SIZE FILENAME; do
        ERROR="No"
        
        if [[ -z "$SIZE" || "$SIZE" == "0" ]]; then
            ERROR="Yes"
            ((failed_count++))
            error_rate+="['$DATE', 1],"
        else
            ((successful_count++))
            error_rate+="['$DATE', 0],"
        fi

        data_growth+="['$DATE', $SIZE],"
        week_num=$(date -d "$DATE" +"%U")
        [[ -z ${week_counts[$week_num]} ]] && week_counts[$week_num]=0
        ((week_counts[$week_num]++))

        HTML_BODY_CONTENTS+="<tr>
            <td>$count</td>
            <td>$SERVER_NAME</td>
            <td>$OS</td>
            <td>$FREQUENCY</td>
            <td>$LOCATION</td>
            <td>$TYPE</td>
            <td>$SIZE</td>
            <td>$DATE</td>
            <td>$FILENAME</td>
            <td>${ERROR}</td>
        </tr>"
        ((count++))
    done
done < <(tail -n +2 $ACTIVE_SERVERS_FILE)

for week_num in "${!week_counts[@]}"; do
    backup_frequency+="['Week $week_num', ${week_counts[$week_num]}],"
done

# Finalize the HTML report content
HTML_REPORT="${HTML_HEAD}
${HTML_BODY_CONTENTS}
</table>
<h2>Backup Summary</h2>
<p>Successful Backups: ${successful_count}</p>
<p>Failed Backups: ${failed_count}</p>
</body>
</html>"

# Save the HTML report to file
echo "$HTML_REPORT" > $REPORT_OUTPUT

# Notify user
echo "Monthly backup report has been generated and saved to ${REPORT_OUTPUT}"
"""

# Save the HTML report
echo -e "$HTML_REPORT" > $REPORT_OUTPUT

# Notify user
echo "Monthly backup report has been generated and saved to ${REPORT_OUTPUT}"
