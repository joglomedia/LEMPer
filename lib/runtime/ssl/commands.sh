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



function show_usage() {
cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Generates self-signed SSL certificate on Debian/Ubuntu server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTION]...

Options:
  -4, --ipv4 <IPv4 address>
      Any valid IPv4 addreess for listening on.
  -6, --ipv6 <IPv6 address>
      Any valid IPv6 addreess for listening on.
  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed, i.e. example.app or sub.example.app.

  -h, --help
      Print this message and exit.
  -v, --version
      Output version information and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} --domain-name example.com

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Validate FQDN domain.
# Uses ERE (grep -E) with a separate length check for portability.
##
function validate_fqdn() {
    core_validate_fqdn "$@"
}

##
# Validate IPv4 address.
##
function validate_ipv4() {
    core_validate_ipv4 "$@"
}

##
# Sanitize a string for safe use in sed replacement patterns.
# Escapes backslash, ampersand, and forward-slash to prevent injection
# when interpolating user input into sed s/.../.../ commands.
##
function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

##
# Usage: generate_selfsigned_ssl <domain> <ipv4> <ipv6>
##
function generate_selfsigned_ssl() {
    local domain="${1:-}" ipv4="${2:-$(hostname -I | awk '{print $1}')}" ipv6="${3:-}"
    [[ $(core_validate_fqdn "$domain") == true ]] || { fail "Invalid certificate domain."; return 1; }
    core_is_valid_ipv4 "$ipv4" || { fail "Invalid certificate IPv4 address."; return 1; }
    [[ -z "$ipv6" ]] || core_is_valid_ipv6 "$ipv6" || { fail "Invalid certificate IPv6 address."; return 1; }
    lemper_load_module services/ssl/certificates || return 1
    lemper_with_lock lemper_ssl_generate_selfsigned "$domain" "$ipv4" "$ipv6"
}

##
# Main App
#
function lemper_ssl_command() {
    # Command line arguments.
    lemper_parse_args 'd:4:6:hv' 'domain-name:,ipv4:,ipv6:,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    # Default parameter values.
    DOMAIN=""
    IPv4=""
    IPv6=""

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
                DOMAIN="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
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

    if [[ "${MAIN_ARGS}" -ge 1 ]]; then
        generate_selfsigned_ssl "${DOMAIN}" "${IPv4}" "${IPv6}"
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
