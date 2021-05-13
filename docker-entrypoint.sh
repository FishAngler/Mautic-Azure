#!/bin/bash

set -e

if [ ! -f /usr/local/etc/php/php.ini ]; then
cat <<EOF > /usr/local/etc/php/php.ini
date.timezone = "${PHP_INI_DATE_TIMEZONE}"
always_populate_raw_post_data = -1
memory_limit = ${PHP_MEMORY_LIMIT}
file_uploads = On
upload_max_filesize = ${PHP_MAX_UPLOAD}
post_max_size = ${PHP_MAX_UPLOAD}
max_execution_time = ${PHP_MAX_EXECUTION_TIME}
EOF
fi

if [ -n "$MYSQL_PORT_3306_TCP" ]; then
        if [ -z "$MAUTIC_DB_HOST" ]; then
                export MAUTIC_DB_HOST='mysql'
                if [ "$MAUTIC_DB_USER" = 'root' ] && [ -z "$MAUTIC_DB_PASSWORD" ]; then
                        export MAUTIC_DB_PASSWORD="$MYSQL_ENV_MYSQL_ROOT_PASSWORD"
                fi
        else
                echo "warning: both MAUTIC_DB_HOST and MYSQL_PORT_3306_TCP found"
                echo "  Connecting to MAUTIC_DB_HOST ($MAUTIC_DB_HOST)"
                echo "  instead of the linked mysql container"
        fi
fi


if [ -z "$MAUTIC_DB_HOST" ]; then
        echo >&2 "error: missing MAUTIC_DB_HOST and MYSQL_PORT_3306_TCP environment variables"
        echo >&2 "  Did you forget to --link some_mysql_container:mysql or set an external db"
        echo >&2 "  with -e MAUTIC_DB_HOST=hostname:port?"
        exit 1
fi


if [ -z "$MAUTIC_DB_PASSWORD" ]; then
        echo >&2 "error: missing required MAUTIC_DB_PASSWORD environment variable"
        echo >&2 "  Did you forget to -e MAUTIC_DB_PASSWORD=... ?"
        echo >&2
        echo >&2 "  (Also of interest might be MAUTIC_DB_USER and MAUTIC_DB_NAME.)"
        exit 1
fi


if ! [ -e index.php -a -e app/AppKernel.php ]; then
       echo "Mautic not found in $pwd - copying now..."
        # if [ "$(ls -A)" ]; then
        #        echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
        #        ( set -x; ls -A; sleep 10 )
        # fi

       tar cf - --one-file-system -C /usr/src/mautic . | tar xf -

       echo "Complete! Mautic has been successfully copied to $pwd"
fi

# Ensure the MySQL Database is created
php /makedb.php "$MAUTIC_DB_HOST" "$MAUTIC_DB_USER" "$MAUTIC_DB_PASSWORD" "$MAUTIC_DB_NAME"

echo "========================================================================"
echo ""
echo "This server is now configured to run Mautic!"
echo "The following information will be prefilled into the installer (keep password field empty):"
echo "Host Name: $MAUTIC_DB_HOST"
echo "Database Name: $MAUTIC_DB_NAME"
echo "Database Username: $MAUTIC_DB_USER"
echo "Database Password: $MAUTIC_DB_PASSWORD"


# Write the database connection to the config so the installer prefills it
if ! [ -e app/config/local.php ]; then
        echo "Config not found in $pwd/app/config - creating now..."
        php /makeconfig.php

        # Make sure our web user owns the config file if it exists
        chown www-data:www-data /home/site/wwwroot/app/config/local.php
        mkdir -p /home/site/wwwroot/app/logs
        chown www-data:www-data /home/site/wwwroot/app/logs
        echo "Complete! Config has been created"
fi

if [[ "$MAUTIC_RUN_CRON_JOBS" == "true" ]]; then
    if [ ! -e /var/log/cron.pipe ]; then
        mkfifo /var/log/cron.pipe
        chown www-data:www-data /var/log/cron.pipe
    fi
    (tail -f /var/log/cron.pipe | while read line; do echo "[CRON] $line"; done) &
    CRONLOGPID=$!
    cron -f &
    CRONPID=$!

    echo "Checking if mautic.crontab exists in /home"
    if ! [ -e /home/mautic.crontab ]; then
        echo "Moving mautic.crontab file to /home/mautic.crontab"
        cp /mautic.crontab /home/mautic.crontab
    fi
    #move the mautic cron job file to /etc/cron.d
    echo "Moving mautic.crontab file to /etc/cron.d/mautic"
    cp /home/mautic.crontab /etc/cron.d/mautic
    chmod 644 /etc/cron.d/mautic
    
else
    echo "Not running cron as requested."
fi

echo ""
echo "========================================================================"

#"$@" &
#MAINPID=$!

# shut_down() {
#     if [[ "$MAUTIC_RUN_CRON_JOBS" == "true" ]]; then
#         kill -TERM $CRONPID || echo 'Cron not killed. Already gone.'
#         kill -TERM $CRONLOGPID || echo 'Cron log not killed. Already gone.'
#     fi
#     kill -TERM $MAINPID || echo 'Main process not killed. Already gone.'
# }
#trap 'shut_down;' TERM INT

# wait until all processes end (wait returns 0 retcode)
#while :; do
#    if wait; then
#        break
#    fi
#done

echo "Executing Azure Entrypoint"
source /bin/init_container.sh
echo "Finished Executing Azure Entrypoint"