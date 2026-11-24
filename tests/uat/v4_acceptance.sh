#!/usr/bin/env bash
# Real v4 bootstrap/install/remove acceptance in a marked disposable Linux container.
set -u -o pipefail
if [[ "$(id -u)" -ne 0 || ! -f /run/.containerenv || ! -f /run/lemper-uat/authorized ||
      "$(cat /proc/1/comm)" != systemd ]]; then
    echo "Run only in the designated disposable Podman/systemd UAT container." >&2
    exit 2
fi
archive="${LEMPER_UAT_ARCHIVE:-/source/dist/v4.0.0/lemper-v4.0.0.tar.gz}"
profile=/checkout/.env
logs=/var/log/lemper-uat/v4
install -d -m 0700 "$logs"
# shellcheck source=tests/uat/helpers.bash
. /run/lemper-uat/helpers.bash
read -r checksum _ < "$archive.sha256"
cases=0 failures=0 config_hash=""

function uat_case() {
    local name="$1" rc=0
    shift
    cases=$((cases+1))
    "$@" > "$logs/$name.log" 2>&1 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (exit %s; log %s)\n' "$name" "$rc" "$logs/$name.log"
        failures=$((failures+1))
        uat_apt_failure_summary "$logs/$name.log"
    fi
}
function bootstrap() {
    bash /checkout/get-lemper --version 4.0.0 --archive "$archive" --sha256 "$checksum" "$@"
}
function invalid_profile() {
    local invalid rc=0
    invalid=$(mktemp) || return 1
    sed 's/^RSA_PUB_KEY=.*/RSA_PUB_KEY=/' "$profile" > "$invalid"
    bootstrap --install --config "$invalid" --minimal --yes || rc=$?
    rm -f "$invalid"
    [[ "$rc" -ne 0 && ! -e /opt/lemper/current && ! -e /etc/lemper/lemper.conf ]]
}
function services() {
    local service
    for service in nginx php8.5-fpm mariadb fail2ban; do
        systemctl is-active --quiet "$service" || {
            printf 'Core service is inactive: %s\n' "$service" >&2
            return 1
        }
    done
    fail2ban-client status sshd >/dev/null || return 1
    fail2ban-client get sshd journalmatch >/dev/null
}
function minimal_selection() {
    local decoded
    decoded=$(mktemp) || return 1
    openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
        -pass file:/etc/lemper/.config_key -in /etc/lemper/lemper.conf -out "$decoded" || { rm -f "$decoded"; return 1; }
    local rc=0 key service
    for key in INSTALL_WEB_ADMIN INSTALL_REDIS INSTALL_POSTGRES INSTALL_FTP_SERVER INSTALL_MAILER; do
        grep -qx "$key=false" "$decoded" || rc=1
    done
    rm -f "$decoded"
    [[ ! -e /usr/share/nginx/html/lcp/dbadmin/index.php ]] || rc=1
    for service in valkey-server postgresql pure-ftpd memcached; do
        systemctl is-active --quiet "$service" && rc=1
    done
    if dpkg-query -W -f='${Status}\n' 'php8.4*' 2>/dev/null | grep -q 'install ok installed'; then rc=1; fi
    [[ "$(stat -c %a /etc/lemper/lemper.conf)" == 600 ]] || rc=1
    return "$rc"
}
function php_http() {
    lemperctl site create v4-uat.test --type=default --runtime=php@8.5 --runtime-user=lemper \
        --webroot=/home/lemper/webapps/v4-uat.test || return 1
    local probe answer="" _attempt
    probe=$(mktemp) || return 1
    printf '<?php echo PHP_VERSION;' > "$probe"
    install -o lemper -g lemper -m 0644 "$probe" /home/lemper/webapps/v4-uat.test/version.php
    rm -f "$probe"
    for _attempt in {1..30}; do
        answer=$(curl --noproxy '*' -fsS --max-time 5 -H 'Host: v4-uat.test' http://127.0.0.1/version.php) || true
        [[ "$answer" != 8.5.* ]] || return 0
        sleep 0.2
    done
    return 1
}
function pinned_release() {
    [[ "$(readlink -f /opt/lemper/current)" == /opt/lemper/4.0.0 ]] &&
        [[ "$(cat /opt/lemper/4.0.0/.release-sha256)" == "$checksum" ]]
}
function repeat_bootstrap() {
    config_hash=$(sha256sum /etc/lemper/lemper.conf)
    bootstrap || return 1
    [[ "$(sha256sum /etc/lemper/lemper.conf)" == "$config_hash" ]] && pinned_release
}
function update_check() {
    bash /opt/lemper/current/update.sh --check || return 1
    [[ "$(sha256sum /etc/lemper/lemper.conf)" == "$config_hash" ]]
}
function aliases() {
    [[ "$(lemperctl --version)" == 'lemperctl version 4.0.0' ]] &&
        [[ "$(lemper-cli --version)" == 'lemper-cli version 4.0.0' ]] &&
        [[ "$(readlink -f /usr/local/bin/lemperctl)" == "$(readlink -f /usr/local/bin/lemper-cli)" ]]
}
function ssh_login() {
    local known rc=0
    known=$(mktemp) || return 1
    awk '{print "[127.0.0.1]:2269 " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub > "$known"
    ssh -F /dev/null -i /run/lemper-uat/key -o BatchMode=yes -o IdentitiesOnly=yes \
        -o UserKnownHostsFile="$known" -o StrictHostKeyChecking=yes -p 2269 lemper@127.0.0.1 true || rc=$?
    rm -f "$known"
    return "$rc"
}
function full_removal() {
    lemperctl stack remove --all --yes || return 1
    [[ ! -e /etc/lemper && ! -L /usr/local/bin/lemperctl && ! -L /usr/local/bin/lemper-cli &&
       ! -L /usr/bin/lemper-cli ]] || return 1
    local service
    for service in nginx php8.5-fpm mariadb fail2ban; do
        systemctl is-active --quiet "$service" && return 1
    done
    if dpkg-query -W -f='${Status}\n' 'php8.5*' 2>/dev/null | grep -q 'install ok installed'; then return 1; fi
    ! getent passwd lemper >/dev/null
}
uat_case invalid_profile_refused invalid_profile
uat_case real_bootstrap_install bootstrap --install --config "$profile" --minimal --yes
[[ "$failures" -eq 0 ]] || { echo "Bootstrap prerequisites failed."; exit 1; }
uat_case config_schema lemperctl config check
uat_case core_services services
uat_case minimal_selection minimal_selection
uat_case php_http php_http
uat_case pinned_release pinned_release
uat_case repeat_bootstrap repeat_bootstrap
uat_case alias_version aliases
uat_case ssh_key_login ssh_login
uat_case legacy_update_check update_check
uat_case site_purge lemperctl site remove v4-uat.test --purge --yes
uat_case full_stack_removal full_removal
printf 'v4 UAT total: %s; passed: %s; failed: %s\n' "$cases" "$((cases-failures))" "$failures"
[[ "$failures" -eq 0 ]]
