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



function lemper_apt_key_matches() (
    local key="$1" expected="$2" work output
    [[ -f "$key" && ! -L "$key" ]] || return 1
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    output=$(gpg --batch --homedir "$work" --with-colons --show-keys "$key" 2>/dev/null) || return 1
    awk -F: -v expected="$expected" '
        $1=="pub" {if (primary) bad=1; primary=1; count++}
        primary && $1=="fpr" {if (!$10 || (expected!="" && $10!=expected)) bad=1; primary=0}
        END {exit (count<1 || (expected!="" && count!=1) || bad || primary)}
    ' <<<"$output"
)

# Function-only APT driver. The caller owns distro/version selection.
function lemper_apt_install_key() (
    local url="$1" key="$2" fingerprint="${3:-}" checksum_url="${4:-}" work actual
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would install scoped signing key: $key"; return 0; fi
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    chmod 0700 "$work" || return 1
    curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 3 -o "$work/key" "$url" || return 1
    if [[ -n "$checksum_url" ]]; then
        curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 3 -o "$work/checksum" "$checksum_url" || return 1
        read -r actual _ < "$work/checksum"
        [[ "$actual" =~ ^[A-Fa-f0-9]{64}$ && "$(sha256sum "$work/key" | cut -d ' ' -f 1)" == "${actual,,}" ]] || {
            error "Repository signing-key checksum does not match."; return 1;
        }
    fi
    if ! lemper_apt_key_matches "$work/key" "$fingerprint"; then
        if [[ -n "$fingerprint" ]]; then error "Repository signing-key fingerprint does not match."
        else error "Invalid repository signing key."; fi
        return 1
    fi
    gpg --batch --homedir "$work" --yes --dearmor -o "$work/key.gpg" "$work/key" || return 1
    lemper_exec install -d -m 0755 -- "${key%/*}" || return 1
    local prepared
    prepared=$(mktemp "${key}.XXXXXXXX") || return 1
    if ! lemper_exec install -m 0644 "$work/key.gpg" "$prepared" || ! lemper_exec mv -T -- "$prepared" "$key"; then
        rm -f -- "$prepared"; return 1
    fi
)

function lemper_apt_source_uri_matches() {
    local family="$1" uri="${2%/}"
    case "$family:$uri" in
        php:http://packages.sury.org/php|php:https://packages.sury.org/php|\
        php:http://ppa.launchpad.net/ondrej/php/ubuntu|php:https://ppa.launchpad.net/ondrej/php/ubuntu|\
        php:http://ppa.launchpadcontent.net/ondrej/php/ubuntu|php:https://ppa.launchpadcontent.net/ondrej/php/ubuntu|\
        openswoole:http://ppa.launchpad.net/openswoole/ppa/ubuntu|openswoole:https://ppa.launchpad.net/openswoole/ppa/ubuntu|\
        openswoole:http://ppa.launchpadcontent.net/openswoole/ppa/ubuntu|openswoole:https://ppa.launchpadcontent.net/openswoole/ppa/ubuntu) return 0 ;;
        pgdg:http://apt.postgresql.org/pub/repos/apt|pgdg:https://apt.postgresql.org/pub/repos/apt|\
        redis:http://packages.redis.io/deb|redis:https://packages.redis.io/deb|\
        bun:http://bun.sh/apt|bun:https://bun.sh/apt|\
        mongodb:http://repo.mongodb.org/apt/debian|mongodb:https://repo.mongodb.org/apt/debian|\
        mongodb:http://repo.mongodb.org/apt/ubuntu|mongodb:https://repo.mongodb.org/apt/ubuntu|\
        deadsnakes:http://ppa.launchpad.net/deadsnakes/ppa/ubuntu|deadsnakes:https://ppa.launchpad.net/deadsnakes/ppa/ubuntu|\
        deadsnakes:http://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu|deadsnakes:https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu|\
        maxmind:http://ppa.launchpad.net/maxmind/ppa/ubuntu|maxmind:https://ppa.launchpad.net/maxmind/ppa/ubuntu|\
        maxmind:http://ppa.launchpadcontent.net/maxmind/ppa/ubuntu|maxmind:https://ppa.launchpadcontent.net/maxmind/ppa/ubuntu|\
        golang:http://ppa.launchpad.net/longsleep/golang-backports/ubuntu|golang:https://ppa.launchpad.net/longsleep/golang-backports/ubuntu|\
        golang:http://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu|golang:https://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu) return 0 ;;
        myguard:http://deb.myguard.nl/apt/nginx/*|myguard:https://deb.myguard.nl/apt/nginx/*) return 0 ;;
        mariadb:*)
            [[ "$uri" =~ ^https?://(deb\.mariadb\.org|dlm\.mariadb\.com|downloads\.mariadb\.com|mirror\.mariadb\.org|[a-z0-9.-]+\.mariadb\.com)/ ]] ;;
        *) return 1 ;;
    esac
}

# Render first, then replace. Other repositories and source options are preserved.
# Mixed-URI deb822 stanzas must be split explicitly before assigning a key.
function lemper_apt_scope_file() {
    if ! lemper_apt_file_has_source "$1" "$2"; then cat -- "$1"; return $?; fi
    local file="$1" family="$2" key="$3" line uri options rewritten
    local block=() uris=() source_options=() field count other signed index
    if [[ "$file" == *.sources ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ -n "$line" ]]; then block+=("$line"); continue; fi
            [[ ${#block[@]} -gt 0 ]] || continue
            count=0; other=0; signed=false
            for ((index=0; index<${#block[@]}; index++)); do
                field="${block[index]}"
                if [[ "${field,,}" == uris:* ]]; then
                    field="${field#*:}"
                    while (( index+1 < ${#block[@]} )) && [[ "${block[index+1]}" == [[:space:]]* ]]; do
                        index=$((index+1)); field+=" ${block[index]}"
                    done
                    read -r -a uris <<< "$field"
                    for uri in "${uris[@]}"; do
                        if lemper_apt_source_uri_matches "$family" "$uri"; then count=$((count+1)); else other=$((other+1)); fi
                    done
                fi
            done
            [[ "$count" == 0 || "$other" == 0 ]] || {
                error "Split mixed-repository URIs before assigning Signed-By."; return 1;
            }
            if [[ "$count" -gt 0 ]]; then
                for field in "${block[@]}"; do
                    if [[ "${field,,}" =~ ^(trusted|allow-insecure|allow-weak):[[:space:]]*(yes|true|1|on)[[:space:]]*$ ]]; then
                        error "Repository source bypasses signature verification; reconcile it before migration."; return 1
                    fi
                done
            fi
            for ((index=0; index<${#block[@]}; index++)); do
                field="${block[index]}"
                if [[ "$count" -gt 0 && "${field,,}" == signed-by:* ]]; then
                    printf 'Signed-By: %s\n' "$key"; signed=true
                    # Skip an existing inline armored key, not other fields.
                    while (( index+1 < ${#block[@]} )) && [[ "${block[index+1]}" == [[:space:]]* ]]; do index=$((index+1)); done
                else printf '%s\n' "$field"; fi
            done
            [[ "$count" == 0 || "$signed" == true ]] || printf 'Signed-By: %s\n' "$key"
            printf '\n'
            block=()
        done < <(cat -- "$file"; printf '\n\n')
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*deb(-src)?[[:space:]]+)(\[[^]]*\][[:space:]]+)?([^[:space:]]+)(.*)$ ]]; then
            uri="${BASH_REMATCH[4]}"
            local prefix="${BASH_REMATCH[1]}" tail="${BASH_REMATCH[5]}"
            options="${BASH_REMATCH[3]}"
            if lemper_apt_source_uri_matches "$family" "$uri"; then
                options="${options#\[}"; options="${options%]*}"
                rewritten=""; local option
                read -r -a source_options <<< "$options"
                for option in "${source_options[@]}"; do
                    case "${option,,}" in trusted=yes|trusted=true|trusted=1|trusted=on|allow-insecure=yes|allow-insecure=true|allow-insecure=1|allow-insecure=on|allow-weak=yes|allow-weak=true|allow-weak=1|allow-weak=on)
                        error "Repository source bypasses signature verification; reconcile it before migration."; return 1 ;; esac
                    [[ "${option,,}" == signed-by=* ]] || rewritten+="$option "
                done
                printf '%s[%ssigned-by=%s] %s%s\n' "$prefix" "$rewritten" "$key" "$uri" "$tail"
                continue
            fi
        fi
        printf '%s\n' "$line"
    done < "$file"
}

function lemper_apt_scope_sources() (
    local family="$1" key="$2" root="${LEMPER_APT_ROOT:-/etc/apt}" file temporary
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would scope existing $family sources to $key."; return 0; fi
    for file in "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ -f "$file" ]] || continue
        [[ ! -L "$file" ]] || { error "Refusing symlink APT source file."; return 1; }
        temporary=$(mktemp "${file}.XXXXXXXX") || return 1
        if ! lemper_apt_scope_file "$file" "$family" "$key" > "$temporary"; then
            rm -f -- "$temporary"; return 1
        fi
        if cmp -s "$file" "$temporary"; then rm -f -- "$temporary"; continue; fi
        if [[ ! -e "${file}.lemper-before-key-scope" ]]; then
            lemper_exec cp -p -- "$file" "${file}.lemper-before-key-scope" || { rm -f -- "$temporary"; return 1; }
        fi
        if ! chmod --reference="$file" "$temporary" || ! chown --reference="$file" "$temporary" ||
           ! lemper_exec mv -T -- "$temporary" "$file"; then
            rm -f -- "$temporary"; return 1
        fi
    done
)

# Remove only dedicated legacy files containing exclusively the scoped key identities.
# Shared or unrelated keyrings are retained; no blanket global trust deletion.
function lemper_apt_retire_key() {
    local legacy="$1" scoped="$2" root="${LEMPER_APT_ROOT:-/etc/apt}" work old current
    [[ -f "$legacy" ]] || return 0
    [[ ! -L "$legacy" ]] || { error "Refusing symlink legacy keyring."; return 1; }
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would retire dedicated legacy keyring: $legacy"; return 0; fi
    work=$(mktemp -d) || return 1
    old=$(gpg --batch --homedir "$work" --with-colons --show-keys "$legacy" 2>/dev/null | awk -F: '$1=="fpr" {print $10}')
    current=$(gpg --batch --homedir "$work" --with-colons --show-keys "$scoped" 2>/dev/null | awk -F: '$1=="fpr" {print $10}')
    rm -rf -- "$work"
    [[ -n "$old" && -n "$current" ]] || { error "Cannot verify legacy signing-key ownership."; return 1; }
    local fingerprint
    while IFS= read -r fingerprint; do
        grep -Fxq -- "$fingerprint" <<< "$current" || {
            error "Legacy keyring contains unrelated keys; review it before retirement."; return 1;
        }
    done <<< "$old"
    # An unrelated repository explicitly referencing this filename must keep it.
    if grep -Fl -- "$legacy" "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources 2>/dev/null | read -r _; then
        error "Legacy keyring is still referenced by an APT source."; return 1
    fi
    lemper_exec mv -- "$legacy" "${legacy}.lemper-retired"
}

function lemper_apt_file_has_source() {
    local file="$1" family="$2" line word words=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" != [[:space:]]*'#'* && "$line" != '#'* ]] || continue
        read -r -a words <<< "$line"
        for word in "${words[@]}"; do
            if lemper_apt_source_uri_matches "$family" "$word"; then return 0; fi
        done
    done < "$file"
    return 1
}

function lemper_apt_has_source() {
    local family="$1" root="${LEMPER_APT_ROOT:-/etc/apt}" file
    for file in "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ -f "$file" ]] || continue
        if lemper_apt_file_has_source "$file" "$family"; then return 0; fi
    done
    return 1
}

function lemper_apt_write_source() {
    local file="$1" content="$2"
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would write scoped repository: $file"; return 0; fi
    [[ ! -L "$file" ]] || { error "Refusing symlink APT source target."; return 1; }
    local prepared
    prepared=$(mktemp "${file}.XXXXXXXX") || return 1
    if ! printf '%s\n' "$content" > "$prepared" || ! chmod 0644 "$prepared"; then
        rm -f -- "$prepared"; return 1
    fi
    if [[ -f "$file" ]]; then
        if cmp -s "$file" "$prepared"; then rm -f -- "$prepared"; return 0; fi
        if [[ ! -e "${file}.lemper-before-key-scope" ]]; then
            lemper_exec cp -p -- "$file" "${file}.lemper-before-key-scope" || { rm -f -- "$prepared"; return 1; }
        fi
    fi
    if ! lemper_exec mv -T -- "$prepared" "$file"; then rm -f -- "$prepared"; return 1; fi
}
