#!/usr/bin/env bash

# Run with Nginx 1.25.1+, curl and OpenSSL in a disposable Linux environment.
# All HTTP exchanges stay on loopback. The checkout can be mounted read-only.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
pid=
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf -- "$work"' EXIT

chmod 0755 "$work"
mkdir -p "$work"/{cache,logs,www/lcp/memcadmin,www/lcp/redisadmin}
printf 'public fixture\n' >"$work/www/index.html"
printf 'admin fixture\n' >"$work/www/lcp/index.html"
printf 'hidden fixture\n' >"$work/www/lcp/.private"
printf 'PHP fixture\n' >"$work/www/lcp/test.php"
printf 'Cache fixture\n' >"$work/www/lcp/memcadmin/index.php"
printf 'Cache fixture\n' >"$work/www/lcp/redisadmin/index.php"
ln -s index.html "$work/www/same-owner.html"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
cp -R "$root/etc/nginx" "$work/nginx"
mkdir -p "$work/nginx/ssl"
printf 'fixture-admin:%s\n' "$(openssl passwd -apr1 admin-fixture-password)" >"$work/nginx/lemper-admin.htpasswd"
printf 'fixture-hosting:%s\n' "$(openssl passwd -apr1 hosting-fixture-password)" >"$work/hosting.htpasswd"
chgrp www-data "$work/nginx/lemper-admin.htpasswd" "$work/hosting.htpasswd"
chmod 0640 "$work/nginx/lemper-admin.htpasswd" "$work/hosting.htpasswd"
openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 -out "$work/nginx/ssl/dhparam-2048.pem"
find "$work/nginx" -type f -exec sed -i \
    -e "s|/etc/nginx|$work/nginx|g" \
    -e "s|/var/log/nginx|$work/logs|g" \
    -e "s|/var/cache/nginx/proxy_cache|$work/cache|g" \
    -e "s|/usr/share/nginx/html|$work/www|g" \
    -e "s|/srv/.htpasswd|$work/hosting.htpasswd|g" {} +

port=$((18000 + BASHPID % 1000))
public=$port admin=$((port + 1000)) tls_public=$((port + 2000))
tls_admin=$((port + 3000)) proxy=$((port + 4000)) upstream=$((port + 5000))
legacy_media=$((port + 8000))
hosting=$((port + 9000))

sed -i -e '/listen \[::/d' -e 's|listen 80 default_server;|listen 127.0.0.1:'"$public"' default_server;|' \
    -e "s|listen 127.0.0.1:8082;|listen 127.0.0.1:$admin;|" "$work/nginx/sites-available/default"
sed -i -e '/listen \[::/d' \
    -e "s|listen 443 ssl default_server;|listen 127.0.0.1:$tls_public ssl default_server;|" \
    -e "s|listen 8083 ssl;|listen 127.0.0.1:$tls_admin ssl;|" \
    -e "s|listen 80;|listen 127.0.0.1:$((port + 6000));|" \
    -e "s|listen 8082;|listen 127.0.0.1:$((port + 7000));|" \
    -e "s|HOSTNAME_CERT_PATH/fullchain.pem|$work/cert.pem|g" \
    -e "s|HOSTNAME_CERT_PATH/privkey.pem|$work/key.pem|g" "$work/nginx/sites-available/default-ssl"

mkdir -p "$work/nginx/wpms/example.test"
printf 'branch.example.test 2;\n' >"$work/nginx/wpms/example.test/sites.conf"
mkdir -p "$work/wpms-www/wp-content/blogs.dir/2/files"
printf 'mapped media fixture\n' >"$work/wpms-www/wp-content/blogs.dir/2/files/logo.txt"
# shellcheck source=lib/services/nginx/vhost.sh
source "$root/lib/services/nginx/vhost.sh"
SERVERNAME=example.test prepare_vhost_wpms |
    sed "s|/etc/nginx/|$work/nginx/|" >"$work/wpms.conf"

cat >"$work/nginx.conf" <<EOF
daemon off;
user www-data;
pid $work/nginx.pid;
error_log $work/logs/main.log;
events {}
http {
    log_format lp_cache combined;
    access_log off;
    client_body_temp_path $work/body;
    fastcgi_temp_path $work/fastcgi;
    proxy_temp_path $work/proxy;
    scgi_temp_path $work/scgi;
    uwsgi_temp_path $work/uwsgi;
    include $work/nginx/fastcgi_https_map;
    include $work/nginx/proxy_cache;
    include $work/nginx/sites-available/default;
    include $work/nginx/sites-available/default-ssl;
    include $work/wpms.conf;
    server {
        listen 127.0.0.1:$proxy;
        include $work/nginx/includes/proxy_cache.conf;
        location / { proxy_pass http://127.0.0.1:$upstream; }
    }
    server {
        listen 127.0.0.1:$upstream;
        root $work/www;
        disable_symlinks if_not_owner;
        location = /blog-id { return 200 \$blogid; }
        location = /private {
            add_header Cache-Control 'private, no-store';
            return 200 'private fixture';
        }
        location = /session {
            add_header Set-Cookie 'fixture=1';
            return 200 'session fixture';
        }
    }
    server {
        listen 127.0.0.1:$legacy_media;
        set \$root_path $work/wpms-www;
        root \$root_path;
        include $work/nginx/vhost/site_wordpress-ms.conf;
    }
    server {
        listen 127.0.0.1:$hosting;
        root $work/www;
        auth_basic "Fixture hosting";
        auth_basic_user_file $work/hosting.htpasswd;
    }
}
EOF
nginx -t -p "$work" -c "$work/nginx.conf"
nginx -p "$work" -c "$work/nginx.conf" &
pid=$!

function request() {
    curl --noproxy '*' --silent --show-error --max-time 5 "$@"
}
function status_is() {
    local wanted="$1"
    shift
    [[ "$(request -o /dev/null -w '%{http_code}' "$@")" == "$wanted" ]]
}
function cache_is() {
    local wanted="$1"
    shift
    request -D - -o /dev/null "$@" | tr -d '\r' | grep -Fx "X-Cache-Status: $wanted"
}

for _ in {1..20}; do
    if status_is 200 "http://127.0.0.1:$public/" 2>/dev/null; then break; fi
    sleep 0.1
done
[[ "$(request "http://127.0.0.1:$public/")" == 'public fixture' ]]
status_is 404 "http://127.0.0.1:$public/lcp/index.html"
status_is 404 "http://127.0.0.1:$public/lcp"
status_is 401 "http://127.0.0.1:$admin/lcp/index.html"
status_is 401 "http://127.0.0.1:$admin/lcp/test.php"
[[ "$(request -u fixture-admin:admin-fixture-password "http://127.0.0.1:$admin/lcp/")" == 'admin fixture' ]]
status_is 404 -u fixture-admin:admin-fixture-password "http://127.0.0.1:$admin/lcp/.private"
status_is 404 --cacert "$work/cert.pem" "https://localhost:$tls_public/lcp/index.html"
status_is 401 --cacert "$work/cert.pem" "https://localhost:$tls_admin/lcp/index.html"
[[ "$(request --cacert "$work/cert.pem" -u fixture-admin:admin-fixture-password "https://localhost:$tls_admin/lcp/")" == 'admin fixture' ]]
[[ "$(request -u fixture-hosting:hosting-fixture-password "http://127.0.0.1:$hosting/index.html")" == 'public fixture' ]]
for panel in memcadmin redisadmin; do
    status_is 401 -u fixture-hosting:hosting-fixture-password "http://127.0.0.1:$admin/lcp/$panel/index.php"
    status_is 401 --cacert "$work/cert.pem" -u fixture-hosting:hosting-fixture-password \
        "https://localhost:$tls_admin/lcp/$panel/index.php"
done

[[ "$(request "http://127.0.0.1:$upstream/same-owner.html")" == 'public fixture' ]]
[[ "$(request -H 'Host: branch.example.test' "http://127.0.0.1:$upstream/blog-id")" == 2 ]]
[[ "$(request -H 'Host: example.test' "http://127.0.0.1:$upstream/blog-id")" == 0 ]]
[[ "$(request -H 'Host: branch.example.test' "http://127.0.0.1:$legacy_media/branch/files/logo.txt")" == 'mapped media fixture' ]]
cache_is MISS "http://127.0.0.1:$proxy/"
cache_is HIT "http://127.0.0.1:$proxy/"
cache_is BYPASS -H 'Cookie: fixture=1' "http://127.0.0.1:$proxy/"
cache_is BYPASS -H 'Authorization: Bearer fixture' "http://127.0.0.1:$proxy/"
cache_is MISS "http://127.0.0.1:$proxy/private"
cache_is MISS "http://127.0.0.1:$proxy/private"
cache_is MISS "http://127.0.0.1:$proxy/session"
cache_is MISS "http://127.0.0.1:$proxy/session"

mkdir -p "$work/fail2ban/"{filter.d,jail.d}
cp "$root/etc/fail2ban/filter.d/wordpress.conf" "$work/fail2ban/filter.d/"
sed -e "s|/etc/nginx|$work/nginx|g" -e "s|/var/log/nginx|$work/logs|g" \
    -e "s|/etc/fail2ban|$work/fail2ban|g" "$root/lib/services/nginx/protection.sh" >"$work/protection.sh"
# shellcheck source=/dev/null # Loads the path-isolated copy rendered above.
source "$work/protection.sh"
# shellcheck source=lib/core/security.sh
source "$root/lib/core/security.sh"
# shellcheck source=lib/core/validation.sh
source "$root/lib/core/validation.sh"
function lemper_exec() { "$@"; }
function fail2ban-client() { return 0; }
function error() { printf '%s\n' "$*" >&2; }
function success() { printf '%s\n' "$*"; }
reload_status=0
function service() {
    [[ "$*" == 'fail2ban reload' ]] || return 1
    return "$reload_status"
}

domain=example.test
log="$work/logs/$domain.access.log"
jail="$work/fail2ban/jail.d/$domain.conf"
printf 'access_log %s lp_cache buffer=32k flush=5s;\n' "$log" >"$work/nginx/sites-available/$domain.conf"
if lemper_nginx_fail2ban_enable "$domain" wordpress-ms 30d 2>/dev/null; then
    printf 'Fail2ban accepted an unavailable log.\n' >&2
    exit 1
fi
[[ ! -e "$jail" ]]
touch "$log"
lemper_nginx_fail2ban_enable "$domain" wordpress-ms 30d
grep -Fx "logpath = $log" "$jail"
grep -Fx 'filter = wordpress' "$jail"
cp -- "$jail" "$work/previous-jail"
reload_status=1
if lemper_nginx_fail2ban_enable "$domain" wordpress 7d 2>/dev/null; then
    printf 'Fail2ban accepted a failed reload.\n' >&2
    exit 1
fi
cmp "$jail" "$work/previous-jail"
printf 'Nginx public/admin routing, protected map, proxy cache and Fail2ban input checks passed.\n'
