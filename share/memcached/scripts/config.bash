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

# Bash adaptation of Debian's parsers by Jay Bonci and Christos Trochalakis.
# Configuration remains literal data; no eval, shell expansion or command strings.
function memcached_words() {
    local line="$1" character quote="" word="" escaped=false present=false index
    words=()
    for ((index = 0; index < ${#line}; index++)); do
        character="${line:index:1}"
        if [[ "$escaped" == true ]]; then
            word+="$character"
            escaped=false
            present=true
            continue
        fi
        if [[ "$character" == \\ && "$quote" != "'" ]]; then
            escaped=true
            continue
        fi
        if [[ -n "$quote" ]]; then
            if [[ "$character" == "$quote" ]]; then quote=""; else word+="$character"; fi
            present=true
        elif [[ "$character" == '"' || "$character" == "'" ]]; then
            quote="$character"
            present=true
        elif [[ "$character" == \# ]]; then
            break
        elif [[ "$character" == ' ' || "$character" == $'\t' ]]; then
            [[ "$present" != true ]] || words+=("$word")
            word="" present=false
        else
            word+="$character"
            present=true
        fi
    done
    [[ -z "$quote" && "$escaped" == false ]] || return 1
    [[ "$present" != true ]] || words+=("$word")
    return 0
}
# shellcheck disable=SC2034 # parameters, words and logfile are parser outputs.
function memcached_config() {
    local file="$1" line word user=false index
    words=() parameters=() logfile=/dev/null
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ ! "${line//$'\t'/}" =~ [[:cntrl:]] ]] || return 1
        memcached_words "$line" || return 1
        [[ ${#words[@]} != 0 ]] || continue
        case "${words[0]}" in
            logfile)
                [[ ${#words[@]} == 2 && "${words[1]}" == /* ]] || return 1
                logfile="${words[1]}"
                continue
                ;;
            -d | -h) continue ;;
            -P)
                [[ ${#words[@]} == 2 ]] || return 1
                continue
                ;;
            -*) ;;
            *) return 1 ;;
        esac
        for ((index = 0; index < ${#words[@]}; index++)); do
            word="${words[index]}"
            if [[ "$word" == -u ]]; then
                [[ -n "${words[index + 1]:-}" ]] || return 1
                user=true
            fi
            parameters+=("$word")
        done
    done <"$file"
    # Installed LEMPer configs supply -u. The safe fallback is the service user.
    [[ "$user" == true ]] || parameters+=(-u memcache)
}
