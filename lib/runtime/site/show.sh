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

function site_show_usage() {
    cat <<HELP
Usage: ${CMD_PARENT:-lemperctl} site show <domain> [--config|--fpm|--app|--ssl|--all|--json]
Displays the full configuration for a virtual host: Nginx/FPM, public application/ownership metadata and certificate details.
  -c, --config  Nginx configuration (default).
  -f, --fpm     PHP-FPM pool configuration.
  -a, --app     Public application, site and mounted-app metadata.
  -s, --ssl     Configured certificate details, validity, SANs and hostname match.
  -A, --all     All views.
  -j, --json    One JSON object containing all views.
  -h, --help    Show help.
  -v, --version Show version.
Credential-bearing configuration fields are redacted. Private keys are never displayed.
HELP
}
function lemper_site_show_command() {
    local view=config domain="" root argument
    lemper_parse_args cafsAjhv 'config,fpm,app,ssl,all,json,help,version' "$@" || return 1
    for argument in "${LEMPER_PARSED_ARGS[@]}"; do
        case "$argument" in -h | --help)
            site_show_usage
            return 0
            ;;
        -v | --version)
            echo "${PROG_NAME:-lemperctl} version ${PROG_VERSION:-}"
            return 0
            ;;
        esac
    done
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --config) [[ "$view" == json ]] || view=config ;;
            -f | --fpm) [[ "$view" == json ]] || view=fpm ;;
            -a | --app) [[ "$view" == json ]] || view=app ;;
            -s | --ssl) [[ "$view" == json ]] || view=ssl ;;
            -A | --all) [[ "$view" == json ]] || view=all ;;
            -j | --json) view=json ;;
            --)
                shift
                break
                ;;
            *) return 1 ;;
        esac
        shift
    done
    [[ $# == 1 ]] || {
        error "site show requires one domain."
        return 1
    }
    domain="$1"
    [[ $(core_validate_fqdn "$domain") == true ]] || {
        error "Invalid site domain."
        return 1
    }
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd) || return 1
    command -v python3 >/dev/null || {
        error "Python 3 is required for site diagnostics."
        return 1
    }
    python3 -I "$root/services/site/inspect.py" "$domain" "$view"
}
