#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer is a simple LEMP stack installer for Debian/Ubuntu Linux         |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 18.04 or Linux Mint 17   |
# | Last Update       : 13/02/2022                                          |
# | Author            : MasEDI.Net (me@masedi.net)                          |
# | Since Version     : 2.6.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

PROG_NAME=$(basename "$0")

# Make sure only root can run this installer script.
if [[ "$(id -u)" -ne 0 ]]; then
    if ! hash sudo 2>/dev/null; then
        echo "Installer script must be run as 'root' or with sudo."
        exit 1
    else
        sudo -E "$0" "$@"
        exit 0
    fi
fi

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

##
# Main LEMPer Installer
##
function lemper_install() {
    echo "Starting LEMPer Stack installation..."
    echo "Please ensure that you're on a fresh install!"
    echo -e "\nPress [Ctrl+C] to abort the installation process."

    sleep 3

    if [[ "${AUTO_INSTALL}" != true ]]; then
        echo ""
        read -t 60 -rp "Press [Enter] to continue..." </dev/tty
    fi

    # Init log.
    run init_log

    # Init config.
    run init_config

    ### Install dependencies packages ###
    if [ -f ./scripts/install_dependencies.sh ]; then
        echo ""
        . ./scripts/install_dependencies.sh
    fi

    ### Server clean-up ###
    if [ -f ./scripts/server_cleanup.sh ]; then
        echo ""
        . ./scripts/server_cleanup.sh
    fi

    ### Create default account ###
    echo ""
    USERNAME=${LEMPER_USERNAME:-"lemper"}
    create_account "${USERNAME}"

    ### Certbot Let's Encrypt SSL installation ###
    if [ -f ./scripts/install_certbotle.sh ]; then
        echo ""
        . ./scripts/install_certbotle.sh
    fi

    ### PHP installation ###
    if [ -f ./scripts/install_php.sh ]; then
        echo ""
        . ./scripts/install_php.sh
    fi

    ### Phalcon PHP installation ###
    if [ -f ./scripts/install_phalcon.sh ]; then
        echo ""
        . ./scripts/install_phalcon.sh
    fi

    ### Nginx installation ###
    if [ -f ./scripts/install_nginx.sh ]; then
        echo ""
        . ./scripts/install_nginx.sh
    fi

    ### MySQL database installation ###
    if [ -f ./scripts/install_mariadb.sh ]; then
        echo ""
        . ./scripts/install_mariadb.sh
    fi

    ### Redis database installation ###
    if [ -f ./scripts/install_redis.sh ]; then
        echo ""
        . ./scripts/install_redis.sh
    fi

    ### MongoDB database installation ###
    if [ -f ./scripts/install_mongodb.sh ]; then
        echo ""
        . ./scripts/install_mongodb.sh
    fi

    ### Memcached installation ###
    if [ -f ./scripts/install_memcached.sh ]; then
        echo ""
        . ./scripts/install_memcached.sh
    fi

    ### Imagick installation ###
    if [ -f ./scripts/install_imagemagick.sh ]; then
        echo ""
        . ./scripts/install_imagemagick.sh
    fi

    ### Mail server installation ###
    if [ -f ./scripts/install_mailer.sh ]; then
        echo ""
        . ./scripts/install_mailer.sh
    fi

    ### FTP installation ###
    if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
        if [ -f ./scripts/install_pureftpd.sh ]; then
            echo ""
            . ./scripts/install_pureftpd.sh
        fi
    else
        if [ -f ./scripts/install_vsftpd.sh ]; then
            echo ""
            . ./scripts/install_vsftpd.sh
        fi
    fi

    ### Fail2ban, intrusion prevention software framework. ###
    if [ -f ./scripts/install_fail2ban.sh ]; then
        echo ""
        . ./scripts/install_fail2ban.sh
    fi

    ### LEMPer tools installation ###
    if [ -f ./scripts/install_tools.sh ]; then
        echo ""
        . ./scripts/install_tools.sh
    fi

    ### Basic server optimization ###
    if [ -f ./scripts/server_optimization.sh ]; then
        echo ""
        . ./scripts/server_optimization.sh
    fi

    ### Basic server security setup ###
    if [ -f ./scripts/server_security.sh ]; then
        echo ""
        . ./scripts/server_security.sh
    fi

    ### FINAL SETUP ###
    if [[ "${FORCE_REMOVE}" == true ]]; then
        # Cleaning up all build dependencies hanging around on production server?
        echo -e "\nClean up installation process..."
        run apt-get autoremove -qq -y

        # Cleanup build dir
        echo "Clean up build directory..."
        if [ -d "$BUILD_DIR" ]; then
            run rm -fr "$BUILD_DIR"
        fi
    fi

    if [[ "${DRYRUN}" != true ]]; then
        status -e "\nCongrats, your LEMPer Stack installation has been completed."

        ### Recap ###
        if [[ -n "${PASSWORD}" ]]; then
            CREDENTIALS="~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~
Default System Information:
        Hostname : ${HOSTNAME}
        Server IP: ${SERVER_IP}
        SSH Port : ${SSH_PORT}

LEMPer Stack Admin Account:
        Username : ${USERNAME}
        Password : ${PASSWORD}

Database Administration (Adminer):
        http://${SERVER_IP}:8082/lcp/dbadmin/

        Database root password: ${MYSQL_ROOT_PASSWORD}

Mariabackup Information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}

Simple File Manager (Experimental):
    http://${SERVER_IP}:8082/lcp/filemanager/

    Use your default LEMPer Stack admin account for Filemanager login."

            if [[ "${INSTALL_MAILER}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Default Mail Service:
    Maildir      : /home/${USERNAME}/Maildir
    Sender Domain: ${SENDER_DOMAIN}
    Sender IP    : ${SERVER_IP}
    IMAP Port    : 143, 993 (SSL/TLS)
    POP3 Port    : 110, 995 (SSL/TLS)

    Domain Key   : lemper._domainkey.${SENDER_DOMAIN}
    DKIM Key     : ${DKIM_KEY}
    SPF Record   : v=spf1 ip4:${SERVER_IP} include:${SENDER_DOMAIN} mx ~all

    Use your default LEMPer Stack admin account for Mail login."
            fi

            if [[ "${INSTALL_MEMCACHED}" == true && "${MEMCACHED_SASL}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Memcached SASL Login:
    Username    : ${MEMCACHED_USERNAME}
    Password    : ${MEMCACHED_PASSWORD}"
            fi

            if [[ "${INSTALL_MONGODB}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

MongoDB Test Admin Login:
    Username    : ${MONGODB_ADMIN_USER}
    Password    : ${MONGODB_ADMIN_PASSWORD}"
            fi

            if [[ "${INSTALL_REDIS}" == true && "${REDIS_REQUIRE_PASSWORD}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Redis required password enabled:
    Password    : ${REDIS_PASSWORD}"
            fi

            CREDENTIALS="${CREDENTIALS}

Please Save the above Credentials & Keep it Secure!
~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

            status "${CREDENTIALS}"

            # Save it to log file
            #save_log "${CREDENTIALS}"

            # Securing LEMPer stack credentials.
            #secure_config
        fi
    else
        warning -e "\nLEMPer installation has been completed in dry-run mode."
    fi

    echo -e "\nSee the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!\n"

    info "SECURITY PRECAUTION! Due to the log file contains some credential data,
You SHOULD delete it after your stack completely installed."
}

##
# Main LEMPer Uninstaller
##
function lemper_remove() {
    echo "Are you sure to remove LEMPer Stack installation?"
    echo "Please ensure that you've backed up your critical data!"
    echo ""

    if [[ "${AUTO_REMOVE}" == false ]]; then
        read -rt 20 -p "Press [Enter] to continue..." </dev/tty
    fi

    # Fix broken install, first?
    if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
        run dpkg --configure -a
        run apt-get install -qq -y --fix-broken
    fi

    ### Remove Nginx ###
    if [ -f ./scripts/remove_nginx.sh ]; then
        echo ""
        . ./scripts/remove_nginx.sh
    fi

    ### Remove MySQL ###
    if [ -f ./scripts/remove_mariadb.sh ]; then
        echo ""
        . ./scripts/remove_mariadb.sh
    fi

    ### Remove PHP & FPM ###
    if [ -f ./scripts/remove_php.sh ]; then
        echo ""
        . ./scripts/remove_php.sh
    fi

    ### Remove Redis ###
    if [ -f ./scripts/remove_redis.sh ]; then
        echo ""
        . ./scripts/remove_redis.sh
    fi

    ### Remove MongoDB ###
    if [ -f ./scripts/remove_mongodb.sh ]; then
        echo ""
        . ./scripts/remove_mongodb.sh
    fi

    ### Remove PHP & FPM ###
    if [ -f ./scripts/remove_memcached.sh ]; then
        echo ""
        . ./scripts/remove_memcached.sh
    fi

    ### Remove Certbot ###
    if [ -f ./scripts/remove_certbotle.sh ]; then
        echo ""
        . ./scripts/remove_certbotle.sh
    fi

    ### Remove FTP installation ###
    if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
        if [ -f ./scripts/remove_pureftpd.sh ]; then
            echo ""
            . ./scripts/remove_pureftpd.sh
        fi
    else
        if [ -f ./scripts/remove_vsftpd.sh ]; then
            echo ""
            . ./scripts/remove_vsftpd.sh
        fi
    fi

    ### Remove Fail2ban ###
    if [ -f ./scripts/remove_fail2ban.sh ]; then
        echo ""
        . ./scripts/remove_fail2ban.sh
    fi

    ### Remove server security setup ###
    if [ -f ./scripts/server_security.sh ]; then
        echo ""
        . ./scripts/server_security.sh --remove
    fi

    ### Remove default user account ###
    echo ""
    echo "Removing created default account..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_ACCOUNT="y"
    else
        while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
            read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
        done
    fi

    if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t delete_account)" == "function" ]]; then
            delete_account "${LEMPER_USERNAME}"
        fi
    fi

    ### Remove created swap ###
    echo ""
    echo "Removing created swap..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_SWAP="y"
    else
        while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
            read -rp "Remove created Swap? [y/n]: " -e REMOVE_SWAP
        done
    fi

    if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t remove_swap)" == "function" ]]; then
            remove_swap
        fi
    fi

    ### Remove web tools ###
    [ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper

    # Clean up existing lemper config.
    [ -f /etc/lemper/lemper.conf ] && run rm -f /etc/lemper/lemper.conf
    [ -d /etc/lemper/cli-plugins ] && run rm -fr /etc/lemper/cli-plugins

    ### Remove unnecessary packages ###
    echo -e "\nCleaning up unnecessary packages..."

    run apt-get autoremove -qq -y && \
    run apt-get autoclean -qq -y && \
    run apt-get clean -qq -y

    echo -e "\nLEMPer Stack has been removed completely."
    warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer Stack or have 
any other reasons to uninstall it, please let us know ^^

Submit your issue here: https://github.com/joglomedia/LEMPer/issues"
}

##
# Check if the argument is empty.
##
function exit_if_optarg_is_empty() {
    OPT=${1}
    OPTARG=${2}
    if [[ -z "${OPTARG}" || "${OPTARG}" == -* ]]; then
        echo "${PROG_NAME}: option '${OPT}' requires an argument."
        exit 1
    fi
}

##
# Set installer's debug mode.
##
function set_debug_mode() {
    DEBUG_MODE=${1}

    if [[ "${DEBUG_MODE}" == true ]]; then
        # For verbose output.
        set -exv -o pipefail
    else
        set -e -o pipefail
    fi
}

##
# Set installer's dry-run mode.
##
function set_dryrun_mode() {
    DRYRUN=${1}

    if [[ "${DRYRUN}" == true ]]; then
        sed -i "s/DRYRUN=[a-zA-Z]*/DRYRUN=true/g" .env
    else
        sed -i "s/DRYRUN=[a-zA-Z]*/DRYRUN=false/g" .env
    fi
}

##
# Calculate installation total time.
##
function final_time_result() {
    START_TIME=${1}
    END_TIME=$(date +%s)
    TOTAL_TIME_S=$((END_TIME-START_TIME))
    TOTAL_TIME_M=$((TOTAL_TIME_S/60))

    if [[ "${TOTAL_TIME_M}" -gt "0" ]]; then
        echo -e "\nTime consumed:\033[32m ${TOTAL_TIME_M} \033[0mMinute(s)"
    else
        echo -e "\nTime consumed:\033[32m ${TOTAL_TIME_S} \033[0mSecond(s)"
    fi
}

##
# Clone the LEMPer repository.
##
function git_clone_lemper() {
    GIT_BRANCH=${1:-master}

    if [[ -z $(command -v git) ]]; then
        echo "Git is not installed, now installing..."
        apt-get update -y && apt-get install -y git
    fi

    if [[ -n $(command -v git) && ! -d LEMPer/.git ]]; then
        echo -e "\nCloning LEMPer from ${GIT_BRANCH} branch..."
        git clone https://github.com/joglomedia/LEMPer.git
    else
        echo -e "\nUpdating LEMPer from ${GIT_BRANCH} branch..."
        cd LEMPer
        git pull
        cd ..
    fi

    cd LEMPer
    git checkout "${GIT_BRANCH}"
}

##
# Run lemper.sh <COMMANDS> <OPTIONS>
#
# COMMANDS:
#   install
#   uninstall | remove
#
# OPTIONS:
#   --with-mysql-server <server_name-version_number>: Install MySQL Server (MySQL or MariaDB) with specific version.
##
function init_lemper_install() {
    START_TIME=$(date +%s)

    # Clone LEMPer repository first.
    git_clone_lemper "master" > /dev/null 2>&1

    # Check dotenv config file.
    if [[ ! -f .env.dist ]]; then
        echo "${PROG_NAME}: .env.dist file not found."
        exit 1
    fi

    if [[ -f .env ]]; then
        cp -f .env .env.bak
    else
        cp .env.dist .env
    fi

    # Set default args.
    DEBUG_MODE=false
    DRYRUN=false

    # Get sub command.
    CMD=${1}
    shift

    # Set getopt options.
    OPTS=$(getopt -o e:h:i:dgpDBF \
        -l admin-email:,debug,development,dry-run,fix-broken-install,force,guided,hostname:,ipv4:,production,unattended \
        -l with-nginx:,with-nginx-installer:,with-nginx-custom-ssl:,with-nginx-lua,with-nginx-pagespeed,with-nginx-passenger \
        -l with-nginx-pcre:,with-nginx-rtmp,with-php:,with-php-extensions:,with-php-loader:,with-mysql-server: \
        -l with-ftp-server:,with-memcached:,with-memcached-installer:,with-mongodb:,with-mongodb-admin:,with-redis: \
        -l with-redis-installer:,with-redis-requirepass:,with-ssh-passwordless,with-ssh-port:,with-ssh-pub-key: \
        -l with-mailer,with-mail-sender-domain: \
        -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            # Usage: --with-nginx <nginx-version>
            --with-nginx)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_VERSION=${1}
                sed -i "s/INSTALL_NGINX=[a-zA-Z]*/INSTALL_NGINX=true/g" .env
                sed -i "s/NGINX_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_VERSION=\"${NGINX_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-nginx-installer <repo | source>
            --with-nginx-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_INSTALLER=${1}
                case "${NGINX_INSTALLER}" in
                    source)
                        sed -i "s/NGINX_INSTALLER=\"[a-zA-Z]*\"/NGINX_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed -i "s/NGINX_INSTALLER=\"[a-zA-Z]*\"/NGINX_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            --with-nginx-custom-ssl)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_CUSTOMSSL_VERSION=${1-"openssl-1.1.1l"}
                sed -i "s/NGINX_WITH_CUSTOMSSL=[a-zA-Z]*/NGINX_WITH_CUSTOMSSL=true/g" .env
                sed -i "s/NGINX_CUSTOMSSL_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_CUSTOMSSL_VERSION=\"${NGINX_CUSTOMSSL_VERSION}\"/g" .env
                shift
            ;;
            --with-nginx-lua)
                sed -i "s/NGX_HTTP_LUA=[a-zA-Z]*/NGX_HTTP_LUA=true/g" .env
                shift
            ;;
            --with-nginx-pagespeed)
                sed -i "s/NGX_PAGESPEED=[a-zA-Z]*/NGX_PAGESPEED=true/g" .env
                shift
            ;;
            --with-nginx-passenger)
                sed -i "s/NGX_HTTP_PASSENGER=[a-zA-Z]*/NGX_HTTP_PASSENGER=true/g" .env
                shift
            ;;
            --with-nginx-pcre)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_PCRE_VERSION=${1-"8.45"}
                sed -i "s/NGINX_WITH_PCRE=[a-zA-Z]*/NGINX_WITH_PCRE=true/g" .env
                sed -i "s/NGINX_PCRE_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_PCRE_VERSION=\"${NGINX_PCRE_VERSION}\"/g" .env
                shift
            ;;
            --with-nginx-rtmp)
                sed -i "s/NGX_RTMP=[a-zA-Z]*/NGX_RTMP=true/g" .env
                shift
            ;;
            # Usage: --with-php <php-version>
            --with-php)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_VERSIONS=${1}
                sed -i "s/INSTALL_PHP=[a-zA-Z]*/INSTALL_PHP=true/g" .env
                sed -i "s/PHP_VERSIONS=\"[a-zA-Z0-9\ ._-]*\"/PHP_VERSIONS=\"${PHP_VERSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-extensions=<ext-name1 ext-name2 ext-name>
            --with-php-extensions)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_EXTENSIONS=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                sed -i "s/PHP_EXTENSIONS=\"[0-9a-zA-Z\ ,._-]*\"/PHP_EXTENSIONS=\"${PHP_EXTENSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-loader <ioncube | sourceguardian>
            --with-php-loader)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed -i "s/INSTALL_PHP_LOADER=[a-zA-Z]*/INSTALL_PHP_LOADER=true/g" .env
                PHP_LOADER=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                case "${PHP_LOADER}" in
                    all)
                        sed -i "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"all\"/g" .env
                    ;;
                    ic | ioncube)
                        sed -i "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"ioncube\"/g" .env
                    ;;
                    sg | sourceguardian)
                        sed -i "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"sourceguardian\"/g" .env
                    ;;
                    *)
                        echo "Selected PHP Loader: ${PHP_LOADER} is not supported."
                        sed -i "s/INSTALL_PHP_LOADER=[a-zA-Z]*/INSTALL_PHP_LOADER=false/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-mysql-server <mysql-5.7 | mariadb-10.6>
            --with-mysql-server)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed -i "s/INSTALL_MYSQL=[a-zA-Z]*/INSTALL_MYSQL=true/g" .env
                MYSQL_SERVER=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                # Reserve default IFS
                _IFS=${IFS}
                IFS='-' read -r -a _MYSQL_SERVER <<< "${MYSQL_SERVER}"
                MYSQL_SERVER_NAME="${_MYSQL_SERVER[0]}"
                MYSQL_SERVER_VER="${_MYSQL_SERVER[1]}"
                # Restore default IFS
                IFS=${_IFS}
                case "${MYSQL_SERVER_NAME}" in
                    mysql | mysql-server)
                        sed -i "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mysql\"/g" .env
                    ;;
                    mariadb)
                        sed -i "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mariadb\"/g" .env
                    ;;
                    *)
                        echo "Selected MySQL Server: ${MYSQL_SERVER} is not supported, fallback to MariaDB Server."
                        sed -i "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mariadb\"/g" .env
                    ;;
                esac
                if [ -n "${MYSQL_SERVER_VER}" ]; then
                    sed -i "s/MYSQL_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MYSQL_VERSION=\"${MYSQL_SERVER_VER}\"/g" .env
                fi
                shift
            ;;
            # Usage: --with-memcached <latest | stable | memcached-version>
            --with-memcached)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_VERSION=${1}
                sed -i "s/INSTALL_MEMCACHED=[a-zA-Z]*/INSTALL_MEMCACHED=true/g" .env
                sed -i "s/MEMCACHED_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MEMCACHED_VERSION=\"${MEMCACHED_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-memcached-installer <source | repo>
            --with-memcached-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_INSTALLER=${1}
                case "${MEMCACHED_INSTALLER}" in
                    source)
                        sed -i "s/MEMCACHED_INSTALLER=\"[a-zA-Z]*\"/MEMCACHED_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed -i "s/MEMCACHED_INSTALLER=\"[a-zA-Z]*\"/MEMCACHED_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-mongodb <mongodb-version>
            --with-mongodb)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MONGODB_VERSION=${1}
                sed -i "s/INSTALL_MONGODB=[a-zA-Z]*/INSTALL_MONGODB=true/g" .env
                sed -i "s/MONGODB_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MONGODB_VERSION=\"${MONGODB_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-mongodb-admin <username:password>
            --with-mongodb-admin)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MONGODB_ADMIN="${1}"
                # Reserve default IFS
                _IFS=${IFS}
                IFS=':' read -r -a MONGODB_ADMIN_AUTH <<< "${MONGODB_ADMIN}"
                MONGODB_ADMIN_USER="${MONGODB_ADMIN_AUTH[0]}"
                MONGODB_ADMIN_PASS="${MONGODB_ADMIN_AUTH[1]}"
                # Restore default IFS
                IFS=${_IFS}
                sed -i "s/MONGODB_ADMIN_USER=\"[a-zA-Z0-9._-]*\"/MONGODB_ADMIN_USER=\"${MONGODB_ADMIN_USER}\"/g" .env
                sed -i "s/MONGODB_ADMIN_PASSWORD=\"[a-zA-Z0-9\ ._-]*\"/MONGODB_ADMIN_PASSWORD=\"${MONGODB_ADMIN_PASS}\"/g" .env
                shift
            ;;
            # Usage: --with-redis <latest | stable | redis-version>
            --with-redis)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_VERSION=${1}
                if [ -z "${REDIS_VERSION}" ]; then REDIS_VERSION="stable"; fi
                sed -i "s/INSTALL_REDIS=[a-zA-Z]*/INSTALL_REDIS=true/g" .env
                sed -i "s/REDIS_VERSION=\"[a-zA-Z0-9\ ._-]*\"/REDIS_VERSION=\"${REDIS_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-redis-installer <source | repo>
            --with-redis-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_INSTALLER=${1}
                case "${REDIS_INSTALLER}" in
                    source)
                        sed -i "s/REDIS_INSTALLER=\"[a-zA-Z]*\"/REDIS_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed -i "s/REDIS_INSTALLER=\"[a-zA-Z]*\"/REDIS_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-redis-requirepass <password>
            --with-redis-requirepass)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_PASSWORD=${1}
                sed -i "s/REDIS_REQUIRE_PASSWORD=[a-zA-Z]*/REDIS_REQUIRE_PASSWORD=true/g" .env
                sed -i "s/REDIS_PASSWORD=\"[a-zA-Z0-9._-](.*)\"/REDIS_PASSWORD=\"${REDIS_PASSWORD}\"/g" .env
                shift
            ;;
            --with-ftp-server)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed -i "s/INSTALL_FTP_SERVER=[a-zA-Z]*/INSTALL_FTP_SERVER=true/g" .env
                FTP_SERVER=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                # Reserve default IFS
                _IFS=${IFS}
                IFS='-' read -r -a _FTP_SERVER <<< "${FTP_SERVER}"
                FTP_SERVER_NAME="${_FTP_SERVER[0]}"
                FTP_SERVER_VER="${_FTP_SERVER[1]}"
                # Restore default IFS
                IFS=${_IFS}
                case "${FTP_SERVER_NAME}" in
                    pureftpd | pure-ftpd)
                        sed -i "s/FTP_SERVER_NAME=\"[a-zA-Z]*\"/FTP_SERVER_NAME=\"pureftpd\"/g" .env
                    ;;
                    vsftpd)
                        sed -i "s/FTP_SERVER_NAME=\"[a-zA-Z]*\"/FTP_SERVER_NAME=\"vsftpd\"/g" .env
                    ;;
                    *)
                        echo "Selected MySQL Server: ${FTP_SERVER_NAME} is not supported, fallback to VSFTPD."
                        sed -i "s/FTP_SERVER_NAME=\"[a-zA-Z0-9._-]*\"/FTP_SERVER_NAME=\"vsftpd\"/g" .env
                    ;;
                esac
                if [ -n "${FTP_SERVER_VER}" ]; then
                    sed -i "s/FTP_SERVER_VERSION=\"[a-zA-Z0-9\ ._-]*\"/FTP_SERVER_VERSION=\"${FTP_SERVER_VER}\"/g" .env
                fi
                shift
            ;;
            --with-mailer)
                sed -i "s/INSTALL_MAILER=[a-zA-Z]*/INSTALL_MAILER=true/g" .env
                shift
            ;;
            --with-mail-sender-domain)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MAIL_SENDER_DOMAIN=${1}
                sed -i "s/SENDER_DOMAIN=\"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\"/SENDER_DOMAIN=\"${MAIL_SENDER_DOMAIN}\"/g" .env
                shift
            ;;
            --with-ssh-port)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SSH_PORT=${1}
                if [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; then
                    sed -i "s/SSH_PORT=[0-9]*/SSH_PORT=${SSH_PORT}/g" .env
                else
                    sed -i "s/SSH_PORT=[0-9]*/SSH_PORT=2269/g" .env
                fi
                shift
            ;;
            --with-ssh-passwordless)
                sed -i "s/SSH_ROOT_LOGIN=[a-zA-Z]*/SSH_ROOT_LOGIN=false/g" .env
                sed -i "s/SSH_PASSWORDLESS=[a-zA-Z]*/SSH_PASSWORDLESS=true/g" .env
                shift
            ;;
            --with-ssh-pub-key)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SSH_PUB_KEY=${1}
                sed -i "s/SSH_PUB_KEY=\"[a-zA-Z0-9._-](.*)\"/SSH_PUB_KEY=\"${SSH_PUB_KEY}\"/g" .env
                shift
            ;;
            -e | --admin-email)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                LEMPER_ADMIN_EMAIL=${1}
                sed -i "s/LEMPER_ADMIN_EMAIL=\"[a-zA-Z0-9._-](.*)\@[a-zA-Z0-9._-](.*)\"/LEMPER_ADMIN_EMAIL=\"${LEMPER_ADMIN_EMAIL}\"/g" .env
                shift
            ;;
            -B | --fix-broken-install)
                sed -i "s/FIX_BROKEN_INSTALL=[a-zA-Z]*/FIX_BROKEN_INSTALL=true/g" .env
                shift
            ;;
            -d | --development)
                sed -i "s/ENVIRONMENT=\"[a-zA-Z]*\"/ENVIRONMENT=\"development\"/g" .env
                shift
            ;;
            -D | --debug)
                DEBUG_MODE=true
                shift
            ;;
            --dry-run)
                DRYRUN=true
                sed -i "s/DRYRUN=[a-zA-Z]*/DRYRUN=true/g" .env
                shift
            ;;
            -F | --force)
                sed -i "s/FORCE_INSTALL=[a-zA-Z]*/FORCE_INSTALL=true/g" .env
                sed -i "s/FORCE_REMOVE=[a-zA-Z]*/FORCE_REMOVE=true/g" .env
                shift
            ;;
            -g | --guided | --unattended)
                sed -i "s/AUTO_INSTALL=[a-zA-Z]*/AUTO_INSTALL=false/g" .env
                sed -i "s/AUTO_REMOVE=[a-zA-Z]*/AUTO_REMOVE=false/g" .env
                shift
            ;;
            -h | --hostname)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SERVER_HOSTNAME=${1}
                sed -i "s/SERVER_HOSTNAME=\"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\"/SERVER_HOSTNAME=\"${SERVER_HOSTNAME}\"/g" .env
                shift
            ;;
            -i | --ipv4)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SERVER_IP=${1}
                sed -i "s/SERVER_IP=\"[0-9.]*\"/SERVER_IP=\"${SERVER_IP}\"/g" .env
                shift
            ;;
            -p | --production)
                sed -i "s/ENVIRONMENT=\"[a-zA-Z]*\"/ENVIRONMENT=\"production\"/g" .env
                shift
            ;;
            --)
                shift
                break
            ;;
            *)
                echo "${PROG_NAME}: '${1}' is not valid argument"
                echo "See '${PROG_NAME} --help' for more information"
                exit 1
            ;;
        esac
    done

    # Set debug mode.
    set_debug_mode "${DEBUG_MODE}"
    set_dryrun_mode "${DRYRUN}"

    # Include helper functions.
    if [[ "$(type -t run)" != "function" ]]; then
        . ./scripts/utils.sh
    fi

    # Make sure only supported distribution can run this installer script.
    preflight_system_check

    # Go action.
    case "${CMD}" in
        --install | install)
            #./install.sh
            header_msg
            lemper_install
            final_time_result "${START_TIME}"
            footer_msg
            exit 0
        ;;
        --uninstall | --remove | uninstall | remove)
            #./remove.sh
            header_msg
            lemper_remove
            final_time_result "${START_TIME}"
            footer_msg
            exit 0
        ;;
        -h | --help | help)
            echo "For more help please visit https://github.com/joglomedia/LEMPer"
            exit 0
        ;;
        *)
            echo "${PROG_NAME}: '${CMD}' is not ${PROG_NAME} command"
            echo "See '${PROG_NAME} --help' for more information"
            exit 1
        ;;
    esac
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_install "$@"
