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

# Functions-only memcached ASCII client. Values are streamed with dd for binary
# dump compatibility; Bash variables hold only protocol headers and statistics.
function memcached_connect() {
    local address="$1" host port input output
    [[ -n "$address" && ! "$address" =~ [[:cntrl:][:space:]] ]] || return 1
    if [[ "$address" == /* ]]; then
        [[ -S "$address" ]] || return 1
        command -v socat >/dev/null || return 1
        coproc MEMCACHED_CLIENT { socat - "UNIX-CONNECT:$address" 2>/dev/null; }
        memcached_pid="$MEMCACHED_CLIENT_PID"
        exec {memcached_in}>&"${MEMCACHED_CLIENT[1]}"
        exec {memcached_out}<&"${MEMCACHED_CLIENT[0]}"
        input="${MEMCACHED_CLIENT[1]}" output="${MEMCACHED_CLIENT[0]}"
        exec {input}>&- {output}<&-
    else
        host="$address" port=11211
        if [[ "$address" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
            host="${BASH_REMATCH[1]}" port="${BASH_REMATCH[2]}"
        elif [[ "$address" == *:* ]]; then host="${address%:*}" port="${address##*:}"; fi
        [[ "$host" =~ ^[A-Za-z0-9.:_-]+$ && "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port > 0 && 10#$port < 65536)) || return 1
        exec {memcached_in}<>"/dev/tcp/$host/$port" || return 1
        exec {memcached_out}<&"$memcached_in"
    fi
}
function memcached_disconnect() {
    [[ -z "${memcached_in:-}" ]] || exec {memcached_in}>&-
    [[ -z "${memcached_out:-}" ]] || exec {memcached_out}<&-
    [[ -z "${memcached_pid:-}" ]] || {
        kill "$memcached_pid" 2>/dev/null || true
        wait "$memcached_pid" 2>/dev/null || true
    }
    memcached_in="" memcached_out="" memcached_pid=""
}
function memcached_request() {
    local command="$1" line
    printf '%s\r\n' "$command" >&"$memcached_in" || return 1
    while IFS= read -r -t 10 line <&"$memcached_out"; do
        line="${line%$'\r'}"
        [[ "$line" != END ]] || return 0
        [[ "$line" != ERROR && "$line" != CLIENT_ERROR* && "$line" != SERVER_ERROR* ]] || return 1
        printf '%s\n' "$line"
    done
    return 1
}
function memcached_query() (
    local memcached_in="" memcached_out="" memcached_pid=""
    trap memcached_disconnect EXIT
    memcached_connect "$1" && memcached_request "$2"
)
