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

# Real installation/restore checks, exclusively in a designated disposable host.
set -euo pipefail
[[ -f /run/lemper-priority-uat-authorized && "$(id -u)" == 0 && -f /source/.env.dist ]] || {
    echo 'Requires a disposable Linux UAT container with authorization marker.' >&2
    exit 1
}
work=/run/lemper-priority-uat
[[ ! -e "$work" ]] || {
    echo 'Use a fresh UAT container.' >&2
    exit 1
}
install -d -m0700 "$work"
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
export DRYRUN=false RED=31 GREEN=32 YELLOW=33 BLUE=34
lemper_load_module core/deployment
lemper_cli_snapshot /source
# Use immutable copied code for every remaining helper/template read.
export LEMPER_UAT_CODE_ROOT
LEMPER_UAT_CODE_ROOT=$(readlink -f /opt/lemper/current)
# shellcheck source=/dev/null
. "$LEMPER_UAT_CODE_ROOT/lib/core/loader.sh"
error() { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }
warning() { printf '%s\n' "$*" >&2; }
install -d -m0700 /etc/lemper /etc/lemper/ssl
sed -e 's/^LOGGING=.*/LOGGING=false/' -e 's/^SSH_PASSWORDLESS=.*/SSH_PASSWORDLESS=false/' \
    -e 's/^DEFAULT_PHP_VERSION=.*/DEFAULT_PHP_VERSION="8.3"/' "$LEMPER_UAT_CODE_ROOT/.env.dist" >/etc/lemper/lemper.conf
chmod 0600 /etc/lemper/lemper.conf
cp "$LEMPER_UAT_CODE_ROOT"/etc/openssl/*.conf /etc/lemper/ssl/
checks=0
function check() {
    "$@"
    checks=$((checks + 1))
}
function rejects() {
    if "$@"; then
        echo 'Expected rejection.' >&2
        return 1
    fi
    checks=$((checks + 1))
}
check lemperctl account uatowner
# Give the web worker search permission while keeping home listings private.
chmod o+x /home/uatowner
check lemperctl selfssl --domain-name priority.test --ipv4 127.0.0.1 --ipv6 ::1
check openssl verify -CAfile /etc/lemper/ssl/priority.test/ca.crt /etc/lemper/ssl/priority.test/cert.pem
check test "$(stat -c %a /etc/lemper/ssl/priority.test/privkey.pem)" = 600
before=$(sha256sum /etc/lemper/ssl/ca.conf /etc/lemper/ssl/csr.conf)
check lemperctl selfssl --domain-name priority.test --ipv4 127.0.0.1 --ipv6 ::1
check test "$(sha256sum /etc/lemper/ssl/ca.conf /etc/lemper/ssl/csr.conf)" = "$before"
rejects lemperctl selfssl --domain-name $'priority.test\ninvalid' --ipv4 127.0.0.1
rejects lemperctl selfssl --domain-name priority.test --ipv4 127.0.0.1 --ipv6 :::
php_version=$(php -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;')
install -d -m0755 /home/uatowner/webapps/priority.test
printf '<?php echo "priority-http-ok";\n' >/home/uatowner/webapps/priority.test/index.php
chown -R uatowner:uatowner /home/uatowner/webapps/priority.test
cat >"/etc/php/$php_version/fpm/pool.d/uatowner.conf" <<POOL
[uatowner]
user=uatowner
group=uatowner
listen=/run/php/php$php_version-fpm.uatowner.sock
listen.owner=www-data
listen.group=www-data
listen.mode=0660
pm=ondemand
pm.max_children=2
POOL
check "/usr/sbin/php-fpm$php_version" -t
check systemctl restart "php$php_version-fpm"
install -d -m0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
cat >/etc/nginx/sites-available/priority.test.conf <<VHOST
server {
    listen 9443 ssl;
    server_name priority.test;
    ssl_certificate /etc/lemper/ssl/priority.test/fullchain.pem;
    ssl_certificate_key /etc/lemper/ssl/priority.test/privkey.pem;
    root /home/uatowner/webapps/priority.test;
    index index.php;
    location = /index.php {
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root/index.php;
        fastcgi_pass unix:/run/php/php$php_version-fpm.uatowner.sock;
    }
}
VHOST
ln -s /etc/nginx/sites-available/priority.test.conf /etc/nginx/sites-enabled/priority.test.conf
check nginx -t
check systemctl restart nginx
check curl --fail --silent --show-error --cacert /etc/lemper/ssl/priority.test/ca.crt \
    --resolve priority.test:9443:127.0.0.1 https://priority.test:9443/
install -d -m0700 /etc/lemper/sites /etc/lemper/site-apps/priority.test/demo
cat >/etc/lemper/sites/priority.test.conf <<META
OWNER_MARKER=lemper-site-v1
DOMAIN=priority.test
OWNER=uatowner
WEBROOT=/home/uatowner/webapps/priority.test
RUNTIME=php@$php_version
DATABASE=app_priority
META
printf 'OWNER_MARKER=lemper-app-v1\nDOMAIN=priority.test\nMOUNT=/demo/nested\nTYPE=laravel\nOWNER=uatowner\n' >/etc/lemper/site-apps/priority.test/demo/nested.conf
lemperctl site show priority.test --json >"$work/site.json"
check python3 - "$work/site.json" <<'PYTHON'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['site_metadata']['owner']=='uatowner'
assert d['apps'][0]['mount']=='/demo/nested'
assert 'pm.max_children=2' in d['fpm_pool']['content']
assert d['ssl']['hostname_matches'] and not d['ssl']['expired']
assert 'priority.test' in d['ssl']['dns_names']
assert 360 <= d['ssl']['days_remaining'] <= 365
PYTHON
check systemctl start mariadb
check mariadb -e 'CREATE DATABASE app_priority; CREATE TABLE app_priority.example (value VARCHAR(30)); INSERT INTO app_priority.example VALUES ("before");'
check lemperctl db backup priority.test --dbfile="$work/sql"
archive=$(find "$work/sql" -name '*.sql.gz' -print -quit)
check test -s "$archive"
check mariadb -e 'DELETE FROM app_priority.example; INSERT INTO app_priority.example VALUES ("changed");'
check lemperctl db restore priority.test "$archive"
check test "$(mariadb -N -e 'SELECT value FROM app_priority.example')" = before
check lemperctl db backup-schedule priority.test --dbfile="$work/scheduled" --dbschedule='0 2 * * *'
check bash -c 'crontab -l | grep -q -- "--dbname=app_priority"'
rejects lemperctl db backup priority.test --dbname=wrongdb --dry-run
rejects lemperctl db backup unowned.test --dry-run
install -d -m0700 /etc/lemper/vhost.d
printf '[priority.test]\nAPP_DB_NAME=app_other\n' >/etc/lemper/vhost.d/priority.test.conf
rejects lemperctl db backup priority.test --dbfile="$work/rejected"
check test ! -e "$work/rejected"
check test "$(mariadb -N -e 'SELECT value FROM app_priority.example')" = before
rm -f /etc/lemper/vhost.d/priority.test.conf
# Verify current repository keys/sources against real signed indexes.
lemper_load_module services/apt/catalog
# os-release is an OS-owned shell data file in this designated test container.
# shellcheck source=/dev/null
. /etc/os-release
export DISTRIB_NAME="$ID" RELEASE_NAME="$VERSION_CODENAME"
for family in pgdg redis; do
    row=$(lemper_apt_repository_spec "$family")
    IFS=$'\t' read -r uri suite _ _ _ <<<"$row"
    printf 'deb %s %s main\n' "$uri" "$suite" >"/etc/apt/sources.list.d/legacy-$family.list"
    check lemper_apt_prepare_repository "$family"
    check test -f "/etc/apt/sources.list.d/legacy-$family.list.lemper-before-key-scope"
    check grep -q 'signed-by=' "/etc/apt/sources.list.d/legacy-$family.list"
done
check apt-get update -qq
# Exercise the official binary download/checksum/architecture path in isolation.
lemper_load_module services/bun/binary
export LEMPER_BUN_PREFIX="$work/bun-test" BUNJS_VERSION=1.4.5
check lemper_bun_install_binary
check "$LEMPER_BUN_PREFIX/usr/local/bin/bun" --version
if [[ "${1:-}" == --build-tls ]]; then
    # This compiles a disposable binary; make install is deliberately absent.
    # shellcheck source=/dev/null
    . "$LEMPER_UAT_CODE_ROOT/scripts/nginx/nginx_ssl_builders.sh"
    export NGINX_BUILD_DIR=/var/tmp/lemper-priority-source NGINX_HTTP3=true
    NGX_CONFIGURE_ARGS=()
    check build_openssl openssl-3.5.9
    curl -fsSL --proto '=https' --retry 3 -o "$work/nginx.tar.gz" https://nginx.org/download/nginx-1.30.7.tar.gz
    tar -xzf "$work/nginx.tar.gz" -C "$NGINX_BUILD_DIR"
    cd "$NGINX_BUILD_DIR/nginx-1.30.7"
    check ./configure --prefix="$work/nginx-local" --user=www-data --group=www-data --with-http_ssl_module "${NGX_CONFIGURE_ARGS[@]}"
    check make -j2
    # The binary path is passed as a positional argument to the fixed child script.
    # shellcheck disable=SC2016
    check bash -c '"$1" -V 2>&1 | grep -q "OpenSSL 3.5.9"' _ "$PWD/objs/nginx"
    # Validate the exact compiled binary with the same FPM and certificates.
    install -d "$work/nginx-local/logs"
    sed '/server {/a\    listen 9443 quic reuseport;\n    http3 on;' /etc/nginx/sites-available/priority.test.conf >"$work/nginx-local/vhost.conf"
    printf 'events {}\nhttp { include /etc/nginx/mime.types; include %s/vhost.conf; }\n' "$work/nginx-local" >"$work/nginx-local/nginx.conf"
    check "$PWD/objs/nginx" -t -c "$work/nginx-local/nginx.conf"
    check systemctl stop nginx
    check "$PWD/objs/nginx" -c "$work/nginx-local/nginx.conf"
    check curl --fail --silent --show-error --cacert /etc/lemper/ssl/priority.test/ca.crt \
        --resolve priority.test:9443:127.0.0.1 https://priority.test:9443/
    check bash -c 'ss -lnu | grep -q ":9443 "'
    check "$PWD/objs/nginx" -s quit -c "$work/nginx-local/nginx.conf"
fi
printf 'Priority UAT passed: %s checks.\n' "$checks"
