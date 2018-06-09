#!/bin/bash

# ELIXIR-ITALY
# INDIGO-DataCloud
# IBIOM-CNR
#
# Contributors:
# author: Tangaro Marco
# email: ma.tangaro@ibiom.cnr.it

# Script based on install_tools_wrapper from B. Gruening and adpted to our ansible roles.
# https://raw.githubusercontent.com/bgruening/docker-galaxy-stable/master/galaxy/install_tools_wrapper.sh

# Usage: install-tools GALAXY_ADMIN_API_KEY tool-list.yml

GALAXY='/home/galaxy/galaxy'
GALAXY_USER='galaxy'
#---
now=$(date +"%b-%d-%y-%H%M%S")
install_log="/var/log/galaxy/galaxy_tools_install_$now.log"
install_pidfile='/var/log/galaxy/galaxy_tools_install.pid'
#---
ephemeris_version='0.7.0'

#________________________________
# Get Distribution
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
fi

#________________________________
# Check if postgresql is running
function start_postgresql_vm {

  if [[ $ID = "ubuntu" ]]; then
    echo "[Ubuntu][VM] Check postgresql."
    if [[ $VERSION_ID = "16.04" ]]; then
      service start postgresql
    else
      systemctl start postgresql
    fi
  elif [[ $ID = "centos" ]]; then
      echo "[EL][VM] Check postgresql"
      systemctl start postgresql-9.6
  fi
}

function start_postgresql_docker {

  if [[ $ID = "ubuntu" ]]; then
    echo "[Ubuntu][Docker] Check postgresql."
    service start postgresql
  elif [ "$ID" = "centos" ]; then
    echo "[EL][Docker] Check postgresql"
    if [[ ! -f /var/lib/pgsql/9.6/data/postmaster.pid ]]; then
      echo "Starting postgres on centos"
      sudo -E -u postgres /usr/pgsql-9.6/bin/pg_ctl -D /var/lib/pgsql/9.6/data -w start
    fi
  fi

}

function check_postgres_status {

  PGUSER="${PGUSER:="postgres"}"

  if [[ $ID = "ubuntu" ]]; then
    echo 'placeholder'
  elif [ "$ID" = "centos" ]; then
    /usr/pgsql-9.6/bin/pg_isready -U "$PGUSER" -q
    DATA=$?
  fi

}

function check_postgresql {

  start_postgresql_vm

  check_postgres_status

  # wait for database to finish starting up
  while [[ ${DATA}  != 0 ]]
  do
    echo "waiting for database."
    check_postgres_status
    sleep 1
  done
}

#________________________________
# Install lsof

function install_lsof {
  if [[ $ID = "ubuntu" ]]; then
    echo "[Ubuntu] Installing lsof with apt."
    apt-get install -y lsof
  else
    echo "[EL] Installing lsof with yum."
    yum install -y lsof
  fi
}

function check_lsof {
  type -P lsof &>/dev/null || { echo "lsof is not installed. Installing.."; install_lsof; }
}

#________________________________
function install_ephemeris {
  echo "Load clean virtual environment"
  virtualenv /tmp/tools_venv
  source /tmp/tools_venv/bin/activate
  echo "Install ephemeris using pip in the clean environment"
  pip install bioblend
  pip install ephemeris==$ephemeris_version
}

#________________________________
# clean logs
echo "Clean logs"
rm $install_log
rm $install_pidfile

# ensure Galaxy is not running through supervisord
if pgrep "supervisord" > /dev/null
then
    echo "Galaxy managed using supervisord. Shutting it down."
    supervisorctl stop galaxy:
fi

# ensure galaxy is not running on run.sh and 8080 port
check_lsof
echo "Kill run.sh Galaxy instance listening on 8080 port"
kill -9 $(lsof -t -i :8080)
# install lsof to be sure

# check PostgreSQL
check_postgresql

# create log file
sudo -E -u $GALAXY_USER touch $install_log
 
# start Galaxy
export PORT=8080
echo "starting Galaxy"
sudo -E -u $GALAXY_USER $GALAXY/run.sh --daemon --log-file=$install_log --pid-file=$install_pidfile

# wait galaxy to start
galaxy_install_pid=`cat $install_pidfile`
echo $galaxy_install_pid

while : ; do
  tail -n 2 $install_log | grep -E -q "Removing PID file galaxy_install.pid|Daemon is already running"
  if [ $? -eq 0 ] ; then
    echo "Galaxy could not be started."
    echo "More information about this failure may be found in the following log snippet from galaxy_install.log:"
    echo "========================================"
    tail -n 60 $install_log
    echo "========================================"
    echo $1
    exit 1
  fi
  tail -n 2 $install_log | grep -q "Starting server in PID $galaxy_install_pid"
  if [ $? -eq 0 ] ; then
    echo "Galaxy is running."
    break
  fi
done

# install tools
install_ephemeris

shed-install -g "http://localhost:$PORT" -a $1 -t "$2"

exit_code=$?

if [ $exit_code != 0 ] ; then
    exit $exit_code
fi

# stop Galaxy
echo "stopping Galaxy"
sudo -E -u $GALAXY_USER $GALAXY/run.sh --stop-daemon --log-file=$install_log --pid-file=$install_pidfile

