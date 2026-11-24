#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer HTTP/3 Protocol Acceptance                                       |
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
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-protocols-authorized &&
    $(cat /proc/1/comm) == systemd && $(findmnt -no OPTIONS /source) == ro,* ]] || {
    echo 'Designated disposable protocol UAT container required.' >&2
    exit 2
}
work=/run/lemper-protocols
logs=/var/log/lemper-protocols
client="$work/curl-8.23.0/src/curl"
server=/var/tmp/lemper-protocols-source/nginx-1.30.8/objs/nginx
[[ -x "$client" && -x "$server" ]] || {
    echo 'Prepare the verified curl and Nginx protocol builds first.' >&2
    exit 2
}
install -d -m 0700 "$logs" "$work/nginx/logs"
checks=0
function check() {
    local name="$1"
    shift
    if "$@" >"$logs/$name.log" 2>&1; then
        checks=$((checks + 1))
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"
        exit 1
    fi
}
function nginx() { "$server" "$@"; }
# The driver expects the initialized Linux installer helpers.
function sed_inplace() { sed -i "$@"; }
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module services/nginx/configure
export DRYRUN=false NGINX_HTTP3=true RED=31 GREEN=32 YELLOW=33 BLUE=34
function client_http3_capable() { "$client" --version | grep -q 'Features:.*HTTP3'; }
function server_http3_capable() { "$server" -V 2>&1 | grep -q -- --with-http_v3_module; }
check client_http3 client_http3_capable
check server_http3 server_http3_capable
install -d -m 0755 /etc/nginx/includes /etc/nginx/sites-available /etc/nginx/ssl
check certificate openssl req -x509 -newkey rsa:4096 -nodes -days 1 \
    -keyout "$work/server.key" -out "$work/server.crt" \
    -subj /CN=protocols.lemper-uat.test -addext subjectAltName=DNS:protocols.lemper-uat.test
chmod 0600 "$work/server.key"
if [[ ! -f /etc/nginx/ssl/dhparam-2048.pem ]]; then
    check dh_parameters openssl dhparam -out /etc/nginx/ssl/dhparam-2048.pem 2048
else
    check dh_parameters openssl dhparam -in /etc/nginx/ssl/dhparam-2048.pem -check -noout
fi
install -m 0644 /source/etc/nginx/includes/ssl.conf /etc/nginx/includes/ssl.conf
cat >/etc/nginx/sites-available/default <<'VHOST'
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name protocols.lemper-uat.test;
    ssl_certificate /run/lemper-protocols/server.crt;
    ssl_certificate_key /run/lemper-protocols/server.key;
    include /etc/nginx/includes/ssl.conf;
    location / { return 200 "lemper-http3-uat\n"; }
}
VHOST
cat >"$work/nginx/nginx.conf" <<'NGINX'
worker_processes 1;
pid /run/lemper-protocols/nginx.pid;
events { worker_connections 256; }
http {
    log_format protocol '$server_protocol $ssl_protocol early=$ssl_early_data';
    access_log /var/log/lemper-protocols/access.log protocol;
    include /etc/nginx/sites-available/default;
}
NGINX
check driver_configuration configure_http3
check server_configuration nginx -t -c "$work/nginx/nginx.conf"
check server_start nginx -c "$work/nginx/nginx.conf"
trap 'nginx -s quit -c "$work/nginx/nginx.conf" >/dev/null 2>&1 || true' EXIT
common=(--noproxy '*' --silent --show-error --max-time 15 \
    --cacert "$work/server.crt" --resolve protocols.lemper-uat.test:443:127.0.0.1)
url=https://protocols.lemper-uat.test/
check quic_request "$client" "${common[@]}" --http3-only --ssl-sessions "$work/sessions" \
    -D "$work/headers" -o "$work/body" -w '%{http_version} %{response_code} %{tls_earlydata}\n' "$url"
check quic_metadata grep -qx '3 200 0' "$logs/quic_request.log"
function response_body_valid() { [[ $(cat "$work/body") == lemper-http3-uat ]]; }
check response_body response_body_valid
check alt_svc grep -Fiq 'Alt-Svc: h3=":443"' "$work/headers"
check early_data_default "$client" "${common[@]}" --http3-only --tls-earlydata --ssl-sessions "$work/sessions" \
    -o /dev/null -w '%{http_version} %{response_code} %{tls_earlydata}\n' "$url"
check early_data_metadata grep -qx '3 200 0' "$logs/early_data_default.log"
check quic_tls13 grep -q '^HTTP/3.0 TLSv1.3 early=-$' "$logs/access.log"
function untrusted_certificate() {
    local status=0
    "$client" --noproxy '*' --http3-only --silent --show-error --max-time 15 \
        --resolve protocols.lemper-uat.test:443:127.0.0.1 "$url" >/dev/null 2>&1 || status=$?
    [[ "$status" == 60 ]]
}
function invalid_hostname() {
    local status=0
    "$client" --noproxy '*' --http3-only --silent --show-error --max-time 15 \
        --cacert "$work/server.crt" --resolve wrong.lemper-uat.test:443:127.0.0.1 \
        https://wrong.lemper-uat.test/ >/dev/null 2>&1 || status=$?
    [[ "$status" == 60 ]]
}
check untrusted_certificate_refused untrusted_certificate
check hostname_mismatch_refused invalid_hostname
printf 'Protocol UAT: %s checks passed.\n' "$checks"
