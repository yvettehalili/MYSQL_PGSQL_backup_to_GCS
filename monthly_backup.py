import os
import datetime
import subprocess
import mysql.connector
import matplotlib.pyplot as plt
import base64

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

# Chart Images
STATUS_CHART_IMAGE = os.path.join(BACKUP_DIR, "status_chart.png")
UTILIZATION_CHART_IMAGE = os.path.join(BACKUP_DIR, "utilization_chart.png")

# SQL Query to include the state field
DAILY_BACKUP_LOGS_QUERY = f"""
SELECT backup_date, server, size, state
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
    DATE, SERVER, SIZE, STATE = row
    DATE = str(DATE)

    # Strip the time part correctly and keep the date only
    DATE_ONLY = DATE.split(" ")[0]

    # Validate SIZE is numeric and not null
    if SIZE and isinstance(SIZE, (int, float)):
        MONTH = datetime.datetime.strptime(DATE_ONLY, "%Y-%m-%d").strftime("%Y-%m")

        # Sum storage per month
        storage_utilization[MONTH] = storage_utilization.get(MONTH, 0) + SIZE

        # Backup status overview checking state
        if STATE == "Completed":
            successful_count += 1
        elif STATE == "Error":
            failed_count += 1
    else:
        print(f"Warning: Invalid SIZE value encountered: {SIZE} on {DATE} for {SERVER}")

# Generate and save the Backup Status Overview chart
plt.figure(figsize=(6, 6))
labels = ['Successful', 'Failed']
sizes = [successful_count, failed_count]
colors = ['#4B286D', '#E53935']
plt.pie(sizes, labels=labels, colors=colors, autopct='%1.1f%%', startangle=140)
plt.title('Backup Status Overview')
plt.savefig(STATUS_CHART_IMAGE)
plt.close()

# Generate and save the Storage Utilization chart
months = ["2024-01", "2024-02", "2024-03", "2024-04", "2024-05", "2024-06", "2024-07", "2024-08", "2024-09", "2024-10", "2024-11"]
utilization_gb = [round(storage_utilization.get(month, 0) / 1073741824, 2) for month in months]

plt.figure(figsize=(10, 6))
plt.plot(months, utilization_gb, marker='o', color='#63A74A')
plt.title('Storage Utilization (Monthly) from Jan 2024 to Nov 2024')
plt.xlabel('Month')
plt.ylabel('Storage Utilization (GB)')
plt.grid(True)
plt.savefig(UTILIZATION_CHART_IMAGE)
plt.close()

# Helper function to read and encode image to base64
def encode_image_to_base64(image_path):
    with open(image_path, 'rb') as img_file:
        return base64.b64encode(img_file.read()).decode('utf-8')

# HTML for report with embedded images
HTML_HEAD = f"""
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Backup Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }}
        h1, h2 {{ margin: 0 0 10px; padding-bottom: 5px; border-bottom: 2px solid #4B286D; }}
        h1 {{ color: #4B286D; }}
        h2 {{ color: #6C77A1; }}
        .chart-container {{ display: flex; justify-content: space-around; flex-wrap: wrap; }}
        .chart {{ width: 45%; min-width: 300px; height: 400px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); background-color: #fff; padding: 20px; border-radius: 10px; }}
        img {{ width: 100%; height: auto; }}
    </style>
</head>
<body>
<h1 align='center'>Backup Report - Jan 2024 to Nov 2024</h1>
<p>This report provides an overview of the backup activities from January 2024 to November 2024.</p>
<div class='chart-container'>
    <div class='chart'>
        <h2>Backup Status Overview</h2>
        <img src="cid:status_chart" alt="Status Chart">
    </div>
    <div class='chart'>
        <h2>Storage Utilization (Monthly)</h2>
        <img src="cid:utilization_chart" alt="Utilization Chart">
    </div>
</div>
</body>
</html>
"""

# Save the HTML report to the file
with open(REPORT_OUTPUT, 'w') as file:
    file.write(HTML_HEAD)

# Notify user
print(f"Backup report has been generated and saved to {REPORT_OUTPUT}")

# Read the HTML report into a string for email
with open(REPORT_OUTPUT, 'r') as file:
    html_report_content = file.read()

# Send Email using ssmtp
def send_email():
    email_recipient = "yvette.halili@telusinternational.com"
    email_subject = "November 2024 Backup Report"
    
    # Email boundary to separate parts
    boundary = "===============123456789=="

    # Email headers with multipart content type
    email_headers = f"""To: {email_recipient}
From: no-reply@telusinternational.com
Subject: {email_subject}
MIME-Version: 1.0
Content-Type: multipart/related; boundary="{boundary}"

--{boundary}
Content-Type: text/html; charset="UTF-8"

{html_report_content}

--{boundary}
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-ID: <status_chart>

{encode_image_to_base64(STATUS_CHART_IMAGE)}

--{boundary}
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-ID: <utilization_chart>

{encode_image_to_base64(UTILIZATION_CHART_IMAGE)}
--{boundary}--
"""

    # Execute ssmtp command
    try:
        process = subprocess.Popen(['/usr/sbin/sendmail', '-t'], stdin=subprocess.PIPE)
        process.communicate(email_headers.encode('utf-8'))
        print(f"Email sent to {email_recipient}")
    except Exception as e:
        print(f"Failed to send email: {e}")

send_email()

# Close DB connection
cursor.close()
db_conn.close()

