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

# Curated existing LEMPer sources, shared by installers and legacy migration.
function lemper_apt_repository_spec() {
    local family="$1" distro="${2:-${DISTRIB_NAME:-}}" release="${3:-${RELEASE_NAME:-}}" version="${MONGODB_VERSION:-6.0}"
    local repo suite="$release" component=main key_url fingerprint=""
    [[ "$distro" == ubuntu || "$distro" == debian ]] && [[ "$release" =~ ^[a-z][a-z0-9-]{1,25}$ ]] || return 1
    case "$family" in
        pgdg)
            repo=https://apt.postgresql.org/pub/repos/apt
            suite="$release-pgdg"
            key_url=https://www.postgresql.org/media/keys/ACCC4CF8.asc
            fingerprint=B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8
            ;;
        redis)
            repo=https://packages.redis.io/deb
            key_url=https://packages.redis.io/gpg
            fingerprint=54318FA4052D1E61A6B6F7BB5F4349D6BF53AA0C
            ;;
        mongodb)
            [[ "$version" =~ ^[0-9]{1,2}\.[0-9]{1,2}$ ]] || return 1
            repo="https://repo.mongodb.org/apt/$distro"
            suite="$release/mongodb-org/$version"
            [[ "$distro" != ubuntu ]] || component=multiverse
            key_url="https://www.mongodb.org/static/pgp/server-$version.asc"
            case "$version" in
                6.0) fingerprint=39BD841E4BE5FB195A65400E6A26B1AE64C3C388 ;;
                8.0) fingerprint=4B0752C1BCA238C0B4EE14DC41DE058A4E7DCA05 ;;
            esac
            ;;
        bun)
            error "The former Bun APT endpoint is unavailable; select BUNJS_INSTALLER=source for the official binary release."
            return 1
            ;;
        deadsnakes)
            [[ "$distro" == ubuntu ]] || return 1
            repo=https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu
            fingerprint=F23C5A6CF475977595C89F51BA6932366A755776
            ;;
        maxmind)
            [[ "$distro" == ubuntu ]] || return 1
            repo=https://ppa.launchpadcontent.net/maxmind/ppa/ubuntu
            fingerprint=F44B38CE3DB1BF64B61DBD28DE1997DCDE742AFA
            ;;
        golang)
            [[ "$distro" == ubuntu ]] || return 1
            repo=https://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu
            fingerprint=876B22BA887CA91614B5323FC631127F87FA12D1
            ;;
        *)
            error "Unknown repository family."
            return 1
            ;;
    esac
    [[ -n "${key_url:-}" ]] || key_url="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint"
    printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$suite" "$component" "$key_url" "$fingerprint"
}
function lemper_apt_prepare_repository() {
    local family="$1" row repo suite component key_url fingerprint root="${LEMPER_APT_ROOT:-/etc/apt}" file key
    lemper_load_module services/apt/repositories || return 1
    row=$(lemper_apt_repository_spec "$family") || return 1
    IFS=$'\t' read -r repo suite component key_url fingerprint <<<"$row"
    [[ "$root" == /* && ! -L "$root" && ! -L "$root/keyrings" && ! -L "$root/sources.list.d" ]] || return 1
    key="$root/keyrings/lemper-$family.gpg"
    [[ "$family" != mongodb ]] || key="$root/keyrings/lemper-mongodb-${MONGODB_VERSION:-6.0}.gpg"
    # Render every matching source before mutation so an unsafe later stanza
    # cannot leave a partially migrated repository family.
    for file in "$root/sources.list" "$root/sources.list.d/"*.list "$root/sources.list.d/"*.sources; do
        [[ -f "$file" ]] || continue
        [[ ! -L "$file" ]] || return 1
        if [[ "$family" == mongodb ]]; then
            local line word words=()
            while IFS= read -r line; do
                read -r -a words <<<"$line"
                for word in "${words[@]}"; do
                    [[ "$word" != \#* ]] || break
                    if [[ "$word" == */mongodb-org/* && "${word##*/}" != "${MONGODB_VERSION:-6.0}" ]]; then
                        error "MongoDB sources select another major version; reconcile the upgrade before key migration."
                        return 1
                    fi
                done
            done <"$file"
        fi
        lemper_apt_scope_file "$file" "$family" "$key" >/dev/null || return 1
    done
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would prepare scoped $family repository for $suite."
        return 0
    fi
    lemper_exec install -d -m0755 "$root/keyrings" "$root/sources.list.d" || return 1
    lemper_apt_install_key "$key_url" "$key" "$fingerprint" || return 1
    lemper_apt_scope_sources "$family" "$key" || return 1
    if ! lemper_apt_has_source "$family"; then
        lemper_apt_write_source "$root/sources.list.d/lemper-$family.list" "deb [signed-by=$key] $repo $suite $component" || return 1
    fi
    local legacy
    # Retire only verifiably dedicated legacy PPA/global keys; mixed or still
    # referenced keyrings stay intact for administrator review.
    for legacy in "$root/trusted.gpg.d/$family.gpg" "$root/trusted.gpg.d/$family-ubuntu-ppa.gpg" \
        "$root/trusted.gpg.d/longsleep-ubuntu-golang-backports.gpg"; do
        [[ -f "$legacy" ]] || continue
        [[ "$legacy" != *longsleep* || "$family" == golang ]] || continue
        if ! lemper_apt_retire_key "$legacy" "$key"; then warning "Retained legacy keyring requiring review: $legacy"; fi
    done
}
