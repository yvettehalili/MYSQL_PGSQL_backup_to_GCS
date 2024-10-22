import mysql.connector
from datetime import datetime, timedelta
import pandas as pd
import logging
import os

# Database configuration
DB_USER = "trtel.backup"
DB_PASS = "Telus2017#"
DB_NAME = "db_legacy_maintenance"

# Configure logging
current_date = datetime.now().strftime("%Y-%m-%d")
# Adjusted the log path to reflect the typical structure
log_filename = "/backup/logs/{}_daily_log_report.log".format(current_date)

# Ensure the log directory exists
if not os.path.exists("/backup/logs"):
    os.makedirs("/backup/logs")

logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Establish a connection to the MySQL database
conn = mysql.connector.connect(
    user=DB_USER,
    password=DB_PASS,
    host='localhost',  # Change this to the appropriate host if different
    database=DB_NAME
)
cursor = conn.cursor()

# Get yesterday's date
yesterday_date = (datetime.now() - timedelta(1)).strftime('%Y-%m-%d')

# Define the query to fetch active servers and related backup data from yesterday
query = """
SELECT @rownum := @rownum + 1 AS No, ldb_server AS Server, 
       (CASE 
            WHEN (TRUNCATE((ldb_size_byte / 1024), 0) > 0) 
            THEN (CASE 
                      WHEN (TRUNCATE(((ldb_size_byte / 1024) / 1024), 0) > 0) 
                      THEN TRUNCATE(((ldb_size_byte / 1024) / 1024), 2) 
                      ELSE TRUNCATE((ldb_size_byte / 1024), 2) 
                  END) 
            ELSE ldb_size_byte 
        END) AS size, 
       (CASE 
            WHEN (TRUNCATE((ldb_size_byte / 1024), 0) > 0) 
            THEN (CASE 
                      WHEN (TRUNCATE(((ldb_size_byte / 1024) / 1024), 0) > 0) 
                      THEN 'MB' 
                      ELSE 'KB'
                  END) 
            ELSE 'B'
        END) AS size_name, 
       s.srv_location AS Location, 
       s.srv_type AS DB_engine,
       s.srv_os AS OS,
       CASE 
           WHEN ldb_size_byte > 0 
           THEN 'No' 
           ELSE 'Yes' 
       END AS Error
FROM lgm_daily_backup b
JOIN lgm_servers s ON s.srv_name = b.ldb_server, 
     (SELECT @rownum := 0) r
WHERE s.srv_active = '1'
AND ldb_date = DATE_SUB(CAST(NOW() AS DATE), INTERVAL 1 DAY)
ORDER BY s.srv_type DESC;
"""

try:
    # Log the query being executed
    logging.info("Executing query: {}".format(query))

    # Execute the query
    cursor.execute(query)

    # Fetch column names
    columns = [i[0] for i in cursor.description]

    # Fetch data
    data = cursor.fetchall()

    if data:
        logging.info("Fetched {} records from the query.".format(len(data)))
        
        # Create a DataFrame from the fetched data
        df = pd.DataFrame(data, columns=columns)

        # Insert data into the monthly_report table
        for index, row in df.iterrows():
            insert_row_query = """
            INSERT INTO monthly_report (`No`, `Server`, `size`, `size_name`, `Location`, `DB_engine`, `OS`, `Error`)
            VALUES ({}, '{}', {}, '{}', '{}', '{}', '{}', '{}');
            """.format(row['No'], row['Server'], row['size'], row['size_name'], row['Location'], row['DB_engine'], row['OS'], row['Error'])

            # Log each insert statement
            logging.info("Executing query: {}".format(insert_row_query))

            try:
                cursor.execute(insert_row_query)
            except Exception as e:
                logging.error("Error inserting row {}: {}".format(index + 1, e))

        # Commit the transaction
        conn.commit()
        logging.info("All records inserted successfully and committed.")

    else:
        logging.info("No records fetched from the query.")

except Exception as e:
    logging.error("Error: {}".format(e))

finally:
    # Close the database connection
    cursor.close()
    conn.close()
