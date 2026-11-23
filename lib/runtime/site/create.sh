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
#

##
# Show usage
# output to STDERR.
#
function show_usage {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer Stack virtual host (vhost) configurator,
creates Nginx vhost configuration file on Debian/Ubuntu server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage: ${CMD_PARENT} ${CMD_NAME} [options]...
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework>
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework> -w <webroot-path>

Options:
  -4, --ipv4 <IPv4 address>
      Any valid IPv4 addreess for listening on.
  -6, --ipv6 <IPv6 address>
      Any valid IPv6 addreess for listening on.
  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed, i.e. example.app or sub.example.app.
  -f, --framework <website framework>
      Type of PHP web Framework and CMS, i.e. default.
      Supported PHP Framework and CMS: default (vanilla PHP), framework (codeigniter, laravel,
      lumen, phalcon, symfony), CMS (drupal, mautic, roundcube, sendy, wordpress, wordpress-ms).
      Another framework and cms will be added soon.
  -p, --php-version
      PHP version for selected framework; supported installation versions are 8.2-8.5.
  -u, --username <virtual-host username>
      Use username added from useradd. Default user set as LEMPer's user, Do not use root user!!
  -w, --webroot <web root>
      Web root is an absolute path to the website root directory, i.e. /home/lemper/webapps/example.test.

  -c, --enable-fastcgi-cache
      Enable FastCGI cache module.
  -D, --dryrun
      Dry run mode, only for testing.
  -F, --enable-fail2ban
      Enable fail2ban filter.
  -i, --install-app
      Install application files for a supported automatic installer.
      Mautic and Roundcube install the latest stable complete, checksummed release packages.
      Sendy supports vhost setup with manually deployed licensed files.
  -s, --enable-ssl
      Enable HTTPS with Let's Encrypt free SSL certificate.
  -W, --wildcard-domain
      Enable wildcard (*) domain.

  -h, --help
      Print this message and exit.
  -v, --version
      Show version number and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} -u lemper -d example.com -f default -w /home/lemper/webapps/example.test

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

# shellcheck disable=SC2034 # Request fields are consumed by the named provisioning/rendering drivers.
function lemper_site_create_command() {
    # Command line arguments.
    lemper_parse_args 'u:d:e:f:4:6:w:p:iScsFWDhv' 'username:,domain-name:,admin-email:,framework:,ipv4:,ipv6:,webroot:,php-version:,install-app,subdomains,enable-fastcgi-cache,enable-ssl,enable-fail2ban,wildcard-domain,dryrun,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    # Default parameter values.
    IPv4=""
    IPv6=""
    USERNAME=""
    SERVERNAME=""
    WEBROOT=""
    FRAMEWORK="default"
    PHP_VERSION="${DEFAULT_PHP_VERSION:-8.5}"
    INSTALL_APP=false
    WPMS_SUBDOMAINS=""
    ENABLE_FASTCGI_CACHE=false
    ENABLE_SSL=false
    ENABLE_WILDCARD_DOMAIN=false
    ENABLE_FAIL2BAN=false
    TMPDIR="/tmp/lemper"

    # Dry run (test mode).
    DRYRUN=false

    # Args counter
    MAIN_ARGS=0

    # Parse flags
    while true; do
        case "${1}" in
            -4 | --ipv4)
                shift
                IPv4="${1}"
                shift
                ;;
            -6 | --ipv6)
                shift
                IPv6="${1}"
                shift
                ;;
            -d | --domain-name)
                shift
                SERVERNAME="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
                ;;
            -e | --admin-email)
                shift
                APP_ADMIN_EMAIL="${1}"
                shift
                ;;
            -f | --framework)
                shift
                FRAMEWORK="${1}"
                shift
                ;;
            -u | --username)
                shift
                USERNAME="${1}"
                shift
                ;;
            -w | --webroot)
                shift
                # Remove badly and trailing slash.
                #WEBROOT=$(echo "${1}" | sed 's:/*$::')
                WEBROOT=$(echo "${1}" | tr -s /)
                shift
                ;;
            -p | --php-version)
                shift
                PHP_VERSION="${1}"
                shift
                ;;

            -c | --enable-fastcgi-cache)
                shift
                ENABLE_FASTCGI_CACHE=true
                ;;
            -D | --dryrun)
                shift
                DRYRUN=true
                ;;
            -F | --enable-fail2ban)
                shift
                ENABLE_FAIL2BAN=true
                ;;

            -i | --install-app)
                shift
                INSTALL_APP=true
                ;;
            -S | --subdomains)
                shift
                WPMS_SUBDOMAINS="--subdomains"
                ;;
            -s | --enable-ssl)
                shift
                ENABLE_SSL=true
                ;;
            -W | --wildcard-domain)
                shift
                ENABLE_WILDCARD_DOMAIN=true
                ;;
            -h | --help)
                shift
                show_usage
                return 0
                ;;
            -v | --version)
                shift
                echo "${PROG_NAME} version ${PROG_VERSION}"
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

    lemper_load_module services/nginx/vhost || return 1
    lemper_load_module services/php/pools || return 1
    lemper_load_module services/site/skeletons || return 1
    lemper_load_module services/site/provision || return 1
    lemper_site_provision "$@"
}
