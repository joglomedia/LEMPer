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



# Unlike legacy run(), failure is returned to the orchestrator.
function lemper_exec() {
    if [[ "${DRYRUN:-false}" == true ]]; then
        printf 'Would run: '
        printf '%s\n' "$(redact_secrets "$@")"
        return 0
    fi
    "$@"
}

function lemper_with_lock() {
    local callback="$1" lock="${LEMPER_OPERATION_LOCK:-/var/lock/lemper-operation.lock}"
    shift
    if [[ "${DRYRUN:-false}" == true ]]; then "$callback" "$@"; return $?; fi
    (
        local fd caller_umask
        caller_umask=$(umask)
        umask 077
        exec {fd}>"$lock" || return 1
        umask "$caller_umask"
        flock -n "$fd" || { error "Another LEMPer operation is running."; return 1; }
        "$callback" "$@"
    )
}

# Source only an internal, named module; callers cannot supply filesystem paths.
function lemper_load_module() {
    local module="$1" root
    case "$module" in
        runtime/site/create|runtime/site/commands|runtime/site/apps|runtime/stack/commands|runtime/stack/config|runtime/mail/commands|services/mail/store|services/mail/configure|services/php/lifecycle|services/php/packages|services/php/defaults|services/nginx/apps|core/config-update|\
        runtime/account/commands|runtime/database/commands|runtime/ssl/commands|runtime/tui/commands|services/accounts/user|services/restic/backup|services/monitoring/monit|services/firewall/nftables|runtime/data/commands|runtime/firewall/commands|services/optional|services/systemd|services/inventory|services/mariadb/database|services/apt/repositories|compat/components|core/deployment|services/hosting/quota|services/hosting/plans|runtime/hosting/commands|core/progress) ;;
        *) error "Unknown library module."; return 1 ;;
    esac
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd) || return 1
    # Modules are checked independently, including their dynamic dependencies.
    # shellcheck source=/dev/null
    . "$root/$module.sh"
}
