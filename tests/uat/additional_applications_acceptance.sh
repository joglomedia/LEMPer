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

# Full-package HTTP checks only in the designated disposable application host.
set -euo pipefail
[[ "$EUID" == 0 && -f /run/lemper-additional-apps-uat-authorized && -f /source/.env.dist ]] || exit 1
for prerequisite in jq nginx php8.3 composer mariadb git curl; do
    command -v "$prerequisite" >/dev/null || {
        printf 'Missing UAT prerequisite: %s\n' "$prerequisite" >&2
        exit 1
    }
done
suffix="${1:-}"
[[ "$suffix" =~ ^[a-z0-9]{0,8}$ ]] || exit 1
work="/var/tmp/lemper-additional-apps$suffix"
owner="appsowner$suffix"
resume="${2:-}"
if [[ "$resume" == --resume ]]; then
    [[ -d "$work" ]] || exit 1
else
    [[ ! -e "$work" ]] || exit 1
    install -d -m0700 "$work"
fi
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module core/deployment
lemper_cli_snapshot /source
code_root=$(readlink -f /opt/lemper/current)
cp -a /etc/nginx "$work/nginx-before"
cp -a "$code_root/etc/nginx/includes" "$code_root/etc/nginx/vhost" /etc/nginx/
for config in nginx.conf charset cors fastcgi_cache fastcgi_https_map http_cloudflare_ips fastcgi_params; do
    install -m0644 "$code_root/etc/nginx/$config" "/etc/nginx/$config"
done
nginx -t
systemctl start nginx mariadb php8.3-fpm
systemctl reload nginx
checks=0
check() {
    local label="$1"
    shift
    [[ ! -f "$work/$label.log" ]] || cp "$work/$label.log" "$work/$label.previous.log"
    if ! "$@" >"$work/$label.log" 2>&1; then
        printf 'FAIL %s\n' "$label" >&2
        return 1
    fi
    checks=$((checks + 1))
    printf 'ok %s\n' "$label"
}
reject() { if "$@"; then return 1; fi; }
if [[ "$resume" == --resume ]]; then check account id "$owner"; else check account lemperctl account "$owner"; fi
ensure_site() {
    local type="$1" domain="$2" project="$3"
    if [[ "$resume" == --resume && -f "/etc/lemper/sites/$domain.conf" ]]; then
        grep -qx "OWNER=$owner" "/etc/lemper/sites/$domain.conf" || return 1
        return 0
    else
        lemperctl site create "$domain" --type="$type" --runtime=php@8.3 --runtime-user="$owner" --install-skeleton
    fi
}
if [[ "$resume" == --resume ]]; then
    for type in snappymail mybb nextcloud ojs slim phplist xenforo; do
        domain="extra-$type$suffix.test"
        project="/home/$owner/webapps/$domain"
        [[ -f "/etc/lemper/sites/$domain.conf" ]] || continue
        grep -qx "OWNER=$owner" "/etc/lemper/sites/$domain.conf" || exit 1
        # Refresh only owned disposable fixtures, then restart once for the batch.
        # shellcheck disable=SC2016 # Fixed child Bash uses positional arguments.
        bash -c '. "$1/lib/core/loader.sh"; lemper_load_module services/site/releases; lemper_load_module services/nginx/release-site; lemper_site_release_render "$2" "$3" "$4" "$5" 8.3' \
            _ "$code_root" "$type" "$domain" "$project" "$owner" >"/etc/nginx/sites-available/$domain.conf"
        if [[ "$type" == nextcloud && -f "$project/.lemper-setup-pending" ]]; then chmod 0644 "$project/.lemper-setup-pending"; fi
    done
    nginx -t
    systemctl restart nginx
fi
phplist_database_fixture() {
    local project="$1" db="uatlist_$suffix"
    [[ ! -f "$work/phplist-db-ready" ]] || return 0
    (
        umask 077
        openssl rand -hex 24 >"$work/phplist-db.pass"
    ) || return 1
    lemperctl db account create --dbuser="$db" --dbpass-file="$work/phplist-db.pass" || return 1
    lemperctl db create --dbname="$db" --dbuser="$db" || return 1
    cp "$project/public_html/lists/config/config.php" "$work/phplist-original.php" || return 1
    local password
    IFS= read -r password <"$work/phplist-db.pass" || return 1
    [[ "$password" =~ ^[a-f0-9]{48}$ && "$db" =~ ^uatlist_[A-Za-z0-9]+$ ]] || return 1
    # shellcheck disable=SC2016 # Literal PHP configuration, not shell expansion.
    {
        printf '<?php\n$database_host="localhost";\n$database_name="%s";\n$database_user="%s";\n$database_password="%s";\n' "$db" "$db" "$password"
        printf '$pageroot="";\n$adminpages="/admin";\n$userview="";\n$TEST=0;\n'
    } >"$project/public_html/lists/config/config.php" || return 1
    chown "$owner:$owner" "$project/public_html/lists/config/config.php" || return 1
    chmod 0600 "$project/public_html/lists/config/config.php" || return 1
    touch "$work/phplist-db-ready"
}
for type in snappymail mybb nextcloud ojs slim phplist; do
    domain="extra-$type$suffix.test"
    project="/home/$owner/webapps/$domain"
    check "$type-install" ensure_site "$type" "$domain" "$project"
    check "$type-config" nginx -t
    check "$type-receipt" test -s "$project/.lemper-release"
    check "$type-ownership" grep -qx 'DATABASE=' "/etc/lemper/sites/$domain.conf"
    check "$type-unix-socket" grep -Fq "unix:/run/php/php8.3-fpm.$owner.sock" "/etc/nginx/sites-available/$domain.conf"
    case "$type" in
        snappymail | nextcloud | slim) route=/ ;;
        mybb) route=/install/index.php ;;
        ojs) route=/index.php/index/install ;;
        phplist) route=/admin/index.php ;;
    esac
    if [[ "$type" == phplist ]]; then check phplist-database-fixture phplist_database_fixture "$project"; fi
    check "$type-http" curl --noproxy '*' --resolve "$domain:80:127.0.0.1" -fsSL "http://$domain$route"
    case "$type" in
        nextcloud)
            check nextcloud-caldav test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/.well-known/caldav)" = 301
            check nextcloud-path-info curl --noproxy '*' -s -H "Host: $domain" http://127.0.0.1/remote.php/dav/
            address=$(hostname -I)
            address="${address%% *}"
            check nextcloud-unconfigured-private test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" "http://$address/")" = 403
            ;;
        ojs)
            check ojs-storage test "$(stat -c %a "$project-files")" = 700
            check ojs-storage-config grep -Fq "files_dir = \"$project-files\"" "$project/config.inc.php"
            ;;
        snappymail)
            check snappymail-private-data test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/data/)" = 404
            version=$(cut -d '|' -f2 "$project/.lemper-release")
            check snappymail-css curl --noproxy '*' -fsS -H "Host: $domain" "http://127.0.0.1/snappymail/v/$version/static/css/app.min.css"
            ;;
        slim)
            check slim-public-root grep -Fq "root \"$project/public\";" "/etc/nginx/sites-available/$domain.conf"
            check slim-users-api curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/users
            ;;
        phplist)
            check phplist-public-root grep -Fq "root \"$project/public_html/lists\";" "/etc/nginx/sites-available/$domain.conf"
            check phplist-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/admin/ui/default/css/all.min.css
            ;;
        mybb) check mybb-installer-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/install/stylesheet.css ;;
    esac
    if [[ "$type" == ojs ]]; then
        check ojs-frontend-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/styles/build.css
        check ojs-library-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/lib/pkp/styles/fontawesome/fontawesome.css
    fi
done
domain="extra-xenforo$suffix.test"
check xenforo-reject-license-download reject lemperctl site create "$domain" --type=xenforo --runtime=php@8.3 --runtime-user="$owner" --install-skeleton
if [[ "$resume" == --resume && -f "/etc/lemper/sites/$domain.conf" ]]; then
    check xenforo-manual-vhost grep -qx "OWNER=$owner" "/etc/lemper/sites/$domain.conf"
else
    check xenforo-manual-vhost lemperctl site create "$domain" --type=xenforo --runtime=php@8.3 --runtime-user="$owner"
fi
check xenforo-unix-socket grep -Fq "unix:/run/php/php8.3-fpm.$owner.sock" "/etc/nginx/sites-available/$domain.conf"
check xenforo-config nginx -t
# Routing probes are synthetic; licensed XenForo code is not distributed here.
nc_project="/home/$owner/webapps/extra-nextcloud$suffix.test"
mybb_project="/home/$owner/webapps/extra-mybb$suffix.test"
xf_project="/home/$owner/webapps/$domain"
cp -p "$nc_project/remote.php" "$work/nextcloud-remote.before"
cp -p "$mybb_project/showthread.php" "$work/mybb-showthread.before"
restore_routing() {
    cp -p "$work/nextcloud-remote.before" "$nc_project/remote.php"
    cp -p "$work/mybb-showthread.before" "$mybb_project/showthread.php"
    systemctl restart php8.3-fpm
}
trap restore_routing EXIT
for probe in "$nc_project/remote.php" "$mybb_project/showthread.php" "$xf_project/index.php"; do
    cat >"$probe" <<'PHP'
<?php
header('Content-Type: application/json');
echo json_encode(['method'=>$_SERVER['REQUEST_METHOD'],'uri'=>$_SERVER['REQUEST_URI'],
 'path'=>$_SERVER['PATH_INFO']??'', 'rawquery'=>$_SERVER['QUERY_STRING'], 'query'=>$_GET, 'body'=>file_get_contents('php://input')]);
PHP
    chown "$owner:$owner" "$probe"
    chmod 0644 "$probe"
done
systemctl restart php8.3-fpm
check nextcloud-dav-routing curl --noproxy '*' --resolve "extra-nextcloud$suffix.test:80:127.0.0.1" -fsS -X PROPFIND \
    --data '<probe/>' "http://extra-nextcloud$suffix.test/remote.php/dav/files/test?keep=1"
check nextcloud-dav-method jq -e '.method=="PROPFIND" and .path=="/dav/files/test" and .query.keep=="1" and .body=="<probe/>"' "$work/nextcloud-dav-routing.log"
check mybb-friendly-routing curl --noproxy '*' --resolve "extra-mybb$suffix.test:80:127.0.0.1" -fsS "http://extra-mybb$suffix.test/thread-123.html?keep=1"
check mybb-friendly-query jq -e '.query.tid=="123" and .query.keep=="1"' "$work/mybb-friendly-routing.log"
check xenforo-friendly-routing curl --noproxy '*' --resolve "$domain:80:127.0.0.1" -fsS -X POST --data 'probe-body' "http://$domain/threads/example.1/?keep=1"
check xenforo-friendly-query jq -e '.method=="POST" and (.rawquery|startswith("/threads/example.1/")) and .query.keep=="1" and .body=="probe-body"' "$work/xenforo-friendly-routing.log"
install -d -o "$owner" -g "$owner" -m0700 "$xf_project/internal_data" "$xf_project/src"
printf 'private-probe' >"$xf_project/internal_data/probe.conf"
printf 'private-probe' >"$xf_project/src/probe.conf"
check xenforo-private-data test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/internal_data/probe.conf)" = 404
check xenforo-private-source test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/src/probe.conf)" = 404
check ojs-config-private test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: extra-ojs$suffix.test" http://127.0.0.1/config.inc.php)" = 404
check phplist-config-private test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: extra-phplist$suffix.test" http://127.0.0.1/config/config.php)" = 404
restore_routing
trap - EXIT
printf 'Additional application UAT passed: %s checks\n' "$checks"
