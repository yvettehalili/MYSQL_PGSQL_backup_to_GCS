import mysql.connector
from datetime import datetime
import pandas as pd
import logging
import os

# Database configuration
DB_USER = "trtel.backup"
DB_PASS = "Telus2017#"
DB_NAME = "db_legacy_maintenance"

# Configure logging
current_date = datetime.now().strftime("%Y-%m-%d")
log_filename = "/logs/{}_daily_log_report.log".format(current_date)

# Ensure the log directory exists
if not os.path.exists("/logs"):
    os.makedirs("/logs")

logging.basicConfig(filename=log_filename, level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Establish a connection to the MySQL database
conn = mysql.connector.connect(
    user=DB_USER,
    password=DB_PASS,
    host='localhost',  # Change this to the appropriate host if different
    database=DB_NAME
)
cursor = conn.cursor()

# Define the query (this should be your specific query)
query = """
SELECT @rownum := @rownum + 1 AS No, ldb_server as Server, 
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
       s.srv_location Location, 
       s.srv_type DB_engine,
       s.srv_os OS,
       CASE 
           WHEN ldb_size_byte > 0 
           THEN 'No' 
           ELSE 'Yes' 
       END as Error
FROM lgm_daily_backup b
JOIN lgm_servers s ON s.srv_name = b.ldb_server, 
     (SELECT @rownum := 0) r
WHERE ldb_date = CAST(NOW() AS DATE) 
      AND s.srv_type='MYSQL' 
      AND srv_location='GCP'
ORDER BY s.srv_type DESC;
"""

try:
    # Execute the query
    cursor.execute(query)

    # Fetch column names
    columns = [i[0] for i in cursor.description]

    # Fetch data
    data = cursor.fetchall()

    # Create a DataFrame from the fetched data
    df = pd.DataFrame(data, columns=columns)

    # Log the number of records fetched
    logging.info("Fetched {} records from the query.".format(len(df)))

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

    # Optionally, save DataFrame to a CSV file for monthly reporting
    current_month = datetime.now().strftime("%Y-%m")
    backup_file = "backup_report_{}.csv".format(current_month)
    df.to_csv(backup_file, index=False)

    print("Monthly backup report saved to {}".format(backup_file))
    logging.info("Monthly backup report saved to {}".format(backup_file))

except Exception as e:
    logging.error("Error: {}".format(e))

finally:
    # Close the database connection
    cursor.close()
    conn.close()
