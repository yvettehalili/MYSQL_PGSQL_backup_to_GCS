import os
import datetime
import subprocess
import mysql.connector
import matplotlib.pyplot as plt
import numpy as np
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
REPORT_OUTPUT = os.path.join(BACKUP_DIR, "backup_report_2024.html")

# Chart Images
STATUS_CHART_IMAGE = os.path.join(BACKUP_DIR, "status_chart.png")
DATABASE_COUNT_CHART_IMAGE = os.path.join(BACKUP_DIR, "database_count_chart.png")
BACKUP_BY_SERVER_CHART_IMAGE = os.path.join(BACKUP_DIR, "backup_by_server_chart.png")

# SQL Query to include the state field
DAILY_BACKUP_LOGS_QUERY = f"""
SELECT `backup_date`, `server`, `size`, `state`, `database`
FROM `daily_log`
WHERE `backup_date` BETWEEN '{START_DATE}' AND '{END_DATE}';
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
database_backup_counts = {}  # {month: set of (server, database)}
server_backup_counts = {}  # Count backups per server
successful_count = 0
failed_count = 0

# Function to parse and aggregate data
for row in data:
    DATE, SERVER, SIZE, STATE, DATABASE = row
    DATE = str(DATE)

    # Capture the time part correctly and keep the date only
    DATE_ONLY = DATE.split(' ')[0]

    MONTH = datetime.datetime.strptime(DATE_ONLY, '%Y-%m-%d').strftime('%Y-%m')

    # Count unique (server, database) pairs per month
    if MONTH not in database_backup_counts:
        database_backup_counts[MONTH] = set()
    database_backup_counts[MONTH].add((SERVER, DATABASE))
    
    # Count backups per server
    server_backup_counts[SERVER] = server_backup_counts.get(SERVER, 0) + 1

    # Backup status overview checking state
    if STATE.lower() == "completed":
        successful_count += 1
    elif STATE.lower() == "error":
        failed_count += 1

# Convert database count from set to length
database_backup_counts = {month: len(databases) for month, databases in database_backup_counts.items()}

# Generate and save the Backup Status Overview chart
plt.figure(figsize=(10, 6))
labels = ['Successful', 'Failed']
sizes = [successful_count, failed_count]
colors = ['#4B286D', '#63A74A']
plt.pie(sizes, explode=(0.1, 0), labels=labels, colors=colors, autopct='%1.1f%%', startangle=140, shadow=True)
plt.title('Backup Status Overview')
plt.savefig(STATUS_CHART_IMAGE)
plt.close()

# Generate and save the Unique Database Count chart
months = ["2024-01", "2024-02", "2024-03", "2024-04", "2024-05", "2024-06", "2024-07", "2024-08", "2024-09", "2024-10", "2024-11"]
unique_db_count = [database_backup_counts.get(month, 0) for month in months]

plt.figure(figsize=(14, 8))
plt.plot(months, unique_db_count, marker='o', color='#4B286D', linewidth=2, markersize=8)
plt.fill_between(months, unique_db_count, color='#4B286D', alpha=0.1)
plt.title('Monthly Database Backup Count from Jan 2024 to Nov 2024')
plt.xlabel('Month')
plt.ylabel('Unique Database Count')
plt.grid(True, which="both", linestyle='--', linewidth=0.5)
plt.tight_layout()
plt.savefig(DATABASE_COUNT_CHART_IMAGE)
plt.close()

# Generate and save the Backup Count by Server chart
sorted_server_backup_counts = dict(sorted(server_backup_counts.items(), key=lambda item: item[1], reverse=True))
servers = list(sorted_server_backup_counts.keys())
backup_counts = list(sorted_server_backup_counts.values())

fig, ax = plt.subplots(figsize=(14, 8))
bars = ax.barh(servers, backup_counts, color='#4B286D', zorder=3)
ax.set_title('Backups by Server')
ax.set_xlabel('Number of Backups')
ax.set_ylabel('Server')
ax.grid(True, axis='x', linestyle='--', linewidth=0.5, zorder=0)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_visible(False)
ax.spines['bottom'].set_visible(False)

# Add gradient fill to bars and rounding using patches
for bar in bars:
    grad = np.linspace(0, 1, 256)
    colors = plt.cm.plasma(grad)
    gradient = np.vstack((colors, colors))
    ax.imshow(gradient, aspect='auto', extent=[bar.get_x(), bar.get_x() + bar.get_width(), bar.get_y(), bar.get_y() + bar.get_height()], zorder=1, alpha=0.6)
    bar.set_edgecolor((0.8, 0.8, 0.8, 0.5))
    bar.set_linewidth(1)
    rect = patches.FancyBboxPatch(
        (bar.get_x(), bar.get_y()), bar.get_width(), bar.get_height(),
        boxstyle="round,pad=0.3", edgecolor="none", linewidth=0,
        facecolor=bar.get_facecolor(), fill=True)
    ax.add_patch(rect)
    bar.set_visible(False)

plt.tight_layout()
plt.savefig(BACKUP_BY_SERVER_CHART_IMAGE)
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
        body {{
            font-family: 'Segoe UI', Arial, sans-serif;
            background-color: #f4f4f4;
            padding: 0;
            margin: 0;
        }}
        h1, h2 {{
            margin: 20px 0;
            padding-bottom: 5px;
            border-bottom: 2px solid #4B286D;
            text-align: center;
        }}
        h1 {{
            color: #4B286D;
        }}
        h2 {{
            color: #6C77A1;
        }}
        .chart-container {{
            text-align: center;
            width: 100%;
            padding: 20px;
            background-color: #ffffff;
            box-sizing: border-box;
        }}
        .chart {{
            display: inline-block;
            width: 90%;
            max-width: 800px;
            margin-bottom: 40px;
            padding: 20px;
            border-radius: 15px;
            background-color: #fff;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
        }}
        footer {{
            font-size: 14px;
            color: purple;
            text-align: center;
            margin-top: 20px;
            background-color: #ffffff;
            padding: 10px;
            border-top: 1px solid #ddd;
        }}
        img {{
            width: 100%;
            height: auto;
            border-radius: 10px;
        }}
    </style>
</head>
<body>
<h1>Backup Report - Jan 2024 to Nov 2024</h1>
<p style="text-align: center;">This report provides an overview of the backup activities from January 2024 to November 2024.</p>

<div class='chart-container'>
    <div class='chart'>
        <h2>Backup Status Overview</h2>
        <img src="cid:status_chart" alt="Status Chart">
    </div>
    <div class='chart'>
        <h2>Backups by Server</h2>
        <img src="cid:backup_by_server_chart" alt="Backups by Server Chart">
    </div>
    <div class='chart'>
        <h2>Monthly Database Backup Count</h2>
        <img src="cid:database_count_chart" alt="Database Count Chart">
    </div>
</div>

<footer>Report generated by Database Engineering</footer>
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
Content-ID: <backup_by_server_chart>

{encode_image_to_base64(BACKUP_BY_SERVER_CHART_IMAGE)}

--{boundary}
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-ID: <database_count_chart>

{encode_image_to_base64(DATABASE_COUNT_CHART_IMAGE)}
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

