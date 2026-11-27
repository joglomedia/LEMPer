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



function account_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Create a system user account for LEMPer-managed web applications.

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTIONS] [username]

Options:
  -u, --username <name>  Account name (default: LEMPER_USERNAME or 'lemper').
  --admin                Grant restricted service administration and web administration access.
  --restrict-sudo        Migrate an existing LEMPer-owned account to restricted sudo.
  --plan <name>          Provision with disk/inode limits on a quota-ready filesystem.
  -h, --help             Print this message and exit.
  -v, --version          Output version information and exit.

Each new account receives a freshly generated password.
Use '${CMD_PARENT} adduser' for an interactive prompt.
EOL
}

##
# Validate a Linux username: lowercase letters, digits, '_' and '-',
# starting with a letter or underscore, max 32 characters.
##

##
# Create a system account and its web application directories.
##
function lemper_account_command() {
    local USERNAME="" ROLE=hosting MIGRATE=false PLAN=""

    lemper_parse_args 'u:hv' 'username:,admin,restrict-sudo,plan:,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while true; do
        case "${1}" in
            -u | --username)
                USERNAME="${2}"
                shift 2
            ;;
            --admin)
                ROLE="admin"
                shift
            ;;
            --plan)
                PLAN="$2"
                shift 2
            ;;
            --restrict-sudo)
                MIGRATE=true
                shift
            ;;
            -h | --help)
                account_show_usage
                return 0
            ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VERSION}"
                return 0
            ;;
            --)
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
            ;;
        esac
    done

    if [[ -n "${1:-}" ]]; then
        USERNAME="${1}"
        shift
    fi

    if [[ $# -gt 0 ]]; then
        fail "Unexpected argument: ${1}"
    fi

    if [[ -n "$PLAN" ]]; then
        [[ "$ROLE" == hosting && "$MIGRATE" == false ]] || { error "Hosting plans apply only to hosting accounts."; return 1; }
        lemper_load_module services/hosting/quota || return 1
        lemper_load_module services/hosting/plans || return 1
        lemper_with_lock lemper_account_with_plan "${USERNAME:-${LEMPER_USERNAME:-lemper}}" "$PLAN"
    elif [[ "${MIGRATE}" == true ]]; then
        restrict_account_sudo "${USERNAME:-${LEMPER_USERNAME:-lemper}}"
    else
        lemper_load_module services/accounts/user || return 1
        lemper_with_lock create_account "${USERNAME}" "${ROLE}"
    fi
}

function lemper_account_with_plan() {
    local user="$1" plan="$2"
    lemper_hosting_preflight "$plan" || return 1
    if getent passwd "$user" >/dev/null; then
        error "Account already exists; use hosting assign for an owned account."; return 1
    fi
    lemper_load_module services/accounts/user || return 1
    create_account "$user" hosting "$plan"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
