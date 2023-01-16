#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper Manage - Simple LEMP Virtual Host Manager                        |
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

# Version control.
#PROG_NAME=$(basename "$0")
#PROG_VER="2.x.x"
#CMD_PARENT="lemper-cli"
#CMD_NAME="sslgen"

# Make sure only root can access and not direct access.
if ! declare -F "requires_root" &>/dev/null; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

# Usage: sslgen <domain> <ip-address>
function sslgen() {
    DOMAIN=${1}
    SERVER_IP=${2:-$(hostname -I | awk '{print $1}')}
    KEY_HASH_LENGTH=2048

    if [ -z "${DOMAIN}" ]; then
        echo "Please specify domain name."
        exit 1
    fi

    if [ ! -d "/etc/lemper/ssl/${DOMAIN}" ]; then
        mkdir -p "/etc/lemper/ssl/${DOMAIN}"
    fi

    # Self-signed certificate for local development environment.
    sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/ca.conf && \
    sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed -i "s|^DNS\.2\ =\ .*|DNS\.2\ =\ www\.${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    sed -r -i "s|^IP.1\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.1\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    sed -r -i "s|^IP.2\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.2\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/cert.conf

    # Create Certificate Authority (CA).
    if [[ ! -f /etc/lemper/ssl/lemperCA.key || ! -f /etc/lemper/ssl/lemperCA.crt ]]; then
        run openssl req -x509 -sha256 -days 365000 -nodes -newkey "rsa:${KEY_HASH_LENGTH}" \
            -keyout "/etc/lemper/ssl/${DOMAIN}-ca.key" -out "/etc/lemper/ssl/${DOMAIN}-ca.crt" \
            -config /etc/lemper/ssl/ca.conf

        CA_KEY_FILE="/etc/lemper/ssl/${DOMAIN}-ca.key"
        CA_CRT_FILE="/etc/lemper/ssl/${DOMAIN}-ca.crt"
    else
        CA_KEY_FILE="/etc/lemper/ssl/lemperCA.key"
        CA_CRT_FILE="/etc/lemper/ssl/lemperCA.crt"
    fi

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
        echo "Self-signed SSL certificate has been successfully generated."
        echo "Certificate file: /etc/lemper/ssl/${DOMAIN}/cert.pem"
        echo "Private key file: /etc/lemper/ssl/${DOMAIN}/privkey.pem"
        exit 0
    else
        echo "An error occurred when generating self-signed SSL certificate."
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
sslgen "$@"
