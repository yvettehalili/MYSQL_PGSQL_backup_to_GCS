#!/bin/bash

# Database Credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="db_legacy_maintenance"

# Date configurations for Jan 2024 - Oct 2024
START_DATE="2024-01-01"
END_DATE="2024-10-31"

# File paths for temporary data storage
BACKUP_DIR="/backup"
DAILY_BACKUP_LOGS_FILE="${BACKUP_DIR}/daily_backup_logs.txt"
REPORT_OUTPUT="${BACKUP_DIR}/backup_report_2024.html"

# SQL Queries
DAILY_BACKUP_LOGS_QUERY="SELECT ldb_date, ldb_server, ldb_size_byte FROM lgm_daily_backup WHERE ldb_date BETWEEN '${START_DATE}' AND '${END_DATE}';"

# Extract data to file
mysql -u$DB_USER -p$DB_PASS -e "$DAILY_BACKUP_LOGS_QUERY" $DB_NAME > $DAILY_BACKUP_LOGS_FILE

# Initialize data aggregation variables
declare -A backup_status_overview
declare -A storage_utilization

successful_count=0
failed_count=0

# Ensure headers are manually removed
tail -n +2 $DAILY_BACKUP_LOGS_FILE > temp_logs && mv temp_logs $DAILY_BACKUP_LOGS_FILE

# Parse and aggregate data
while IFS=$'\t' read -r DATE SERVER SIZE; do
    # Convert size to GB
    SIZE_GB=$(echo "scale=2; $SIZE / 1073741824" | bc) # 1 GB = 1073741824 bytes
    MONTH=$(date -d "$DATE" +"%Y-%m")

    # Backup status overview
    if (( $(echo "$SIZE == 0" | bc -l) )); then
        ERROR="Yes"
        ((failed_count++))
    else
        ERROR="No"
        ((successful_count++))
        storage_utilization[$MONTH]=$(echo "scale=2; ${storage_utilization[$MONTH]} + $SIZE_GB" | bc)
    fi
done < $DAILY_BACKUP_LOGS_FILE

# Prepare data for charts
storage_utilization_chart="["
for MONTH in "${!storage_utilization[@]}"; do
    storage_utilization_chart+="['$MONTH', ${storage_utilization[$MONTH]}],"
done
storage_utilization_chart=${storage_utilization_chart%?}]  # Remove last comma and close the array

# HTML and JavaScript parts
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
            drawStorageUtilizationChart();
        }

        function drawBackupStatusOverviewChart() {
            var data = google.visualization.arrayToDataTable([
                ['Status', 'Count'],
                ['Successful', ${successful_count}],
                ['Failed', ${failed_count}]
            ]);
            var options = {
                title: 'Backup Status Overview',
                colors: ['#4B286D', '#63A74A'],
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' }
            };
            var chart = new google.visualization.PieChart(document.getElementById('backup_status_overview_chart'));
            chart.draw(data, options);
        }

        function drawStorageUtilizationChart() {
            var data = google.visualization.arrayToDataTable([
                ['Month', 'Storage Utilization (GB)'], ${storage_utilization_chart}
            ]);
            var options = {
                title: 'Storage Utilization (Monthly) from Jan 2024 to Oct 2024',
                colors: ['#63A74A'],
                backgroundColor: '#ffffff',
                titleTextStyle: { color: '#6C77A1' },
                hAxis: { title: 'Month', textStyle: { color: '#4B286D' } },
                vAxis: { title: 'Storage Utilization (GB)', textStyle: { color: '#4B286D' } },
                pointSize: 5,
                curveType: 'function'
            };
            var chart = new google.visualization.LineChart(document.getElementById('storage_utilization_chart'));
            chart.draw(data, options);
        }
    </script>
</head>
<body>
<h1 align='center'>Backup Report - Jan 2024 to Oct 2024</h1>
<p>This report provides an overview of the backup activities from January 2024 to October 2024.</p>

<div class='chart-container'>
    <div id='backup_status_overview_chart' class='chart'></div>
    <div id='storage_utilization_chart' class='chart'></div>
</div>

</body>
</html>"

# Save the HTML report to the file
echo "$HTML_HEAD" > $REPORT_OUTPUT

# Notify user
echo "Backup report has been generated and saved to ${REPORT_OUTPUT}"
