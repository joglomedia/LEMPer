#!/usr/bin/env bash
# Destructive acceptance checks for an explicitly marked disposable Podman container.
set -u -o pipefail
if [[ "$(id -u)" -ne 0 || ! -f /run/.containerenv || ! -f /run/lemper-uat/authorized ||
      "$(cat /proc/1/comm)" != systemd ]]; then
    echo "Run only in the designated disposable Podman/systemd UAT container." >&2
    exit 2
fi
source_root="${LEMPER_UAT_SOURCE:-/checkout}"
log_root=/var/log/lemper-uat/cli
install -d -m 0700 "$log_root"
# Functions only; configuration is decoded below without printing credentials.
# shellcheck source=/dev/null
. "$source_root/lib/core/loader.sh"
export DRYRUN=false
config_tmp=$(mktemp)
mysql_options=$(mktemp)
trap 'rm -f "$config_tmp" "$mysql_options"' EXIT
openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
    -pass file:/etc/lemper/.config_key -in /etc/lemper/lemper.conf -out "$config_tmp" || exit 1
uat_user=lemper
root_password=""
while IFS=$'\t' read -r key value; do
    case "$key" in
        MYSQL_ROOT_PASSWORD) root_password="$value" ;;
        LEMPER_USERNAME) uat_user="$value" ;;
    esac
done < <(safe_parse_dotenv "$config_tmp")
root_password="${root_password//\\/\\\\}"
root_password="${root_password//\"/\\\"}"
printf '[client]\nuser=root\npassword="%s"\n' "$root_password" > "$mysql_options"
unset root_password
failures=0
cases=0
function uat_case() {
    local name="$1" rc=0
    shift
    cases=$((cases+1))
    "$@" > "$log_root/$name.log" 2>&1 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (exit %s; log %s)\n' "$name" "$rc" "$log_root/$name.log"
        failures=$((failures+1))
    fi
}
function sql() { mysql --defaults-extra-file="$mysql_options" -Nse "$1"; }
function assert_active() {
    local service
    for service in "$@"; do systemctl is-active --quiet "$service" || return 1; done
}
function php_http() {
    local answer="" _attempt
    # Nginx reload is graceful/asynchronous; wait for the selected vhost generation.
    for _attempt in {1..20}; do
        answer=$(curl --noproxy '*' -fsS --max-time 5 -H 'Host: uat-php.test' http://127.0.0.1/uat-version.php) || true
        [[ "$answer" != 8.4.* ]] || return 0
        sleep 0.2
    done
    echo "PHP response did not become ready." >&2
    return 1
}

function create_php_site() {
    lemperctl site create uat-php.test --type=default --runtime=php@8.4 --runtime-user="$uat_user" \
        --webroot="/home/$uat_user/webapps/uat-php.test" || return 1
    local probe
    probe=$(mktemp) || return 1
    printf '<?php echo PHP_VERSION;' > "$probe"
    install -o "$uat_user" -g "$uat_user" -m 0644 "$probe" "/home/$uat_user/webapps/uat-php.test/uat-version.php"
    local rc=$?
    rm -f "$probe"
    [[ "$rc" -eq 0 ]] && php_http
}
function wordpress_http() {
    [[ -f /etc/nginx/sites-available/lemper.test.conf &&
       -f "/home/$uat_user/webapps/lemper.test/wp-config.php" ]] || return 1
    local status
    status=$(curl --noproxy '*' -sS --max-time 30 -o /dev/null -w '%{http_code}' -H 'Host: lemper.test' http://127.0.0.1/) || return 1
    [[ "$status" == 200 || "$status" == 301 || "$status" == 302 ]]
}
function batch_features() {
    lemperctl site update uat-php.test lemper.test --cors-enable --fastcgi-cache-enable || return 1
    nginx -t || return 1
    grep -q 'cors-uat-php.test.conf' /etc/nginx/sites-available/uat-php.test.conf || return 1
    grep -q 'cors-lemper.test.conf' /etc/nginx/sites-available/lemper.test.conf || return 1
    php_http || return 1
    local headers="" status _attempt
    # PHP can be ready in an old worker while its new header policy is loading.
    for _attempt in {1..30}; do
        headers=$(curl --noproxy '*' -fsS -D - -o /dev/null --max-time 10 -H 'Host: uat-php.test' \
            -H 'Origin: https://client.example.test' http://127.0.0.1/uat-version.php) || true
        if grep -iqE '^Access-Control-Allow-Origin: \*' <<< "$headers" &&
            grep -iqE '^X-FastCGI-Cache: HIT' <<< "$headers"; then break; fi
        sleep 0.2
    done
    grep -iqE '^Access-Control-Allow-Origin: \*' <<< "$headers" || return 1
    grep -iqE '^X-FastCGI-Cache: HIT' <<< "$headers" || return 1
    status=$(curl --noproxy '*' -sS --max-time 10 -o /dev/null -w '%{http_code}' -X OPTIONS \
        -H 'Host: uat-php.test' -H 'Origin: https://client.example.test' http://127.0.0.1/uat-version.php)
    [[ "$status" == 204 ]]
}
function dry_run_unchanged() {
    local before
    before=$(sha256sum /etc/nginx/sites-available/uat-php.test.conf)
    lemperctl site update uat-php.test --cors-disable --dry-run || return 1
    [[ "$(sha256sum /etc/nginx/sites-available/uat-php.test.conf)" == "$before" ]]
}
function referenced_php_guard() {
    local rc=0
    lemperctl stack remove php --php-version 8.4 --yes || rc=$?
    [[ "$rc" -ne 0 ]] && dpkg-query -W php8.4-fpm >/dev/null && php_http
}
function state_cycle() {
    lemperctl site disable uat-php.test || return 1
    [[ ! -e /etc/nginx/sites-enabled/uat-php.test.conf ]] || return 1
    lemperctl site enable uat-php.test || return 1
    php_http
}
function state_repeat() { lemperctl site enable uat-php.test && php_http; }
function tls_cycle() {
    lemperctl site update uat-php.test --ssl-enable || return 1
    local answer="" _attempt
    for _attempt in {1..20}; do
        answer=$(curl --noproxy '*' -fsS --max-time 5 --resolve uat-php.test:443:127.0.0.1 \
            --cacert /etc/lemper/ssl/uat-php.test/ca.crt https://uat-php.test/uat-version.php) || true
        [[ "$answer" != 8.4.* ]] || break
        sleep 0.2
    done
    [[ "$answer" == 8.4.* ]] || return 1
    lemperctl site manage uat-php.test --ssl-disable || return 1
    php_http
}
function retain_then_purge() {
    lemperctl site remove uat-php.test --yes || return 1
    [[ -f "/home/$uat_user/webapps/uat-php.test/uat-version.php" ]] || return 1
    lemperctl site delete uat-php.test --purge --yes || return 1
    [[ ! -d "/home/$uat_user/webapps/uat-php.test" ]]
}
function php_shared_assets() {
    lemperctl stack remove php --php-version 8.4 --force --yes || return 1
    [[ -d /usr/lib/php && -d /var/lib/php ]] || return 1
    dpkg-query -W php8.5-fpm >/dev/null || return 1
    systemctl is-active --quiet php8.5-fpm
}
function eol_policy() {
    local rc=0
    lemperctl stack install php --php-version 8.1 || rc=$?
    [[ "$rc" -ne 0 ]] || return 1
    apt-get install -y -q php8.1-fpm php8.1-cli || return 1
    lemperctl stack status php --php-version 8.1 || return 1
    rc=0
    lemperctl stack remove php --php-version 8.1 --yes || rc=$?
    [[ "$rc" -ne 0 ]] || return 1
    lemperctl stack remove php --php-version 8.1 --force --yes || return 1
    dpkg-query -W php8.5-fpm >/dev/null && systemctl is-active --quiet php8.5-fpm
}
function ssh_key_login() {
    bash "$source_root/scripts/server_security.sh" || return 1
    local known
    known=$(mktemp) || return 1
    awk '{print "[127.0.0.1]:2269 " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub > "$known"
    ssh -F /dev/null -i /tmp/lemper-uat-key -o BatchMode=yes -o IdentitiesOnly=yes \
        -o UserKnownHostsFile="$known" -o StrictHostKeyChecking=yes -p 2269 "$uat_user@127.0.0.1" true
    local rc=$?
    rm -f "$known"
    return "$rc"
}
function backup_verify() {
    local probe=/etc/nginx/includes/uat-backup-probe.conf before
    printf '# Original synthetic UAT configuration\n' > "$probe" || return 1
    before=$(sha256sum "$probe")
    lemperctl backup create --output /var/backups/lemper/uat || return 1
    local archive
    archive=$(find /var/backups/lemper/uat -maxdepth 1 -name 'lemper-config-*.tar.gz' | sort | tail -n 1)
    lemperctl backup verify "$archive" || return 1
    printf '# Modified synthetic UAT configuration\n' > "$probe" || return 1
    lemperctl backup restore --file "$archive" --yes --reload || return 1
    [[ "$(sha256sum "$probe")" == "$before" ]] || return 1
    rm -f "$probe"
    nginx -t && php_http
}
function wordpress_purge() {
    local database="" key value
    while IFS=$'\t' read -r key value; do [[ "$key" != DATABASE ]] || database="$value"; done < <(safe_parse_dotenv /etc/lemper/sites/lemper.test.conf)
    [[ "$database" =~ ^app_[a-z0-9]+$ ]] || return 1
    [[ "$(sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$database';")" == 1 ]] || return 1
    lemperctl site remove lemper.test --purge --yes || return 1
    [[ "$(sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$database';")" == 0 ]]
}
uat_case config_schema lemperctl config check
uat_case provisioned_services assert_active nginx php8.5-fpm mariadb postgresql memcached valkey-server pure-ftpd fail2ban
uat_case database_authentication sql 'SELECT 1;'
uat_case wordpress_http wordpress_http
uat_case php_84_install lemperctl stack install php --php-version 8.4
if [[ "$failures" -gt 0 ]]; then echo "Prerequisite failures: $failures"; exit 1; fi
uat_case php_84_http create_php_site
uat_case php_restart_all lemperctl stack restart php
uat_case php_reload_selected lemperctl stack reload php --php-version 8.4
uat_case php_status_all lemperctl stack status php
uat_case php_update_selected lemperctl stack update php --php-version 8.4
uat_case batch_cors_cache batch_features
uat_case site_dry_run dry_run_unchanged
uat_case referenced_php_removal_guard referenced_php_guard
uat_case site_disable_enable state_cycle
uat_case site_enable_repeat state_repeat
uat_case site_tls_cycle tls_cycle
uat_case ssh_key_authentication ssh_key_login
uat_case backup_real_configuration backup_verify
uat_case site_retain_then_purge retain_then_purge
uat_case php_84_removal_shared_assets php_shared_assets
uat_case installed_eol_management eol_policy
uat_case wordpress_database_purge wordpress_purge
uat_case remaining_services assert_active nginx php8.5-fpm mariadb
printf 'UAT total: %s; passed: %s; failed: %s\n' "$cases" "$((cases-failures))" "$failures"
[[ "$failures" -eq 0 ]]
