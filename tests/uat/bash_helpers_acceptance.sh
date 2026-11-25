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

# Native bundled-helper acceptance in a designated disposable Linux container.
set -euo pipefail
[[ "$EUID" == 0 && -f /run/.containerenv && -f /run/lemper-bash-helpers-uat-authorized && "$(cat /proc/1/comm)" == systemd ]] || exit 2
[[ "$(findmnt -no OPTIONS /source)" == ro,* ]] || exit 2
work=/var/tmp/lemper-bash-helpers-uat
install -d -m0700 "$work"
install -d -m0755 "$work/scripts"
cp -a /source/share/memcached/scripts/. "$work/scripts/"
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
install -d -m0755 /usr/local/lib/lemper/memcached
cp "$work/scripts/"* /usr/local/lib/lemper/memcached/
chmod 0755 /usr/local/lib/lemper/memcached/{start-memcached,systemd-memcached-wrapper,memcached-tool,damemtop}
install -d -o nobody -g nogroup -m0700 /run/lemper-bash-cache
printf '%s\n' '-d' '-m 8' '-u nobody' '-U 0' '-s /run/lemper-bash-cache/cache.sock' '-P /run/ignored-cache.pid' >/etc/memcached_bashuat.conf
cp /source/etc/systemd/memcached@.service /etc/systemd/system/memcached@bashuat.service
systemctl daemon-reload
pidfile=/run/lemper-bash-cache-tcp.pid
cleanup() {
    systemctl stop memcached@bashuat.service || true
    [[ ! -f "$pidfile" ]] || kill "$(cat "$pidfile")" 2>/dev/null || true
}
trap cleanup EXIT
check cache-systemd-start systemctl start memcached@bashuat.service
systemd_pid() {
    local pid
    pid=$(systemctl show -p MainPID --value memcached@bashuat.service)
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$(cat "/proc/$pid/comm")" == memcached ]]
    sleep 1
    [[ "$(systemctl show -p MainPID --value memcached@bashuat.service)" == "$pid" ]]
}
check foreground-mainpid systemd_pid
for ((attempt = 0; attempt < 30; attempt++)); do
    [[ -S /run/lemper-bash-cache/cache.sock ]] && break
    sleep .1
done
tool="$work/scripts/memcached-tool"
check unix-stats bash "$tool" /run/lemper-bash-cache/cache.sock stats
check unix-settings bash "$tool" /run/lemper-bash-cache/cache.sock settings
check slab-display bash "$tool" /run/lemper-bash-cache/cache.sock display
# Binary values include NUL and embedded CRLF. Dump must preserve exact bytes.
binary_dump() {
    local attempt
    printf 'set binary 7 0 7\r\na\0b\r\ncd\r\nquit\r\n' | socat - UNIX-CONNECT:/run/lemper-bash-cache/cache.sock >"$work/set-response"
    grep -q STORED "$work/set-response"
    printf 'add binary 7 0 7\r\na\0b\r\ncd\r\n' >"$work/expected"
    # Newly inserted keys may remain in the hot LRU, which cachedump omits.
    for ((attempt = 0; attempt < 30; attempt++)); do
        bash "$tool" /run/lemper-bash-cache/cache.sock dump >"$work/dump" || return 1
        cmp -s "$work/dump" "$work/expected" && return 0
        sleep .2
    done
    return 1
}
check binary-cache-dump binary_dump
cat >"$work/top.yaml" <<'YAML'
delay: 1
mode: t
top_mode:
    sort_column: hostname
    sort_order: asc
    columns:
        - hostname
        - all_version
        - all_fill_rate
        - hit_rate
servers:
    - /run/lemper-bash-cache/cache.sock
YAML
check cluster-sample bash "$work/scripts/damemtop" --config "$work/top.yaml" --once
grep -q '/run/lemper-bash-cache/cache.sock' "$work/cluster-sample.log"
printf '%s\n' '-m 8' '-u nobody' '-U 0' '-l 127.0.0.1' '-p 11219' >"$work/tcp.conf"
check cache-compatibility-start bash "$work/scripts/start-memcached" "$work/tcp.conf" "$pidfile"
for ((attempt = 0; attempt < 30; attempt++)); do
    if bash "$tool" 127.0.0.1:11219 stats >"$work/tcp-ready" 2>&1; then break; fi
    sleep .1
done
check tcp-stats bash "$tool" 127.0.0.1:11219 stats
before_pid=$(cat "$pidfile")
check repeat-start bash "$work/scripts/start-memcached" "$work/tcp.conf" "$pidfile"
[[ "$(cat "$pidfile")" == "$before_pid" ]]
install -d -m0700 "$work/pure/etc/pure-ftpd/conf" "$work/pure/etc/pure-ftpd/auth"
printf 2 >"$work/pure/etc/pure-ftpd/conf/TLS"
printf yes >"$work/pure/etc/pure-ftpd/conf/NoAnonymous"
printf '30000 40000' >"$work/pure/etc/pure-ftpd/conf/PassivePortRange"
check pure-wrapper-options env LEMPER_PUREFTPD_ROOT="$work/pure" bash /source/sbin/pure-ftpd-wrapper --show-options
grep -Fq -- '-Y 2' "$work/pure-wrapper-options.log"
grep -Fq -- '-p 30000:40000' "$work/pure-wrapper-options.log"
printf '%s native bundled-helper checks passed.\n' "$count"
