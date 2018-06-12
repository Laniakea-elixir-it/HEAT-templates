#!/bin/bash

#________________________________
# Control variables

repository_url='https://raw.githubusercontent.com/galaxycloud-elixir-IT/HEAT-templates/master/build_system'

ansible_venv=/tmp/myansible
ANSIBLE_VERSION=2.2.1

OS_BRANCH='master'
BRANCH='devel'
FASTCONFIG_BRANCH='master'
TOOLS_BRANCH='master'
TOOLDEPS_BRANCH='master'
REFDATA_BRANCH='master'

role_dir=/tmp/roles

#________________________________
# Start logging
LOGFILE="/tmp/setup.log"
now=$(date +"%b %d %y - %H.%M.%S")
rm -f $LOGFILE
echo "Start log: ${now}" &>>  $LOGFILE

#________________________________
# Mount external volumes
# The volume is mounted only on running instances
# When a new image is built, there's no need of an external volume.
if [[ $action == 'RUN' ]]; then
  {
  volid=$volume_id
  volume_dev="/dev/disk/by-id/virtio-$(echo ${volid} | cut -c -20)"
  mkdir -p $volume_mountpoint
  mkfs.ext4 ${volume_dev} && mount ${volume_dev} $volume_mountpoint || notify_err "Some problems occurred with block device (Volume 1)"
  echo "Device successfully mounted ${volume_mountpoint}"
  } &>> $LOGFILE
fi

#________________________________
# Get Distribution
DISTNAME=''
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo $ID &>> $LOGFILE
    if [ "$ID" = "ubuntu" ]; then
      echo 'Distribution Ubuntu' &>> $LOGFILE
      DISTNAME='ubuntu'
    else
      echo 'Distribution: CentOS' &>> $LOGFILE
      DISTNAME='centos'
    fi
else
    echo "Not running a distribution with /etc/os-release available" &>> $LOGFILE
fi

#________________________________
# Install prerequisites
function prerequisites(){

  if [[ $DISTNAME = "ubuntu" ]]; then
    apt-get -y update
    apt-get -y install git vim wget
  else
    yum install -y epel-release
    yum update -y
    yum install -y git vim wget
  fi

}

#________________________________
# Ansible management
function install_ansible(){

  echo 'Remove ansible virtualenv if exists'
  rm -rf $ansible_venv

  if [[ $DISTNAME = "ubuntu" ]]; then
    #Remove old ansible as workaround for https://github.com/ansible/ansible-modules-core/issues/5144
    dpkg -r ansible
    apt-get autoremove -y
    apt-get -y update
    apt-get install -y python-pip python-dev libffi-dev libssl-dev python-virtualenv
  else
    yum install -y epel-release
    yum update -y
    yum groupinstall -y "Development Tools"
    yum install -y python-pip python-devel libffi-devel openssl-devel python-virtualenv
  fi

  # Install ansible in a specific virtual environment
  virtualenv --system-site-packages $ansible_venv
  . $ansible_venv/bin/activate
  pip install pip --upgrade

  #install ansible 2.2.1 (version used in INDIGO)
  pip install ansible==$ANSIBLE_VERSION

  # workaround for https://github.com/ansible/ansible/issues/20332
  cd $ansible_venv
  wget https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg  -O $ansible_venv/ansible.cfg

  sed -i 's\^#remote_tmp     = ~/.ansible/tmp.*$\remote_tmp     = $HOME/.ansible/tmp\' $ansible_venv/ansible.cfg
  sed -i 's\^#local_tmp      = ~/.ansible/tmp.*$\local_tmp      = $HOME/.ansible/tmp\' $ansible_venv/ansible.cfg
  #sed -i 's:#remote_tmp:remote_tmp:' /tmp/myansible/ansible.cfg

  # Enable ansible log file
  sed -i 's\^#log_path = /var/log/ansible.log.*$\log_path = /var/log/ansible.log\' $ansible_venv/ansible.cfg

}

# Remove ansible
function remove_ansible(){

  echo "Removing ansible venv"
  deactivate
  rm -rf $ansible_venv

  echo 'Removing roles'
  rm -rf $role_dir

  echo 'Removing ansible'
  if [[ $DISTNAME = "ubuntu" ]]; then
    apt-get -y autoremove ansible
  else
    yum remove -y ansible
  fi

}

#________________________________
# Install ansible roles
function install_ansible_roles(){

  mkdir -p $role_dir

  # Dependencies
  ansible-galaxy install --roles-path $role_dir indigo-dc.galaxycloud-indigorepo
  ansible-galaxy install --roles-path $role_dir indigo-dc.oneclient
  ansible-galaxy install --roles-path $role_dir indigo-dc.cvmfs-client

  # 1. indigo-dc.galaxycloud-os
  git clone https://github.com/indigo-dc/ansible-role-galaxycloud-os.git $role_dir/indigo-dc.galaxycloud-os
  cd $role_dir/indigo-dc.galaxycloud-os && git checkout $OS_BRANCH

  # 2. indigo-dc.galaxycloud and indigo-dc.galaxycloud-fastconfig
  git clone https://github.com/indigo-dc/ansible-role-galaxycloud.git $role_dir/indigo-dc.galaxycloud
  cd $role_dir/indigo-dc.galaxycloud && git checkout $BRANCH

  git clone https://github.com/indigo-dc/ansible-role-galaxycloud-fastconfig.git $role_dir/indigo-dc.galaxycloud-fastconfig
  cd $role_dir/indigo-dc.galaxycloud-fastconfig && git checkout $FASTCONFIG_BRANCH

  #### # 3. indigo-dc.galaxy-tools
  #### git clone https://github.com/indigo-dc/ansible-galaxy-tools.git $role_dir/indigo-dc.galaxy-tools
  #### cd $role_dir/indigo-dc.galaxy-tools && git checkout $TOOLS_BRANCH

  # 3. indigo-dc.galaxycloud-tools and indigo-dc.galaxycloud-tooldeps
  git clone https://github.com/indigo-dc/ansible-role-galaxycloud-tools.git $role_dir/indigo-dc.galaxycloud-tools
  cd $role_dir/indigo-dc.galaxycloud-tools && git checkout $TOOLS_BRANCH

  git clone https://github.com/indigo-dc/ansible-role-galaxycloud-tooldeps.git $role_dir/indigo-dc.galaxycloud-tooldeps
  cd $role_dir/indigo-dc.galaxycloud-tooldeps && git checkout $TOOLDEPS_BRANCH

  # 4. indigo-dc.galaxycloud-refdata
  git clone https://github.com/indigo-dc/ansible-role-galaxycloud-refdata.git $role_dir/indigo-dc.galaxycloud-refdata
  cd $role_dir/indigo-dc.galaxycloud-refdata && git checkout $REFDATA_BRANCH

}

#________________________________
# Postgresql management
function start_postgresql(){

  echo 'Start postgresql'
  if [[ $DISTNAME = "ubuntu" ]]; then
    systemctl start postgresql
  else
    systemctl start postgresql-9.6
  fi

}

#________________________________
# Stop all services with rigth order
function stop_services(){

  echo 'Stop Galaxy'
  /usr/bin/galaxyctl stop galaxy --force

  # shutdown supervisord
  echo 'Stop supervisord'
  kill -INT `cat /var/run/supervisord.pid`

  # stop postgres
  echo 'Stop postgresql'
  if [[ $DISTNAME = "ubuntu" ]]; then
    systemctl stop postgresql
    systemctl disable postgresql
  else
    systemctl stop postgresql-9.6
    systemctl disable postgresql-9.6
  fi

  # stop nginx
  echo 'Stop nginx'
  systemctl stop nginx
  systemctl disable nginx

  # stop proftpd
  echo 'Stop proftpd'
  systemctl stop proftpd
  systemctl disable proftpd

}

#________________________________
# Start all services with rigth order
function start_services(){

  # start postgres
  echo 'Start postgresql'
  if [[ $DISTNAME = "ubuntu" ]]; then
    systemctl start postgresql
    systemctl enable postgresql
  else
    systemctl start postgresql-9.6
    systemctl enable postgresql-9.6
  fi

  # start nginx
  echo 'Start nginx'
  systemctl start nginx
  systemctl enable nginx

  # start proftpd
  echo 'Start proftpd'
  systemctl start proftpd
  systemctl enable proftpd

  # start galaxy
  echo 'Start Galaxy'
  /usr/local/bin/galaxy-startup

}

#________________________________
# Run playbook
function run_playbook(){

  wget ${repository_url}/$action/$galaxy_flavor.yml -O /tmp/playbook.yml
  
  cd $ansible_venv
  ansible-playbook /tmp/playbook.yml

}

#________________________________
function build_base_image () {

  # Install depdendencies
  if [[ $DISTNAME = "ubuntu" ]]; then
    apt-get -y update
    apt-get -y install python-pip python-dev libffi-dev libssl-dev
    apt-get -y install git vim python-pycurl wget
  else
    yum install -y epel-release
    yum update -y
    yum groupinstall -y "Development Tools"
    yum install -y python-pip python-devel libffi-devel openssl-devel
    yum install -y git vim python-curl wget
    # fix font problem with centos and fastqc tool.
    yum install -y fontconfig dejavu*
    /usr/bin/fc-cache /usr/share/fonts/dejavu
  fi

  # Install cvmfs packages
  echo 'Install cvmfs client'
  if [[ $DISTNAME = "ubuntu" ]]; then
    wget https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb -O /tmp/cvmfs-release-latest_all.deb
    sudo dpkg -i /tmp/cvmfs-release-latest_all.deb
    rm -f /tmp/cvmfs-release-latest_all.deb
    sudo apt-get update
    apt-get install -y cvmfs cvmfs-config-default
  else
    yum install -y https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest.noarch.rpm
    yum install -y cvmfs cvmfs-config-default
  fi

}

#________________________________
# build image with slurm already installed
# currently only for centos
# TODO ubuntu
function build_slurm_base_image () {

  build_base_image

  # Install slurm
  if [[ $DISTNAME = "ubuntu" ]]; then
    # TODO install slurm
    echo 'to do'
  else
    #build indigo slurm repository url path
    slurm_ver='16.05.8'
    package_ver='1'
    family='el7'
    distribution='centos'
    architecture='x86_64'
    slurm_url='https://github.com/indigo-dc/ansible-role-slurm/raw/master/files/centos7/'${slurm_ver}
    # download packages
    wget $slurm_url/slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-devel-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-devel-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-munge-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-munge-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-openlava-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-openlava-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-pam_slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-pam_slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-perlapi-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-perlapi-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-plugins-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-plugins-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-seff-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-seff-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-sjobexit-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-sjobexit-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-sjstat-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-sjstat-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-slurmdb-direct-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-slurmdb-direct-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-slurmdbd-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-slurmdbd-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-sql-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-sql-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    wget $slurm_url/slurm-torque-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm -O /tmp/slurm-torque-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
    # install slurm packages
    yum --nogpgcheck localinstall -y /tmp/slurm-plugins-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-devel-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-munge-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-perlapi-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-openlava-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-pam_slurm-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-seff-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-sjobexit-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-sjstat-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-slurmdb-direct-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-slurmdbd-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-sql-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm \
                                     /tmp/slurm-torque-${slurm_ver}-${package_ver}.${family}.$distribution.${architecture}.rpm
  fi

}

#________________________________
function run_tools_script() {

  galaxy_config_file=/home/galaxy/galaxy/config/galaxy.ini
  galaxy_venv_path=/home/galaxy/galaxy/.venv
  conda_prefix=/home/galaxy/tool_deps/_conda
  galaxy_custom_script_path=/usr/local/bin

  # Get install script
  wget ${repository_url}/install_tools.sh -O ${galaxy_custom_script_path}/install-tools
  chmod +x $galaxy_custom_script_path/install-tools

  # Get recipe
  echo 'Get tools recipe'
  wget $tools_recipe_url -O /tmp/tools.yml

  # create fake user
  echo 'create fake user'
  $galaxy_venv_path/bin/python $galaxy_custom_script_path/create_galaxy_user.py --user placeholder@placeholder.com --password placeholder --username placeholder -c $galaxy_config_file --key placeholder_api_key

  # make fake user galaxy administrator
  sed -i 's\^#admin_users = None\admin_users = placeholder@placeholder.com\' $galaxy_config_file

  # run install script
  echo 'run install-tools script'
  $galaxy_custom_script_path/install-tools placeholder_api_key /tmp/tools.yml

  echo 'remove conda tarballs'
  $conda_prefix/bin/conda clean --tarballs --yes > /dev/null

  # delete fake user
  echo 'delete fake user'
  cd /home/galaxy/galaxy
  $galaxy_venv_path/bin/python $galaxy_custom_script_path/delete_galaxy_user.py --user placeholder@placeholder.com

  # remove fake user from galaxy.ini admin section
  sed -i 's\^admin_users = placeholder@placeholder.com\#admin_users = None\' $galaxy_config_file
}

#________________________________
# Clean package manager cache
function clean_package_manager_cache(){

  echo "Clean package manager cache"
  if [[ $DISTNAME = "ubuntu" ]]; then
    apt-get clean
  else
    yum clean all
  fi

}

#________________________________
# Copy remove cloud-init artifact and user  script
# Run this script after setup finished
function copy_clean_instance_script(){
  wget ${repository_url}/clean_instance.sh -O /tmp/clean_instance.sh
  chmod +x /tmp/clean_instance.sh
}

#________________________________
# MAIN FUNCTION

{

# install dependencies
prerequisites

if [[ $galaxy_flavor == "base_image" ]]; then
  if [[ $action == 'BUILD' ]]; then build_base_image; fi

elif [[ $galaxy_flavor == "slurm_base_image" ]]; then
  if [[ $action == 'BUILD' ]]; then build_slurm_base_image; fi

elif [[ $galaxy_flavor == "run_tools_script" ]]; then
  start_postgresql
  run_tools_script
  if [[ $action == 'BUILD' ]]; then stop_services; fi
  if [[ $action == 'RUN' ]]; then start_services; fi

else
  # Prepare the system: install ansible, ansible roles
  install_ansible
  install_ansible_roles
  # Run ansible play
  run_playbook
  # Stop all services and remove ansible
  if [[ $action == 'BUILD' ]]; then stop_services; fi
  if [[ $action == 'BUILD' ]]; then remove_ansible; fi

fi

# Clean the environment
clean_package_manager_cache
copy_clean_instance_script

} &>> $LOGFILE

echo 'End setup script' &>> $LOGFILE
