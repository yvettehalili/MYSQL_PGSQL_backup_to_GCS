import os
import datetime
import subprocess
import mysql.connector

# Database Credentials
DB_USER = "trtel.backup"
DB_PASS = "Telus2017#"
DB_NAME = "ti_db_inventory"

# Date configurations
START_DATE = "2024-01-01"
END_DATE = "2024-11-30"

# File paths for temporary data storage
BACKUP_DIR = "/backup"
DAILY_BACKUP_LOGS_FILE = os.path.join(BACKUP_DIR, "daily_backup_logs.txt")
REPORT_OUTPUT = os.path.join(BACKUP_DIR, "backup_report_2024.html")

# SQL Query
DAILY_BACKUP_LOGS_QUERY = f"""
SELECT backup_date, server, size 
FROM daily_log 
WHERE backup_date BETWEEN '{START_DATE}' AND '{END_DATE}';
"""

# Connect to MySQL
db_conn = mysql.connector.connect(
    host="localhost",
    user=DB_USER,
    password=DB_PASS,
    database=DB_NAME
)
cursor = db_conn.cursor()
cursor.execute(DAILY_BACKUP_LOGS_QUERY)
data = cursor.fetchall()

# Initialize data aggregation variables
storage_utilization = {}
successful_count = 0
failed_count = 0

# Function to parse and aggregate data
for row in data:
    DATE, SERVER, SIZE = row
    DATE = str(DATE)

    # Strip the time part correctly and keep the date only
    DATE_ONLY = DATE.split(" ")[0]

    # Validate SIZE is numeric and not null
    if SIZE and isinstance(SIZE, (int, float)):
        MONTH = datetime.datetime.strptime(DATE_ONLY, "%Y-%m-%d").strftime("%Y-%m")

        # Sum storage per month
        storage_utilization[MONTH] = storage_utilization.get(MONTH, 0) + SIZE

        # Backup status overview
        if SIZE == 0:
            failed_count += 1
        else:
            successful_count += 1
    else:
        print(f"Warning: Invalid SIZE value encountered: {SIZE} on {DATE} for {SERVER}")

# Prepare data for charts (converting to GB)
storage_utilization_chart = [["Month", "Storage Utilization (GB)"]]
MONTHS = ["2024-01", "2024-02", "2024-03", "2024-04", "2024-05", "2024-06", "2024-07", "2024-08", "2024-09", "2024-10", "2024-11"]
for MONTH in MONTHS:
    STORAGE_BYTES = storage_utilization.get(MONTH, 0)
    # Convert bytes to GB
    STORAGE_GB = round(STORAGE_BYTES / 1073741824, 2)
    storage_utilization_chart.append([MONTH, STORAGE_GB])

# HTML and JavaScript for report
HTML_HEAD = f"""
<!DOCTYPE html>
<html lang='en'>
<head>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }}
        h1, h2 {{ margin: 0 0 10px; padding-bottom: 5px; border-bottom: 2px solid #4B286D; }}
        h1 {{ color: #4B286D; }}
        h2 {{ color: #6C77A1; }}
        .chart-container {{ display: flex; justify-content: space-around; flex-wrap: wrap; }}
        .chart {{ width: 45%; min-width: 300px; height: 400px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); background-color: #fff; padding: 20px; border-radius: 10px; }}
    </style>
    <script type='text/javascript' src='https://www.gstatic.com/charts/loader.js'></script>
    <script type='text/javascript'>
        google.charts.load('current', {{'packages':['corechart']}});
        google.charts.setOnLoadCallback(drawCharts);
        function drawCharts() {{
            drawBackupStatusOverviewChart();
            drawStorageUtilizationChart();
        }}
        function drawBackupStatusOverviewChart() {{
            var data = google.visualization.arrayToDataTable([
                ['Status', 'Count'],
                ['Successful', {successful_count}],
                ['Failed', {failed_count}]
            ]);
            var options = {{
                title: 'Backup Status Overview',
                colors: ['#4B286D', '#63A74A'],
                backgroundColor: '#ffffff',
                titleTextStyle: {{ color: '#6C77A1' }}
            }};
            var chart = new google.visualization.PieChart(document.getElementById('backup_status_overview_chart'));
            chart.draw(data, options);
        }}
        function drawStorageUtilizationChart() {{
            var data = google.visualization.arrayToDataTable({storage_utilization_chart});
            var options = {{
                title: 'Storage Utilization (Monthly) from Jan 2024 to Oct 2024',
                colors: ['#63A74A'],
                backgroundColor: '#ffffff',
                titleTextStyle: {{ color: '#6C77A1' }},
                hAxis: {{ title: 'Month', textStyle: {{ color: '#4B286D' }} }},
                vAxis: {{ title: 'Storage Utilization (GB)', textStyle: {{ color: '#4B286D' }} }},
                pointSize: 5,
                curveType: 'function'
            }};
            var chart = new google.visualization.LineChart(document.getElementById('storage_utilization_chart'));
            chart.draw(data, options);
        }}
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
</html>
"""

# Save the HTML report to the file
with open(REPORT_OUTPUT, 'w') as file:
    file.write(HTML_HEAD)

# Notify user
print(f"Backup report has been generated and saved to {REPORT_OUTPUT}")

# Read the HTML report into a string
with open(REPORT_OUTPUT, 'r') as file:
    html_report_content = file.read()

# Send Email using ssmtp
def send_email():
    # Configure email header and content
    email_content = f"""
To: yvette.halili@telusinternational.com
From: no-reply@telusinternational.com
MIME-Version: 1.0
Content-Type: text/html; charset=utf-8
Subject: Daily Backup Report - November 2024

{html_report_content}
    """

    # Execute ssmtp command
    try:
        process = subprocess.Popen(['/usr/sbin/sendmail', '-t'], stdin=subprocess.PIPE)
        process.communicate(email_content.encode('utf-8'))
        print("Email sent to yvette.halili@telusinternational.com")
    except Exception as e:
        print(f"Failed to send email: {e}")

send_email()

# Close DB connection
cursor.close()
db_conn.close()

