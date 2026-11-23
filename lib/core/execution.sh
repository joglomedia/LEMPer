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
    if [[ "${DRYRUN:-false}" == true ]]; then
        "$callback" "$@"
        return $?
    fi
    (
        local fd caller_umask
        caller_umask=$(umask)
        umask 077
        exec {fd}>"$lock" || return 1
        umask "$caller_umask"
        flock -n "$fd" || {
            error "Another LEMPer operation is running."
            return 1
        }
        "$callback" "$@"
    )
}

# Source only an internal, named module; callers cannot supply filesystem paths.
function lemper_load_module() {
    local module="$1" root
    case "$module" in
        runtime/site/create | runtime/site/commands | runtime/site/apps | runtime/stack/commands | runtime/stack/config | runtime/mail/commands | services/mail/store | services/mail/configure | services/php/lifecycle | services/php/packages | services/php/defaults | services/nginx/apps | core/config-update | \
            runtime/account/commands | runtime/database/commands | runtime/ssl/commands | runtime/tui/commands | services/accounts/user | services/restic/backup | services/monitoring/monit | services/firewall/nftables | runtime/data/commands | runtime/firewall/commands | services/optional | services/systemd | services/inventory | services/mariadb/backup | services/mariadb/database | services/apt/repositories | compat/components | core/deployment | services/hosting/quota | services/hosting/plans | runtime/hosting/commands | core/progress | services/ssl/certificates | services/apt/catalog | runtime/site/show | runtime/site/state | services/site/applications | services/site/database | services/bun/binary) ;;
        services/site/releases | services/nginx/release-site | services/site/release_metadata | services/site/release_archive | services/site/release_prepare | services/site/inspect | services/mariadb/option_guard | services/php/repository | services/mariadb/repository) ;;
        services/nginx/vhost | services/php/pools | services/site/skeletons | services/site/provision | services/nginx/features | services/nginx/protection | services/ssl/site | runtime/site/manage | services/php/update | services/php/migrate | services/nginx/repository | services/nginx/update | services/mariadb/update | services/tools/update | runtime/stack/update) ;;
        services/bun/install | services/ssl/install | services/security/crowdsec_install | services/system/dependencies) ;;
        services/security/fail2ban_install | services/imagemagick/install | services/mariadb/install | services/memcached/install) ;;
        services/security/modsec_install | services/mongodb/install | services/nginx/install | services/php/phalcon) ;;
        services/php/install | services/postgres/install | services/ftp/pureftpd_install | services/redis/install) ;;
        services/tools/install | services/ftp/vsftpd_install | services/bun/remove | services/ssl/remove) ;;
        services/security/crowdsec_remove | services/security/fail2ban_remove | services/imagemagick/remove | services/mariadb/remove) ;;
        services/memcached/remove | services/security/modsec_remove | services/mongodb/remove | services/nginx/remove) ;;
        services/php/remove | services/postgres/remove | services/ftp/pureftpd_remove | services/redis/remove) ;;
        services/tools/remove | services/ftp/vsftpd_remove | services/system/cleanup | services/system/optimization) ;;
        services/system/security | services/nginx/build_common | services/nginx/package_repository | services/nginx/ssl_builders) ;;
        services/nginx/modules_build | services/nginx/module_config | services/nginx/configure | services/nginx/tls) ;;
        services/nginx/build) ;;
        runtime/components/lifecycle) ;;
        runtime/backup/commands | services/configuration/backup | runtime/benchmark/commands | services/system/benchmark | runtime/site/list | services/nginx/list | runtime/modsec/commands | services/security/modsec_config | runtime/account/adduser | runtime/site/permissions | services/accounts/permissions | core/encryption) ;;
        *)
            error "Unknown library module."
            return 1
            ;;
    esac
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd) || return 1
    # Modules are checked independently, including their dynamic dependencies.
    # shellcheck source=/dev/null
    . "$root/$module.sh"
}
