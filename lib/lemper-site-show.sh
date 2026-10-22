#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Virtual Host (Site) Show                                    |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
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

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="site"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Validate FQDN domain name (portable, no PCRE dependency).
##
function validate_fqdn() {
    local FQDN=${1}

    if [[ ${#FQDN} -lt 4 || ${#FQDN} -gt 253 ]]; then
        echo false
        return
    fi

    if grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?$' <<< "${FQDN}"; then
        echo true
    else
        echo false
    fi
}

##
# Show site show help.
##
function site_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} show <domain>

Displays the full configuration for a specific virtual host.

Usage:
  ${CMD_PARENT} ${CMD_NAME} show <domain> [OPTIONS]

Options:
  -c, --config      Show Nginx vhost config (default).
  -f, --fpm         Show PHP-FPM pool configuration.
  -a, --app         Show application metadata (credentials, DB, etc.).
  -s, --ssl         Show SSL certificate information.
  -A, --all         Show all (config + FPM + app + SSL).
  -j, --json       Output as JSON instead of plain text.
  -h, --help        Print this message and exit.

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Extract the domain name from a vhost config file.
##
function extract_vhost_domain() {
    local VHOST_FILE=${1}
    grep -m1 'server_name' "${VHOST_FILE}" 2>/dev/null | \
        sed -E 's/.*server_name\s+([^;]+);.*/\1/' | \
        awk '{print $1}'
}

##
# Extract the PHP-FPM version from a vhost config file.
##
function extract_vhost_php_version() {
    local VHOST_FILE=${1}
    grep -m1 'fastcgi_pass' "${VHOST_FILE}" 2>/dev/null | \
        sed -E 's/.*php([0-9]+\.[0-9]+)-fpm.*/\1/' | \
        head -1
}

##
# Extract the FPM pool username from a vhost config file.
##
function extract_vhost_fpm_user() {
    local VHOST_FILE=${1}
    grep -m1 'fastcgi_pass' "${VHOST_FILE}" 2>/dev/null | \
        sed -E 's/.*fpm\.([a-zA-Z0-9_-]+)\.sock.*/\1/' | \
        head -1
}

##
# Extract the framework name from a vhost config file.
##
function extract_vhost_framework() {
    local VHOST_FILE=${1}
    grep -m1 'include.*vhost/site_' "${VHOST_FILE}" 2>/dev/null | \
        sed -E 's/.*site_([^.]+)\.conf.*/\1/' | \
        head -1
}

##
# Show the vhost configuration for a domain.
##
function show_vhost_config() {
    local DOMAIN=${1}
    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"

    if [[ ! -f "${VHOST_FILE}" ]]; then
        fail "Virtual host not found: ${DOMAIN} (expected at ${VHOST_FILE})"
    fi

    echo "========================================"
    echo " NGINX Virtual Host Configuration"
    echo "========================================"
    echo "Domain:   ${DOMAIN}"
    echo "File:     ${VHOST_FILE}"
    echo "Enabled:  $([[ -L /etc/nginx/sites-enabled/${DOMAIN}.conf ]] && echo "Yes" || echo "No")"
    echo "========================================"
    echo ""
    cat "${VHOST_FILE}"
    echo ""
}

##
# Show the PHP-FPM pool configuration for a domain.
##
function show_fpm_pool() {
    local DOMAIN=${1}
    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"

    if [[ ! -f "${VHOST_FILE}" ]]; then
        fail "Virtual host not found: ${DOMAIN}"
    fi

    local PHP_VERSION
    PHP_VERSION=$(extract_vhost_php_version "${VHOST_FILE}")

    local FPM_USER
    FPM_USER=$(extract_vhost_fpm_user "${VHOST_FILE}")

    local POOL_FILE=""
    if [[ -n "${PHP_VERSION}" && -n "${FPM_USER}" ]]; then
        POOL_FILE="/etc/php/${PHP_VERSION}/fpm/pool.d/${FPM_USER}.conf"
    fi

    echo "========================================"
    echo " PHP-FPM Pool Configuration"
    echo "========================================"
    echo "Domain:   ${DOMAIN}"
    echo "PHP ver:  ${PHP_VERSION:-unknown}"
    echo "FPM user: ${FPM_USER:-unknown}"
    echo "========================================"
    echo ""

    if [[ -n "${POOL_FILE}" && -f "${POOL_FILE}" ]]; then
        cat "${POOL_FILE}"
    else
        info "FPM pool file not found at ${POOL_FILE:-<not determined>}"
        info "The domain may not have a dedicated PHP-FPM pool."
    fi
    echo ""
}

##
# Show application metadata for a domain.
##
function show_app_metadata() {
    local DOMAIN=${1}
    local META_FILE="/etc/lemper/vhost.d/${DOMAIN}.conf"

    echo "========================================"
    echo " Application Metadata"
    echo "========================================"
    echo "Domain: ${DOMAIN}"
    echo "========================================"
    echo ""

    if [[ -f "${META_FILE}" ]]; then
        cat "${META_FILE}"
    else
        info "No application metadata found for ${DOMAIN}."
        info "Metadata is created when installing an application (WordPress, Laravel, etc.) via 'lemper-cli create'."
    fi
    echo ""
}

##
# Show SSL certificate information for a domain.
##
function show_ssl_info() {
    local DOMAIN=${1}
    local SSL_DIR="/etc/lemper/ssl/${DOMAIN}"

    echo "========================================"
    echo " SSL Certificate Information"
    echo "========================================"
    echo "Domain: ${DOMAIN}"
    echo "========================================"
    echo ""

    # Check Let's Encrypt certificate.
    if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
        echo "Certificate Type: Let's Encrypt (ACME)"
        echo "Certificate Path: /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        echo "Private Key Path: /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        if command -v certbot &>/dev/null; then
            certbot certificates 2>/dev/null | grep -A5 "${DOMAIN}" || true
        fi
        echo ""
    fi

    # Check self-signed certificate.
    if [[ -f "${SSL_DIR}/cert.pem" && -f "${SSL_DIR}/privkey.pem" ]]; then
        echo "Certificate Type: Self-Signed"
        echo "Certificate Path: ${SSL_DIR}/cert.pem"
        echo "Private Key Path: ${SSL_DIR}/privkey.pem"
        echo ""

        if command -v openssl &>/dev/null; then
            openssl x509 -in "${SSL_DIR}/cert.pem" -noout -subject -issuer -dates 2>/dev/null || true
        fi
        echo ""
    fi

    # Check if SSL is configured in the vhost.
    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"
    if [[ -f "${VHOST_FILE}" ]]; then
        if grep -qE '^\s*ssl_certificate\s+' "${VHOST_FILE}"; then
            echo "SSL: Enabled in vhost configuration"
        else
            echo "SSL: Not enabled in vhost configuration"
        fi
    fi
}

##
# Show all information for a domain in JSON format.
##
function show_all_json() {
    local DOMAIN=${1}
    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"
    local META_FILE="/etc/lemper/vhost.d/${DOMAIN}.conf"
    local SSL_DIR="/etc/lemper/ssl/${DOMAIN}"

    echo "{"
    echo "  \"domain\": \"${DOMAIN}\","
    echo "  \"vhost_file\": \"${VHOST_FILE}\","
    echo "  \"enabled\": $([[ -L /etc/nginx/sites-enabled/${DOMAIN}.conf ]] && echo "true" || echo "false"),"

    # Nginx config
    if [[ -f "${VHOST_FILE}" ]]; then
        echo "  \"nginx_config\": {"
        echo "    \"php_version\": \"$(extract_vhost_php_version "${VHOST_FILE}")\","
        echo "    \"framework\": \"$(extract_vhost_framework "${VHOST_FILE}")\","
        echo "    \"fpm_user\": \"$(extract_vhost_fpm_user "${VHOST_FILE}")\""
        echo "  },"
    else
        echo "  \"nginx_config\": null,"
    fi

    # App metadata
    if [[ -f "${META_FILE}" ]]; then
        echo "  \"app_metadata\": "
        # Parse the INI-like config file.
        python3 -c "
import configparser, json, sys
config = configparser.ConfigParser()
config.read('${META_FILE}')
for section in config.sections():
    print('  {\"' + section + '\": ' + json.dumps(dict(config[section])) + '}')" 2>/dev/null || echo "  null"
    else
        echo "  \"app_metadata\": null,"
    fi

    # SSL info
    if [[ -f "${SSL_DIR}/cert.pem" ]]; then
        echo "  \"ssl\": {"
        echo "    \"type\": \"self-signed\","
        echo "    \"cert_path\": \"${SSL_DIR}/cert.pem\""
        echo "  }"
    elif [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
        echo "  \"ssl\": {"
        echo "    \"type\": \"letsencrypt\","
        echo "    \"cert_path\": \"/etc/letsencrypt/live/${DOMAIN}/fullchain.pem\""
        echo "  }"
    else
        echo "  \"ssl\": null"
    fi
    echo "}"
}

##
# Main App
##
function init_lemper_site_show() {
    if [[ -z "${1}" ]]; then
        site_show_usage
        exit 1
    fi

    # Check for help flag first.
    case "${1}" in
        -h | --help)
            site_show_usage
            exit 0
        ;;
    esac

    # Validate domain name.
    if [[ $(validate_fqdn "${1}") == false ]]; then
        fail "Invalid domain name: '${1}' is not a valid FQDN."
    fi

    local DOMAIN="${1}"
    shift

    local SHOW_CONFIG=true
    local SHOW_FPM=false
    local SHOW_APP=false
    local SHOW_SSL=false
    local SHOW_ALL=false
    local OUTPUT_FORMAT="text"

    if [[ $# -gt 0 ]]; then
        local OPTS
        OPTS=$(getopt -o cafAsAj \
          -l config,fpm,app,ssl,all,help \
          -n "${PROG_NAME}" -- "$@")
        eval set -- "${OPTS}"

        while true; do
            case "${1}" in
                -c | --config)
                    SHOW_CONFIG=true
                    SHOW_FPM=false
                    SHOW_APP=false
                    SHOW_SSL=false
                    SHOW_ALL=false
                    shift
                ;;
                -f | --fpm)
                    SHOW_CONFIG=false
                    SHOW_FPM=true
                    SHOW_APP=false
                    SHOW_SSL=false
                    SHOW_ALL=false
                    shift
                ;;
                -a | --app)
                    SHOW_CONFIG=false
                    SHOW_FPM=false
                    SHOW_APP=true
                    SHOW_SSL=false
                    SHOW_ALL=false
                    shift
                ;;
                -s | --ssl)
                    SHOW_CONFIG=false
                    SHOW_FPM=false
                    SHOW_APP=false
                    SHOW_SSL=true
                    SHOW_ALL=false
                    shift
                ;;
                -A | --all)
                    SHOW_ALL=true
                    shift
                ;;
                -j | --json)
                    OUTPUT_FORMAT="json"
                    shift
                ;;
                -h | --help)
                    site_show_usage
                    exit 0
                ;;
                --)
                    shift
                    break
                ;;
                *)
                    fail "Invalid argument: ${1}"
                    exit 1
                ;;
            esac
        done
    fi

    if [[ "${SHOW_ALL}" == true ]]; then
        if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
            show_all_json "${DOMAIN}"
        else
            show_vhost_config "${DOMAIN}"
            show_fpm_pool "${DOMAIN}"
            show_app_metadata "${DOMAIN}"
            show_ssl_info "${DOMAIN}"
        fi
    else
        if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
            site_show_usage
            exit 1
        fi

        if [[ "${SHOW_CONFIG}" == true ]]; then
            show_vhost_config "${DOMAIN}"
        fi
        if [[ "${SHOW_FPM}" == true ]]; then
            show_fpm_pool "${DOMAIN}"
        fi
        if [[ "${SHOW_APP}" == true ]]; then
            show_app_metadata "${DOMAIN}"
        fi
        if [[ "${SHOW_SSL}" == true ]]; then
            show_ssl_info "${DOMAIN}"
        fi
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_site_show "$@"
