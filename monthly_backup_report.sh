#!/bin/bash

# Maintenance Access
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_MAINTENANCE="db_legacy_maintenance"

# Variables de Entorno
CUR_DATE=$(date +"%Y-%m-%d")
CUR_MONTH=$(date +"%Y-%m")

# Directory to store backup logs
BACKUP_DIR="/backup"
REPORT_FILE="${BACKUP_DIR}/$pastmonth_backup_report.txt"

# Report Output File
REPORT_OUTPUT="${BACKUP_DIR}/monthly_backup_report.html"

# SQL Query to extract monthly data
SQL_QUERY="SELECT ls.srv_name, ls.srv_os, ls.srv_frecuency, ls.srv_location, ls.srv_type, lb.lbl_size_byte, lb.lbl_created_dt
FROM lgm_servers ls
JOIN lgm_backups_log lb ON ls.srv_name = lb.lbl_server
WHERE lb.lbl_created_dt LIKE '${CUR_MONTH}%'
ORDER BY lb.lbl_created_dt;"

# Execute the SQL Query and save the result to a file
mysql -u$DB_USER -p$DB_PASS -e "$SQL_QUERY" $DB_MAINTENANCE > $REPORT_FILE

# Initialize HTML report content
HTML_REPORT="
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

        h1 { color: #4B286D; } /* Telus Purple */
        h2 { color: #6C77A1; } /* Telus Secondary Purple */

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
                ['Successful', 80],  // Example data
                ['Failed', 20]  // Example data
            ]);

            var options = {
                title: 'Backup Status Overview',
                colors: ['#4B286D', '#63A74A'], /* Purple for successful, green for failed */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' }
            };

            var chart = new google.visualization.PieChart(document.getElementById('backup_status_overview_chart'));
            chart.draw(data, options);
        }

        function drawDataGrowthOverTimeChart() {
            var data = google.visualization.arrayToDataTable([
                ['Month', 'Data Growth', 'Total Storage'],
                ['2024-01', 1000, 5000],  // Example data
                ['2024-02', 1200, 6200],  // Example data
                ['2024-03', 900, 7100]  // Example data
            ]);

            var options = {
                title: 'Data Growth Over Time',
                colors: ['#63A74A', '#4B286D'], /* Light green for data growth, purple for total storage */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                legend: { position: 'bottom' },
                hAxis: { title: 'Month', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Size (MB)', textStyle: { color: '#4B286D' } }
            };

            var chart = new google.visualization.LineChart(document.getElementById('data_growth_over_time_chart'));
            chart.draw(data, options);
        }

        function drawBackupFrequencyChart() {
            var data = google.visualization.arrayToDataTable([
                ['Week', 'Backups'],
                ['Week 1', 5],  // Example data
                ['Week 2', 7],  // Example data
                ['Week 3', 6],  // Example data
                ['Week 4', 8]  // Example data
            ]);

            var options = {
                title: 'Backup Frequency',
                colors: ['#4B286D', '#63A74A'], /* Alternating colors */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                legend: { position: 'bottom' },
                hAxis: { title: 'Week', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Number of Backups', textStyle: { color: '#4B286D' } },
                bar: { groupWidth: '75%' }
            };

            var chart = new google.visualization.ColumnChart(document.getElementById('backup_frequency_chart'));
            chart.draw(data, options);
        }

        function drawErrorRateChart() {
            var data = google.visualization.arrayToDataTable([
                ['Month', 'Errors'],
                ['2024-09', 5],  // Previous month, example data
                ['2024-10', 3]  // Current month, example data
            ]);

            var options = {
                title: 'Error Rate',
                colors: ['#4B286D', '#63A74A'], /* Purple for previous months, green for current month */
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                legend: { position: 'bottom' },
                hAxis: { title: 'Month', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Number of Errors', textStyle: { color: '#4B286D' } },
                isStacked: true
            };

            var chart = new google.visualization.ColumnChart(document.getElementById('error_rate_chart'));
            chart.draw(data, options);
        }
    </script>
</head>
<body>

<h1 align='center'>Monthly Backup Report - $CUR_DATE</h1>
<p>This report provides an overview of the backup activities for the month of $CUR_MONTH.</p>

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
        <th>Date Created</th>
    </tr>"
# Read data from extracted report file and append to HTML report
count=1
while IFS=$'\t' read -r srv_name srv_os srv_frecuency srv_location srv_type lbl_size_byte lbl_created_dt; do
    HTML_REPORT+="<tr>
        <td>$count</td>
        <td>$srv_name</td>
        <td>$srv_os</td>
        <td>$srv_frecuency</td>
        <td>$srv_location</td>
        <td>$srv_type</td>
        <td>$lbl_size_byte</td>
        <td>$lbl_created_dt</td>
    </tr>"
    ((count++))
done < $REPORT_FILE

# Close the HTML tags
HTML_REPORT+="
</table>

</body>
</html>
"

# Save the HTML report
echo "$HTML_REPORT" > $REPORT_OUTPUT

# Notify user
echo "Monthly backup report has been generated and saved to $REPORT_OUTPUT"
