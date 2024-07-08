#!/usr/bin/env bash

# Fix file permission
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 07/07/2024
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

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