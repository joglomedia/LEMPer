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

# Native site creation only in a designated disposable Nginx/PHP host.
set -euo pipefail
[[ "$EUID" == 0 && -f /run/lemper-a3-uat-authorized && -f /source/.env.dist ]] || {
    echo 'Designated disposable application-capability UAT container required.' >&2
    exit 1
}
suffix="${1:-}"
[[ "$suffix" =~ ^[a-z0-9]{0,8}$ ]] || exit 1
work="/var/tmp/lemper-a3-uat$suffix"
owner="a3owner$suffix"
[[ ! -e "$work" ]] || {
    echo 'Use a fresh UAT workspace.' >&2
    exit 1
}
install -d -m0700 "$work"
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module core/deployment
lemper_cli_snapshot /source
code_root=$(readlink -f /opt/lemper/current)
# Keep subsequent helper/template reads on the same immutable CLI snapshot.
# shellcheck source=/dev/null
. "$code_root/lib/core/loader.sh"
# This host starts from distro Nginx. Install tracked LEMPer templates used by
# the real create path; keep the prior disposable configuration for review.
cp -a /etc/nginx "$work/nginx-before"
cp -a "$code_root/etc/nginx/includes" "$code_root/etc/nginx/vhost" /etc/nginx/
for config in nginx.conf charset cors fastcgi_cache fastcgi_https_map http_cloudflare_ips fastcgi_params; do
    install -m0644 "$code_root/etc/nginx/$config" "/etc/nginx/$config"
done
install -d -o www-data -g www-data -m0750 /var/cache/nginx/fastcgi_cache
nginx -t
systemctl reload nginx
checks=0
check() {
    local label="$1"
    shift
    if ! "$@" >"$work/$label.log" 2>&1; then
        printf 'FAIL %s\n' "$label" >&2
        return 1
    fi
    checks=$((checks + 1))
    printf 'ok %s\n' "$label"
}
reject() { if "$@"; then return 1; fi; }
check account lemperctl account "$owner"
# Nginx requires search access to the test user's home; keep listings private.
chmod o+x "/home/$owner"
for type in mautic roundcube sendy; do
    domain="a3-$type$suffix.test"
    if [[ "$type" == sendy ]]; then
        check "$type-rejected" reject lemperctl site create "$domain" --type="$type" --runtime=php@8.3 \
            --runtime-user="$owner" --webroot="/home/$owner/webapps/$domain" --install-skeleton
    fi
    check "$type-no-vhost" test ! -e "/etc/nginx/sites-available/$domain.conf"
    check "$type-no-project" test ! -e "/home/$owner/webapps/$domain"
    check "$type-manual-vhost" lemperctl site create "$domain" --type="$type" --runtime=php@8.3 \
        --runtime-user="$owner" --webroot="/home/$owner/webapps/$domain"
    check "$type-config-valid" nginx -t
    # Verify the manual vhost actually serves through its configured PHP pool.
    printf '<?php echo "manual-site";' >"/home/$owner/webapps/$domain/probe.php"
    chown "$owner:$owner" "/home/$owner/webapps/$domain/probe.php"
    sleep 0.2
    response=$(curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/probe.php)
    check "$type-http" test "$response" = manual-site
    check "$type-no-app-credentials" test ! -e "/etc/lemper/vhost.d/$domain.conf"
done
for type in mautic roundcube; do
    domain="a3-installed-$type$suffix.test"
    project="/home/$owner/webapps/$domain"
    check "$type-release-install" lemperctl site create "$domain" --type="$type" --runtime=php@8.3 \
        --runtime-user="$owner" --webroot="$project" --install-skeleton
    check "$type-release-config" nginx -t
    check "$type-release-receipt" test -s "$project/.lemper-release"
    check "$type-release-private-receipt" test "$(stat -c %a "$project/.lemper-release")" = 600
    check "$type-no-fictional-database" grep -qx 'DATABASE=' "/etc/lemper/sites/$domain.conf"
    if [[ "$type" == roundcube ]]; then
        check roundcube-public-root grep -Fq "root \"$project/public_html\";" "/etc/nginx/sites-available/$domain.conf"
        check roundcube-installer-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/static.php/installer/styles.css
        route=/installer.php
    else
        check mautic-installer-css curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/media/css/app.css
        check mautic-installer-favicon curl --noproxy '*' -fsS -H "Host: $domain" http://127.0.0.1/app/assets/images/favicon.ico
        route=/installer
    fi
    check "$type-upstream-installer" curl --noproxy '*' -fsSL -H "Host: $domain" "http://127.0.0.1$route"
    check "$type-installer-content" grep -qi "$type" "$work/$type-upstream-installer.log"
    address=$(hostname -I)
    address="${address%% *}"
    check "$type-public-setup-blocked" test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" "http://$address$route")" = 403
    printf 'private-config' >"$project/config/probe.conf"
    check "$type-private-permissions" test "$(stat -c %a "$project/config")" = 700
    check "$type-private-config" test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/config/probe.conf)" = 404
    probe_root="$project"
    [[ "$type" != roundcube ]] || probe_root="$project/public_html"
    printf '<?php echo "must-not-execute";' >"$probe_root/probe.php"
    chown "$owner:$owner" "$probe_root/probe.php"
    check "$type-arbitrary-php" test "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' -H "Host: $domain" http://127.0.0.1/probe.php)" = 404
    printf 'preserve-this-config' >"$project/config/lemper-repeat.fixture"
    chown "$owner:$owner" "$project/config/lemper-repeat.fixture"
    # shellcheck disable=SC2016 # Fixed child Bash program receives positional arguments.
    check "$type-release-repeat" bash -c '
        . "$1/lib/core/loader.sh"
        lemper_load_module services/site/releases
        lemper_site_release_install "$2" "$3" "$4" 8.3
    ' _ "$code_root" "$type" "$project" "$owner"
    check "$type-config-preserved" test "$(cat "$project/config/lemper-repeat.fixture")" = preserve-this-config
done
check codeigniter-install lemperctl site create "a3-codeigniter$suffix.test" --type=codeigniter \
    --runtime=php@8.3 --runtime-user="$owner" --install-skeleton --webroot="/home/$owner/webapps/a3-codeigniter$suffix.test"
check codeigniter-project test -s "/home/$owner/webapps/a3-codeigniter$suffix.test/spark"
check codeigniter-entry test -s "/home/$owner/webapps/a3-codeigniter$suffix.test/public/index.php"
check codeigniter-dependencies test -s "/home/$owner/webapps/a3-codeigniter$suffix.test/vendor/autoload.php"
check codeigniter-ownership test -f "/etc/lemper/sites/a3-codeigniter$suffix.test.conf"
check codeigniter-config nginx -t
sleep 0.2
codeigniter_http() {
    local response
    response=$(curl --noproxy '*' -fsS -H "Host: a3-codeigniter$suffix.test" http://127.0.0.1/) || return 1
    [[ "$response" == *'Welcome to CodeIgniter'* ]]
}
check codeigniter-http codeigniter_http
printf 'Application capability UAT passed: %s checks\n' "$checks"
