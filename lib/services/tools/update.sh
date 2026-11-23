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
    if [[ -n "${UPDATE_SOURCE_DIR}" ]]; then
        printf '%s\n' "${UPDATE_SOURCE_DIR}"
        return 0
    fi

    if [[ -f "${LEMPER_UPDATE_SOURCE_FILE}" ]]; then
        head -n 1 "${LEMPER_UPDATE_SOURCE_FILE}"
        return 0
    fi

    if [[ -n "${LEMPER_SRC_DIR:-}" ]]; then
        printf '%s\n' "${LEMPER_SRC_DIR}"
        return 0
    fi

    return 1
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
# Decrypt lemper.conf into dest. The key file is preferred.
##
function tools_decrypt_config() {
    local src="${1}"
    local dest="${2}"
    local pw=""

    if [[ -f /etc/lemper/.config_key ]]; then
        pw=$(tr -d '\n' </etc/lemper/.config_key)
    elif [[ -n "${LEMPER_PASSWORD:-}" ]]; then
        pw="${LEMPER_PASSWORD}"
    else
        return 1
    fi

    openssl enc -aes-256-cbc -a -d -salt -md sha256 -pbkdf2 \
        -k "${pw}" -in "${src}" -out "${dest}" 2>/dev/null
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
        tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-tools-env.XXXXXX") || return 1
        chmod 0600 "${tmp}" || true
        if tools_config_is_encrypted "${conf}"; then
            if tools_decrypt_config "${conf}" "${tmp}"; then
                printf '%s\n' "${tmp}"
                return 0
            fi
            rm -f "${tmp}"
            warning "Could not decrypt ${conf}; falling back to .env.dist."
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
    local src

    if ! src=$(update_resolve_source); then
        warning "No LEMPer source checkout recorded; skipping CLI/plugin refresh."
        warning "Run update.sh from a checkout to enable future tooling updates."
        return 0
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
    if [[ "${LEMPER_TOOLING_ALREADY_INSTALLED:-false}" != true ]]; then
        lemper_cli_snapshot "$src" || return 1
    fi

    printf '%s\n' "${src}" >"${LEMPER_UPDATE_SOURCE_FILE}"
    chmod 0600 "${LEMPER_UPDATE_SOURCE_FILE}"

    reinstall_admin_tools "${src}" true || return 1
    success "LEMPer CLI, plugins, and web administration tools reinstalled from ${src}."
}
