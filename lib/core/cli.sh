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


function core_help_entry() {
    printf '  %-16s%s\n' "${1}" "${2}"
}

function core_help_subentry() {
    printf '    %-28s  %s\n' "${1}" "${2}"
}

function core_cmd_help() {
    local root
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return 1
    # shellcheck source=/dev/null
    . "$root/runtime/help.sh" || return 1
    lemper_runtime_help
}

function core_cmd_version() {
    echo "${PROG_NAME} version ${PROG_VERSION}"
    exit 0
}

function core_init_lemper_cli() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        CMD="${1}"
        shift # Pass the remaining arguments as sub-command options (parameters).

        case "${CMD}" in
            site|create|add|manage|mod|stack)
                if [[ "${CMD}" == stack ]]; then
                    lemper_load_module runtime/stack/commands || return 1
                    init_lemper_stack "$@"
                else
                    lemper_load_module runtime/site/commands || return 1
                    case "${CMD}" in
                        site) init_lemper_site "$@" ;;
                        create|add) init_lemper_site create "$@" ;;
                        manage|mod) init_lemper_site manage "$@" ;;
                    esac
                fi
                return $?
            ;;
            config)
                if [[ "${1:-}" != check || $# -ne 1 ]]; then
                    error "Usage: ${PROG_NAME} config check"
                    return 1
                fi
                local checked="${CONFIG_FILE}" temporary="" rc=0
                if is_config_encrypted "${checked}"; then
                    temporary=$(decrypt_config_file "${checked}") || return 1
                    checked="${temporary}"
                fi
                validate_config_file "${checked}" strict || rc=$?
                [[ -z "${temporary}" ]] || secure_shred "${temporary}"
                [[ "${rc}" -ne 0 ]] || echo "Configuration schema valid."
                return "${rc}"
            ;;
            help | -h | --help)
                cmd_help
            ;;
            version | -v | --version)
                cmd_version
            ;;
            tui | --tui | -i | --interactive)
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-tui" ]]; then
                    # shellcheck disable=SC1090,SC1091
                    . "${CLI_PLUGINS_DIR}/lemper-tui" "$@"
                else
                    echo "${PROG_NAME}: TUI plugin not found."
                    echo "See '${PROG_NAME} --help' for more information."
                    exit 1
                fi
            ;;
            *)
                local registered=false _name target
                while IFS=: read -r _name target; do
                    [[ "$target" != "lemper-${CMD}" ]] || registered=true
                done < <(lemper_command_plugins)
                if [[ "$registered" == true && -x "${CLI_PLUGINS_DIR}/lemper-${CMD}" ]]; then
                    # Source the plugin executable file.
                    # shellcheck disable=SC1090
                    . "${CLI_PLUGINS_DIR}/lemper-${CMD}" "$@"
                else
                    echo "${PROG_NAME}: '${CMD}' is not valid command."
                    echo "See '${PROG_NAME} --help' for more information."
                    exit 1
                fi
            ;;
        esac
    else
        echo "${PROG_NAME}: missing required arguments"
        echo "See '${PROG_NAME} --help' for more information"
        exit 1
    fi
}

function help_entry() {
    core_help_entry "$@"
}

function help_subentry() {
    core_help_subentry "$@"
}

function cmd_help() {
    core_cmd_help
}

function cmd_version() {
    core_cmd_version
}

function init_lemper_cli() {
    core_init_lemper_cli "$@"
}
