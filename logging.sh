#!/bin/bash

# Maintenance Access
DB_USER=trtel.backup
DB_PASS='Telus2017#'
DB_MAINTENANCE=ti_db_inventory

# Variables de Entorno
STORAGE=/root/cloudstorage
DBA_STORAGE=/root/DBA_Storage

BUCKET=ti-dba-prod-sql-01

CUR_DATE=$(date +"%Y-%m-%d")
OLD_DATE=$(date -d "$CUR_DATE" +"%d-%m-%Y")
YEAR_DATE=$(date -d "$CUR_DATE" +"%Y")
MONTH_DATE=$(date -d "$CUR_DATE" +"%m")
CUR_DAY=$(date -d "$CUR_DATE" +"%d")
DOW=$(date -d "$CUR_DATE" "+%u")
CUR_DATE2=$(date -d "$CUR_DATE" +"%Y%m%d")
CUR_DATE3=$(date -d "$CUR_DATE" +"%d-%m-%Y")
CUR_DO=$(date -d "$CUR_DATE" +%a)

# SQL Query to Fetch Server Details
query="SELECT name, ip, user, pwd, os, frecuency, domain, save_path, location, type FROM ti_db_inventory.servers where srv_active = 1 and location = 'GCP' order by location, type, os"

clear

echo "============================================================================================================"
echo "INICIANDO FECHA: $CUR_DATE ................................................................................."
echo "============================================================================================================"
gcsfuse --key-file=/root/jsonfiles/ti-dba-prod-01.json $BUCKET $STORAGE

# myread prevents collapsing of empty fields
myread() {
    local input
    IFS= read -r input || return $?
    while (( $# > 1 )); do
        IFS= read -r "$1" <<< "${input%%[$IFS]*}"
        input="${input#*[$IFS]}"
        shift
    done
    IFS= read -r "$1" <<< "$input"
}

MB=1024.00

while IFS=$'\t' myread SERVER SERVERIP WUSER WUSERP OS FRECUENCY DOMAIN SAVEPATH LOCATION TYPE;
do
    echo "============================================================================================================"
    echo "SERVIDOR: $SERVER - $SERVERIP - $OS - $TYPE - $SAVEPATH - $LOCATION"
    echo "============================================================================================================"
    begincopy=$(date +"%Y-%m-%d %H:%M:%S")
    rm "/backup/cronlog/$SERVER".txt
    echo "LOCATION: $LOCATION"
    if [ "$LOCATION" == "OnPrem" ]; then
        echo "TIPO: $TYPE"
        if [ "$TYPE" == "MYSQL" ]; then
            cd $STORAGE
            cd Backups
            cd Current
            gsutil -q stat gs://$BUCKET/Backups/Current/MYSQL/$SERVER/

            return_value=$?
            if [ $return_value = 0 ]; then
                CHECK=0
                SIZE=0
                NO=0
                rsync -P --size-only $WUSER@${SERVERIP}:/${DIR}/*${CUR_DATE}*.sql* $STORAGE/Backups/Current/MYSQL/$SERVER/
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MYSQL/$SERVER/*${CUR_DATE}* | awk '{print $1}')

                if [[ $SIZE != *[!\ ]* ]]; then
                    CHECK=0
                else
                    if [ "$SIZE" != "0" ]; then
                        CHECK=$SIZE;
                    else
                        CHECK=0
                        SIZE=0
                    fi
                fi
                find  $STORAGE/Backups/Current/MYSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
            else
                mkdir $SERVER
                chmod 775 -R $STORAGE/Backups/Current/MYSQL/$SERVER/
                CHECK=0
                SIZE=0
                NO=0
                rsync -P --size-only $WUSER@${SERVERIP}:/${DIR}/${CUR_DATE}*.sql* $STORAGE/Backups/Current/MYSQL/$SERVER/
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MYSQL/$SERVER/${CUR_DATE}* | awk '{print $1}')
                if [[ $SIZE != *[!\ ]* ]]; then
                    CHECK=0
                else
                    if [ "$SIZE" != "0" ]; then
                        CHECK=$SIZE;
                    else
                        CHECK=0
                        SIZE=0
                    fi
                fi
                find  $STORAGE/Backups/Current/MYSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
            fi
        elif [ "$TYPE" == "MSSQL" ]; then
            if [ "$SAVEPATH" == "Storage" ]; then
                mount -t cifs //172.25.20.14/DBA_Storage /root/DBA_Storage/ -o domain=TI,username=dba.backup,password=6sIRG7R2J9ICtaa7M6y7

                CHECK=0
                SIZE=0
                gsutil -m -o GSUtil:parallel_composite_upload_threshold=50M mv -n $DBA_STORAGE/$SERVER/*"${CUR_DATE}"* gs://$BUCKET/Backups/Current/MSSQL/$SERVER/

                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE}"* | awk '{print $1}')

                if [[ $SIZE != *[!\ ]* ]]; then
                    CHECK=0
                else
                    if [ "$SIZE" != "0" ]; then
                        CHECK=$SIZE;
                        find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
                    else
                        CHECK=0
                        SIZE=0
                    fi
                fi
                if [ "$CHECK" == "0" ]; then
                    gsutil -m -o GSUtil:parallel_composite_upload_threshold=50M mv -n $DBA_STORAGE/$SERVER/*"${CUR_DATE2}"* gs://$BUCKET/Backups/Current/MSSQL/$SERVER/
                    SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE2}"* | awk '{print $1}')
                    if [[ $SIZE != *[!\ ]* ]]; then
                        CHECK=0
                    else
                        if [ "$SIZE" != "0" ]; then
                            CHECK=$SIZE;
                        else
                            CHECK=0
                            SIZE=0
                        fi
                    fi
                    find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE2}*" -print > "/backup/cronlog/$SERVER".txt
                fi
                if [ "$CHECK" == "0" ]; then
                    gsutil -m -o GSUtil:parallel_composite_upload_threshold=50M mv -n $DBA_STORAGE/$SERVER/*"${CUR_DATE3}"* gs://$BUCKET/Backups/Current/MSSQL/$SERVER/
                    SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE3}"* | awk '{print $1}')
                    if [[ $SIZE != *[!\ ]* ]]; then
                        CHECK=0
                    else
                        if [ "$SIZE" != "0" ]; then
                            CHECK=$SIZE;
                        else
                            CHECK=0
                            SIZE=0
                        fi
                    fi
                    find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE3}*" -print > "/backup/cronlog/$SERVER".txt
                fi
                mount -lf /root/DBA_Storage/
            elif [ "$SAVEPATH" == "Bucket" ]; then
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE}"* | awk '{print $1}')

                if [[ $SIZE != *[!\ ]* ]]; then
                    CHECK=0
                else
                    if [ "$SIZE" != "0" ]; then
                        CHECK=$SIZE
                        find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
                    else
                        CHECK=0
                        SIZE=0
                    fi
                fi
                if [ "$CHECK" == "0" ]; then
                    SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE2}"* | awk '{print $1}')
                    if [[ $SIZE != *[!\ ]* ]]; then
                        CHECK=0
                    else
                        if [ "$SIZE" != "0" ]; then
                            CHECK=$SIZE;
                            find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE2}*" -print > "/backup/cronlog/$SERVER".txt
                        else
                            CHECK=0
                            SIZE=0
                        fi
                    fi
                fi
                if [ "$CHECK" == "0" ]; then
                    SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE3}"* | awk '{print $1}')
                    if [[ $SIZE != *[!\ ]* ]]; then
                        CHECK=0
                    else
                        if [ "$SIZE" != "0" ]; then
                            CHECK=$SIZE;
                        else
                            CHECK=0
                            SIZE=0
                        fi
                    fi
                    find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE3}*" -print > "/backup/cronlog/$SERVER".txt
                fi
            fi
        fi
    elif [ "$LOCATION" == "GCP" ]; then
        echo "TYPE: $TYPE"
        if [ "$TYPE" == "MSSQL" ]; then
           SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE}"* | awk '{print $1}')

           if [[ $SIZE != *[!\ ]* ]]; then
                CHECK=0
           else
                if [ "$SIZE" != "0" ]; then
                   CHECK=$SIZE
                   find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
                else
                   CHECK=0
                   SIZE=0
                fi
           fi
           if [ "$CHECK" == "0" ]; then
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE2}"* | awk '{print $1}')
                if [[ $SIZE != *[!\ ]* ]]; then
                   CHECK=0
                else
                   if [ "$SIZE" != "0" ]; then
                      CHECK=$SIZE;
                      find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE2}*" -print > "/backup/cronlog/$SERVER".txt
                   else
                      CHECK=0
                      SIZE=0
                   fi
                fi
            fi
            if [ "$CHECK" == "0" ]; then
               SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MSSQL/$SERVER/*"${CUR_DATE3}"* | awk '{print $1}')
               if [[ $SIZE != *[!\ ]* ]]; then
                  CHECK=0
               else
                  if [ "$SIZE" != "0" ]; then
                     CHECK=$SIZE;
                     find  $STORAGE/Backups/Current/MSSQL/$SERVER/ -type f -name "*${CUR_DATE3}*" -print > "/backup/cronlog/$SERVER".txt
                  else
                     CHECK=0
                     SIZE=0
                  fi
               fi
            fi
        elif [ "$TYPE" == "MYSQL" ]; then
            CHECK=0
            SIZE=0

            SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MYSQL/$SERVER/*"${CUR_DATE}"* | awk '{print $1}')
            if [[ $SIZE != *[!\ ]* ]]; then
               CHECK=0
            else
               if [ "$SIZE" != "0" ]; then
                  CHECK=$SIZE;
                  find  $STORAGE/Backups/Current/MYSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
               else
                  CHECK=0
                  SIZE=0
               fi
            fi
            if [ "$CHECK" == "0" ]; then
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MYSQL/$SERVER/*"${CUR_DATE2}"* | awk '{print $1}')
                if [[ $SIZE != *[!\ ]* ]]; then
                   CHECK=0
                else
                   if [ "$SIZE" != "0" ]; then
                      CHECK=$SIZE;
                      find  $STORAGE/Backups/Current/MYSQL/$SERVER/ -type f -name "*${CUR_DATE2}*" -print > "/backup/cronlog/$SERVER".txt
                   else
                      CHECK=0
                      SIZE=0
                   fi
                fi
            fi
            if [ "$CHECK" == "0" ]; then
               SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/MYSQL/$SERVER/*"${CUR_DATE3}"* | awk '{print $1}')
               if [[ $SIZE != *[!\ ]* ]]; then
                  CHECK=0
               else
                  if [ "$SIZE" != "0" ]; then
                     CHECK=$SIZE;
                     find  $STORAGE/Backups/Current/MYSQL/$SERVER/ -type f -name "*${CUR_DATE3}*" -print > "/backup/cronlog/$SERVER".txt
                  else
                     CHECK=0
                     SIZE=0
                  fi
               fi
            fi
        elif [ "$TYPE" == "POSQL" ]; then
            CHECK=0
            SIZE=0

            SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/PGSQL/$SERVER/*"${CUR_DATE}"* | awk '{print $1}')
            if [[ $SIZE != *[!\ ]* ]]; then
               CHECK=0
            else
               if [ "$SIZE" != "0" ]; then
                  CHECK=$SIZE;
                  find  $STORAGE/Backups/Current/PGSQL/$SERVER/ -type f -name "*${CUR_DATE}*" -print > "/backup/cronlog/$SERVER".txt
               else
                  CHECK=0
                  SIZE=0
               fi
            fi
            if [ "$CHECK" == "0" ]; then
                SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/PGSQL/$SERVER/*"${CUR_DATE2}"* | awk '{print $1}')
                if [[ $SIZE != *[!\ ]* ]]; then
                   CHECK=0
                else
                   if [ "$SIZE" != "0" ]; then
                      CHECK=$SIZE;
                      find  $STORAGE/Backups/Current/PGSQL/$SERVER/ -type f -name "*${CUR_DATE2}*" -print > "/backup/cronlog/$SERVER".txt
                   else
                      CHECK=0
                      SIZE=0
                   fi
                fi
            fi
            if [ "$CHECK" == "0" ]; then
               SIZE=$(gsutil du -s gs://$BUCKET/Backups/Current/PGSQL/$SERVER/*"${CUR_DATE3}"* | awk '{print $1}')
                if [[ $SIZE != *[!\ ]* ]]; then
                  CHECK=0
                else
                        if [ "$SIZE" != "0" ]; then
                                CHECK=$SIZE;
                                find  $STORAGE/Backups/Current/PGSQL/$SERVER/ -type f -name "*${CUR_DATE3}*" -print > "/backup/cronlog/$SERVER".txt
                        else
                                CHECK=0
                                SIZE=0
                        fi
                fi
            fi
        fi
    fi

    echo "============================================================================================================"
    echo "SERVIDOR: $SERVER"
    echo "Tamaño $CUR_DATE: $CHECK"
    echo "============================================================================================================"

    endcopy=$(date +"%Y-%m-%d %H:%M:%S")
    IQUERY="INSERT INTO daily_log (backup_date, server, size) VALUES ('$CUR_DATE','$SERVER','$begincopy','$endcopy',$CHECK)"
    IQUERY+=" ON DUPLICATE KEY UPDATE size=$CHECK;"

    value="/backup/cronlog/$SERVER.txt"
    fsize=0
    tfsize=0

    mysql --defaults-group-suffix=bk $DB_MAINTENANCE -e "${IQUERY}"

    while read line; do
        fsize=$(du -sb $line | awk '{print $1}')
        file=$(basename $line)
        tfsize=$(($fsize + $tfsize))
        SQUERY="INSERT INTO backup_log (backup_date, server, size, filepath) VALUES ('$CUR_DATE','$SERVER','$file',$fsize,'$line')"
        SQUERY+=" ON DUPLICATE KEY UPDATE last_update=NOW(), size=$fsize, state = CASE WHEN $fsize > 0 THEN 'Completed' ELSE 'Error' END;"
        mysql --defaults-group-suffix=bk $DB_MAINTENANCE -e "${SQUERY}"
    done < $value
done < <(mysql --defaults-group-suffix=bk  ${DB_MAINTENANCE} --batch -se "${query}")

fusermount -uz $STORAGE

printf "done"
