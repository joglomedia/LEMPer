#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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

##
# Main Functions
##

##
# Show usage
# output to STDERR.
##
function show_usage() {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer Stack virtual host (vhost) manager,
enable, disable, remove Nginx vhost on Debian/Ubuntu server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTION]...

Options:
  -b, --enable-brotli <vhost domain name>
      Enable Brotli compression.
  -c, --enable-fastcgi-cache <vhost domain name>
      Enable FastCGI cache.
  --disable-fastcgi-cache <vhost domain name>
      Disable FastCHI cache.
  --enable-cors <vhost domain name>
      Enable CORS with a wildcard origin (any origin).
  --disable-cors <vhost domain name>
      Disable CORS.
  -d, --disable <vhost domain name>
      Disable virtual host.
  -e, --enable <vhost domain name>
      Enable virtual host.
  -f, --enable-fail2ban <vhost domain name>
      Enable fail2ban jail.
  --disable-fail2ban <vhost domain name>
      Disable fail2ban jail.
  -g, --enable-gzip <vhost domain name>
      Enable Gzip compression.
  --enable-modsec <vhost domain name>
      Enable ModSecurity v3 WAF.
  --disable-modsec <vhost domain name>
      Disable ModSecurity v3 WAF.
  --disable-compression  <vhost domain name>
      Disable Gzip/Brotli compression.
  -r, --remove <vhost domain name>
      Remove virtual host configuration.
  -s, --enable-ssl <vhost domain name>
      Enable HTTP over SSL with Let's Encrypt.
  -w, --enforce-non-www <vhost domain name>
      Redirect www to non www host.
  --disable-ssl <vhost domain name>
      Disable HTTP over SSL.
  --remove-ssl <vhost domain name>
      Remove SSL certificate.
  --renew-ssl <vhost domain name>
      Renew SSL certificate.

  -h, --help
      Print this message and exit.
  -v, --version
      Output version information and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} --remove example.com

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Remove vhost.
##
function remove_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Removing virtual host is not reversible."
    read -t 30 -rp "Press [Enter] to continue..." </dev/tty

    # Get web root path from vhost config, first.
    local WEBROOT \
        && WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    # Deleting data is a separate opt-in from deleting the vhost config.
    local SITE_OWNER
    SITE_OWNER=$(getent passwd "${LEMPER_USERNAME:-lemper}" | cut -d: -f1)
    if [[ "${WEBROOT}" == /home/* ]]; then
        SITE_OWNER="${WEBROOT#/home/}"
        SITE_OWNER="${SITE_OWNER%%/*}"
    fi
    read -rp "Do you want to delete website root directory? [y/n]: " -e DELETE_DIR
    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        # The configured document root is the boundary; never silently broaden
        # /app/public to /app or fall back to an unrelated directory.
        [[ -n "${SITE_OWNER}" ]] || {
            error "Cannot establish site owner; data kept."
            return 1
        }
        WEBROOT=$(safe_webroot "${WEBROOT}" "${SITE_OWNER}") || {
            error "Refusing unsafe website root; configuration kept."
            return 1
        }
    fi

    # Remove Nginx's vhost config.
    [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]] \
        && run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] \
        && run rm -f "/etc/nginx/sites-available/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] \
        && run rm -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf" ]] \
        && run rm -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

    [[ -f "/etc/lemper/vhost.d/${DOMAIN}.conf" ]] \
        && run rm -f "/etc/lemper/vhost.d/${DOMAIN}.conf"

    # If we have local domain setup in hosts file, remove it.
    if grep -qwE "${DOMAIN}" "/etc/hosts"; then
        info "Domain ${DOMAIN} found in your hosts file. Removing now..."
        run cp -p "/etc/hosts" "/etc/hosts.backup"
        # Use grep -vF (fixed-string) instead of sed to prevent regex injection.
        run grep -v -F "${DOMAIN}" "/etc/hosts" >"/etc/hosts.tmp" && run mv "/etc/hosts.tmp" "/etc/hosts"
    fi

    success "Virtual host configuration file removed."

    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        delete_site_webroot "${WEBROOT}" "${SITE_OWNER}" || return 1
        success "Virtual host root directory removed."
    fi

    # Drop MySQL database.
    read -rp "Do you want to Drop database associated with this domain? [y/n]: " -e DROP_DB
    if [[ "${DROP_DB}" == Y* || "${DROP_DB}" == y* ]]; then
        until [[ "${MYSQL_USER}" != "" ]]; do
            read -rp "MySQL Username: " -e MYSQL_USER
        done

        until [[ "${MYSQL_PASS}" != "" ]]; do
            echo -n "MySQL Password: "
            stty -echo
            read -r MYSQL_PASS
            stty echo
            echo
        done

        echo ""
        echo "Please select your database below!"
        echo "+-------------------------------+"
        echo "|         Database name          "
        echo "+-------------------------------+"

        # Show user's databases
        #MYSQL_PWD="${MYSQL_PASS}" mysql -u "${MYSQL_USER}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema"
        local DATABASES \
            && DATABASES=$(MYSQL_PWD="${MYSQL_PASS}" mysql -u "${MYSQL_USER}" -N -B -e "SHOW DATABASES;" | grep -vE "^mysql$|_schema$")

        if [[ -n "${DATABASES}" ]]; then
            printf '%s\n' "${DATABASES}"
        else
            echo "No database found."
        fi

        echo "+-------------------------------+"

        until [[ "${DBNAME}" != "" ]]; do
            read -rp "MySQL Database: " -e DBNAME
        done

        [[ "${DBNAME}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || {
            error "Invalid database identifier."
            return 1
        }
        if grep -Fxq -- "${DBNAME}" <<<"${DATABASES}"; then
            echo "Deleting database ${DBNAME}..."
            MYSQL_PWD="${MYSQL_PASS}" run mysql -u "${MYSQL_USER}" -e "DROP DATABASE \`${DBNAME}\`"
            success "Database '${DBNAME}' dropped."
        else
            info "Sorry, database ${DBNAME} not found. Skipped..."
        fi
    fi

    echo "Virtual host ${DOMAIN} has been removed."

    # Reload Nginx.
    reload_nginx
}

##
# Main Manage CLI Wrapper
##
function init_lemper_manage() {
    lemper_parse_args 'c:d:e:f:r:s:bghv' 'enable:,disable:,remove:,enable-fail2ban:,disable-fail2ban:,enable-fastcgi-cache:,disable-fastcgi-cache:,enable-ssl:,disable-ssl:,remove-ssl:,renew-ssl:,enable-brotli:,enable-gzip:,disable-compression:,enable-modsec:,disable-modsec:,enable-cors:,disable-cors:,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while true; do
        case "${1}" in
            -e | --enable)
                enable_vhost "${2}" || return $?
                shift 2
                return 0
                ;;
            -d | --disable)
                disable_vhost "${2}" || return $?
                shift 2
                return 0
                ;;
            -r | --remove)
                remove_vhost "${2}" || return $?
                shift 2
                return 0
                ;;
            -c | --enable-fastcgi-cache)
                enable_fastcgi_cache "${2}" || return $?
                shift 2
                return 0
                ;;
            --disable-fastcgi-cache)
                disable_fastcgi_cache "${2}" || return $?
                shift 2
                return 0
                ;;
            -f | --enable-fail2ban)
                enable_fail2ban "${2}"
                shift 2
                return 0
                ;;
            --disable-fail2ban)
                disable_fail2ban "${2}"
                shift 2
                return 0
                ;;
            -s | --enable-ssl)
                enable_ssl "${2}" || return $?
                shift 2
                return 0
                ;;
            --disable-ssl)
                disable_ssl "${2}" || return $?
                shift 2
                return 0
                ;;
            --remove-ssl)
                remove_ssl "${2}" || return $?
                shift 2
                return 0
                ;;
            --renew-ssl)
                renew_ssl "${2}" || return $?
                shift 2
                return 0
                ;;
            -b | --enable-brotli)
                enable_brotli "${2}" || return $?
                shift 2
                return 0
                ;;
            -g | --enable-gzip)
                enable_gzip "${2}" || return $?
                shift 2
                return 0
                ;;
            --enable-modsec)
                enable_modsec "${2}" || return $?
                shift 2
                return 0
                ;;
            --disable-modsec)
                disable_modsec "${2}" || return $?
                shift 2
                return 0
                ;;
            --enable-cors)
                enable_cors "${2}" || return $?
                shift 2
                return 0
                ;;
            --disable-cors)
                disable_cors "${2}" || return $?
                shift 2
                return 0
                ;;
            --disable-compression)
                disable_compression "${2}" || return $?
                shift 2
                return 0
                ;;
            -h | --help)
                show_usage
                shift 2
                return 0
                ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VERSION}"
                shift 2
                return 0
                ;;
            --)
                # End of all options, shift to the next (non getopt) argument as $1.
                shift
                break
                ;;
            *)
                fail "Invalid argument: ${1}"
                return 1
                ;;
        esac
    done

    echo "${CMD_PARENT} ${CMD_NAME}: missing required argument"
    echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
}
