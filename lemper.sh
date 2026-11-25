#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Command Entry Point                                        |
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

# Compatibility entry point for install/remove/update and legacy installer flags.
LEMPER_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
export BASE_DIR="$LEMPER_ROOT"
# shellcheck source=/dev/null
. "$LEMPER_ROOT/lib/runtime/stack/entry.sh" || exit 1
function init_lemper_install() {
    local action="${1:-help}"
    [[ $# -eq 0 ]] || shift
    lemper_entry_main "$action" "$@"
}
init_lemper_install "$@"
