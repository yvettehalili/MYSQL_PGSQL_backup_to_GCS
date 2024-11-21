#!/bin/bash

# Set environment variable to enable cleartext authentication plugin
export LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN=1

TMP_PATH="/backup/dumps/"
BACKUPS_PATH="/root/cloudstorage/Backups/Current/"
BUCKET_PATH="/root/cloudstorage/"
BUCKET="ti-sql-02"
SSL_PATH="/ssl-certs/"

DB_USR="GenBackupUser"
DB_PWD="DBB@ckuPU53r*"

LDUMP_DATE=$(date +"%Y-%m-%d %H:%M:%S")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
CUR_DATE=$(date +"%Y-%m-%d")
DAY=$(date +"%u")

SERVERS_LIST="/backup/configs/servers_list.csv"
readarray -t lines < "${SERVERS_LIST}"

printf "================================== ${CUR_DATE} =============================================\n"

for line in "${lines[@]}"; do
    column_values=$(echo $line | tr "," "\n")
    I=0
    for value in $column_values; do
        if [ $I == 0 ]; then
            SERVER=$value
        elif [ $I == 1 ]; then
            HOST=$value
        elif [ $I == 2 ]; then
            SSL=$value
        fi
        I=$((I+1))
    done

    DB_HOST=$HOST
    printf "${TIMESTAMP}: DUMPING SERVER: ${SERVER}\n"

    if [ "$SSL" != "y" ]; then
        DB_LIST=$(mysql -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password -h "$DB_HOST" -Bs -e "SHOW DATABASES")
        if [ $? -ne 0 ]; then
            printf "Error retrieving database list for server: ${SERVER}\n" >&2
            continue
        fi
    else
        DB_LIST=$(mysql -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password -h "$DB_HOST" \
                   --ssl-ca="${SSL_PATH}${SERVER}/server-ca.pem" \
                   --ssl-cert="${SSL_PATH}${SERVER}/client-cert.pem" \
                   --ssl-key="${SSL_PATH}${SERVER}/client-key.pem" -Bs -e "SHOW DATABASES")
        if [ $? -ne 0 ]; then
            printf "Error retrieving database list for server: ${SERVER}\n" >&2
            continue
        fi
    fi

    cd "${TMP_PATH}"
    [ ! -d "${SERVER}" ] && mkdir -p "$SERVER"
    cd "$SERVER"

    for DB in $DB_LIST; do
        if [[ "$DB" != "information_schema" ]] && [[ "$DB" != "performance_schema" ]] && [[ "$DB" != "sys" ]] && [[ "$DB" != "mysql" ]]; then
            printf "Dumping DB $DB\n"
            if [ "$SSL" != "y" ]; then
                mysqldump -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password --set-gtid-purged=OFF --single-transaction --lock-tables=false --quick \
                          --triggers --events --routines -h"$DB_HOST" "$DB" | gzip > "${CUR_DATE}_${DB}.sql.gz"
            else
                if [[ "$DB" == "db_hr_osticket_us" || "$DB" == "db_hr_osticket_ph" || "$DB" == "db_osticket_workday_global" || "$SERVER" == "isdba-cloudsql-us-we1-a-08" ]]; then
                    if [[ "$DAY" == "6" && "$DB" == "db_hr_osticket_ph" ]]; then
                        mysqldump -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password --set-gtid-purged=OFF \
                                  --ssl-ca="${SSL_PATH}${SERVER}/server-ca.pem" \
                                  --ssl-cert="${SSL_PATH}${SERVER}/client-cert.pem" \
                                  --ssl-key="${SSL_PATH}${SERVER}/client-key.pem" \
                                  --single-transaction --max_allowed_packet=2147483648 --hex-blob --net_buffer_length=4096 \
                                  --triggers --events --lock-tables=false --routines --quick -h"$DB_HOST" "$DB" | gzip > "${CUR_DATE}_${DB}.sql.gz"
                    else
                        if [[ "$DB" == "db_hr_osticket_ph" ]]; then
                            mysqldump -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password --set-gtid-purged=OFF \
                                      --ssl-ca="${SSL_PATH}${SERVER}/server-ca.pem" \
                                      --ssl-cert="${SSL_PATH}${SERVER}/client-cert.pem" \
                                      --ssl-key="${SSL_PATH}${SERVER}/client-key.pem" \
                                      --single-transaction --max_allowed_packet=2147483648 --hex-blob --net_buffer_length=4096 \
                                      --ignore-table="$DB".hr_file_chunk --lock-tables=false \
                                      --triggers --events --routines --quick -h"$DB_HOST" "$DB" | gzip > "${CUR_DATE}_${DB}.sql.gz"
                        else
                            mysqldump -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password --set-gtid-purged=OFF \
                                      --ssl-ca="${SSL_PATH}${SERVER}/server-ca.pem" \
                                      --ssl-cert="${SSL_PATH}${SERVER}/client-cert.pem" \
                                      --ssl-key="${SSL_PATH}${SERVER}/client-key.pem" \
                                      --single-transaction --max_allowed_packet=2147483648 --hex-blob --net_buffer_length=4096 \
                                      --lock-tables=false --quick \
                                      --triggers --events --routines -h"$DB_HOST" "$DB" | gzip > "${CUR_DATE}_${DB}.sql.gz"
                        fi
                    fi
                else
                    mysqldump -u"$DB_USR" -p"$DB_PWD" --default-auth=mysql_native_password --set-gtid-purged=OFF \
                              --ssl-ca="${SSL_PATH}${SERVER}/server-ca.pem" \
                              --ssl-cert="${SSL_PATH}${SERVER}/client-cert.pem" \
                              --ssl-key="${SSL_PATH}${SERVER}/client-key.pem" \
                              --single-transaction --max_allowed_packet=2147483648 --lock-tables=false --net_buffer_length=4096 \
                              --triggers --events --routines --quick -h"$DB_HOST" "$DB" | gzip > "${CUR_DATE}_${DB}.sql.gz"
                fi
            fi
            if [ $? -ne 0 ]; then
                printf "Error dumping database: $DB on server: ${SERVER}\n" >&2
            else
                printf "Successfully dumped database: $DB on server: ${SERVER}\n"
            fi
        fi
    done
    gsutil -m -o GSUtil:parallel_composite_upload_threshold=150MB mv *.gz gs://"${BUCKET}/Backups/Current/${SERVER}/"
done

printf "============================================================================================\n\n"
cd ~
exit
