#!/usr/bin/env bash
# Forked from https://gist.github.com/fideloper/9052820
 
SSL_DIR="/etc/ssl/xip.io"
DOMAIN="*.xip.io"
PASSPHRASE="vaprobash"
 
SUBJ="
C=US
ST=Connecticut
O=Vaprobash
localityName=New Haven
commonName=$DOMAIN
organizationalUnitName=
emailAddress=
"
 
sudo mkdir -p "$SSL_DIR"
 
sudo openssl genrsa -out "$SSL_DIR/xip.io.key" 1024
sudo openssl req -new -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -key "$SSL_DIR/xip.io.key" -out "$SSL_DIR/xip.io.csr" -passin pass:$PASSPHRASE
sudo openssl x509 -req -days 365 -in "$SSL_DIR/xip.io.csr" -signkey "$SSL_DIR/xip.io.key" -out "$SSL_DIR/xip.io.crt"
 
# If apache, enable SSL via `sudo a2enmod ssl`, then restart `sudo service apache2 restart`
# If nginx, already enabled
 
# If apache, edit vhost to include HTTPS portion
# If nginx, edit vhost to include HTTPS portion
# .. and then reload relevant service 