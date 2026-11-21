#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer PHP Default Alternatives                                         |
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

function lemper_php_default_restore() {
    local group rc=0 index
    local -n restore_changed="$1" restore_previous="$2" restore_modes="$3"
    for ((index=${#restore_changed[@]}-1; index>=0; index--)); do
        group="${restore_changed[$index]}"
        if [[ "${restore_modes[$group]}" == auto ]]; then
            lemper_exec update-alternatives --auto "$group" || rc=1
        else lemper_exec update-alternatives --set "$group" "${restore_previous[$group]}" || rc=1; fi
    done
    [[ "$rc" == 0 ]] || error "PHP alternatives rollback needs administrator recovery."
    return "$rc"
}

# Used by the installer and stack config. Optional developer tools are changed
# only when their matching binary/group exists; php itself is mandatory.
function lemper_php_default_switch() {
    local version="$1" profile="${2:-}" group binary query line candidate status previous_value prepared="" backup=""
    local groups=() changed=()
    local -A targets=() previous=() modes=()
    lemper_php_supported "$version" || { error "Supported PHP defaults are 8.2-8.5."; return 1; }
    for group in php phar phar.phar php-config phpize; do
        binary=$(command -v "$group$version") || binary=""
        query=$(update-alternatives --query "$group" 2>/dev/null) || query=""
        if [[ -z "$binary" || -z "$query" ]]; then
            [[ "$group" != php ]] || { error "PHP $version CLI and its registered alternative are required."; return 1; }
            info "Skipping optional $group: its PHP $version binary/alternative is not installed."
            continue
        fi
        [[ "$binary" == /* && -x "$binary" ]] || { error "Invalid PHP alternative executable."; return 1; }
        status="" previous_value="" candidate=""
        while IFS= read -r line; do
            case "$line" in
                'Status: '*) status="${line#Status: }" ;;
                'Value: '*) previous_value="${line#Value: }" ;;
                'Alternative: '*) [[ "${line#Alternative: }" != "$binary" ]] || candidate="$binary" ;;
            esac
        done <<< "$query"
        [[ -n "$candidate" && "$previous_value" == /* && ( "$status" == auto || "$status" == manual ) ]] || {
            error "The PHP $version target is not registered for $group; no alternatives changed."; return 1;
        }
        groups+=("$group"); targets[$group]="$candidate"; previous[$group]="$previous_value"; modes[$group]="$status"
    done
    if [[ "${DRYRUN:-false}" == true ]]; then
        for group in "${groups[@]}"; do lemper_exec update-alternatives --set "$group" "${targets[$group]}" || return 1; done
        [[ -z "$profile" ]] || info "Would persist DEFAULT_PHP_VERSION=$version (profile encryption preserved)."
        return 0
    fi
    if [[ -n "$profile" ]]; then
        lemper_load_module core/config-update || return 1
        prepared=$(core_config_prepare_value "$profile" DEFAULT_PHP_VERSION "$version") || return 1
        if [[ -n "$prepared" ]]; then
            backup=$(mktemp "${profile}.pre-default.XXXXXXXX") || { secure_shred "$prepared"; return 1; }
            if ! cp "$profile" "$backup" || ! chmod 0600 "$backup"; then
                secure_shred "$prepared"; secure_shred "$backup"; return 1
            fi
        fi
    fi
    for group in "${groups[@]}"; do
        [[ "${previous[$group]}" != "${targets[$group]}" || "${modes[$group]}" != manual ]] || continue
        changed+=("$group")
        if ! lemper_exec update-alternatives --set "$group" "${targets[$group]}"; then
            lemper_php_default_restore changed previous modes || true
            [[ -z "$prepared" ]] || secure_shred "$prepared"
            error "PHP default change failed; previous alternatives restored."
            return 1
        fi
    done
    if [[ -n "$prepared" ]] && ! lemper_exec mv -Tf "$prepared" "$profile"; then
        lemper_php_default_restore changed previous modes || true
        secure_shred "$prepared"
        error "Profile update failed; previous PHP alternatives restored."
        return 1
    fi
    success "Default PHP CLI and new-site runtime: php@$version. Existing FPM/site runtimes are retained."
}
