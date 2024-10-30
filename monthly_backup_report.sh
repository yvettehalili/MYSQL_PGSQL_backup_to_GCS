#!/bin/bash

# Database Credentials
DB_USER="trtel.backup"
DB_PASS="Telus2017#"
DB_NAME="db_legacy_maintenance"

# Date configurations for October 2024
START_DATE="2024-10-01"
END_DATE="2024-10-31"

# File paths for temporary data storage
BACKUP_DIR="/backup"
DAILY_BACKUP_LOGS_FILE="${BACKUP_DIR}/daily_backup_logs.txt"
REPORT_OUTPUT="${BACKUP_DIR}/october_2024_backup_report.html"

# SQL Queries
DAILY_BACKUP_LOGS_QUERY="SELECT ldb_date, ldb_server, ldb_size_byte FROM lgm_daily_backup WHERE ldb_date BETWEEN '${START_DATE}' AND '${END_DATE}';"

# Extract data to file
mysql -u$DB_USER -p$DB_PASS -e "$DAILY_BACKUP_LOGS_QUERY" $DB_NAME > $DAILY_BACKUP_LOGS_FILE

# Initialize data aggregation variables
declare -A backup_status_overview
declare -A data_growth_over_time
declare -A backup_frequency
declare -A error_rate

successful_count=0
failed_count=0
total_storage=0

# Ensure headers are manually removed
tail -n +2 $DAILY_BACKUP_LOGS_FILE > temp_logs && mv temp_logs $DAILY_BACKUP_LOGS_FILE

# Iterate over each line to process data
while IFS=$'\t' read -r DATE SERVER SIZE; do
    ERROR="No"
    
    # Convert SIZE to MB
    SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
    
    # Check if Size is 0 to determine error
    if (( $(echo "$SIZE == 0" |bc -l) )); then
        ERROR="Yes"
        ((failed_count++))
        error_rate[$DATE]=$((error_rate[$DATE]+1))
    else
        ((successful_count++))
        data_growth_over_time[$DATE]=$((data_growth_over_time[$DATE]+SIZE_MB))
        total_storage=$((total_storage + SIZE_MB))
    fi
    
    # Get week number to append to backup_frequency
    week_num=$(date -d "$DATE" +"%U")
    backup_frequency[$week_num]=$((backup_frequency[$week_num]+1))

done < $DAILY_BACKUP_LOGS_FILE

# Prepare data for Charts
data_growth_chart="["
for DATE in "${!data_growth_over_time[@]}"; do
    data_growth_chart+="['$DATE', ${data_growth_over_time[$DATE]}],"
done
data_growth_chart+="]"

backup_frequency_chart="["
for WEEK in "${!backup_frequency[@]}"; do
    backup_frequency_chart+="['Week $WEEK', ${backup_frequency[$WEEK]}],"
done
backup_frequency_chart+="]"

error_rate_chart="["
for DATE in "${!error_rate[@]}"; do
    error_rate_chart+="['$DATE', ${error_rate[$DATE]}],"
done
error_rate_chart+="]"

# HTML and JavaScript Parts
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
            drawDataGrowthOverTimeChart();
            drawBackupFrequencyChart();
            drawErrorRateChart();
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

        function drawDataGrowthOverTimeChart() {
            var data = google.visualization.arrayToDataTable([
                ['Date', 'Data Growth (MB)'], ${data_growth_chart}
            ]);
            var options = {
                title: 'Data Growth Over Time',
                colors: ['#63A74A'],
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
                ['Week', 'Backups'], ${backup_frequency_chart}
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
                ['Date', 'Errors'], ${error_rate_chart}
            ]);
            var options = {
                title: 'Error Rate',
                colors: ['#E74C3C'],
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
<h1 align='center'>Monthly Backup Report - October 2024</h1>
<p>This report provides an overview of the backup activities for the month of October 2024.</p>

<div class='chart-container'>
    <div id='backup_status_overview_chart' class='chart'></div>
    <div id='data_growth_over_time_chart' class='chart'></div>
    <div id='backup_frequency_chart' class='chart'></div>
    <div id='error_rate_chart' class='chart'></div>
</div>

</body>
</html>"

# Save the HTML report to the file
echo "$HTML_HEAD" > $REPORT_OUTPUT

# Notify user
echo "Monthly backup report has been generated and saved to ${REPORT_OUTPUT}"
