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
# | Last Update       : 24/06/2019                                          |
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
    . scripts/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
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

### Main ###
case $1 in
    --install)
        header_msg
        echo -e "\nStarting LEMP stack installation...\nPlease ensure that you're on a fresh box install!\n"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        ### Clean up ###
        . scripts/cleanup_server.sh

        ### ADD Repos ###
        . scripts/add_repo.sh

        ### Nginx Installation ###
        . scripts/install_nginx.sh

        ### PHP Installation ###
        . scripts/install_php.sh
        . scripts/install_memcache.sh

        ### MySQL Database Installation ###
        . scripts/install_mariadb.sh

        ### Redis Database Installation ###
        . scripts/install_redis.sh

        ### Mail Server Installation ###
        . scripts/install_postfix.sh

        ### Install Let's Encrypt SSL ###
        . scripts/install_letsencrypt.sh

        ### Addon Installation ###
        . scripts/install_tools.sh

        ### FINAL STEP ###
        # Cleaning up all build dependencies hanging around on production server?
        run apt-get autoremove -y

        status -e "\nLEMPer installation has been completed."

        ### Recap ###
        if [[ ! -z "$katasandi" ]]; then
            status -e "\nHere is your default system account information:

        Server IP : ${IPAddr}
        SSH Port  : 22
        Username  : lemper
        Password  : ${katasandi}

        Please keep it private!
        "
        fi

        echo -e "\nNow, you can reboot your server and enjoy it!\n"
    ;;
    --uninstall)
        header_msg
        echo -e "\nAre you sure to remove LEMP stack installation?\n"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        # Remove nginx
        echo -e "\nUninstalling Nginx...\n"

        if [[ -n $(which nginx) ]]; then
            # Stop Nginx web server
            run service nginx stop

            # Remove Nginx
            if [ $(dpkg-query -l | grep nginx-common | awk '/nginx-common/ { print $2 }') ]; then
            	echo "Nginx-common package found. Removing..."
                run apt-get remove -y nginx-common
            elif [ $(dpkg-query -l | grep nginx-custom | awk '/nginx-custom/ { print $2 }') ]; then
            	echo "Nginx-custom package found. Removing..."
                run apt-get remove -y nginx-custom
            elif [ $(dpkg-query -l | grep nginx-stable | awk '/nginx-stable/ { print $2 }') ]; then
            	echo "Nginx-stable package found. Removing..."
                run apt-get remove -y nginx-stable
            else
            	echo "Nginx package not found. Possibly installed from source."

                # Only if nginx package not installed / nginx installed from source)
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

            echo -en "Completely remove Nginx configuration files (This action is not reversible)? [Y/n]: "
            read rmngxconf
            if [[ "${rmngxconf}" == Y* || "${rmngxconf}" == y* ]]; then
        	    echo "All your Nginx configuration files deleted permanently..."
        	    run rm -fr /etc/nginx
        	    # rm nginx-cache
        	    run rm -fr /var/cache/nginx
        	    # rm nginx html
        	    run rm -fr /usr/share/nginx
            fi
        else
            warning "Nginx installation not found."
        fi

        # Remove PHP
        echo -e "\nUninstalling PHP FPM...\n"

        if [[ -n $(which php-fpm5.6) \
            || -n $(which php-fpm7.0) \
            || -n $(which php-fpm7.1) \
            || -n $(which php-fpm7.2) \
            || -n $(which php-fpm7.3) ]]; then
            # Stop php5-fpm server
            service php5.6-fpm stop
            service php7.0-fpm stop
            service php7.1-fpm stop
            service php7.2-fpm stop
            service php7.3-fpm stop

            # Stop Memcached server
            run service memcached stop

            # Stop Redis server
            run service redis-server stop

            run apt-get --purge remove -y php* php*-* pkg-php-tools spawn-fcgi geoip-database snmp memcached redis-server

            echo -n "Completely remove PHP-FPM configuration files (This action is not reversible)? [Y/n]: "
            read rmfpmconf
            if [[ "${rmfpmconf}" == Y* || "${rmfpmconf}" == y* ]]; then
        	    echo "All your PHP-FPM configuration files deleted permanently..."
        	    run rm -fr /etc/php/
        	    # Remove ioncube
                run rm -fr /usr/lib/php/loaders/
            fi
        else
            warning "PHP installation not found."
        fi

        # Remove MySQL
        echo -e "\nUninstalling MariaDB (SQL DBMS)...\n"

        if [[ -n $(which mysql) ]]; then
            # Stop MariaDB mysql server
            run service mysql stop

            run apt-get remove -y mariadb-server-10.1 mariadb-client-10.1 mariadb-server-core-10.1 mariadb-common mariadb-server libmariadbclient18 mariadb-client-core-10.1

            echo -n "Completely remove MariaDB SQL database and configuration files (This action is not reversible)? [Y/n]: "
            read rmsqlconf
            if [[ "${rmsqlconf}" == Y* || "${rmsqlconf}" == y* ]]; then
        	    echo "All your SQL database and configuration files deleted permanently..."
        	    run rm -fr /etc/mysql
        	    run rm -fr /var/lib/mysql
            fi
        else
            warning "MariaDB installation not found."
        fi

        #run apt-get autoremove -y
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
