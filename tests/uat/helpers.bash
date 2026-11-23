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

# Literal fixture rewrites; failure on missing/duplicate keys catches stale UAT.
function uat_profile_set() {
    local file="$1" key="$2" value="$3" work
    [[ "$key" =~ ^[A-Z_]+$ && ! "$value" =~ [[:cntrl:]] && -f "$file" && ! -L "$file" ]] || return 1
    [[ "$(awk -v key="$key" 'index($0,key "=")==1 {n++} END {print n+0}' "$file")" == 1 ]] || return 1
    work=$(mktemp "${file}.XXXXXXXX") || return 1
    if ! LEMPER_UAT_VALUE="$value" awk -v key="$key" '
        index($0,key "=")==1 {print key "=" ENVIRON["LEMPER_UAT_VALUE"]; next}
        {print}
    ' "$file" >"$work"; then
        rm -f -- "$work"
        return 1
    fi
    cat "$work" >"$file"
    local status=$?
    rm -f -- "$work"
    return "$status"
}
