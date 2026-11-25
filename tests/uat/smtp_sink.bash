#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Private SMTP Acceptance Fixture                                 |
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

# A transcript sink for fixture-only alerts; it never forwards messages.
function uat_smtp_session() {
    local directory="$1" line message complete
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    printf '220 lemper-uat-backup ESMTP\r\n'
    while IFS= read -r line; do
        line="${line%$'\r'}"
        case "${line%% *}" in
            EHLO|HELO) printf '250 lemper-uat-backup\r\n' ;;
            MAIL|RCPT|RSET|NOOP) printf '250 OK\r\n' ;;
            DATA)
                message=$(mktemp "$directory/message.XXXXXXXX") || return 1
                chmod 0600 "$message" || return 1
                printf '354 End with a dot\r\n'
                complete=false
                while IFS= read -r line; do
                    line="${line%$'\r'}"
                    if [[ "$line" == . ]]; then complete=true; break; fi
                    printf '%s\n' "$line" >> "$message" || return 1
                done
                [[ "$complete" == true ]] || return 1
                printf '250 Accepted\r\n'
                ;;
            QUIT) printf '221 Bye\r\n'; return 0 ;;
            *) printf '502 Unsupported fixture command\r\n' ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    [[ -f /run/.containerenv && -f /run/lemper-integration-backend-authorized ]] || exit 2
    uat_smtp_session /srv/backup/smtp-capture
fi
