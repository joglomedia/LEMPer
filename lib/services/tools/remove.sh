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

function lemper_tools_remove_entry() {
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
}
