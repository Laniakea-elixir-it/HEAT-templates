#!/bin/bash

# Log file
LOGFILE='/var/log/recas-netconfig.log'

#________________________________
# Check for private IP
function find_private_nic(){

  # If the private interface is on use this command to determine its name
  PRIVATE_IFACE_NAME=$(ip a | grep -E '172.30.[0-9]{1,3}' -B 2 | head -1 | awk -F\: '{print $2}' | sed "s/^ //")

  # Exit if the variable is unset or empty
  if [ -z "$PRIVATE_IFACE_NAME" ]
  then
    echo "The variable PRIVATE_IFACE_NAME is not set" >> $LOGFILE
    exit 1
  fi

  # Determine the private IP assigned by OpenStack's DHCP
  PRIVATE_IP=$(hostname -I | grep -Ewo '172.30.[0-9]{1,3}.[0-9]{1,3}')

  # Exit if the variable is unset or empty
  if [ -z "$PRIVATE_IP" ]
  then
    echo "The variable PRIVATE_IP is not set" >> $LOGFILE
    exit 3
  fi

  # Configure the private IP as static
  PRIVATE_IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-$PRIVATE_IFACE_NAME

  true

}

#________________________________
# Check for public IP
function find_public_nic(){

  # If the public interface is on use this command to determine its name
  PUBLIC_IFACE_NAME=$(ip a | grep -E '90.147.[0-9]{1,3}' -B 2 | head -1 | awk -F\: '{print $2}' | sed "s/^ //")

  # Exit if the variable is unset or empty
  if [ -z "$PUBLIC_IFACE_NAME" ]
  then
    echo "The variable PUBLIC_IFACE_NAME is not set" >> $LOGFILE
    exit 2
  fi

  # Determine the public IP assigned by OpenStack's DHCP
  PUBLIC_IP=$(hostname -I | grep -Ewo '90.147.[0-9]{1,3}.[0-9]{1,3}')

  # Exit if the variable is unset or empty
  if [ -z "$PUBLIC_IP" ]
  then
    echo "The variable PUBLIC_IP is not set" >> $LOGFILE
    exit 4
  fi

  # Configure the public IP as static
  PUBLIC_IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-$PUBLIC_IFACE_NAME

  true

}

#________________________________
#________________________________
# Main script

# Check if the number of network interfaces is not two and decide how to behave
if [[ $(ls -A /sys/class/net | wc -l)  == 3 ]]
then

  # Wait a little for DHCP lease
  sleep 15

  # Call both here to set all needed variables
  find_private_nic
  find_public_nic

  # Configure the private IP as static
  echo 'BOOTPROTO=static' > $PRIVATE_IFCFG_FILE
  echo 'DEVICE='$PRIVATE_IFACE_NAME >> $PRIVATE_IFCFG_FILE
  echo 'ONBOOT=yes' >> $PRIVATE_IFCFG_FILE
  echo 'TYPE=Ethernet' >> $PRIVATE_IFCFG_FILE
  echo 'USERCTL=no' >> $PRIVATE_IFCFG_FILE
  echo 'IPADDR='$PRIVATE_IP >> $PRIVATE_IFCFG_FILE
  echo 'NETMASK=255.255.255.0' >> $PRIVATE_IFCFG_FILE

  # Configure the public IP as static
  echo 'BOOTPROTO=dhcp' > $PUBLIC_IFCFG_FILE
  echo 'DEVICE='$PUBLIC_IFACE_NAME >> $PUBLIC_IFCFG_FILE
  echo 'ONBOOT=yes' >> $PUBLIC_IFCFG_FILE
  echo 'TYPE=Ethernet' >> $PUBLIC_IFCFG_FILE
  echo 'USERCTL=no' >> $PUBLIC_IFCFG_FILE

  # Default gateway to be configured
  PUBLIC_GW=$(echo $PUBLIC_IP | awk -F\. '{print $1"."$2"."$3".1"}')

  # Exit if the variable is unset or empty
  if [ -z "$PUBLIC_GW" ]
  then
    echo "The variable PUBLIC_GW is not set" >> $LOGFILE
    exit 5
  fi

  # Current default gateway configuration
  DEFAULT_GW_CONF=$(ip r | grep default)

  # Exit if the variable is unset or empty
  if [ -z "$DEFAULT_GW_CONF" ]
  then
    echo "The variable DEFAULT_GW_CONF is not set" >> $LOGFILE
    exit 6
  fi

  # Configure the new default gateway
  ip r delete $DEFAULT_GW_CONF && ip r add default via $PUBLIC_GW dev $PUBLIC_IFACE_NAME

else

  # If only one interface is found, we determine its name and discharge the other one.

  # If the interface is on use this command to determine its name
  IFACE_NAME=$(ip a | grep -E '172.30.[0-9]{1,3}|90.147.[0-9]{1,3}' -B 2 | head -1 | awk -F\: '{print $2}' | sed "s/^ //")

  # Exit if the variable is unset or empty
  if [ -z "$IFACE_NAME" ]
  then
    echo "The variable IFACE_NAME is not set" >> $LOGFILE
    exit 7
  fi

  # Configure the IP as dhcp
  IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-$IFACE_NAME

  # Configure the private nic as dhcp
  echo 'BOOTPROTO=dhcp' > $IFCFG_FILE
  echo 'DEVICE='$IFACE_NAME >> $IFCFG_FILE
  echo 'ONBOOT=yes' >> $IFCFG_FILE
  echo 'TYPE=Ethernet' >> $IFCFG_FILE
  echo 'USERCTL=no' >> $IFCFG_FILE

  # Remove the remaining unuseful configuration file
  if [[ $IFACE_NAME == 'eth0' ]]; then
    rm /etc/sysconfig/network-scripts/ifcfg-eth1
  elif [[ $IFACE_NAME == 'eth1' ]]; then
    rm /etc/sysconfig/network-scripts/ifcfg-eth0
  fi

fi # end main if
