#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Fix File & Directory Permission                            |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
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

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

# Usage: fixpermission path
function fixpermission() {
    # Path file / directory
    [ "${1}" = "" ] && return 0

    find "${1}" -type d -print0 | xargs -0 chmod 755
    find "${1}" -type f -print0 | xargs -0 chmod 644
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
fixpermission "$@"