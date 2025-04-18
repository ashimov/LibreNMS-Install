#!/bin/bash
# LibreNMS Install script
# NOTE: Script will update and upgrade currently installed packages.
# Updated for Ubuntu 24.04

# Set the script to exit immediately if a command exits with a non-zero status.
set -e

echo "This will install LibreNMS. Developed on Ubuntu 22.04 LTS"
echo "###########################################################"
echo "Updating the repo cache and installing needed repos"
echo "###########################################################"

# Set the system timezone
echo "Have you set the system time zone?: [yes/no]"
read -r ANS # Use read -r to prevent backslash escapes
if [[ "$ANS" =~ ^[Nn][Oo]?$ ]]; then # Use regex for case-insensitive comparison
    echo "We will list the timezones"
    echo "Use q to quit the list"
    echo "-----------------------------"
    sleep 5
    echo " "
    timedatectl list-timezones
    echo "Enter system time zone:"
    read -r TZ
    timedatectl set-timezone "$TZ" # Quote the variable
    echo "The timezone $TZ has been set"
else
    TZ="$(cat /etc/timezone)"
fi

echo " "
echo "updating repos"
apt update -y

# Installing Required Packages
echo " "
echo "Installing required packages"
apt install -y software-properties-common
# Workaround for non-UTF-8 locales
LC_ALL=C.UTF-8 add-apt-repository universe
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php # Add the Ondrej PPA for more recent PHP versions
apt update -y
echo "Upgrading installed packages in the system"
echo "###########################################################"
apt upgrade -y
echo "Installing dependencies" # Corrected spelling
echo "###########################################################"
sleep 1
echo " Here "
sleep 1
echo  " we "
sleep 2
echo " GO!!! "
echo "###########################################################"
echo "###########################################################"

# Version 8 has moved json into core code and it is no longer a separate module.
# composer, python3-memcashe, not listed for 22.04
apt install -y acl composer curl fping git graphviz imagemagick mariadb-client \
    mariadb-server mtr-tiny nginx-full nmap php8.3-cli php8.3-curl php8.3-fpm \
    php8.3-gd php8.3-gmp php8.3-mbstring php8.3-mysql php8.3-snmp php8.3-xml \
    php8.3-zip python3-pymysql python3-psutil python3-setuptools python3-systemd python3-pip rrdtool \
    snmp snmpd whois unzip traceroute

# Download LibreNMS
echo "Downloading libreNMS to /opt"
echo "###########################################################"
cd /opt
git clone https://github.com/librenms/librenms.git

# Add librenms user
echo "Creating libreNMS user account, set the home directory, don't create it."
echo "###########################################################"
# add user link home directory, do not create home directory, system user
useradd librenms -d /opt/librenms -M -r -s "$(which bash)"

# Add librenms user to www-data group
# echo "Adding libreNMS user to the www-data group"
# echo "###########################################################"
# usermod -a -G www-data librenms # Corrected group name

# Set permissions and access controls
echo "Setting permissions and file access controls"
echo "###########################################################"
# set owner:group recursively on directory
chown -R librenms:librenms /opt/librenms
# mod permission on directory O=All,G=All, Oth=none
chmod 771 /opt/librenms
# mod default ACL
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
# mod ACL recursively
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/

### Install PHP dependencies
echo "running PHP installer script as librenms user"
echo "###########################################################"
# run php dependencies installer
su librenms -s /bin/bash -c '/opt/librenms/scripts/composer_wrapper.php install --no-dev' # Added -s /bin/bash
# warn for failure
echo " "
echo "###########################################################"
echo "The script may fail when using a proxy. The workaround is to install the composer \
package manually. See the install page of LibreNMS."
echo " "
sleep 10

# Configure MySQL (mariadb)
echo "###########################################################"
echo "Configuring MariaDB"
echo "###########################################################"
systemctl restart mariadb

# Pass commands to mysql and create DB, user, and privileges
echo " "
echo "Please enter a password for the Database:"
read -r ANS
echo " "
echo "###########################################################"
echo "######### MariaDB DB:librenms Password:$ANS #################"
echo "###########################################################"
mysql -uroot -e "CREATE DATABASE librenms CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -uroot -e "CREATE USER 'librenms'@'localhost' IDENTIFIED BY '$ANS';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

##### Within the [mysqld] section of the config file please add: ####
## innodb_file_per_table=1
## lower_case_table_names=0
sed -i '/\[mysqld\]/ a innodb_file_per_table=1' /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i '/\[mysqld\]/ a lower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf

##### Restart mysql and enable run at startup
systemctl restart mariadb
systemctl enable mariadb

### Configure and Start PHP-FPM ####
## NEW in 20.04 brought forward to 22.04##
cp /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/librenms.conf
# vi /etc/php/8.3/fpm/pool.d/librenms.conf
#line 4
sed -i 's/\[www\]/\[librenms\]/' /etc/php/8.3/fpm/pool.d/librenms.conf
# line 23
sed -i 's/user = www-data/user = librenms/' /etc/php/8.3/fpm/pool.d/librenms.conf
# line 24
sed -i 's/group = www-data/group = librenms/' /etc/php/8.3/fpm/pool.d/librenms.conf
# line 36
sed -i 's/listen = \/run\/php\/php8.3-fpm.sock/listen = \/run\/php-fpm-librenms.sock/' /etc/php/8.3/fpm/pool.d/librenms.conf

#### Change time zone to America/[City] in the following: ####
# /etc/php/8.3/fpm/php.ini
# /etc/php/8.3/cli/php.ini
echo "Timezone is being set to $TZ in /etc/php/8.3/fpm/php.ini and /etc/php/8.3/cli/php.ini.  Change if needed."
echo "Changing to $TZ"
echo "################################################################################"
echo " "
# Line 969 Appended
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/8.3/fpm/php.ini
# Line 969 Appended
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/8.3/cli/php.ini
echo "????????????????????????????????????????????????????????????????????????????????"
read -p "Please review changes in another terminal session, then press [Enter] to continue..."

### restart PHP-fpm ###
systemctl restart php8.3-fpm

####  Config NGINX webserver ####
### Create the .conf file ###
echo "################################################################################"
echo "We need to change the server name to the current IP unless the name is resolvable /etc/nginx/conf.d/librenms.conf"
echo "################################################################################"
echo "Enter Hostname [x.x.x.x or serv.example.com]: "
read -r HOSTNAME
echo "server {" > /etc/nginx/conf.d/librenms.conf
echo "  listen 80;" >>/etc/nginx/conf.d/librenms.conf
echo "  server_name $HOSTNAME;" >>/etc/nginx/conf.d/librenms.conf
echo "  root /opt/librenms/html;" >>/etc/nginx/conf.d/librenms.conf
echo "  index index.php;" >>/etc/nginx/conf.d/librenms.conf
echo " " >>/etc/nginx/conf.d/librenms.conf
echo "  charset utf-8;" >>/etc/nginx/conf.d/librenms.conf
echo "  gzip on;" >>/etc/nginx/conf.d/librenms.conf
echo "  gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml \
text/plain text/xsd text/xsl text/xml image/x-icon;" >>/etc/nginx/conf.d/librenms.conf
echo "  location / {" >>/etc/nginx/conf.d/librenms.conf
echo "    try_files $uri $uri/ /index.php?$query_string;" >>/etc/nginx/conf.d/librenms.conf
echo "  }" >>/etc/nginx/conf.d/librenms.conf
echo "  location ~ [^/]\.php(/|$) {" >>/etc/nginx/conf.d/librenms.conf
echo "    fastcgi_pass unix:/run/php-fpm-librenms.sock;" >>/etc/nginx/conf.d/librenms.conf
echo "    fastcgi_split_path_info ^(.+\.php)(/.+)$;" >>/etc/nginx/conf.d/librenms.conf
echo "    include fastcgi.conf;" >>/etc/nginx/conf.d/librenms.conf
echo "  }" >>/etc/nginx/conf.d/librenms.conf
echo "  location ~ /\.(?!well-known).* {" >>/etc/nginx/conf.d/librenms.conf
echo "    deny all;" >>/etc/nginx/conf.d/librenms.conf
echo "  }" >>/etc/nginx/conf.d/librenms.conf
echo "}" >>/etc/nginx/conf.d/librenms.conf

##### remove the default site link #####
rm /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl restart php8.3-fpm

#### Enable LNMS Command completion ####
ln -s /opt/librenms/lnms /usr/bin/lnms
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

### Configure snmpd
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf

### Edit the text which says RANDOMSTRINGGOESHERE and set your own community string.
echo "We need to change community string"
echo "Enter community string for this server [e.g.: public]: "
read -r ANS
sed -i "s/RANDOMSTRINGGOESHERE/$ANS/g" /etc/snmp/snmpd.conf

######## get standard MIBs
curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro

#### Enable SNMP to run at startup ####
systemctl enable snmpd
systemctl restart snmpd

##### Setup Cron job
cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms

####Enable the scheduler
cp /opt/librenms/dist/librenms-scheduler.service /etc/systemd/system/
cp /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/ # Added this line
systemctl enable librenms-scheduler.timer
systemctl start librenms-scheduler.timer

##### Setup logrotate config
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
######
echo " "
echo "###############################################################################################"
echo "Navigate to http://$HOSTNAME/install in your web browser to finish the installation."
echo "###############################################################################################"
echo "Have a nice day! ;)"
#END#
