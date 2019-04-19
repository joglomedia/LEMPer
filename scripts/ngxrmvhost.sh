#!/usr/bin/env bash

#  +------------------------------------------------------------------------+
#  | NgxVhost - Simple Nginx vHost Configs File Generator                   |
#  +------------------------------------------------------------------------+
#  | Copyright (c) 2014-2019 NgxTools (https://ngxtools.eslabs.id)          |
#  +------------------------------------------------------------------------+
#  | This source file is subject to the New BSD License that is bundled     |
#  | with this package in the file docs/LICENSE.txt.                        |
#  |                                                                        |
#  | If you did not receive a copy of the license and are unable to         |
#  | obtain it through the world-wide-web, please send an email             |
#  | to license@eslabs.id so we can send you a copy immediately.            |
#  +------------------------------------------------------------------------+
#  | Authors: Edi Septriyanto <eslabs.id@gmail.com>                         |
#  +------------------------------------------------------------------------+

# Version Control
APPNAME="ngxrmvhost"
VERSION="1.5.0-beta"

# May need to run this as sudo!
# I have it in /usr/local/bin and run command 'ngxvhost' from anywhere, using sudo.
if [ $(id -u) -ne 0 ]; then
    echo "You must be root: 'sudo $APPNAME'" >&2
    exit 1  #error
fi

# Help
function show_usage {
cat <<- _EOF_
$APPNAME, enable/disable/remove Nginx vHost config file in Ubuntu Server.

Requirements: 
 Nginx with /etc/nginx/sites-available and /etc/nginx/sites-enabled setup used.

Usage:
 $APPNAME [OPTION]...

Options:
 -e, --enable         enable vhost 
 -d, --disable        disable vhost
 -r, --remove         remove vhost

 -h, --help     display this help and exit
 -V, --version  output version information and exit
 
Example:
 $APPNAME --remove example.com

For more details visit http://masedi.net.
Mail bug reports and suggestions to <hi@masedi.net>.
_EOF_
}

#ngxrmvhost --enable vhost
function enable_vhost {
    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/$1.conf" && -f "/etc/nginx/sites-available/$1.conf" ]]; then
        ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/$1.conf
        
        # Reload Nginx.
        service nginx reload -s
        echo "Your site $1 has been enabled..."
    else
        echo "Sorry, we can't find $1. Probably, it has been enabled or not yet created..."
    fi
    exit 0
}

#ngxvhost --disable vhost
function disable_vhost {
    # Disable Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/$1.conf" ]; then
        unlink /etc/nginx/sites-enabled/$1.conf
        
        # Reload Nginx.
        service nginx reload -s
        echo "Your site $1 has been disabled..."
    else
        echo "Sorry, we can't find $1. Probably, it has been disabled or removed..."
    fi
    exit 0  #success
}

#ngxvhost --remove sitename
function remove_vhost {
    # Remove Nginx's vhost config.
    if [ -f "/etc/nginx/sites-available/$1.conf" ]; then
        echo "Sorry, we can't find Nginx config for $1..."
    else
        unlink /etc/nginx/sites-enabled/$1.conf
        rm -f /etc/nginx/sites-available/$1.conf

        # Remove vhost root directory.
        echo -n "Do you want to delete website root directory? (Y/n): "; read isdeldir
        if [[ "${isdeldir}" = "Y" || "${isdeldir}" = "y" || "${isdeldir}" = "yes" ]]; then
            echo -n "Enter the real path to website root directory: "; read sitedir
            rm -fr ${sitedir}
        fi

        # Drop MySQL database.
        echo -n "Do you want to Drop database associated to this website? (Y/n): "; read isdropdb
        if [[ "${isdropdb}" = "Y" || "${isdropdb}" = "y" || "${isdropdb}" = "yes" ]]; then
            echo -n "MySQL username: "; read username
            echo -n "MySQL password: "; stty -echo; read password; stty echo; echo
            sleep 1
            echo "Starting to drop database, please select your database name!"
            echo -n "MySQL database: "; read dbname
            
            mysql -u $username -p"$password" -e "DROP DATABASE $dbname"
        fi

        # Reload Nginx.
        service nginx reload -s
        echo "Your site $1 has been removed..."
    fi
    exit 0  #success
}

# Sanity Check - are there an arguments with value?

#getopt
OPTS=`getopt -o Vhe:d:r: -l help,version,enable:,disable:,remove: -- "$@"`

if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$OPTS"

while true ; do
    case "$1" in
        -h | --help) show_usage; exit 0; shift;;
        -e | --enable) enable_vhost $2; shift 2;;
        -d | --disable) disable_vhost $2; shift 2;;
        -r | --remove) remove_vhost $2; shift 2;;
        -V | --version) echo "$APPNAME version $VERSION"; exit 1; shift;;
        --) shift; break;;
    esac
done

echo "$APPNAME: missing optstring argument"
echo "Try '$APPNAME --help' for more information."
