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
    if MONTH not in database
