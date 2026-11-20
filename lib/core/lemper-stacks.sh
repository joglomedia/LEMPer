#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Installer & Uninstaller - Shared Logic                     |
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



# Compatibility module for install.sh/remove.sh/lemper.sh and the historical
# scripts/lemper_stacks.sh symlink. Runtime recipe modules define functions only.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi
if [[ -z "${BASE_DIR:-}" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." >/dev/null 2>&1 && pwd )
    export BASE_DIR
fi
# shellcheck source=/dev/null
. "$BASE_DIR/lib/runtime/stack/recipe.sh" || return 1
