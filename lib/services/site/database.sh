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

# Resolve only a recorded ownership mapping; never guess a DB name or read .env.
function lemper_site_database_for_domain() {
    local domain="$1" database key value metadata="${LEMPER_SITE_METADATA_ROOT:-/etc/lemper/vhost.d}"
    is_valid_domain "$domain" || {
        error "Invalid database site domain."
        return 1
    }
    lemper_load_module runtime/site/state || return 1
    lemper_site_read_state "$domain" || return 1
    database="$LEMPER_SITE_DATABASE"
    [[ -n "$database" ]] || {
        error "Site has no recorded database; use --dbname or reconcile site ownership."
        return 1
    }
    if [[ -f "$metadata/$domain.conf" ]]; then
        [[ ! -L "$metadata/$domain.conf" ]] || return 1
        while IFS=$'\t' read -r key value; do
            if [[ "$key" == APP_DB_NAME && -n "$value" && "$value" != "$database" ]]; then
                error "Site/database metadata disagree; reconcile ownership before using the domain shortcut."
                return 1
            fi
        done < <(safe_parse_dotenv "$metadata/$domain.conf")
    fi
    printf '%s\n' "$database"
}
