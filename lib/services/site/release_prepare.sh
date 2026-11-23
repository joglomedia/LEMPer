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

function lemper_site_release_prepare() (
    local stage="$1" project="$2" domain="$3" target="$1/config.inc.php" work
    [[ "$project" =~ ^/[A-Za-z0-9_./\ -]+$ && "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ -f "$stage/config.TEMPLATE.inc.php" && ! -L "$stage/config.TEMPLATE.inc.php" && ! -L "$target" ]] || return 1
    if [[ -e "$target" ]] && grep -q '[^[:space:]]' "$target"; then
        cmp -s "$target" "$stage/config.TEMPLATE.inc.php" || return 1
    fi
    work=$(mktemp "$stage/.ojs-config-XXXXXXXX") || return 1
    trap 'rm -f -- "$work"' EXIT
    # ENVIRON preserves literal values; awk -v would decode backslashes.
    LEMPER_OJS_PROJECT="$project" LEMPER_OJS_DOMAIN="$domain" awk '
        /^files_dir[[:space:]]*=/ {print "files_dir = \"" ENVIRON["LEMPER_OJS_PROJECT"] "-files\""; files++; next}
        /^base_url[[:space:]]*=/ {print "base_url = \"http://" ENVIRON["LEMPER_OJS_DOMAIN"] "\""; urls++; next}
        {print}
        END {if (files != 1 || urls != 1) exit 1}
    ' "$stage/config.TEMPLATE.inc.php" >"$work" || return 1
    chmod 0600 "$work" && mv -T -- "$work" "$target"
)
