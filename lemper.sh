#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Installer & Manager                                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
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

# Help must not require root, a dotenv file, or a repository checkout.
case "${1:-}" in
    -h | --help | help)
        echo "LEMPer Stack installer"
        echo "Usage: ${PROG_NAME} install [options]"
        echo "       ${PROG_NAME} remove [options]"
        echo "For more help please visit https://github.com/joglomedia/LEMPer"
        exit 0
    ;;
esac

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

# Run from the checkout root so relative paths (.env, scripts/, share/) work
# regardless of the caller's working directory.
LEMPER_ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
cd "${LEMPER_ROOT}" || { echo "${PROG_NAME}: cannot enter ${LEMPER_ROOT}."; exit 1; }
export BASE_DIR="${LEMPER_ROOT}"

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

##
# Main LEMPer Installer & Uninstaller functions.
# Shared with install.sh and remove.sh via lib/core/lemper-stacks.sh
##
. ./lib/core/lemper-stacks.sh

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
        sed_inplace "s/DRYRUN=[a-zA-Z]*/DRYRUN=true/g" .env
    else
        sed_inplace "s/DRYRUN=[a-zA-Z]*/DRYRUN=false/g" .env
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

    # Check dotenv config file.
    if [[ ! -f "${BASE_DIR}/.env.dist" ]]; then
        echo "${PROG_NAME}: .env.dist file not found."
        exit 1
    fi

    if [[ -f "${BASE_DIR}/.env" ]]; then
        cp -f "${BASE_DIR}/.env" "${BASE_DIR}/.env.bak"
    else
        cp "${BASE_DIR}/.env.dist" "${BASE_DIR}/.env"
    fi

    # Include helper functions before parsing options: option handlers update
    # .env through sed_inplace and set_env_value.
    if [[ "$(type -t run)" != "function" ]]; then
        . "${BASE_DIR}/scripts/utils.sh"
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
        -l with-nginx:,with-nginx-installer:,with-nginx-custom-ssl:,with-nginx-lua,with-nginx-passenger \
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
                sed_inplace "s/INSTALL_NGINX=[a-zA-Z]*/INSTALL_NGINX=true/g" .env
                sed_inplace "s/NGINX_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_VERSION=\"${NGINX_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-nginx-installer <repo | source>
            --with-nginx-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_INSTALLER=${1}
                case "${NGINX_INSTALLER}" in
                    source)
                        sed_inplace "s/NGINX_INSTALLER=\"[a-zA-Z]*\"/NGINX_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed_inplace "s/NGINX_INSTALLER=\"[a-zA-Z]*\"/NGINX_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            --with-nginx-custom-ssl)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_CUSTOMSSL_VERSION=${1-"openssl-1.1.1l"}
                sed_inplace "s/NGINX_WITH_CUSTOMSSL=[a-zA-Z]*/NGINX_WITH_CUSTOMSSL=true/g" .env
                sed_inplace "s/NGINX_CUSTOMSSL_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_CUSTOMSSL_VERSION=\"${NGINX_CUSTOMSSL_VERSION}\"/g" .env
                shift
            ;;
            --with-nginx-lua)
                sed_inplace "s/NGX_HTTP_LUA=[a-zA-Z]*/NGX_HTTP_LUA=true/g" .env
                shift
            ;;
            --with-nginx-passenger)
                sed_inplace "s/NGX_HTTP_PASSENGER=[a-zA-Z]*/NGX_HTTP_PASSENGER=true/g" .env
                shift
            ;;
            --with-nginx-pcre)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                NGINX_PCRE_VERSION=${1-"8.45"}
                sed_inplace "s/NGINX_WITH_PCRE=[a-zA-Z]*/NGINX_WITH_PCRE=true/g" .env
                sed_inplace "s/NGINX_PCRE_VERSION=\"[a-zA-Z0-9\ ._-]*\"/NGINX_PCRE_VERSION=\"${NGINX_PCRE_VERSION}\"/g" .env
                shift
            ;;
            --with-nginx-rtmp)
                sed_inplace "s/NGX_RTMP=[a-zA-Z]*/NGX_RTMP=true/g" .env
                shift
            ;;
            # Usage: --with-php <php-version>
            --with-php)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_VERSIONS=${1}
                sed_inplace "s/INSTALL_PHP=[a-zA-Z]*/INSTALL_PHP=true/g" .env
                sed_inplace "s/PHP_VERSIONS=\"[a-zA-Z0-9\ ._-]*\"/PHP_VERSIONS=\"${PHP_VERSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-extensions=<ext-name1 ext-name2 ext-name>
            --with-php-extensions)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                PHP_EXTENSIONS=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                sed_inplace "s/PHP_EXTENSIONS=\"[0-9a-zA-Z\ ,._-]*\"/PHP_EXTENSIONS=\"${PHP_EXTENSIONS}\"/g" .env
                shift
            ;;
            # Usage: --with-php-loader <ioncube | sourceguardian>
            --with-php-loader)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed_inplace "s/INSTALL_PHP_LOADER=[a-zA-Z]*/INSTALL_PHP_LOADER=true/g" .env
                PHP_LOADER=$( echo "${1}" | tr '[:upper:]' '[:lower:]' )
                case "${PHP_LOADER}" in
                    all)
                        sed_inplace "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"all\"/g" .env
                    ;;
                    ic | ioncube)
                        sed_inplace "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"ioncube\"/g" .env
                    ;;
                    sg | sourceguardian)
                        sed_inplace "s/PHP_LOADER=\"[a-zA-Z]*\"/PHP_LOADER=\"sourceguardian\"/g" .env
                    ;;
                    *)
                        echo "Selected PHP Loader: ${PHP_LOADER} is not supported."
                        sed_inplace "s/INSTALL_PHP_LOADER=[a-zA-Z]*/INSTALL_PHP_LOADER=false/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-mysql-server <mysql-5.7 | mariadb-10.6>
            --with-mysql-server)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed_inplace "s/INSTALL_MYSQL=[a-zA-Z]*/INSTALL_MYSQL=true/g" .env
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
                        sed_inplace "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mysql\"/g" .env
                    ;;
                    mariadb)
                        sed_inplace "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mariadb\"/g" .env
                    ;;
                    *)
                        echo "Selected MySQL Server: ${MYSQL_SERVER} is not supported, fallback to MariaDB Server."
                        sed_inplace "s/MYSQL_SERVER=\"[a-zA-Z]*\"/MYSQL_SERVER=\"mariadb\"/g" .env
                    ;;
                esac
                if [ -n "${MYSQL_SERVER_VER}" ]; then
                    sed_inplace "s/MYSQL_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MYSQL_VERSION=\"${MYSQL_SERVER_VER}\"/g" .env
                fi
                shift
            ;;
            # Usage: --with-memcached <latest | stable | memcached-version>
            --with-memcached)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_VERSION=${1}
                sed_inplace "s/INSTALL_MEMCACHED=[a-zA-Z]*/INSTALL_MEMCACHED=true/g" .env
                sed_inplace "s/MEMCACHED_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MEMCACHED_VERSION=\"${MEMCACHED_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-memcached-installer <source | repo>
            --with-memcached-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MEMCACHED_INSTALLER=${1}
                case "${MEMCACHED_INSTALLER}" in
                    source)
                        sed_inplace "s/MEMCACHED_INSTALLER=\"[a-zA-Z]*\"/MEMCACHED_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed_inplace "s/MEMCACHED_INSTALLER=\"[a-zA-Z]*\"/MEMCACHED_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-mongodb <mongodb-version>
            --with-mongodb)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MONGODB_VERSION=${1}
                sed_inplace "s/INSTALL_MONGODB=[a-zA-Z]*/INSTALL_MONGODB=true/g" .env
                sed_inplace "s/MONGODB_VERSION=\"[a-zA-Z0-9\ ._-]*\"/MONGODB_VERSION=\"${MONGODB_VERSION}\"/g" .env
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
                sed_inplace "s/MONGODB_ADMIN_USER=\"[a-zA-Z0-9._-]*\"/MONGODB_ADMIN_USER=\"${MONGODB_ADMIN_USER}\"/g" .env
                sed_inplace "s/MONGODB_ADMIN_PASSWORD=\"[a-zA-Z0-9\ ._-]*\"/MONGODB_ADMIN_PASSWORD=\"${MONGODB_ADMIN_PASS}\"/g" .env
                shift
            ;;
            # Usage: --with-redis <latest | stable | redis-version>
            --with-redis)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_VERSION=${1}
                if [ -z "${REDIS_VERSION}" ]; then REDIS_VERSION="stable"; fi
                sed_inplace "s/INSTALL_REDIS=[a-zA-Z]*/INSTALL_REDIS=true/g" .env
                sed_inplace "s/REDIS_VERSION=\"[a-zA-Z0-9\ ._-]*\"/REDIS_VERSION=\"${REDIS_VERSION}\"/g" .env
                shift
            ;;
            # Usage: --with-redis-installer <source | repo>
            --with-redis-installer)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_INSTALLER=${1}
                case "${REDIS_INSTALLER}" in
                    source)
                        sed_inplace "s/REDIS_INSTALLER=\"[a-zA-Z]*\"/REDIS_INSTALLER=\"source\"/g" .env
                    ;;
                    *)
                        sed_inplace "s/REDIS_INSTALLER=\"[a-zA-Z]*\"/REDIS_INSTALLER=\"repo\"/g" .env
                    ;;
                esac
                shift
            ;;
            # Usage: --with-redis-requirepass <password>
            --with-redis-requirepass)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                REDIS_PASSWORD=${1}
                sed_inplace "s/REDIS_REQUIRE_PASSWORD=[a-zA-Z]*/REDIS_REQUIRE_PASSWORD=true/g" .env
                sed_inplace "s/REDIS_PASSWORD=\"[a-zA-Z0-9._-](.*)\"/REDIS_PASSWORD=\"${REDIS_PASSWORD}\"/g" .env
                shift
            ;;
            --with-ftp-server)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                sed_inplace "s/INSTALL_FTP_SERVER=[a-zA-Z]*/INSTALL_FTP_SERVER=true/g" .env
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
                        sed_inplace "s/FTP_SERVER_NAME=\"[a-zA-Z]*\"/FTP_SERVER_NAME=\"pureftpd\"/g" .env
                    ;;
                    vsftpd)
                        sed_inplace "s/FTP_SERVER_NAME=\"[a-zA-Z]*\"/FTP_SERVER_NAME=\"vsftpd\"/g" .env
                    ;;
                    *)
                        echo "Selected MySQL Server: ${FTP_SERVER_NAME} is not supported, fallback to VSFTPD."
                        sed_inplace "s/FTP_SERVER_NAME=\"[a-zA-Z0-9._-]*\"/FTP_SERVER_NAME=\"vsftpd\"/g" .env
                    ;;
                esac
                if [ -n "${FTP_SERVER_VER}" ]; then
                    sed_inplace "s/FTP_SERVER_VERSION=\"[a-zA-Z0-9\ ._-]*\"/FTP_SERVER_VERSION=\"${FTP_SERVER_VER}\"/g" .env
                fi
                shift
            ;;
            --with-mailer)
                sed_inplace "s/INSTALL_MAILER=[a-zA-Z]*/INSTALL_MAILER=true/g" .env
                shift
            ;;
            --with-mail-sender-domain)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                MAIL_SENDER_DOMAIN=${1}
                sed_inplace "s/SENDER_DOMAIN=\"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\"/SENDER_DOMAIN=\"${MAIL_SENDER_DOMAIN}\"/g" .env
                shift
            ;;
            --with-ssh-port)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SSH_PORT=${1}
                if [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; then
                    sed_inplace "s/SSH_PORT=[0-9]*/SSH_PORT=${SSH_PORT}/g" .env
                else
                    sed_inplace "s/SSH_PORT=[0-9]*/SSH_PORT=2269/g" .env
                fi
                shift
            ;;
            --with-ssh-passwordless)
                sed_inplace "s/SSH_ROOT_LOGIN=[a-zA-Z]*/SSH_ROOT_LOGIN=false/g" .env
                sed_inplace "s/SSH_PASSWORDLESS=[a-zA-Z]*/SSH_PASSWORDLESS=true/g" .env
                shift
            ;;
            --with-ssh-pub-key)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                RSA_PUB_KEY=${1}
                if ! is_ssh_public_key "${RSA_PUB_KEY}"; then
                    echo "${PROG_NAME}: '${RSA_PUB_KEY}' is not a valid OpenSSH public key."
                    exit 1
                fi
                set_env_value .env RSA_PUB_KEY "${RSA_PUB_KEY}"
                shift
            ;;
            -e | --admin-email)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                LEMPER_ADMIN_EMAIL=${1}
                sed_inplace "s/LEMPER_ADMIN_EMAIL=\"[a-zA-Z0-9._-](.*)\@[a-zA-Z0-9._-](.*)\"/LEMPER_ADMIN_EMAIL=\"${LEMPER_ADMIN_EMAIL}\"/g" .env
                shift
            ;;
            -B | --fix-broken-install)
                sed_inplace "s/FIX_BROKEN_INSTALL=[a-zA-Z]*/FIX_BROKEN_INSTALL=true/g" .env
                shift
            ;;
            -d | --development)
                sed_inplace "s/ENVIRONMENT=\"[a-zA-Z]*\"/ENVIRONMENT=\"development\"/g" .env
                shift
            ;;
            -D | --debug)
                DEBUG_MODE=true
                shift
            ;;
            --dry-run)
                DRYRUN=true
                sed_inplace "s/DRYRUN=[a-zA-Z]*/DRYRUN=true/g" .env
                shift
            ;;
            -F | --force)
                sed_inplace "s/FORCE_INSTALL=[a-zA-Z]*/FORCE_INSTALL=true/g" .env
                sed_inplace "s/FORCE_REMOVE=[a-zA-Z]*/FORCE_REMOVE=true/g" .env
                shift
            ;;
            -g | --guided | --unattended)
                sed_inplace "s/AUTO_INSTALL=[a-zA-Z]*/AUTO_INSTALL=false/g" .env
                sed_inplace "s/AUTO_REMOVE=[a-zA-Z]*/AUTO_REMOVE=false/g" .env
                shift
            ;;
            -h | --hostname)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SERVER_HOSTNAME=${1}
                sed_inplace "s/SERVER_HOSTNAME=\"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\"/SERVER_HOSTNAME=\"${SERVER_HOSTNAME}\"/g" .env
                shift
            ;;
            -i | --ipv4)
                exit_if_optarg_is_empty "${1}" "${2}"
                shift
                SERVER_IP=${1}
                sed_inplace "s/SERVER_IP=\"[0-9.]*\"/SERVER_IP=\"${SERVER_IP}\"/g" .env
                shift
            ;;
            -p | --production)
                sed_inplace "s/ENVIRONMENT=\"[a-zA-Z]*\"/ENVIRONMENT=\"production\"/g" .env
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
