#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Self-signed SSL Generator                                  |
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
CMD_NAME="selfssl"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

## 
# Show usage
# output to STDERR.
##
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
    local FQDN=${1}

    # Length check: 4-253 characters (RFC 1035 / RFC 1123).
    if [[ ${#FQDN} -lt 4 || ${#FQDN} -gt 253 ]]; then
        echo false # error
        return
    fi

    # Validate format: labels of 1-63 chars separated by dots,
    # no leading/trailing dashes, TLD is 2-63 letters, optional trailing dot.
    if grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?$' <<< "${FQDN}"; then
        echo true # success
    else
        echo false # error
    fi
}

##
# Validate IPv4 address.
##
function validate_ipv4() {
    local IP=${1}

    if grep -qE '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' <<< "${IP}"; then
        echo true # success
    else
        echo false # error
    fi
}

##
# Sanitize a string for safe use in sed replacement patterns.
# Escapes backslash, ampersand, and forward-slash to prevent injection
# when interpolating user input into sed s/.../.../ commands.
##
function sanitize_sed_replacement() {
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/[\\&]/\\&/g' -e 's/\//\\\//g'
}

##
# Usage: generate_selfsigned_ssl <domain> <ipv4> <ipv6>
##
function generate_selfsigned_ssl() {
    DOMAIN=${1}
    SERVER_IP=${2:-$(hostname -I | awk '{print $1}')}
    KEY_HASH_LENGTH=4096

    if [ -z "${DOMAIN}" ]; then
        fail "Please specify domain name."
    fi

    if [[ $(validate_fqdn "${DOMAIN}") == false ]]; then
        fail "Your Domain name is not valid 'Fully Qualified Domain Name (FQDN)' format!"
    fi

    # Validate IPv4 address when provided via CLI --ipv4 flag.
    if [ -n "${SERVER_IP}" ] && [[ $(validate_ipv4 "${SERVER_IP}") == false ]]; then
        fail "Invalid IPv4 address: '${SERVER_IP}' is not a valid IPv4 address."
    fi

    if [ ! -d "/etc/lemper/ssl/${DOMAIN}" ]; then
        mkdir -p "/etc/lemper/ssl/${DOMAIN}"
    fi

    # Self-signed certificate for local development environment.
    sed_inplace "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/ca.conf && \
    sed_inplace "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed_inplace "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed_inplace "s|^DNS\.2\ =\ .*|DNS\.2\ =\ www\.${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed_inplace -r "s|^IP.1\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.1\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    sed_inplace -r "s|^IP.2\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.2\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    sed_inplace "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/cert.conf

    # Create Certificate Authority (CA).
    run openssl req -x509 -sha256 -days 365000 -nodes -newkey "rsa:${KEY_HASH_LENGTH}" \
        -keyout "/etc/lemper/ssl/${DOMAIN}/ca.key" -out "/etc/lemper/ssl/${DOMAIN}/ca.crt" \
        -config /etc/lemper/ssl/ca.conf

    CA_KEY_FILE="/etc/lemper/ssl/${DOMAIN}/ca.key"
    CA_CRT_FILE="/etc/lemper/ssl/${DOMAIN}/ca.crt"

    # Create Server Private Key.
    run openssl genrsa -out "/etc/lemper/ssl/${DOMAIN}/privkey.pem" "${KEY_HASH_LENGTH}" && \

    # Generate Certificate Signing Request (CSR) using Server Private Key.
    run openssl req -new -key "/etc/lemper/ssl/${DOMAIN}/privkey.pem" \
        -out "/etc/lemper/ssl/${DOMAIN}/csr.csr" -config /etc/lemper/ssl/csr.conf

    # Generate SSL certificate With self signed CA.
    run openssl x509 -req -sha256 -days 365000 -CAcreateserial \
        -CA "${CA_CRT_FILE}" -CAkey "${CA_KEY_FILE}" \
        -in "/etc/lemper/ssl/${DOMAIN}/csr.csr" -out "/etc/lemper/ssl/${DOMAIN}/cert.pem" \
        -extfile /etc/lemper/ssl/cert.conf

    # Create chain file.
    run cat "/etc/lemper/ssl/${DOMAIN}/cert.pem" "${CA_CRT_FILE}" >> \
        "/etc/lemper/ssl/${DOMAIN}/fullchain.pem"

    if [ -f "/etc/lemper/ssl/${DOMAIN}/cert.pem" ]; then
        info "Self-signed SSL certificate has been successfully generated."
        echo "Certificate file: /etc/lemper/ssl/${DOMAIN}/cert.pem"
        echo "Private key file: /etc/lemper/ssl/${DOMAIN}/privkey.pem"
        echo "Full chain file:  /etc/lemper/ssl/${DOMAIN}/fullchain.pem"
        exit 0
    else
        fail "An error occurred while generating self-signed SSL certificate."
    fi
}

##
# Main App
#
function init_selfsigned_ssl() {
    # Command line arguments.
    OPTS=$(getopt -o d:4:6: \
      -l domain-name:,ipv4:,ipv6: \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

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
                exit 0
            ;;
            -v | --version)
                shift
                echo "${PROG_NAME} version ${PROG_VERSION}"
                exit 0
            ;;
            --)
                # End of all options, shift to the next (non getopt) argument as $1. 
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
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
init_selfsigned_ssl "$@"
