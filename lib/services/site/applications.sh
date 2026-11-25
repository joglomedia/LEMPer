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

# Functions only. CLI, legacy adapters and TUI share the same capability data.
function lemper_site_application_uses_release() {
    case "$1" in mautic | roundcube | snappymail | nextcloud | mybb | phplist | ojs | slim) return 0 ;; *) return 1 ;; esac
}
function lemper_site_application_custom_template() {
    case "$1" in snappymail | nextcloud | mybb | phplist | ojs | slim | xenforo) return 0 ;; *) return 1 ;; esac
}
function lemper_site_application_spec() {
    local type="$1" id label capability wizard markers
    while IFS='|' read -r id label capability wizard markers; do
        [[ "$id" != "$type" ]] || {
            printf '%s|%s|%s|%s\n' "$label" "$capability" "$wizard" "$markers"
            return 0
        }
    done < <(lemper_site_application_registry)
    return 1
}
function lemper_site_application_installable() {
    local label capability wizard markers
    IFS='|' read -r label capability wizard markers < <(lemper_site_application_spec "$1") || return 1
    [[ "$capability" == automatic ]]
}
function lemper_site_application_names() {
    local selection="$1" id label capability wizard markers
    local names=()
    while IFS='|' read -r id label capability wizard markers; do
        case "$selection:$capability" in
            automatic:automatic | manual:manual | none:none | all:*) names+=("$id") ;;
        esac
    done < <(lemper_site_application_registry)
    local IFS=', '
    printf '%s\n' "${names[*]}"
}
function lemper_site_application_validate_request() {
    local type="$1" install="$2" label capability wizard markers
    IFS='|' read -r label capability wizard markers < <(lemper_site_application_spec "$type") || {
        error "Unsupported site type: $type"
        return 1
    }
    [[ "$install" == true ]] || return 0
    case "$capability" in
        automatic) return 0 ;;
        none) error "Vanilla PHP has no application skeleton; omit --install-skeleton/--install-app." ;;
        manual) error "Automatic $label installation is unavailable; omit --install-skeleton/--install-app and deploy the application files manually." ;;
    esac
    return 1
}
function lemper_site_application_check_files() {
    local type="$1" root="$2" label capability wizard markers marker
    local files=()
    IFS='|' read -r label capability wizard markers < <(lemper_site_application_spec "$type") || return 1
    [[ "$capability" == automatic ]] || return 1
    IFS=, read -r -a files <<<"$markers"
    for marker in "${files[@]}"; do
        [[ -f "$root/$marker" && -s "$root/$marker" ]] || {
            error "$label installation did not produce the expected application files ($marker)."
            return 1
        }
    done
}
