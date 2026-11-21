#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Mail Server Installer                                                   |
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

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

# Installer entrypoint; reusable modules have no source-time dispatch.
lemper_load_module services/mail/store || { if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then exit 1; else return 1; fi; }
lemper_load_module services/mail/configure || { if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then exit 1; else return 1; fi; }
function init_mailer_install() {
    if [[ "${AUTO_INSTALL:-false}" == true ]]; then
        [[ "${INSTALL_MAILER:-false}" == true ]] || { info "Mailer installation skipped."; return 0; }
    else
        local answer
        read -rp 'Install Postfix + Dovecot virtual mail hosting? [y/N]: ' answer || return 1
        [[ "$answer" == y || "$answer" == Y ]] || return 0
    fi
    lemper_mail_install
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    lemper_with_lock init_mailer_install "$@"
else
    init_mailer_install "$@"
fi
