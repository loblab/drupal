#!/bin/bash
# Copyright 2017 loblab
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
PROG_DIR=$(dirname $0)

CONFIG=$1
if [ -z "$CONFIG" ]; then
    echo "Usage: $0 [config-file-name], default 'sample'. file extension is '.conf'. "
    echo "  Continue in 10 seconds... (Ctrl+C to stop)"
    CONFIG=sample
    sleep 10 
fi

function log_msg() {
    echo $(date +'%m/%d %H:%M:%S') - $*
}

function install_system_packages() {
    log_msg "Install system packages..."
    codename=$(lsb_release -cs)
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get -y install mysql-server
    sudo apt-get -y install mysql-client
    sudo apt-get -y install nginx
    if [ "$codename" == "jessie" ]; then
        sudo apt-get -y install php5-fpm php5-mysql php5-gd
    else
        sudo apt-get -y install php-fpm php-mysql php-gd php-xml php-mbstring
    fi
    log_msg "Install system packages... done."
}

function install_php_composer() {
    log_msg "Install PHP composer..."
    # See https://getcomposer.org/download/
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php -r "if (hash_file('SHA384', 'composer-setup.php') === '544e09ee996cdf60ece3804abc52599c22b1f40f4323403c44d44fdfdd586475ca9813a858088ffbc1f233e9b180f061') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
    php composer-setup.php
    php -r "unlink('composer-setup.php');"
    # See https://getcomposer.org/doc/00-intro.md#globally
    sudo mv composer.phar /usr/local/bin/composer
    log_msg "Install PHP composer... done."
}

function setup_database() {
    log_msg "Setup database..."
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" 
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"

    echo "[client]" > ~/.my.cnf
    echo "user=$DB_USER" >> ~/.my.cnf
    echo "password=$DB_PASS" >> ~/.my.cnf
    echo "socket=/var/run/mysqld/mysqld.sock" >> ~/.my.cnf
    chmod 600 ~/.my.cnf
    log_msg "Setup database... done."
}

function setup_nginx_drupal_config() {
    log_msg "Donwload nginx config for drupal..."
    cfgfile=/etc/nginx/sites-available/drupal$DRUPAL_MAJOR
    wget -q -O - https://www.nginx.com/resources/wiki/start/topics/recipes/drupal/ |
        perl -pe 's/<.+?>//g' | 
        grep "server {" -A 102 | 
        perl -mHTML::Entities -ne 'print HTML::Entities::decode_entities($_);' |
        perl -pe "s/server_name .+?;/server_name _;/" |
        sed '/location ~ \\..*\/.*\\.php$ {/i \ \ \ \ rewrite ^/core/authorize.php/core/authorize.php(.*)$ /core/authorize.php$1;' |
        sudo tee $cfgfile
    ps -A | grep php5 && php5=1 || php5=0
    if [ $php5 -eq 1 ]; then
        sudo perl -pe 's/#(fastcgi_pass.+php5.+fpm.sock;)/$1/' -i $cfgfile
        sudo perl -pe 's/(fastcgi_pass.+php7.+fpm.sock;)/#$1/' -i $cfgfile
    fi
    cd /etc/nginx/sites-enabled
    sudo ln -sf $cfgfile drupal$DRUPAL_MAJOR
    sudo rm -f default
    sudo service nginx restart
    log_msg "Donwload nginx config for drupal... done."
}

function install_drush() {
    log_msg "Install drush..."
    php -r "readfile('http://files.drush.org/drush.phar');" > drush
    chmod +x drush
    sudo mv drush /usr/local/bin
    drush -y init
    log_msg "Install drush... done."
}

function install_drupal() {
    log_msg "Install drupal..."
    #https://www.drupal.org/documentation/install/developers
    cd $WWW_DIR
    sudo chown -R $MY_ACCOUNT .
    drush -y dl drupal-$DRUPAL_MAJOR
    ver=$(ls -d drupal-$DRUPAL_MAJOR.*/ | sort | tail -n 1 | perl -ne 'print $1 if m#-(.+)/#')
    if [ -z "$ver" ]; then
        echo "Cannot find avaiable drupal version"
        exit 1
    fi
    if [ -f $DRUPAL_DIR ]; then
        rm -f $DRUPAL_DIR
    fi
    ln -s drupal-$ver $DRUPAL_DIR

    cd $DRUPAL_DIR
    composer install
    for module in $PHP_MODULES
    do
        log_msg "Install PHP module: $module..."
        composer require $module
    done

    drush -y site-install $PROFILE --db-url="mysql://$DB_USER:$DB_PASS@localhost/$DB_NAME" --site-name=$SITE_NAME --account-name="$ADMIN_NAME" --account-pass="$ADMIN_PASS" --account-mail="$ADMIN_MAIL"
    host1=$(hostname -I | perl -pe 's/\./\\./g' | perl -pe 's/ //g')
    host2=$(echo $SITE_FQDN | perl -pe 's/\./\\./g')
    config="\$settings['trusted_host_patterns'] = array(
     '^$host1$',
     '^$host2$',
 );
"
    cfgfile=sites/default/settings.php
    sudo chmod 644 $cfgfile
    echo "$config" >> $cfgfile
    sudo chmod 444 $cfgfile
    sudo chown -R $WEB_ACCOUNT modules themes sites/default
    log_msg "Install drupal... done."
}

function setup_drupal_users() {
    log_msg "Create drupal users..."
    drush user-create $USER_NAME --password="$USER_PASS" --mail="$USER_MAIL"
    log_msg "Create drupal users... done."
}

function setup_drupal_modules() {
    log_msg "Download & enable/disable drupal modules..."
    sudo chown -R $MY_ACCOUNT modules
    for module in $DRUPAL_MODULES
    do
        log_msg "Install Drupal module: $module..."
        $DRUSH en $module
    done
    sudo chown -R $WEB_ACCOUNT modules
    log_msg "Download & enable/disable drupal modules... done."
}

function setup_drupal_themes() {
    log_msg "Download & enable/disable drupal themes..."
    sudo chown -R $MY_ACCOUNT themes
    for theme in $DRUPAL_THEMES
    do
        $DRUSH en $theme
    done
    sudo chown -R $WEB_ACCOUNT themes
    $DRUSH config-set system.theme default $DEFAULT_THEME
    $DRUSH config-set system.theme admin $ADMIN_THEME
    log_msg "Download & enable/disable drupal themes... done."
}

function main() {
    log_msg "Load $CONFIG.conf..."
    source $PROG_DIR/$CONFIG.conf
    DRUPAL_DIR=$WWW_DIR/drupal$DRUPAL_MAJOR
    DRUSH="drush -r $DRUPAL_DIR -l $SITE_URL -y"
    install_system_packages
    MY_ACCOUNT=$(id -un):$(id -gn)
    WEB_ACCOUNT=$(ps -Ao user,group,cmd | grep nginx | grep worker | head -n 1 | awk '{printf "%s:%s\n", $1, $2}')
    install_php_composer
    install_drush
    setup_database
    setup_nginx_drupal_config
    install_drupal
    setup_drupal_users
    setup_drupal_modules
    setup_drupal_themes
    $DRUSH cron
    addr=$(hostname -I | sed 's/ //g')
    log_msg "Succeeded. Please access http://$addr/ ($ADMIN_NAME/$ADMIN_PASS or $USER_NAME/$USER_PASS)"
}

main

