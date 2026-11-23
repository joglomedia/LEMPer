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

# Native my_print_defaults remains authoritative for option decoding.
function lemper_mariadb_option_trusted() {
    local path="$1" owner mode
    [[ "$path" == /* ]] || path="$PWD/$path"
    while [[ "$path" != / ]]; do
        owner=$(stat -Lc %u -- "$path") && mode=$(stat -Lc %a -- "$path") || return 1
        [[ "$owner" == "$EUID" ]] || return 1
        if (((8#$mode & 0022) != 0)); then
            [[ "$path" == /tmp || "$path" == /var/tmp ]] && (((8#$mode & 01000) != 0)) || return 1
        fi
        path=$(dirname -- "$path")
    done
}
function lemper_mariadb_option_visit() {
    local path="$1" line directive name child selected=false value index character
    lemper_mariadb_option_trusted "$path" || return 1
    path=$(realpath -e -- "$path") || return 1
    lemper_mariadb_option_trusted "$path" || return 1
    [[ -f "$path" && -z "${option_active[$path]:-}" && ${#option_visited[@]} -lt 128 ]] || return 1
    [[ -z "${option_visited[$path]:-}" ]] || return 0
    option_active["$path"]=1 option_visited["$path"]=1
    # Bash read discards NUL, so check binary content first.
    cmp -s -- "$path" <(LC_ALL=C tr -d '\000' <"$path") || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" && "$line" != \#* && "$line" != \;* ]] || continue
        if [[ "$line" =~ ^!(include|includedir)[[:space:]]+(.+)$ ]]; then
            directive="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}"
            name="${name%"${name##*[![:space:]]}"}"
            if [[ "$directive" == includedir ]]; then
                lemper_mariadb_option_trusted "$name" || return 1
                [[ -d "$name" ]] || return 1
                for child in "$name"/*.cnf; do
                    [[ -e "$child" || -L "$child" ]] || continue
                    lemper_mariadb_option_visit "$child" || return 1
                done
            else
                lemper_mariadb_option_visit "$name" || return 1
            fi
            continue
        fi
        if [[ "$line" == \[* ]]; then
            selected=false
            [[ "$line" != '[mariabackup]'* ]] || selected=true
            continue
        fi
        [[ "$selected" == true ]] || continue
        value="${line#*=}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ ! "$value" =~ [[:cntrl:]] ]] || return 1
        for ((index = 0; index < ${#value}; index++)); do
            character="${value:index:1}"
            if [[ "$character" == \\ && $((index + 1)) -lt ${#value} ]]; then
                [[ "${value:index+1:1}" != [nrtb0] ]] || return 1
                index=$((index + 1))
            fi
        done
    done <"$path"
    unset 'option_active[$path]'
}
function lemper_mariadb_option_guard() {
    local -A option_active=() option_visited=()
    lemper_mariadb_option_visit "$1" 2>/dev/null || {
        error "Unsafe or unsupported legacy MariaDB options (values redacted)."
        return 1
    }
}
