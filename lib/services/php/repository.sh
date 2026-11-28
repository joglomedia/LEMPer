#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer PHP Repository Management                                        |
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

# Sury's maintained archive serves supported Debian and Ubuntu releases.
function lemper_php_repository_release() {
    local distro="${DISTRIB_NAME:-$(get_distrib_name)}" release="${RELEASE_NAME:-$(get_release_name)}"
    case "$distro:$release" in ubuntu:jammy | ubuntu:noble | ubuntu:resolute | debian:bullseye | debian:bookworm) ;;
    *)
        error "No supported Sury PHP repository for this distribution."
        return 1
        ;;
    esac
    printf '%s\n' "$release"
}
function lemper_php_repository_keyring() {
    printf '/usr/share/keyrings/debsuryorg-archive-keyring.gpg\n'
}
function lemper_php_repository_key_valid() {
    lemper_load_module services/apt/repositories || return 1
    lemper_apt_key_matches "$1" "${2:-15058500A0235D97F5D10063B188E2B695BD4743}"
}
function lemper_php_install_archive_keyring() (
    local key="$1" work
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would install the pinned Sury archive signing key."
        return 0
    }
    [[ "${LEMPER_APT_ROOT:-/etc/apt}" == /etc/apt && "$key" == /usr/share/keyrings/debsuryorg-archive-keyring.gpg ]] || return 1
    if lemper_php_repository_key_valid "$key"; then return 0; fi
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 3 --max-filesize 1048576 \
        -o "$work/keyring.deb" https://packages.sury.org/debsuryorg-archive-keyring.deb || return 1
    [[ "$(dpkg-deb -f "$work/keyring.deb" Package)" == debsuryorg-archive-keyring &&
    "$(dpkg-deb -f "$work/keyring.deb" Architecture)" == all ]] || return 1
    set -o pipefail
    dpkg-deb --fsys-tarfile "$work/keyring.deb" \
        | tar -xO -f - ./usr/share/keyrings/debsuryorg-archive-keyring.gpg >"$work/keyring.gpg" || return 1
    lemper_php_repository_key_valid "$work/keyring.gpg" || {
        error "Downloaded Sury archive keyring fingerprint does not match."
        return 1
    }
    local prepared
    prepared=$(mktemp "$key.XXXXXXXX") || return 1
    if ! lemper_exec install -m0644 "$work/keyring.gpg" "$prepared" \
        || ! lemper_exec mv -Tf "$prepared" "$key"; then
        rm -f -- "$prepared"
        return 1
    fi
    lemper_php_repository_key_valid "$key"
)
# Pre-render every file before changing any repository. The generic APT parser
# rejects mixed URI groups and signature bypasses; unrelated sources stay literal.
function lemper_php_repository_render() {
    local file="$1" release="$2" key="$3" action="${4:-prepare}" rendered line uri prefix tail
    local block=() uris=() field selected index matched=0
    if ! lemper_apt_file_has_source "$file" php; then
        cat -- "$file"
        return
    fi
    rendered=$(lemper_apt_scope_file "$file" php "$key") || return 1
    if [[ "$file" == *.sources ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                block+=("$line")
                continue
            fi
            [[ ${#block[@]} != 0 ]] || continue
            selected=false
            for ((index = 0; index < ${#block[@]}; index++)); do
                field="${block[index]}"
                [[ "${field,,}" == uris:* ]] || continue
                field="${field#*:}"
                while ((index + 1 < ${#block[@]})) && [[ "${block[index + 1]}" == [[:space:]]* ]]; do
                    index=$((index + 1))
                    field+=" ${block[index]}"
                done
                read -r -a uris <<<"$field"
                for uri in "${uris[@]}"; do
                    if lemper_apt_source_uri_matches php "$uri"; then selected=true; fi
                done
            done
            [[ "$selected" != true ]] || matched=$((matched + 1))
            if [[ "$selected" == true && "$action" == remove ]]; then
                block=()
                continue
            fi
            for ((index = 0; index < ${#block[@]}; index++)); do
                field="${block[index]}"
                if [[ "$selected" == true && "${field,,}" == uris:* ]]; then
                    printf 'URIs: https://packages.sury.org/php/\n'
                    while ((index + 1 < ${#block[@]})) && [[ "${block[index + 1]}" == [[:space:]]* ]]; do index=$((index + 1)); done
                elif [[ "$selected" == true && "${field,,}" == suites:* ]]; then
                    printf 'Suites: %s\n' "$release"
                    while ((index + 1 < ${#block[@]})) && [[ "${block[index + 1]}" == [[:space:]]* ]]; do index=$((index + 1)); done
                else printf '%s\n' "$field"; fi
            done
            printf '\n'
            block=()
        done < <(printf '%s\n\n' "$rendered")
        ((matched > 0)) || {
            error "Invalid PHP repository stanza."
            return 1
        }
        return 0
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ ^([[:space:]]*deb(-src)?[[:space:]]+(\[[^]]*\][[:space:]]+)?)([^[:space:]]+)[[:space:]]+([^[:space:]]+)(.*)$ ]]; then
            prefix="${BASH_REMATCH[1]}" uri="${BASH_REMATCH[4]}" tail="${BASH_REMATCH[6]}"
            if lemper_apt_source_uri_matches php "$uri"; then
                [[ "$action" != remove ]] || continue
                printf '%shttps://packages.sury.org/php/ %s%s\n' "$prefix" "$release" "$tail"
                continue
            fi
        fi
        printf '%s\n' "$line"
    done <<<"$rendered"
}
function lemper_php_repository_active() {
    local file="$1" line enabled=true selected=false binary=false
    if [[ "$file" != *.sources ]]; then
        grep -Eq '^[[:space:]]*deb[[:space:]]+(\[[^]]*\][[:space:]]+)?https://packages[.]sury[.]org/php/?[[:space:]]' "$file"
        return
    fi
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            [[ "$selected" != true || "$enabled" != true || "$binary" != true ]] || return 0
            selected=false enabled=true binary=false
        elif [[ "${line,,}" == uris:* && "$line" == *https://packages.sury.org/php/* ]]; then
            selected=true
        elif [[ "${line,,}" =~ ^types:([[:space:]]+[a-z-]+)*[[:space:]]+deb([[:space:]]|$) ]]; then
            binary=true
        elif [[ "${line,,}" =~ ^enabled:[[:space:]]*(no|false|0)[[:space:]]*$ ]]; then
            enabled=false
        fi
    done < <(
        cat -- "$file"
        printf '\n\n'
    )
    return 1
}
function lemper_php_repository_reconcile() (
    local action="${1:-prepare}" release key root="${LEMPER_APT_ROOT:-/etc/apt}" file work index active=false result=0 changed legacy_global=false
    local files=() prepared=() applied=() original=()
    lemper_load_module services/apt/repositories || return 1
    release=$(lemper_php_repository_release) && key=$(lemper_php_repository_keyring) || return 1
    [[ "$action" == prepare || "$action" == remove ]] || return 1
    [[ "$root" == /* && ! -L "$root" && ! -L "$root/keyrings" && ! -L "$root/sources.list.d" ]] || return 1
    [[ ! -e "$root/trusted.gpg.d/debsuryorg-archive.gpg" && ! -L "$root/trusted.gpg.d/debsuryorg-archive.gpg" ]] || legacy_global=true
    for file in "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ -f "$file" ]] || continue
        [[ ! -L "$file" ]] || return 1
        lemper_php_repository_render "$file" "$release" "$key" "$action" >/dev/null || return 1
        files+=("$file")
    done
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would $action the scoped Sury PHP repository for $release."
        return 0
    fi
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    for index in "${!files[@]}"; do
        file="${files[index]}"
        lemper_php_repository_render "$file" "$release" "$key" "$action" >"$work/prepared-$index" || return 1
        prepared+=("$work/prepared-$index")
        # The parser needs the original suffix to distinguish deb822.
        if [[ "$file" == *.sources ]]; then
            cp "$work/prepared-$index" "$work/active.sources" || return 1
            if lemper_php_repository_active "$work/active.sources"; then active=true; fi
        else
            if lemper_php_repository_active "$work/prepared-$index"; then active=true; fi
        fi
    done
    if [[ "$action" == prepare && "$active" == false ]]; then
        file="$root/sources.list.d/php.list"
        [[ ! -s "$file" ]] || file="$root/sources.list.d/lemper-php.list"
        [[ ! -s "$file" ]] || {
            error "php.list contains retained configuration; reconcile it before enabling Sury."
            return 1
        }
        files+=("$file") prepared+=("$work/new-source")
        printf 'deb [signed-by=%s] https://packages.sury.org/php/ %s main\n' "$key" "$release" >"$work/new-source"
    fi
    [[ "$action" != prepare ]] || lemper_php_install_archive_keyring "$key" || return 1
    lemper_exec install -d -m0755 "$root/sources.list.d" || return 1
    for index in "${!files[@]}"; do
        file="${files[index]}" changed="${prepared[index]}"
        cmp -s "$file" "$changed" && continue
        if [[ -e "$file" ]]; then
            original[index]="$work/original-$index"
            cp -p -- "$file" "${original[index]}" || {
                result=1
                break
            }
            [[ -e "$file.lemper-before-php-repository" ]] || lemper_exec cp -p -- "$file" "$file.lemper-before-php-repository" || {
                result=1
                break
            }
            if ! chmod --reference="$file" "$changed" || ! chown --reference="$file" "$changed"; then
                result=1
                break
            fi
        else
            original[index]=""
            chmod 0644 "$changed" || {
                result=1
                break
            }
        fi
        applied+=("$index")
        lemper_exec mv -T -- "$changed" "$file" || {
            result=1
            break
        }
    done
    if [[ "$action" == prepare && "$result" == 0 ]]; then lemper_exec apt-get update -q -y || result=1; fi
    if [[ "$result" != 0 ]]; then
        for index in "${applied[@]}"; do
            if [[ -n "${original[index]}" ]]; then
                lemper_exec mv -T -- "${original[index]}" "${files[index]}" || result=1
            else lemper_exec rm -f -- "${files[index]}" || result=1; fi
        done
        error "PHP repository reconciliation failed; previous sources were restored where possible."
        return 1
    fi
    if [[ "$action" == prepare ]]; then
        # New installations use scoped trust only; shared pre-existing trust is
        # retained. DPkg preserves administrator deletion of this conffile.
        if [[ "$legacy_global" == false && -f "$root/trusted.gpg.d/debsuryorg-archive.gpg" ]]; then
            lemper_apt_retire_key "$root/trusted.gpg.d/debsuryorg-archive.gpg" "$key" || return 1
        fi
        for file in "$root/trusted.gpg.d/ondrej-php-$release" "$root/trusted.gpg.d/ondrej-php-$release.gpg" "$root/keyrings/ondrej-php.gpg"; do
            [[ -f "$file" ]] || continue
            if lemper_php_repository_key_valid "$file"; then
                lemper_apt_retire_key "$file" "$key" || warning "Retained a legacy PHP keyring requiring review."
            elif lemper_php_repository_key_valid "$file" 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C; then
                if lemper_php_other_ondrej_source; then
                    warning "Retained a PPA key shared with another Ondrej archive."
                else
                    lemper_apt_retire_key "$file" "$file" || warning "Retained a shared legacy PPA keyring."
                fi
            else
                warning "Retained a legacy PPA keyring; it may be shared with other repositories."
            fi
        done
    fi
)
function lemper_php_other_ondrej_source() {
    local root="${LEMPER_APT_ROOT:-/etc/apt}" file line word words=()
    for file in "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            read -r -a words <<<"$line"
            for word in "${words[@]}"; do
                [[ "$word" != \#* ]] || break
                case "${word%/}" in
                    http://ppa.launchpad.net/ondrej/*/ubuntu | https://ppa.launchpad.net/ondrej/*/ubuntu | \
                        http://ppa.launchpadcontent.net/ondrej/*/ubuntu | https://ppa.launchpadcontent.net/ondrej/*/ubuntu)
                        lemper_apt_source_uri_matches php "$word" || return 0
                        ;;
                esac
            done
        done <"$file"
    done
    return 1
}
function lemper_php_prepare_repository() { lemper_php_repository_reconcile prepare; }
function lemper_php_remove_repository() { lemper_php_repository_reconcile remove; }
