#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer is a simple LEMP stack installer for Debian/Ubuntu Linux         |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 16.04 or Linux Mint 17   |
# | Last Update       : 11/2/2022                                           |
# | Author            : MasEDI.Net (me@masedi.net)                          |
# | Version           : 2.x.x                                               |
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
# Run go.sh <COMMANDS> <OPTIONS>
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

    if [[ ! -f .env.dist ]]; then
        echo "${PROG_NAME}: .env.dist file not found."
        exit 1
    fi

    if [[ -f .env ]]; then
        mv .env .env.bak
    fi

    cp -f .env.dist .env

    # Sub command.
    CMD=${1}
    shift

    # Options.
    OPTS=$(getopt -o h:i:dgpBF \
        -l dry-run,fix-broken-install,force,guided,hostname:,ipv4:,production,unattended \
        -l with-nginx:,with-nginx-installer:,with-php:,with-php-extensions:,with-php-loader: \
        -l with-mysql-server:,with-memcached:,with-memcached-installer:,with-mongodb:,with-mongodb-admin: \
        -l with-redis:,with-redis-installer:,with-redis-requirepass:,with-ftp-server: \
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
                sed -i "s/NGINX_VERSION=\"[0-9a-zA-Z.\ ]*\"/NGINX_VERSION=\"${NGINX_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-nginx-installer <repo | source>
            --with-nginx-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_INSTALLER=${1}
                case "${NGINX_INSTALLER}" in
                    source)
                        sed -i "s/NGINX_INSTALLER=\"[a-zA-Z.\ ]*\"/NGINX_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed -i "s/NGINX_INSTALLER=\"[a-zA-Z]*\"/NGINX_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            --with-nginx-pagespeed)
                sed -i "s/NGX_PAGESPEED=[a-zA-Z]*/NGX_PAGESPEED=true/g" .env
                shift
            ;;
            # Usage: --with-php <php-version>
            --with-php)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_VERSIONS=${1}
                sed -i "s/INSTALL_PHP=[a-zA-Z]*/INSTALL_PHP=true/g" .env
                sed -i "s/PHP_VERSIONS=\"[0-9.\ ]*\"/PHP_VERSIONS=\"${PHP_VERSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-extensions=<ext-name1 ext-name2 ext-name>
            --with-php-extensions)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_EXTENSIONS=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                sed -i "s/PHP_EXTENSIONS=\"[a-zA-Z,\ ]*\"/PHP_EXTENSIONS=\"${PHP_EXTENSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-loader <ioncube | sourceguardian>
            --with-php-loader)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed -i "s/INSTALL_PHP_LOADER=[a-zA-Z]*/INSTALL_PHP_LOADER=true/g" .env
                PHP_LOADER=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                case "${PHP_LOADER}" in
                    sg | sourceguardian)
                        sed -i "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"sourceguardian\"/g" .env
                    ;;
                    ic | ioncube)
                        sed -i "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"ioncube\"/g" .env
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
                    sed -i "s/MYSQL_VERSION=\"[0-9.\ ]*\"/MYSQL_VERSION=\"${MYSQL_SERVER_VER}\"/g" .env
                fi
                shift
            ;;
            # Usage: --with-memcached <latest | stable | memcached-version>
            --with-memcached)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_VERSION=${1}
                sed -i "s/INSTALL_MEMCACHED=[a-zA-Z]*/INSTALL_MEMCACHED=true/g" .env
                sed -i "s/MEMCACHED_VERSION=\"[0-9a-zA-Z.\ ]*\"/MEMCACHED_VERSION=\"${MEMCACHED_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-memcached-installer <source | repo>
            --with-memcached-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_INSTALLER=${1}
                case "${MEMCACHED_INSTALLER}" in
                    source)
                        sed -i "s/MEMCACHED_INSTALLER=\"[a-zA-Z.\ ]*\"/MEMCACHED_INSTALLER=\"source\"/g" .env
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
                sed -i "s/MONGODB_VERSION=\"[0-9a-zA-Z.\ ]*\"/MONGODB_VERSION=\"${MONGODB_VERSION}\"/g" .env
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
                sed -i "s/MONGODB_ADMIN_USER=\"[0-9a-zA-Z._-\ ]*\"/MONGODB_ADMIN_USER=\"${MONGODB_ADMIN_USER}\"/g" .env
                sed -i "s/MONGODB_ADMIN_PASSWORD=\"[0-9a-zA-Z._-\ ]*\"/MONGODB_ADMIN_PASSWORD=\"${MONGODB_ADMIN_PASS}\"/g" .env
                shift
            ;;
            # Usage: --with-redis <latest | stable | redis-version>
            --with-redis)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_VERSION=${1}
                if [ -z "${REDIS_VERSION}" ]; then REDIS_VERSION="stable"; fi
                sed -i "s/INSTALL_REDIS=[a-zA-Z]*/INSTALL_REDIS=true/g" .env
                sed -i "s/REDIS_VERSION=\"[0-9a-zA-Z._-\ ]*\"/REDIS_VERSION=\"${REDIS_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-redis-installer <source | repo>
            --with-redis-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_INSTALLER=${1}
                case "${REDIS_INSTALLER}" in
                    source)
                        sed -i "s/REDIS_INSTALLER=\"[a-zA-Z.\ ]*\"/REDIS_INSTALLER=\"source\"/g" .env
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
                sed -i "s/REDIS_PASSWORD=\"[0-9a-zA-Z._-\ ]*\"/REDIS_PASSWORD=\"${REDIS_PASSWORD}\"/g" .env
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
            -d | --dry-run)
                sed -i "s/DRYRUN=[a-zA-Z]*/DRYRUN=true/g" .env
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
                sed -i "s/SERVER_HOSTNAME=\"[a-zA-Z0-9._-]*\"/SERVER_HOSTNAME=\"${SERVER_HOSTNAME}\"/g" .env
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
                sed -i "s/ENVIRONMENT=\"development\"/ENVIRONMENT=\"production\"/g" .env
                shift
            ;;
            -B | --fix-broken-install)
                sed -i "s/FIX_BROKEN_INSTALL=[a-zA-Z]*/FIX_BROKEN_INSTALL=true/g" .env
                shift
            ;;
            -F | --force)
                sed -i "s/FORCE_INSTALL=[a-zA-Z]*/FORCE_INSTALL=true/g" .env
                sed -i "s/FORCE_REMOVE=[a-zA-Z]*/FORCE_REMOVE=true/g" .env
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

    # Go action.
    case "${CMD}" in
        install)
            ./install.sh
        ;;
        uninstall | remove)
            ./remove.sh
        ;;
        -h | --help | help)
            echo "Help for ${PROG_NAME}:"
            exit 0
        ;;
        *)
            echo "${PROG_NAME}: '${CMD}' is not ${PROG_NAME} command"
            echo "See '${PROG_NAME} --help' for more information"
            exit 1
        ;;
    esac

    END_TIME=$(date +%s)
    TOTAL_TIME=$(((END_TIME-START_TIME)/60))

    echo -e "Time consumed:\033[32m ${TOTAL_TIME} \033[0mMinute(s)"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_install "$@"
