#!/usr/bin/env bash

# Nginx SSL Certificate Generation
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Generate SSL certificate for hostname
# Returns certificate path in HOSTNAME_CERT_PATH variable
##
function generate_hostname_cert() {
    local HOSTNAME="${HOSTNAME:-$(hostname -f)}"
    local SERVER_IP
    SERVER_IP=$(get_ip)

    echo "Generating SSL certificate for default hostname ${HOSTNAME}..."

    # Production environment with valid DNS
    if [[ "${ENVIRONMENT:-development}" == prod* && $(dig "${HOSTNAME}" +short 2>/dev/null) == "${SERVER_IP}" ]]; then
        generate_letsencrypt_cert "${HOSTNAME}"
    else
        # Development environment - self-signed certificate
        generate_selfsigned_cert "${HOSTNAME}" "${SERVER_IP}"
    fi
}

##
# Generate Let's Encrypt certificate
##
function generate_letsencrypt_cert() {
    local DOMAIN="$1"

    echo "Generating Let's Encrypt certificate for ${DOMAIN}..."

    # Stop webserver temporarily
    run systemctl stop nginx.service

    if [[ ! -e "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        run certbot certonly --standalone --agree-tos --preferred-challenges http \
            --webroot-path=/usr/share/nginx/html -d "${DOMAIN}"
    fi

    HOSTNAME_CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"

    # Restart webserver
    run systemctl start nginx.service
}

##
# Generate self-signed SSL certificate
##
function generate_selfsigned_cert() {
    local DOMAIN="$1"
    local SERVER_IP="${2:-$(get_ip)}"
    local KEY_HASH_LENGTH="${KEY_HASH_LENGTH:-2048}"

    echo "Generating self-signed certificate for ${DOMAIN}..."

    # Ensure SSL directory exists
    [[ ! -d "/etc/lemper/ssl/${DOMAIN}" ]] && mkdir -p "/etc/lemper/ssl/${DOMAIN}"

    # Update certificate configuration files
    run sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/ca.conf
    run sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf
    run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf
    run sed -i "s|^DNS\.2\ =\ .*|DNS\.2\ =\ www\.${DOMAIN}|g" /etc/lemper/ssl/csr.conf
    run sed -r -i "s|^IP.1\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.1\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf
    run sed -r -i "s|^IP.2\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.2\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf
    run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/cert.conf

    # Create Certificate Authority (CA)
    run openssl req -x509 -sha256 -days 365000 -nodes -newkey "rsa:${KEY_HASH_LENGTH}" \
        -keyout /etc/lemper/ssl/lemperCA.key -out /etc/lemper/ssl/lemperCA.crt \
        -config /etc/lemper/ssl/ca.conf

    # Create Server Private Key
    run openssl genrsa -out "/etc/lemper/ssl/${DOMAIN}/privkey.pem" "${KEY_HASH_LENGTH}"

    # Generate Certificate Signing Request (CSR)
    run openssl req -new -key "/etc/lemper/ssl/${DOMAIN}/privkey.pem" \
        -out "/etc/lemper/ssl/${DOMAIN}/csr.pem" -config /etc/lemper/ssl/csr.conf

    # Generate SSL certificate with self-signed CA
    run openssl x509 -req -sha256 -days 365000 -CAcreateserial \
        -CA /etc/lemper/ssl/lemperCA.crt -CAkey /etc/lemper/ssl/lemperCA.key \
        -in "/etc/lemper/ssl/${DOMAIN}/csr.pem" -out "/etc/lemper/ssl/${DOMAIN}/cert.pem" \
        -extfile /etc/lemper/ssl/cert.conf

    # Create fullchain (cert + CA)
    run cat "/etc/lemper/ssl/${DOMAIN}/cert.pem" /etc/lemper/ssl/lemperCA.crt > \
        "/etc/lemper/ssl/${DOMAIN}/fullchain.pem"

    if [[ -f "/etc/lemper/ssl/${DOMAIN}/cert.pem" ]]; then
        HOSTNAME_CERT_PATH="/etc/lemper/ssl/${DOMAIN}"
        success "Self-signed SSL certificate has been successfully generated."
    else
        fail "An error occurred when generating self-signed SSL certificate."
    fi
}
