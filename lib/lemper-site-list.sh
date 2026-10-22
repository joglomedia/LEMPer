#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Virtual Host (Site) List                                    |
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
# Show site list help.
##
function site_list_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} list

Lists all configured virtual hosts on this server.

Usage:
  ${CMD_PARENT} ${CMD_NAME} list [OPTIONS]

Options:
  -j, --json      Output as JSON instead of table.
  -a, --all       Show all vhosts including disabled ones (default).
  -e, --enabled   Show only enabled vhosts (symlinked in sites-enabled).
  -d, --disabled  Show only disabled vhosts (no symlink in sites-enabled).
  -h, --help      Print this message and exit.

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
# Extract the framework name from a vhost config file.
##
function extract_vhost_framework() {
    local VHOST_FILE=${1}
    grep -m1 'include.*vhost/site_' "${VHOST_FILE}" 2>/dev/null | \
        sed -E 's/.*site_([^.]+)\.conf.*/\1/' | \
        head -1
}

##
# Check if SSL is enabled for a vhost.
##
function extract_vhost_ssl_status() {
    local VHOST_FILE=${1}
    if grep -qE '^\s*ssl_certificate\s+' "${VHOST_FILE}" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

##
# List all virtual hosts.
##
function list_vhosts() {
    local OUTPUT_FORMAT="table"
    local SHOW_ENABLED=""
    local SHOW_DISABLED=""

    local OPTS
    OPTS=$(getopt -o jeadh \
      -l json,all,enabled,disabled,help \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -j | --json)
                OUTPUT_FORMAT="json"
                shift
            ;;
            -a | --all)
                SHOW_ENABLED=""
                SHOW_DISABLED=""
                shift
            ;;
            -e | --enabled)
                SHOW_ENABLED="yes"
                shift
            ;;
            -d | --disabled)
                SHOW_DISABLED="yes"
                shift
            ;;
            -h | --help)
                site_list_show_usage
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

    if [[ ! -d /etc/nginx/sites-available ]]; then
        error "Directory /etc/nginx/sites-available does not exist."
        exit 1
    fi

    # Collect vhost data.
    local vhost_count=0
    local domains=()
    local php_versions=()
    local frameworks=()
    local ssl_statuses=()
    local enabled_statuses=()

    while IFS= read -r vhost_file; do
        local domain framework php_version ssl_status enabled="disabled"

        domain=$(extract_vhost_domain "${vhost_file}")
        [[ -z "${domain}" ]] && continue

        framework=$(extract_vhost_framework "${vhost_file}")
        php_version=$(extract_vhost_php_version "${vhost_file}")
        ssl_status=$(extract_vhost_ssl_status "${vhost_file}")

        # Check if enabled (symlink in sites-enabled).
        local basename
        basename=$(basename "${vhost_file}")
        if [[ -L "/etc/nginx/sites-enabled/${basename}" ]]; then
            enabled="enabled"
        fi

        # Filter by enabled/disabled flag.
        if [[ -n "${SHOW_ENABLED}" && "${enabled}" != "enabled" ]]; then
            continue
        fi
        if [[ -n "${SHOW_DISABLED}" && "${enabled}" != "disabled" ]]; then
            continue
        fi

        domains+=("${domain}")
        frameworks+=("${framework:-default}")
        php_versions+=("${php_version:-n/a}")
        ssl_statuses+=("${ssl_status}")
        enabled_statuses+=("${enabled}")
        vhost_count=$((vhost_count + 1))
    done < <(find /etc/nginx/sites-available -name "*.conf" -type f 2>/dev/null | sort)

    if [[ ${vhost_count} -eq 0 ]]; then
        info "No virtual hosts found."
        exit 0
    fi

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        # JSON output.
        printf '{\n'
        printf '  "virtual_hosts": [\n'
        for i in "${!domains[@]}"; do
            printf '    {\n'
            printf '      "domain": "%s",\n' "${domains[$i]}"
            printf '      "framework": "%s",\n' "${frameworks[$i]}"
            printf '      "php_version": "%s",\n' "${php_versions[$i]}"
            printf '      "ssl": "%s",\n' "${ssl_statuses[$i]}"
            printf '      "status": "%s"\n' "${enabled_statuses[$i]}"
            if [[ $i -lt $((${#domains[@]} - 1)) ]]; then
                printf '    },\n'
            else
                printf '    }\n'
            fi
        done
        printf '  ],\n'
        printf '  "total": %d\n' "${vhost_count}"
        printf '}\n'
    else
        # Table output.
        printf "%-30s %-12s %-12s %-10s %-10s\n" "DOMAIN" "FRAMEWORK" "PHP VERSION" "SSL" "STATUS"
        printf "%-30s %-12s %-12s %-10s %-10s\n" "------" "---------" "-----------" "---" "------"
        for i in "${!domains[@]}"; do
            printf "%-30s %-12s %-12s %-10s %-10s\n" \
                "${domains[$i]}" \
                "${frameworks[$i]}" \
                "${php_versions[$i]}" \
                "${ssl_statuses[$i]}" \
                "${enabled_statuses[$i]}"
        done
        echo ""
        info "Total: ${vhost_count} virtual host(s)"
    fi
}

##
# Main App
##
function init_lemper_site_list() {
    if [[ -n "${1}" ]]; then
        list_vhosts "$@"
    else
        site_list_show_usage
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_site_list "$@"
