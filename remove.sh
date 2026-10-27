#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Uninstaller                                                |
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

set -e -o pipefail

PROG_NAME=$(basename "$0")

# Help must not require root, a dotenv file, or a repository checkout.
case "${1:-}" in
    -h | --help | help)
        echo "LEMPer Stack uninstaller"
        echo "Usage: ${PROG_NAME} [options]"
        echo "For more help please visit https://github.com/joglomedia/LEMPer"
        exit 0
    ;;
esac

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASE_DIR && \
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Run from the checkout root so relative paths (.env, scripts/, share/) work
# regardless of the caller's working directory.
cd "${BASE_DIR}" || { echo "${PROG_NAME}: cannot enter ${BASE_DIR}."; exit 1; }

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    . "${BASE_DIR}/scripts/utils.sh"
fi

# Make sure only root can run this installer script.
requires_root "$@"

# Make sure only supported distribution can run this installer script.
preflight_system_check

# Source shared install/remove functions (eliminates code duplication with lemper.sh).
. "${BASE_DIR}/lib/core/lemper-stacks.sh"

# Main LEMPer Uninstaller
header_msg

lemper_remove

footer_msg
