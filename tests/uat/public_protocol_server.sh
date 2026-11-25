#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Public Protocol Endpoint                              |
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

set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /fixture/authorized &&
    $(findmnt -no OPTIONS /source) == ro,* &&
    -r /fixture/cert/fullchain.pem && -r /fixture/cert/privkey.pem ]] || exit 2
domain="${LEMPER_UAT_ACME_DOMAIN:-}"
port="${LEMPER_UAT_PUBLIC_PORT:-18443}"
[[ "$domain" =~ ^uat-[a-z0-9-]+\.[a-z0-9.-]+$ &&
    "$port" =~ ^[1-9][0-9]{3,4}$ && "$port" -ge 1024 && "$port" -le 65535 ]] || exit 2
# Function-only services; configuration stays inside the disposable endpoint.
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
is_valid_domain "$domain" || exit 2
lemper_load_module services/nginx/configure
export DRYRUN=false NGINX_HTTP3=true RED=31 GREEN=32 YELLOW=33 BLUE=34
function sed_inplace() { sed -i "$@"; }
install -d -m 0755 /etc/nginx/includes /etc/nginx/sites-available /etc/nginx/ssl /usr/share/nginx/html
install -m 0644 /source/etc/nginx/includes/ssl.conf /etc/nginx/includes/ssl.conf
install -m 0644 /source/share/nginx/html/index.html /usr/share/nginx/html/index.html
openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 \
    -out /etc/nginx/ssl/dhparam-2048.pem
cat >/etc/nginx/sites-available/default <<VHOST
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $domain *.$domain;
    ssl_certificate /fixture/cert/fullchain.pem;
    ssl_certificate_key /fixture/cert/privkey.pem;
    include /etc/nginx/includes/ssl.conf;
    root /usr/share/nginx/html;
    index index.html;
    add_header X-LEMPer-UAT public-protocol always;
    location / { try_files \$uri \$uri/ =404; }
}
VHOST
cat >/etc/nginx/nginx.conf <<'NGINX'
worker_processes 1;
error_log /dev/stderr notice;
pid /run/nginx.pid;
events { worker_connections 128; }
http {
    include /etc/nginx/mime.types;
    log_format uat '$server_protocol $ssl_protocol early=$ssl_early_data';
    access_log /dev/stdout uat;
    include /etc/nginx/sites-available/default;
}
NGINX
configure_http3
# Only this fixture maps the standard internal TLS port to a public high port.
sed -i "s/h3=\":443\"/h3=\":$port\"/; s/ma=86400/ma=60/" /etc/nginx/includes/http3.conf
nginx -t
exec nginx -g 'daemon off;'
