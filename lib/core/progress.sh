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

# Optional presentation helpers; no source-time state or shell option changes.
function lemper_progress_now() { date +%s; }
function lemper_progress_reset() {
    [[ "${1:-}" =~ ^[0-9]{1,6}$ ]] || return 1
    export PROGRESS_TOTAL=$((10#$1))
    export PROGRESS_CURRENT=0
    export PROGRESS_STARTED
    PROGRESS_STARTED=$(lemper_progress_now) || return 1
}
function lemper_progress_eta() {
    local completed="${1}" total="${2}" started="${3}" now elapsed remaining
    [[ "$completed" =~ ^[0-9]{1,6}$ && "$total" =~ ^[0-9]{1,6}$ && "$started" =~ ^[0-9]+$ ]] || return 1
    ((completed > 0 && total > completed)) || return 1
    now=$(lemper_progress_now) || return 1
    elapsed=$((now - started))
    ((elapsed >= 0)) || return 1
    remaining=$((elapsed * (total - completed) / completed))
    printf '~%dm %02ds' "$((remaining / 60))" "$((remaining % 60))"
}
# Emit bytes only on stdout; transfer feedback goes to the interactive terminal.
function lemper_transfer_read() {
    local file="$1" size
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || return 0
    if [[ "${TRANSFER_PROGRESS:-true}" == true && -t 2 ]] && command -v pv >/dev/null; then
        size=$(stat -c %s -- "$file") || return 1
        pv -pterb -s "$size" -- "$file"
    else cat -- "$file"; fi
}
