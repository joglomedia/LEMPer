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


function core_error() {
    echo_color "${RED}" -n "Error: " >&2
    printf '%s\n' "$(redact_secrets "$@")" >&2
}

function core_fail() {
    error "$@"
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function core_success() {
    echo_color "${GREEN}" -n "Success: " >&2
    printf '%s\n' "$(redact_secrets "$@")" >&2
}

function core_info() {
    echo_color "${YELLOW}" -n "Info: " >&2
    printf '%s\n' "$(redact_secrets "$@")" >&2
}

function core_status() {
    echo_color "${GREEN}" "$@"
}

function core_warning() {
    echo_color "${YELLOW}" "$@"
}

function core_echo_ok() {
    echo_color "${GREEN}" "$@"
}

function core_echo_warn() {
    echo_color "${YELLOW}" "$@"
}

function core_echo_err() {
    echo_color "${RED}" "$@"
}

function core_run() {
    if [[ "${DRYRUN}" == true ]]; then
        echo_color "${YELLOW}" -n "would run "
        printf '%s\n' "$(redact_secrets "$@")"
    else
        if ! "$@"; then
            local CMDSTR="${1}"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

function core_init_log() {
    export LOG_FILE=${LOG_FILE:-"./lemper_install.log"}
    if [[ "${DRYRUN}" != true ]]; then
        ( umask 077 && touch "${LOG_FILE}" ) || return 1
        chmod 0600 "${LOG_FILE}" || return 1
    fi
    save_log "Initialize LEMPer installation log..."
}

function core_save_log() {
    if [[ ${DRYRUN} != true ]]; then
        {
            date '+%d-%m-%Y %T %Z'
            [[ "${1:-}" == -e ]] && shift
            printf '%b\n' "$(redact_secrets "$@")"
            echo ""
        } >> "${LOG_FILE}"
    fi
}

function error() {
    core_error "$@"
}

function fail() {
    core_fail "$@"
}

function success() {
    core_success "$@"
}

function info() {
    core_info "$@"
}

function status() {
    core_status "$@"
}

function warning() {
    core_warning "$@"
}

function echo_ok() {
    core_echo_ok "$@"
}

function echo_warn() {
    core_echo_warn "$@"
}

function echo_err() {
    core_echo_err "$@"
}

function run() {
    core_run "$@"
}

function init_log() {
    core_init_log "$@"
}

function save_log() {
    core_save_log "$@"
}
