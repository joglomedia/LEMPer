#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Legacy Tooling Acceptance                                |
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

# A real v3 CLI layout with distro services, not a full v3 installer/storage migration.
set -euo pipefail
umask 077
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-legacy-uat-authorized &&
    $(cat /proc/1/comm) == systemd &&
    $(findmnt -no OPTIONS /legacy-source) == ro,* &&
    $(findmnt -no OPTIONS /release) == ro,* ]] || {
    echo 'An authorized disposable legacy tooling UAT container is required.' >&2
    exit 2
}
logs=/var/log/lemper-legacy-uat
install -d -m 0700 "$logs" /etc/lemper/cli-plugins /run/lemper-legacy-uat
[[ ! -e /opt/lemper/current && ! -e /etc/lemper/lemper.conf ]] || exit 2
archive=/release/lemper-v4.0.0.tar.gz
read -r checksum _ </release/lemper-v4.0.0.tar.gz.sha256
checks=0
function check() {
    local name="$1" status
    shift
    # Run outside a conditional so Bash keeps errexit inside fixture functions.
    set +e
    (set -e; "$@") >"$logs/$name.log" 2>&1
    status=$?
    set -e
    if [[ "$status" == 0 ]]; then
        checks=$((checks + 1))
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"
        exit 1
    fi
}
function prepare_services() {
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y nginx php8.3-fpm php8.3-mysql mariadb-server jq
    systemctl start nginx php8.3-fpm mariadb
    install -d -m 0755 /var/www/legacy-uat.test
    cat >/var/www/legacy-uat.test/index.php <<'PHP'
<?php
$db = new mysqli('localhost', 'legacyuat', 'synthetic-legacy-password', 'legacy_uat');
echo $db->query('SELECT value FROM evidence WHERE id=1')->fetch_row()[0];
PHP
    chmod 0644 /var/www/legacy-uat.test/index.php
    cat >/etc/nginx/sites-available/legacy-uat.test.conf <<'NGINX'
server {
    listen 80;
    server_name legacy-uat.test;
    root /var/www/legacy-uat.test;
    include /etc/nginx/vhost/site_default.conf;
    location / { try_files $uri $uri/ =404; }
    location = /index.php {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
}
NGINX
    install -d -m 0755 /etc/nginx/vhost
    printf '# Synthetic legacy application routing fixture.\n' >/etc/nginx/vhost/site_default.conf
    ln -s /etc/nginx/sites-available/legacy-uat.test.conf /etc/nginx/sites-enabled/legacy-uat.test.conf
    mariadb <<'SQL'
CREATE DATABASE legacy_uat;
CREATE USER 'legacyuat'@'localhost' IDENTIFIED BY 'synthetic-legacy-password';
GRANT SELECT ON legacy_uat.* TO 'legacyuat'@'localhost';
CREATE TABLE legacy_uat.evidence (id INT PRIMARY KEY, value VARCHAR(64));
INSERT INTO legacy_uat.evidence VALUES (1, 'legacy-data-preserved');
SQL
    nginx -t && systemctl reload nginx
    # Legacy mail content is retained; this fixture does not claim live mail migration.
    install -d -m 0700 /var/vmail/legacy-uat.test/alice/Maildir/cur
    printf 'Subject: Synthetic legacy mail\n\nPreserve this message.\n' > /var/vmail/legacy-uat.test/alice/Maildir/cur/fixture
}
function install_legacy_cli() {
    grep -q 'PROG_VERSION="3.6.0"' /legacy-source/bin/lemper-cli.sh
    install -m 0600 /legacy-source/.env.dist /etc/lemper/lemper.conf
    printf '\nINSTALL_WEB_ADMIN=false\n' >>/etc/lemper/lemper.conf
    install -m 0755 /legacy-source/bin/lemper-cli.sh /usr/local/bin/lemper-cli
    ln -s /usr/local/bin/lemper-cli /usr/bin/lemper-cli
    # The legacy updater requires lib-only loading; use its real installer mapping.
    while IFS=: read -r name target; do
        install -m 0755 "/legacy-source/lib/$name.sh" "/etc/lemper/cli-plugins/$target"
    done < <(sed -n "/^lemper-account:lemper-account$/,/^lemper-backup:lemper-backup$/p" /legacy-source/lib/lemper-update.sh)
    ln -s lemper-site-create /etc/lemper/cli-plugins/lemper-site-add
    ln -s lemper-site-update /etc/lemper/cli-plugins/lemper-site-mod
    printf '/legacy-source\n' >/etc/lemper/update-source
    lemper-cli --version | grep -qx 'lemper-cli version 3.6.0'
    lemper-cli site list --json | jq -e 'any(.virtual_hosts[]; .domain == "legacy-uat.test")'
}
function health() {
    local answer="" attempt
    systemctl is-active --quiet nginx php8.3-fpm mariadb
    for ((attempt=0; attempt<30; attempt++)); do
        if answer=$(curl --noproxy '*' -fsS --max-time 5 -H 'Host: legacy-uat.test' http://127.0.0.1/index.php); then
            [[ "$answer" != legacy-data-preserved ]] || break
        fi
        sleep 0.2
    done
    [[ "$answer" == legacy-data-preserved ]]
    [[ $(mariadb -N -B -e 'SELECT value FROM legacy_uat.evidence WHERE id=1') == legacy-data-preserved ]]
}
function snapshot() {
    sha256sum /etc/lemper/lemper.conf /etc/nginx/sites-available/legacy-uat.test.conf \
        /etc/php/8.3/fpm/pool.d/www.conf /var/www/legacy-uat.test/index.php \
        /var/vmail/legacy-uat.test/alice/Maildir/cur/fixture >/run/lemper-legacy-uat/hashes
    systemctl show nginx php8.3-fpm mariadb --property=MainPID --property=ActiveEnterTimestampMonotonic >/run/lemper-legacy-uat/services
    dpkg-query -W -f='${Package} ${Version}\n' | sort >/run/lemper-legacy-uat/packages
}
function preserved() {
    sha256sum -c /run/lemper-legacy-uat/hashes
    systemctl show nginx php8.3-fpm mariadb --property=MainPID --property=ActiveEnterTimestampMonotonic >/run/lemper-legacy-uat/services-after
    cmp /run/lemper-legacy-uat/services /run/lemper-legacy-uat/services-after
    dpkg-query -W -f='${Package} ${Version}\n' | sort >/run/lemper-legacy-uat/packages-after
    cmp /run/lemper-legacy-uat/packages /run/lemper-legacy-uat/packages-after
    health
}
function upgrade() {
    bash /release/get-lemper --version 4.0.0 --archive "$archive" --sha256 "$checksum"
}
function invalid_checksum() {
    if bash /release/get-lemper --version 4.0.0 --archive "$archive" --sha256 "$(printf '%064d' 0)"; then return 1; fi
    [[ ! -e /opt/lemper/current ]]
    lemper-cli --version | grep -qx 'lemper-cli version 3.6.0'
    preserved
}
function aliases() {
    [[ $(lemperctl --version) == 'lemperctl version 4.0.0' &&
       $(lemper-cli --version) == 'lemper-cli version 4.0.0' &&
       $(readlink -f /usr/bin/lemper-cli) == $(readlink -f /usr/local/bin/lemperctl) ]]
    lemperctl site list --json | jq -e 'any(.virtual_hosts[]; .domain == "legacy-uat.test")'
    [[ $(readlink -f /opt/lemper/current) == /opt/lemper/4.0.0 &&
       $(cat /opt/lemper/4.0.0/.release-sha256) == "$checksum" ]]
}
function encrypted_upgrade() {
    openssl rand -hex 32 >/etc/lemper/.config_key
    openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass file:/etc/lemper/.config_key \
        -in /etc/lemper/lemper.conf -out /run/lemper-legacy-uat/encrypted
    install -m 0600 /run/lemper-legacy-uat/encrypted /etc/lemper/lemper.conf
    snapshot
    upgrade
    preserved
    lemperctl site list --json | jq -e 'any(.virtual_hosts[]; .domain == "legacy-uat.test")'
    lemperctl backup create && lemperctl backup verify latest
}
check distro_services_and_synthetic_data prepare_services
check actual_v3_cli_and_site_list install_legacy_cli
check legacy_health health
check snapshot snapshot
check invalid_archive_preserves_v3 invalid_checksum
check exact_archive_upgrade upgrade
check v4_aliases_and_site_list aliases
check packages_configuration_and_data_preserved preserved
check repeat_archive_upgrade upgrade
check repeat_preservation preserved
check configuration_backup lemperctl backup create
check configuration_backup_verify lemperctl backup verify latest
check encrypted_configuration_upgrade encrypted_upgrade
printf 'Legacy tooling UAT: %s checks passed.\n' "$checks"
