#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx 1.10                                                        |
# |     - PHP 5.6/7.0/7.1/7.2/7.3                                           |
# |     - Zend OpCache 7.0.3                                                |
# |     - Memcached 1.4.14                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 02/07/2019                                          |
# | Author            : ESLabs.ID (eslabs.id@gmail.com)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/lemper)               |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

set -e  # Work even if somebody does "sh thisscript.sh".

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

# Make sure this script only run on Ubuntu install
if [ ! -f "/etc/lsb-release" ]; then
    warning -e "\nThis installer only work on Ubuntu server..."
    exit 1
else
    # Variables
    arch=$(uname -p)
    IPAddr=$(hostname -i)

    # export lsb-release vars
    . /etc/lsb-release

    MAJOR_RELEASE_NUMBER=$(echo $DISTRIB_RELEASE | awk -F. '{print $1}')

    if [[ "$DISTRIB_ID" == "LinuxMint" ]]; then
        DISTRIB_RELEASE="LM${MAJOR_RELEASE_NUMBER}"
    fi
fi

# init log
run touch lemper.log
echo "" > lemper.log

### Main ###
case $1 in
    --install)
        header_msg
        echo -e "\nStarting LEMP stack installation...\nPlease ensure that you're on a fresh machine install!"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        ### Clean-up server ###
        if [ -f scripts/cleanup_server.sh ]; then
            . scripts/cleanup_server.sh
        fi

        ### Check swap ###
        check_swap

        ### Create default account ###
        create_account "lemper"

        ### ADD repositories ###
        if [ -f scripts/add_repo.sh ]; then
            . scripts/add_repo.sh
        fi

        ### Nginx installation ###
        if [ -f scripts/install_nginx.sh ]; then
            . scripts/install_nginx.sh
        fi

        ### PHP installation ###
        if [ -f scripts/install_php.sh ]; then
            . scripts/install_php.sh
        fi

        ### Memcached installation ###
        if [ -f scripts/install_memcache.sh ]; then
            . scripts/install_memcache.sh
        fi

        ### MySQL database installation ###
        if [ -f scripts/install_mariadb.sh ]; then
            . scripts/install_mariadb.sh
        fi

        ### Redis database installation ###
        if [ -f scripts/install_redis.sh ]; then
            . scripts/install_redis.sh
        fi

        ### Certbot Let's Encrypt SSL installation ###
        if [ -f scripts/install_letsencrypt.sh ]; then
            . scripts/install_letsencrypt.sh
        fi

        ### Mail server installation ###
        if [ -f scripts/install_mailer.sh ]; then
            . scripts/install_mailer.sh
        fi

        ### Addon-tools installation ###
        if [ -f scripts/install_tools.sh ]; then
            . scripts/install_tools.sh
        fi

        ### Basic server security
        echo -en "Do you want to enable basic server security? [y/n]: "
        read secureServer
        if [[ "${secureServer}" == Y* || "${secureServer}" == y* ]]; then
            if [ -f scripts/secure_server.sh ]; then
                . scripts/secure_server.sh
            fi
        fi

        ### FINAL STEP ###
        # Cleaning up all build dependencies hanging around on production server?
        run apt-get autoremove -y >> lemper.log 2>&1

        status -e "\nLEMPer installation has been completed."

        ### Recap ###
        if [[ ! -z "$PASSWORD" ]]; then
            status -e "\nHere is your default system account information:

        Server IP : ${IPAddr}
        SSH Port  : ${SSHPort}
        Username  : ${USERNAME}
        Password  : ${PASSWORD}

        Access to your Database administration (Adminer):
        http://${IPAddr}:8082/

        Access to your File manager (FileRun):
        http://${IPAddr}:8083/

        Please Save & Keep It Private!
        "
        fi

        echo -e "\nSee the log file (lemper.log) for more information.
        \nNow, you can reboot your server and enjoy it!\n"
    ;;
    --uninstall)
        header_msg
        echo -e "\nAre you sure to remove LEMP stack installation?"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        # Fix broken install, first?
        run apt-get --fix-broken install >> lemper.log 2>&1

        # Remove nginx
        echo -e "\nUninstalling Nginx..."

        if [[ -n $(which nginx) ]]; then
            # Stop Nginx web server process
            run service nginx stop

            # Remove Nginx
            if [ $(dpkg-query -l | grep nginx-common | awk '/nginx-common/ { print $2 }') ]; then
            	echo "Nginx-common package found. Removing..."
                run apt-get --purge remove -y nginx-common >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
            elif [ $(dpkg-query -l | grep nginx-custom | awk '/nginx-custom/ { print $2 }') ]; then
            	echo "Nginx-custom package found. Removing..."
                run apt-get --purge remove -y nginx-custom >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:rtcamp/nginx >> lemper.log 2>&1
                run rm -f /etc/apt/sources.list.d/nginx-*.list
            elif [ $(dpkg-query -l | grep nginx-full | awk '/nginx-full/ { print $2 }') ]; then
            	echo "Nginx-full package found. Removing..."
                run apt-get --purge remove -y nginx-full >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
            elif [ $(dpkg-query -l | grep nginx-stable | awk '/nginx-stable/ { print $2 }') ]; then
            	echo "Nginx-stable package found. Removing..."
                run apt-get --purge remove -y nginx-stable >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
            else
            	echo "Nginx package not found. Possibly installed from source."

                # Only if nginx package not installed / nginx installed from source
                if [ -f /usr/sbin/nginx ]; then
                    run rm -f /usr/sbin/nginx
                fi

                if [ -f /etc/init.d/nginx ]; then
                    run rm -f /etc/init.d/nginx
                fi

                if [ -f /lib/systemd/system/nginx.service ]; then
                    run rm -f /lib/systemd/system/nginx.service
                fi

                if [ -d /usr/lib/nginx/ ]; then
                    run rm -fr /usr/lib/nginx/
                fi

                if [ -d /etc/nginx/modules-available ]; then
                    run rm -fr /etc/nginx/modules-available
                fi

                if [ -d /etc/nginx/modules-enabled ]; then
                    run rm -fr /etc/nginx/modules-enabled
                fi
            fi

            echo -n "Completely remove Nginx configuration files (this action is not reversible)? [y/n]: "
            read rmngxconf
            if [[ "${rmngxconf}" == Y* || "${rmngxconf}" == y* ]]; then
        	    echo "All your Nginx configuration files deleted permanently..."
        	    run rm -fr /etc/nginx
        	    # Remove nginx-cache
        	    run rm -fr /var/cache/nginx
        	    # Remove nginx html
        	    run rm -fr /usr/share/nginx
            fi

            if [[ -z $(which nginx) ]]; then
                status "Nginx web server removed."
            fi
        else
            warning "Nginx installation not found."
        fi

        # Remove PHP
        echo -e "\nUninstalling PHP & FPM..."

        if [[ -n $(which php-fpm5.6) \
            || -n $(which php-fpm7.0) \
            || -n $(which php-fpm7.1) \
            || -n $(which php-fpm7.2) \
            || -n $(which php-fpm7.3) ]]; then

            # Related PHP packages to be removed
            DEBPackages=()

            # Stop default PHP FPM process
            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/5.6" | wc -l) > 0 ]]; then
                run service php5.6-fpm stop
            fi
            if [[ -n $(which php-fpm5.6) ]]; then
                DEBPackages=("php5.6 php5.6-bcmath php5.6-cli php5.6-common \
                    php5.6-curl php5.6-dev php5.6-fpm php5.6-mysql php5.6-gd \
                    php5.6-gmp php5.6-imap php5.6-intl php5.6-json php5.6-ldap \
                    php5.6-mbstring php5.6-opcache php5.6-pspell php5.6-readline \
                    php5.6-recode php5.6-snmp php5.6-soap php5.6-sqlite3 \
                    php5.6-tidy php5.6-xml php5.6-xmlrpc php5.6-xsl php5.6-zip" "${DEBPackages[@]}")
            fi

            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.0" | wc -l) > 0 ]]; then
                run service php7.0-fpm stop
            fi
            if [[ -n $(which php-fpm7.0) ]]; then
                DEBPackages=("php7.0 php7.0-bcmath php7.0-cli php7.0-common \
                    php7.0-curl php7.0-dev php7.0-fpm php7.0-mysql php7.0-gd \
                    php7.0-gmp php7.0-imap php7.0-intl php7.0-json php7.0-ldap \
                    php7.0-mbstring php7.0-opcache php7.0-pspell php7.0-readline \
                    php7.0-recode php7.0-snmp php7.0-soap php7.0-sqlite3 \
                    php7.0-tidy php7.0-xml php7.0-xmlrpc php7.0-xsl php7.0-zip" "${DEBPackages[@]}")
            fi

            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.1" | wc -l) > 0 ]]; then
                run service php7.1-fpm stop
            fi
            if [[ -n $(which php-fpm7.1) ]]; then
                DEBPackages=("php7.1 php7.1-bcmath php7.1-cli php7.1-common \
                    php7.1-curl php7.1-dev php7.1-fpm php7.1-mysql php7.1-gd \
                    php7.1-gmp php7.1-imap php7.1-intl php7.1-json php7.1-ldap \
                    php7.1-mbstring php7.1-opcache php7.1-pspell php7.1-readline \
                    php7.1-recode php7.1-snmp php7.1-soap php7.1-sqlite3 \
                    php7.1-tidy php7.1-xml php7.1-xmlrpc php7.1-xsl php7.1-zip" "${DEBPackages[@]}")
            fi

            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.2" | wc -l) > 0 ]]; then
                run service php7.2-fpm stop
            fi
            if [[ -n $(which php-fpm7.2) ]]; then
                DEBPackages=("php7.2 php7.2-bcmath php7.2-cli php7.2-common \
                    php7.2-curl php7.2-dev php7.2-fpm php7.2-mysql php7.2-gd \
                    php7.2-gmp php7.2-imap php7.2-intl php7.2-json php7.2-ldap \
                    php7.2-mbstring php7.2-opcache php7.2-pspell php7.2-readline \
                    php7.2-recode php7.2-snmp php7.2-soap php7.2-sqlite3 \
                    php7.2-tidy php7.2-xml php7.2-xmlrpc php7.2-xsl php7.2-zip" "${DEBPackages[@]}")
            fi

            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.3" | wc -l) > 0 ]]; then
                run service php7.3-fpm stop
            fi
            if [[ -n $(which php-fpm7.3) ]]; then
                DEBPackages=("php7.3 php7.3-bcmath php7.3-cli php7.3-common \
                    php7.3-curl php7.3-dev php7.3-fpm php7.3-mysql php7.3-gd \
                    php7.3-gmp php7.3-imap php7.3-intl php7.3-json php7.3-ldap \
                    php7.3-mbstring php7.3-opcache php7.3-pspell php7.3-readline \
                    php7.3-recode php7.3-snmp php7.3-soap php7.3-sqlite3 \
                    php7.3-tidy php7.3-xml php7.3-xmlrpc php7.3-xsl php7.3-zip" "${DEBPackages[@]}")
            fi

            if [[ -n ${DEBPackages} ]]; then
                run apt-get --purge remove -y ${DEBPackages} \
                    fcgiwrap php-geoip php-pear pkg-php-tools spawn-fcgi geoip-database >> lemper.log 2>&1
                #run apt-get purge -y ${DEBPackages} >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:ondrej/php >> lemper.log 2>&1
            fi

            echo -n "Completely remove PHP-FPM configuration files (This action is not reversible)? [y/n]: "
            read rmfpmconf
            if [[ "${rmfpmconf}" == Y* || "${rmfpmconf}" == y* ]]; then
        	    echo "All your PHP-FPM configuration files deleted permanently..."
                if [[ -d /etc/php ]]; then
                    run rm -fr /etc/php
                fi
        	    # Remove ioncube
                if [[ -d /usr/lib/php/loaders ]]; then
                    run rm -fr /usr/lib/php/loaders
                fi
            fi

            status "PHP & FPM removed."
        else
            warning "PHP installation not found."
        fi

        # Remove Memcached if exists
        if [[ -n $(which memcached) ]]; then
            echo -e "\nUninstalling Memcached..."

            # Stop Memcached server process
            if [[ $(ps -ef | grep -v grep | grep memcached | wc -l) > 0 ]]; then
                run service memcached stop
            fi

            run apt-get --purge remove -y libmemcached11 memcached php-igbinary \
                php-memcache php-memcached php-msgpack >> lemper.log 2>&1
            #run apt-get purge -y libmemcached11 memcached php-igbinary \
            #    php-memcache php-memcached php-msgpack >> lemper.log 2>&1
            #run rm -f /etc/memcached.conf

            if [[ -z $(which memcached) ]]; then
                status "Memcached server removed."
            fi
        fi

        # Remove Redis if exists
        if [[ -n $(which redis-server) ]]; then
            echo -e "\nUninstalling Redis..."

            # Stop Redis server process
            if [[ $(ps -ef | grep -v grep | grep redis-server | wc -l) > 0 ]]; then
                run service redis-server stop
            fi

            run apt-get --purge remove -y redis-server >> lemper.log 2>&1
            #run apt-get purge -y redis-server >> lemper.log 2>&1
            run add-apt-repository -y --remove ppa:chris-lea/redis-server >> lemper.log 2>&1
            #run rm -f /etc/redis/redis.conf

            if [[ -z $(which redis-server) ]]; then
                status "Redis server removed."
            fi
        fi


        # Remove MySQL
        echo -e "\nUninstalling MariaDB (MySQL)..."

        if [[ -n $(which mysql) ]]; then
            # Stop MariaDB mysql server process
            if [[ $(ps -ef | grep -v grep | grep mysqld | wc -l) > 0 ]]; then
                run service mysql stop
            fi

            run apt-get --purge remove -y mariadb-server libmariadbclient18 >> lemper.log 2>&1
            #run apt-get purge -y mariadb-server libmariadbclient18 >> lemper.log 2>&1

            # Remove repo
            run rm -f /etc/apt/sources.list.d/MariaDB-*.list

            echo -n "Completely remove MariaDB SQL database and configuration files (This action is not reversible)? [y/n]: "
            read rmsqlconf
            if [[ "${rmsqlconf}" == Y* || "${rmsqlconf}" == y* ]]; then
        	    echo "All your SQL database and configuration files deleted permanently."
                if [[ -d /etc/mysql ]]; then
            	    run rm -fr /etc/mysql
                fi
                if [[ -d /var/lib/mysql ]]; then
                    run rm -fr /var/lib/mysql
                fi
            fi

            if [[ -z $(which mysql) ]]; then
                status "MariaDB (MySQL) server removed."
            fi
        else
            warning -e "MariaDB installation not found."
        fi

        # Remove default user
        echo -en "\nRemove default LEMPer account? [y/n]: "
        read rmdefaultuser
        if [[ "${rmdefaultuser}" == Y* || "${rmdefaultuser}" == y* ]]; then
            USERNAME="lemper" # default system account for LEMPer
            if [[ ! -z $(getent passwd "${USERNAME}") ]]; then
                run userdel -r ${USERNAME} >> lemper.log 2>&1
                status "Default LEMPer account deleted."
            else
                warning "Default LEMPer account not found."
            fi
        fi

        # Remove unnecessary packages
        echo -e "\nCleaning up unnecessary packages..."
        run apt-get autoremove -y >> lemper.log 2>&1

        status -e "LEMP stack has been removed completely.\n"
    ;;
    --help)
        echo "Please read the README file for more information!"
        exit 0
    ;;
    *)
        fail "Invalid argument: $1"
        exit 1
    ;;
esac

footer_msg
