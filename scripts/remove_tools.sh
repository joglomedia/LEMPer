#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI Tooling Uninstaller                                          |
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

if [[ "$(type -t run)" != function ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || exit 1
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh" || exit 1
    requires_root "$@"
    preflight_system_check || exit 1
fi

if ! lemper_provisioned tools && [[ "${FORCE_REMOVE:-false}" != true ]]; then
    info "Pre-existing administration tooling is preserved; force is required for removal."
else
    run rm -f /usr/local/bin/lemper-cli /usr/local/bin/lemperctl /usr/bin/lemper-cli
    run rm -rf /etc/lemper/cli-plugins /etc/lemper/core
    for cli_module in runtime services compat; do
        if [[ -L "/etc/lemper/$cli_module" ]]; then run rm -f "/etc/lemper/$cli_module"; fi
    done
    info "CLI entry points removed; release trees retained. Configuration, credentials, and web administration data are retained."
fi
