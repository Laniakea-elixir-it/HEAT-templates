#!/bin/bash

# This script cleans up the instance and
# get it ready for snapshot.

#________________________________
# Get Distribution
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
fi

#________________________________
echo 'Remove SSH keys'
[ -f /home/$ID/.ssh/authorized_keys ] && rm /home/$ID/.ssh/authorized_keys
[ -f /root/.ssh/authorized_keys ] && rm /root/.ssh/authorized_keys

#________________________________
echo 'Cleanup log files'
find /var/log -type f | while read f; do echo -ne '' > $f; done

#________________________________
echo 'Cleanup bash history'
unset HISTFILE
[ -f /root/.bash_history ] && rm /root/.bash_history
[ -f /home/$ID/.bash_history ] && rm /home/$ID/.bash_history

#________________________________
# Remove cloud-init artifact
# you can't remove cloud-init artifact using setup script run by cloud-init
# Run this script before snapshot!!!

echo 'Removing cloud-init artifact'
rm -rf /var/lib/cloud/*
rm /var/log/cloud-init.log
rm /var/log/cloud-init-output.log

#________________________________
# Delete cloud-init user

echo "Remove default user"
userdel -r -f $ID

#________________________________
echo 'Remove /tmp dir content'
rm -rf /tmp/*

#________________________________
echo 'Instance cleanup complete!'
