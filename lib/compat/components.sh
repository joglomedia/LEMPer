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

function lemper_legacy_component() {
    local action="${1}" service="${2}" source="${3}" php="${4}" key="${5}" component="${6}" force="${7}"
    local config="${CONFIG_FILE:-/etc/lemper/lemper.conf}" decrypted="" rc=0
    [[ "${DRYRUN:-false}" != true ]] || { info "Would ${action} stack component ${service}."; return 0; }
    [[ -r "${config}" ]] || { error "Installed configuration is required."; return 1; }
    if is_config_encrypted "${config}"; then
        decrypted=$(decrypt_config_file "${config}") || return 1
        config="${decrypted}"
    fi
    # Isolate sourced installers: their exit, traps, options and globals stay in the child.
    bash -c '
        export BASE_DIR="$1" LEMPER_ENV_FILE="$2"
        cd "${BASE_DIR}" || exit 1
        # shellcheck source=scripts/utils.sh
        . "${BASE_DIR}/scripts/utils.sh" || exit 1
        DRYRUN=false
        AUTO_INSTALL=true
        AUTO_REMOVE=true
        FORCE_REMOVE="$7"
        [[ "$3" == - ]] || printf -v "$3" true
        case "$4" in
            redis|valkey) REDIS_BACKEND="$4" ;;
            pureftpd|vsftpd) FTP_SERVER_NAME="$4" ;;
        esac
        if [[ -n "$5" ]]; then
            PHP_VERSIONS="$5"
            DEFAULT_PHP_VERSION="$5"
        fi
        requires_root
        preflight_system_check || exit 1
        # Only registry-derived, existing component paths reach this source.
        # shellcheck disable=SC1090
        . "$6"
    ' stack-component "${source}" "${config}" "${key}" "${service}" "${php}" "${component}" "${force}" || rc=$?
    [[ -z "${decrypted}" ]] || secure_shred "${decrypted}"
    return "${rc}"
}
