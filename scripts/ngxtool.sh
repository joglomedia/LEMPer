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
APP_NAME=$(basename "$0")
APP_VERSION="1.6.0"

# Decorator
RED=91
GREEN=92
YELLOW=93

DRYRUN=false

function begin_color() {
    color="$1"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="$1"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    local error_message="$@"
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
INITIAL_ENV=$(printenv | sort)
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run"
        echo " $@"
        env_differences=$(comm -13 <(echo "$INITIAL_ENV") <(printenv | sort))

        if [ -n "$env_differences" ]; then
            echo "  with the following additional environment variables:"
            echo "$env_differences" | sed 's/^/    /'
        fi
    else
        if ! "$@"; then
            error "Failure running '$@', exiting."
            exit 1
        fi
    fi
}

# May need to run this as sudo!
# I have it in /usr/local/bin and run command 'ngxvhost' from anywhere, using sudo.
if [ $(id -u) -ne 0 ]; then
    error "You must be root: sudo ${APP_NAME}"
    exit 1  #error
fi

# Help
function show_usage() {
cat <<- _EOF_
$APP_NAME $APP_VERSION
Simple Nginx virtual host (vHost) manager,
enable/disable/remove Nginx vHost config file in Ubuntu Server.

Requirements:
  * Nginx setup uses /etc/nginx/sites-available and /etc/nginx/sites-enabled
  * PHP FPM setup uses /etc/php/{version_number}/fpm/

Usage:
  $APP_NAME [OPTION]...

Options:
  -e, --enable <vhost domain name>
      Enable virtual host.

  -d, --disable <vhost domain name>
      Disable virtual host..

  -r, --remove <vhost domain name>
      Remove virtual host configuration.

  -s, --enable-ssl <vhost domain name>
      Enable Let's Encrypt SSL certificate.

  -h, --help
      Print this message and exit.

  -v, --version
      Output version information and exit.

Example:
 $APP_NAME --remove example.com

For more details visit https://ngxtools.eslabs.id !
Mail bug reports and suggestions to <eslabs.id@gmail.com>
_EOF_
}

# enable vhost
function enable_vhost() {
    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/$1.conf" && -f "/etc/nginx/sites-available/$1.conf" ]]; then
        run ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/$1.conf

        # Reload Nginx.
        run service nginx reload -s
        status "Your site $1 has been enabled..."
    else
        fail "Sorry, we can't find $1 virtual host. Probably, it has been enabled or not yet created."
    fi
    exit 0
}

# disable vhost
function disable_vhost() {
    # Disable Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/$1.conf" ]; then
        run unlink /etc/nginx/sites-enabled/$1.conf

        # Reload Nginx.
        run service nginx reload -s
        status "Your site $1 has been disabled..."
    else
        fail "Sorry, we can't find $1. Probably, it has been disabled or removed."
    fi
    exit 0  #success
}

# remove vhost
function remove_vhost() {
    # Remove Nginx's vhost config.
    if [ -f "/etc/nginx/sites-available/$1.conf" ]; then
        fail "Sorry, we can't find Nginx config for $1..."
    else
        run unlink /etc/nginx/sites-enabled/$1.conf
        run rm -f /etc/nginx/sites-available/$1.conf

        # Remove vhost root directory.
        echo -n "Do you want to delete website root directory? [Y/n]: "; read isdeldir
        if [[ "${isdeldir}" = "Y" || "${isdeldir}" = "y" || "${isdeldir}" = "yes" ]]; then
            echo -n "Enter the real path to website root directory: "; read sitedir
            run rm -fr "${sitedir}"
        fi

        # Drop MySQL database.
        echo -n "Do you want to Drop database associated to this website? [Y/n]: "; read isdropdb
        if [[ "${isdropdb}" = "Y" || "${isdropdb}" = "y" || "${isdropdb}" = "yes" ]]; then
            echo -n "MySQL username: "; read username
            echo -n "MySQL password: "; stty -echo; read password; stty echo; echo
            sleep 1
            echo "Starting to drop database, please select your database name!"
            # Show user's databases
            mysql -u $username -p"$password" -e "SHOW DATABASES"

            echo -n "MySQL database: "; read dbname

            mysql -u $username -p"$password" -e "DROP DATABASE $dbname"
        fi

        # Reload Nginx.
        run service nginx reload -s
        status "Your site $1 has been removed..."
    fi
    exit 0  #success
}

# enable ssl
function enable_ssl() {
    exit 0
}

# Main App
#
function init_app() {
    #getopt
    opts=$(getopt -o vhe:d:r:s: \
      -l version,help,enable:,disable:,remove:,enable-ssl \
      -n "$APP_NAME" -- "$@")

    # Sanity Check - are there an arguments with value?
    if [ $? != 0 ]; then
        fail "Terminating..."
        exit 1
    fi

    eval set -- "$opts"

    while true; do
        case "$1" in
            -h | --help) show_usage; exit 0; shift;;
            -e | --enable) enable_vhost $2; shift 2;;
            -d | --disable) disable_vhost $2; shift 2;;
            -r | --remove) remove_vhost $2; shift 2;;
            -s | --enable-ssl) enable_ssl $2; shift 2;;
            -v | --version) echo "$APP_NAME version $APP_VERSION"; exit 1; shift;;
            --) shift; break;;
        esac
    done

    echo "$APP_NAME: missing optstring argument"
    echo "Try '$APP_NAME --help' for more information."
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_app "$@"
