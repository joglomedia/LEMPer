#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Configuration Use Cases                                    |
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

function lemper_stack_config() {
    local service="" runtime="" argument
    local DRYRUN="${DRYRUN:-false}"
    lemper_parse_args h 'help,default-runtime:,dry-run' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) stack_help; return 0 ;;
            --dry-run) DRYRUN=true ;;
            --default-runtime)
                [[ -z "$runtime" ]] || { error "Specify one default runtime."; return 1; }
                runtime="$1"; shift ;;
            --) [[ $# == 1 ]] || { error "Specify one stack service."; return 1; }; service="$1"; break ;;
        esac
    done
    [[ "$service" == php && "$runtime" =~ ^php@(8\.[2-5])$ ]] || {
        error "Usage: lemperctl stack config php --default-runtime=php@VERSION (8.2-8.5)."; return 1;
    }
    local version="${BASH_REMATCH[1]}" profile="${CONFIG_FILE:-/etc/lemper/lemper.conf}"
    [[ -f "$profile" && ! -L "$profile" ]] || { error "Installed configuration is required."; return 1; }
    lemper_load_module services/php/lifecycle || return 1
    lemper_load_module services/php/defaults || return 1
    lemper_with_lock lemper_php_default_switch "$version" "$profile"
}
