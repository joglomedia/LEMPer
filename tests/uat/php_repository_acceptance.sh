#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer PHP Repository Acceptance Tests                                  |
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

# Real maintained-PHP repository UAT in a designated disposable systemd host.
set -euo pipefail
[[ "$EUID" == 0 && -f /run/.containerenv && -f /run/lemper-php-repository-uat-authorized && "$(cat /proc/1/comm)" == systemd ]] || exit 2
[[ "$(findmnt -no OPTIONS /source)" == ro,* ]] || exit 2
work=/var/tmp/lemper-php-repository-uat
install -d -m0700 "$work"
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
DISTRIB_NAME=$(get_distrib_name) RELEASE_NAME=$(get_release_name)
lemper_load_module services/php/repository
count=0
check() {
    local name="$1"
    shift
    if "$@" >"$work/$name.log" 2>&1; then
        count=$((count + 1))
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$work" "$name"
        exit 1
    fi
}
check archive-prepare lemper_php_prepare_repository
check managed-keyring-file test -s /usr/share/keyrings/debsuryorg-archive-keyring.gpg
check pinned-key lemper_php_repository_key_valid /usr/share/keyrings/debsuryorg-archive-keyring.gpg
check signed-release gpgv --keyring /usr/share/keyrings/debsuryorg-archive-keyring.gpg \
    "/var/lib/apt/lists/packages.sury.org_php_dists_${RELEASE_NAME}_InRelease"
check versioned-php-packages apt-get install -q -y php8.4-cli php8.4-fpm php8.5-cli php8.5-fpm
check php84-cli php8.4 -v
check php85-cli php8.5 -v
check php84-fpm-config php-fpm8.4 -t
check php85-fpm-config php-fpm8.5 -t
check fpm-start systemctl start php8.4-fpm php8.5-fpm
check fpm-active systemctl is-active --quiet php8.4-fpm php8.5-fpm
before=$(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -exec sha256sum {} + | sort)
check repository-repeat lemper_php_prepare_repository
[[ "$before" == "$(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -exec sha256sum {} + | sort)" ]]
check scoped-only-bootstrap test ! -e /etc/apt/trusted.gpg.d/debsuryorg-archive.gpg
lemper_load_module core/deployment
check installed-cli lemper_cli_snapshot /source
install -m0600 /source/.env.dist /etc/lemper/lemper.conf
# Use one inherited PPA entry to exercise the actual installed updater's migration.
printf 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu %s main\n' "$RELEASE_NAME" >/etc/apt/sources.list.d/php.list
check cli-php-repository-migration lemperctl update php --php-version=8.4 --yes
check canonical-source grep -Fx "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $RELEASE_NAME main" /etc/apt/sources.list.d/php.list
check source-backup test -f /etc/apt/sources.list.d/php.list.lemper-before-php-repository
check cli-php-status lemperctl stack status php --php-version=8.5
printf '%s PHP repository acceptance checks passed on %s/%s.\n' "$count" "$DISTRIB_NAME" "$RELEASE_NAME"
