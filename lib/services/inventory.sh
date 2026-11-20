#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Component Inventory                                             |
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

function lemper_component_present() {
    local service="$1" php="${2:-}" _installer _remover units _key family binary package state executable
    read -r _installer _remover units _key family < <(lemper_component_spec "$service")
    binary="${units%%,*}"
    case "$service" in
        php) binary="php$php"; family="php$php" ;;
        postgres|postgresql) binary=psql ;;
        mariadb|mysql) binary=mariadb ;;
        bun) binary=bun ;;
        certbot) binary=certbot ;;
        tools) binary=lemperctl ;;
        imagemagick)
            command -v magick >/dev/null 2>&1 && return 0
            binary=convert ;;
    esac
    executable=$(command -v "$binary") || executable=""
    [[ -n "$executable" && -x "$executable" ]] && return 0
    [[ "$family" != - ]] || return 1
    while IFS=$'\t' read -r package state; do
        [[ "$state" == 'install ok installed' ]] || continue
        package="${package%%:*}"
        case "$package" in "$family"|"$family"-*) return 0 ;; esac
    done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' "$family*" 2>/dev/null)
    return 1
}
