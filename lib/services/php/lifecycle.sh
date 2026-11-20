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



function lemper_php_supported() {
    [[ "${1:-}" =~ ^8\.[2-5]$ ]]
}

# An existing config directory alone does not establish an installed FPM unit.
function lemper_php_inventory() {
    local scope="${1:-fpm}" package state version
    while IFS=$'\t' read -r package state; do
        [[ "$state" == 'install ok installed' ]] || continue
        package="${package%%:*}"
        if [[ "$scope" == fpm ]]; then
            [[ "$package" =~ ^php([0-9]+\.[0-9]+)-fpm$ ]] || continue
        else
            [[ "$package" =~ ^php([0-9]+\.[0-9]+)(-.*)?$ ]] || continue
        fi
        version="${BASH_REMATCH[1]}"
        printf '%s\n' "$version"
    done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' 'php*' 2>/dev/null) |
        sort -Vu
}

# Output the selected versions. Installation policy differs from management.
function lemper_php_resolve() {
    local action="$1" selected="$2" all="$3" scope=all version
    local versions=()
    [[ -z "$selected" || "$selected" =~ ^[0-9]+\.[0-9]+$ ]] ||
        { error "Invalid PHP version."; return 1; }
    [[ -z "$selected" || "$all" != true ]] ||
        { error "Choose --php-version or --all-versions."; return 1; }
    if [[ "$action" == install ]]; then
        [[ "$all" != true ]] || { error "Select one PHP version to install."; return 1; }
        version="${selected:-${DEFAULT_PHP_VERSION:-8.5}}"
        lemper_php_supported "$version" || { error "Supported PHP versions are 8.2-8.5."; return 1; }
        printf '%s\n' "$version"
        return 0
    fi
    case "$action" in start|stop|restart|reload|status) scope=fpm ;; esac
    mapfile -t versions < <(lemper_php_inventory "$scope")
    [[ ${#versions[@]} -gt 0 ]] || { error "No installed PHP $scope instances found."; return 1; }
    if [[ -n "$selected" ]]; then
        for version in "${versions[@]}"; do
            [[ "$version" != "$selected" ]] || { printf '%s\n' "$version"; return 0; }
        done
        error "PHP $selected is not installed."
        return 1
    fi
    if [[ "$action" == remove && ${#versions[@]} -gt 1 && "$all" != true ]]; then
        error "Multiple PHP versions installed; use --php-version or --all-versions."
        return 1
    fi
    printf '%s\n' "${versions[@]}"
}

function lemper_php_check_references() {
    local version="$1" file
    local root="${LEMPER_NGINX_DIR:-/etc/nginx}"
    for file in "$root"/sites-available/* "$root"/sites-enabled/*; do
        [[ -f "$file" ]] || continue
        if grep -Fq "php$version-fpm" "$file" ||
           grep -Eq "set[[:space:]]+\\\$php_version[[:space:]]+\"?$version\"?[[:space:]]*;" "$file"; then
            error "PHP $version is referenced by $file; migrate or remove the site first."
            return 1
        fi
    done
}

function lemper_php_update() {
    local version="$1" package state fpm=false
    local packages=()
    lemper_exec "${LEMPER_CLI_BIN:-lemperctl}" update php --php-version "$version" || return 1
    # EOL branches retain the explicit mitigation/migration policy of update php.
    lemper_php_supported "$version" || return 0
    while IFS=$'\t' read -r package state; do
        [[ "$state" == 'install ok installed' ]] || continue
        package="${package%%:*}"
        case "$package" in "php$version"|"php$version"-*) packages+=("$package") ;; *) continue ;; esac
        [[ "$package" != "php$version-fpm" ]] || fpm=true
    done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' "php$version*" 2>/dev/null)
    [[ ${#packages[@]} -gt 0 ]] ||
        { error "PHP $version has no package update path; source builds require a rebuild."; return 1; }
    lemper_exec apt-get install --only-upgrade -y "${packages[@]}" || return 1
    if [[ "$fpm" == true ]] && systemctl is-active --quiet "php$version-fpm" >/dev/null 2>&1; then
        lemper_service_control reload "php$version-fpm" || return 1
    fi
    return 0
}
