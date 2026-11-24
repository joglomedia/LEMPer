#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable HTTP-01 Renewal Bridge                                |
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


# Test-only pause/resume lets an operator mirror public webroot challenge files.
# Certbot renew is always noninteractive, so --debug-challenges cannot pause it.
set -euo pipefail
umask 077
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-http01-uat-authorized &&
    $(cat /proc/1/comm) == systemd ]] || exit 2
command -v inotifywait >/dev/null || { echo 'Install inotify-tools in this fixture.' >&2; exit 2; }
directory=/var/www/lemper-http01/.well-known/acme-challenge
work=$(mktemp -d /run/http01-renewal-XXXXXXXX)
logs=/var/log/lemper-http01-uat
install -d -m 0755 "$directory"
watcher="" certbot_pid=""
function cleanup() {
    if [[ -n "$certbot_pid" ]] && kill -0 "$certbot_pid" 2>/dev/null; then
        kill -CONT "$certbot_pid" 2>/dev/null || true
        kill -TERM "$certbot_pid" 2>/dev/null || true
        wait "$certbot_pid" 2>/dev/null || true
    fi
    if [[ -n "$watcher" ]]; then
        kill "$watcher" 2>/dev/null || true
        wait "$watcher" 2>/dev/null || true
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
mkfifo "$work/events"
exec 3<>"$work/events"
inotifywait --monitor --event close_write --format '%f' "$directory" \
    >"$work/events" 2>"$logs/renewal-watcher.log" &
watcher=$!
for ((attempt=0; attempt<50; attempt++)); do
    grep -q 'Watches established' "$logs/renewal-watcher.log" && break
    kill -0 "$watcher" 2>/dev/null || { echo 'Challenge watcher failed.' >&2; exit 1; }
    sleep 0.1
done
grep -q 'Watches established' "$logs/renewal-watcher.log"
/opt/certbot/bin/certbot renew --cert-name lemper.eu.org --dry-run --run-deploy-hooks \
    --no-random-sleep-on-renew >"$logs/renewal.log" 2>&1 &
certbot_pid=$!
while kill -0 "$certbot_pid" 2>/dev/null; do
    if IFS= read -r -t 0.2 token <&3; then
        [[ "$token" =~ ^[a-zA-Z0-9_-]{43}$ && -f "$directory/$token" ]] || exit 1
        kill -STOP "$certbot_pid"
        printf '%s\n' "$token" >/run/http01-renewal-token
        printf 'PUBLIC_CHALLENGE_READY_FOR_COPY\n'
        deadline=$((SECONDS + 180))
        until [[ -f /run/http01-renewal-continue ]]; do
            ((SECONDS < deadline)) || { echo 'Challenge bridge timed out.' >&2; exit 1; }
            sleep 0.2
        done
        rm -- /run/http01-renewal-continue
        kill -CONT "$certbot_pid"
    fi
done
if wait "$certbot_pid"; then
    certbot_pid=""
    touch /run/http01-renewal-succeeded
    printf 'REAL_WEBROOT_RENEWAL_AND_DEPLOY_HOOK_SUCCEEDED\n'
else
    echo 'Renewal failed; inspect the private fixture log.' >&2
    exit 1
fi
