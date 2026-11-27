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

##
# Resolve the LEMPer source checkout used to refresh CLI/plugins.
##
function update_resolve_source() {
    if [[ -n "${UPDATE_SOURCE_DIR:-}" ]]; then
        printf '%s\n' "${UPDATE_SOURCE_DIR}"
        return 0
    fi

    lemper_installed_release
}

##
# True when a config file has the openssl enc header.
##
function tools_config_is_encrypted() {
    local file="${1}"
    [[ -f "${file}" ]] || return 1
    head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'
}

##
# Use the same credential precedence and legacy KDF as the dispatcher.
##
function tools_decrypt_config() {
    local src="${1}"
    local dest="${2}"
    local pw=""

    pw=$(core_resolve_config_password) || return 1

    openssl enc -aes-256-cbc -a -d -salt -md sha256 -pbkdf2 \
        -pass fd:3 3<<<"$pw" -in "${src}" -out "${dest}" 2>/dev/null ||
        openssl enc -aes-256-cbc -a -d -salt -md sha256 \
            -pass fd:3 3<<<"$pw" -in "${src}" -out "${dest}" 2>/dev/null
}

##
# Pick the dotenv used to reinstall administration tools.
# Prints the path. Sets LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=true when the
# only available file is the sample .env.dist.
##
function resolve_tools_env() {
    local src="${1}"
    local conf="/etc/lemper/lemper.conf"
    local tmp

    LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=false

    if [[ -f "${src}/.env" ]]; then
        printf '%s\n' "${src}/.env"
        return 0
    fi

    if [[ -f "${conf}" ]]; then
        lemper_directory_trusted /tmp || return 1
        tmp=$(mktemp /tmp/lemper-tools-env.XXXXXXXX) || return 1
        if tools_config_is_encrypted "${conf}"; then
            if tools_decrypt_config "${conf}" "${tmp}"; then
                printf '%s\n' "${tmp}"
                return 0
            fi
            rm -f "${tmp}"
            error "Could not decrypt the installed profile for the administration tools."
            return 1
        else
            cp "${conf}" "${tmp}" || {
                rm -f "${tmp}"
                return 1
            }
            printf '%s\n' "${tmp}"
            return 0
        fi
    fi

    if [[ -f "${src}/.env.dist" ]]; then
        LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=true
        printf '%s\n' "${src}/.env.dist"
        return 0
    fi

    error "No .env, ${conf}, or .env.dist is available for the tools reinstall."
    return 1
}

##
# Re-run scripts/install_tools.sh from a checkout. DRYRUN is forced off so
# the CLI, plugins, Adminer, file manager, and PHP admin panels are replaced.
##
function reinstall_admin_tools() {
    local src="${1}"
    local envfile=""
    local tools_rc=0 cli_installed="${2:-false}"

    [[ -f "${src}/scripts/install_tools.sh" && -f "${src}/scripts/utils.sh" ]] || {
        error "Source at ${src} has no scripts/install_tools.sh."
        return 1
    }

    envfile=$(resolve_tools_env "${src}") || return 1

    [[ "$envfile" != "$src/.env.dist" ]] || LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=true
    info "Reinstalling LEMPer CLI, plugins, and web administration tools from ${src}..."
    DRYRUN=false \
        LEMPER_TOOLS_SKIP_CLI="${cli_installed}" \
        LEMPER_ENV_FILE="${envfile}" \
        LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG="${LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG}" \
        bash -c '
            tools="$1"
            base=$(cd "$(dirname "${tools}")/.." && pwd) || exit 1
            cd "${base}" || exit 1
            export BASE_DIR="${base}"
            # shellcheck source=scripts/utils.sh
            . "${base}/scripts/utils.sh"
            DRYRUN=false
            shift
            # shellcheck source=scripts/install_tools.sh
            . "${tools}"
        ' _ "${src}/scripts/install_tools.sh" || tools_rc=$?

    if [[ "${envfile}" != "${src}/.env" && "${envfile}" != "${src}/.env.dist" ]]; then
        rm -f "${envfile}"
    fi

    return "${tools_rc}"
}

##
# Refresh the CLI and CLI plugins from a source checkout.
##
function update_lemper_tooling() {
    local src result

    if src=$(update_resolve_source); then
        :
    else
        result=$?
        if [[ "$result" == 2 ]]; then
            warning "No installed release available for CLI/plugin refresh."
            warning "Specify --source-dir with a trusted checkout."
            return 0
        fi
        error "The installed release selector or tree is unsafe."
        return 1
    fi

    if [[ ! -f "${src}/bin/lemper-cli.sh" || ! -f "${src}/lib/lemper-update.sh" ]]; then
        error "Source at ${src} is not a LEMPer checkout."
        return 1
    fi

    # Compatibility exports: lemper-create/add/manage/mod/site-db/site-database.
    # shellcheck source=/dev/null
    . "$src/lib/core/registry.sh" || return 1
    # shellcheck source=/dev/null
    . "$src/lib/core/deployment.sh" || return 1
    if [[ "${LEMPER_TOOLING_ALREADY_INSTALLED:-false}" != true && ! "$src" -ef /opt/lemper/current ]]; then
        lemper_cli_snapshot "$src" || return 1
    fi

    printf '%s\n' /opt/lemper/current >"${LEMPER_UPDATE_SOURCE_FILE}"
    chmod 0600 "${LEMPER_UPDATE_SOURCE_FILE}"

    reinstall_admin_tools "${src}" true || return 1
    success "LEMPer CLI, plugins, and web administration tools reinstalled from ${src}."
}
