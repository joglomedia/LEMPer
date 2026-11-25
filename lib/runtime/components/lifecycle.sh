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

# The installer/CLI adapter owns validated configuration and the shared lock.
function lemper_component_apply() {
    [[ $# -ge 2 ]] || {
        error "Specify a component action and name."
        return 1
    }
    local action="$1" component="$2" module handler spec
    local REDIS_BACKEND="${REDIS_BACKEND:-redis}" FTP_SERVER_NAME="${FTP_SERVER_NAME:-pureftpd}"
    shift 2
    case "$component" in
        redis | valkey) REDIS_BACKEND="$component" ;;
        pureftpd | pure-ftpd | vsftpd) FTP_SERVER_NAME="${component//-/}" ;;
    esac
    spec=$(lemper_component_driver "$action" "$component") || {
        error "No registered component driver for $action $component."
        return 1
    }
    read -r module handler <<<"$spec"
    lemper_load_module "$module" || return 1
    "$handler" "$@"
}
