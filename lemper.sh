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
        echo ""
        while [[ $SECURED_SERVER != "y" && $SECURED_SERVER != "n" ]]; do
            read -p "Do you want to enable basic server security? [y/n]: " -e SECURED_SERVER
		done
        if [[ "$SECURED_SERVER" == Y* || "$SECURED_SERVER" == y* ]]; then
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

        ### Remove Nginx ###
        if [ -f scripts/remove_nginx.sh ]; then
            . scripts/remove_nginx.sh
        fi

        ### Remove PHP & FPM ###
        if [ -f scripts/remove_php.sh ]; then
            . scripts/remove_php.sh
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


        ### Remove MySQL ###
        if [ -f scripts/remove_mariadb.sh ]; then
            . scripts/remove_mariadb.sh
        fi
        
        # Remove default user account
        if [ "$(type -t delete_account)" == "function" ]; then
            delete_account "lemper"
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
