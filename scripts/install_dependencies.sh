#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Dependencies Installer                                                  |
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

case "${1:-}" in
    --help | -h)
        printf 'Usage: install_dependencies.sh [--help|--version] (uses the LEMPer configuration profile)\n'
        if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then exit 0; else return 0; fi
        ;;
    --version | -v)
        printf 'LEMPer dependencies install v4.0.0\n'
        if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then exit 0; else return 0; fi
        ;;
esac

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
    cd "${BASE_DIR}" || {
        echo "Cannot enter ${BASE_DIR}."
        exit 1
    }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

lemper_load_module services/system/dependencies || {
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then exit 1; else return 1; fi
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    lemper_with_lock lemper_dependencies_install_entry "$@"
else
    lemper_dependencies_install_entry "$@"
fi
