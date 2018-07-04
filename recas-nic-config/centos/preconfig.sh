#!/bin/bash

#________________________________
#________________________________
# Main script

# Check which interface have been crated
echo 'Find default interface name'
IFACE_NAME=$(ip a | grep -E '172.30.[0-9]{1,3}|90.147.[0-9]{1,3}' -B 2 | head -1 | awk -F\: '{print $2}' | sed "s/^ //")

DEFAULT_IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-$IFACE_NAME
  
# Modify default interface
echo 'Edit default interface: '$IFACE_NAME
  
if grep -Fxq "HOTPLUG=yes" $DEFAULT_IFCFG_FILE
then
  echo 'HOTPLUG already enabled. Nothing to do'
else
  echo 'HOTPLUG=yes' >> $DEFAULT_IFCFG_FILE
  sed -i '/^HWADDR/d' $DEFAULT_IFCFG_FILE
fi
  
# Find second interface
echo 'Find second interface'
if [[ $IFACE_NAME == 'eth0' ]]; then
  IFCFG_FILE_NEW=/etc/sysconfig/network-scripts/ifcfg-eth1
  IFACE_NAME_NEW='eth1'
elif [[ $IFACE_NAME == 'eth1' ]]; then
  IFCFG_FILE_NEW=/etc/sysconfig/network-scripts/ifcfg-eth0
  IFACE_NAME_NEW='eth0'
fi

# Create and modify second interface file
echo 'Create and modify second interface: '$IFACE_NAME_NEW
cp $DEFAULT_IFCFG_FILE $IFCFG_FILE_NEW
sed -i "s/.*DEVICE=$IFACE_NAME.*/DEVICE=$IFACE_NAME_NEW/" $IFCFG_FILE_NEW

# Edit /etc/cloud/cloud.cfg
sed -i '/ssh_pwauth:   0/a \network:\n  config: disabled' /etc/cloud/cloud.cfg
echo 'runcmd:' >> /etc/cloud/cloud.cfg
echo '  - [ bash, /opt/recas-netconfig.sh ]' >> /etc/cloud/cloud.cfg
  
# Copy cloud init script to /opt
curl https://raw.githubusercontent.com/Laniakea-elixir-it/HEAT-templates/master/recas-nic-config/centos/recas-netconfig.sh --output /opt/recas-netconfig.sh
chmod +x /opt/recas-netconfig.sh
