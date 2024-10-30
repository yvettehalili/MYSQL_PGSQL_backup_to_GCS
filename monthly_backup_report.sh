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
REPORT_OUTPUT="${BACKUP_DIR}/monthly_backup_report.html"

# SQL Queries
ACTIVE_SERVERS_QUERY="SELECT srv_name, srv_os, srv_frecuency, srv_location, srv_type FROM lgm_servers WHERE srv_active = 1;"
BACKUP_LOGS_QUERY="SELECT lbl_date, lbl_server, lbl_size_byte, lbl_filename FROM lgm_backups_log WHERE lbl_date LIKE '${CUR_MONTH}%';"

# Extract data to files
mysql -u$DB_USER -p$DB_PASS -e "$ACTIVE_SERVERS_QUERY" $DB_NAME > $ACTIVE_SERVERS_FILE
mysql -u$DB_USER -p$DB_PASS -e "$BACKUP_LOGS_QUERY" $DB_NAME > $BACKUP_LOGS_FILE

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
    </style>
</head>
<body>
<h1 align='center'>Monthly Backup Report - ${CUR_MONTH}</h1>
<h2>Backup Status Overview</h2>
<p>This report provides an overview of the backup activities for the month of ${CUR_MONTH}.</p>

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
        <th>Filename</th>
        <th>Status</th>
    </tr>"

# Read data from extracted files and append to HTML report
count=1
successful_count=0
failed_count=0

while IFS= read -r SERVER_NAME OS FREQUENCY LOCATION TYPE; do
    grep "$SERVER_NAME" $BACKUP_LOGS_FILE | while IFS=$'\t' read -r DATE SERVER SIZE FILENAME; do
        STATUS="Success"
        if [ "$SIZE" == "0" ] || [ -z "$SIZE" ]; then
            STATUS="Failed"
            ((failed_count++))
        else
            ((successful_count++))
        fi

        HTML_REPORT+="<tr>
            <td>$count</td>
            <td>$SERVER_NAME</td>
            <td>$OS</td>
            <td>$FREQUENCY</td>
            <td>$LOCATION</td>
            <td>$TYPE</td>
            <td>$SIZE</td>
            <td>$DATE</td>
            <td>$FILENAME</td>
            <td>$STATUS</td>
        </tr>"
        ((count++))
    done
done < <(tail -n +2 $ACTIVE_SERVERS_FILE)

HTML_REPORT+="
</table>
<h2>Backup Summary</h2>
<p>Successful Backups: ${successful_count}</p>
<p>Failed Backups: ${failed_count}</p>
</body>
</html>"

# Save the HTML report
echo "$HTML_REPORT" > $REPORT_OUTPUT

# Notify user
echo "Monthly backup report has been generated and saved to ${REPORT_OUTPUT}"
