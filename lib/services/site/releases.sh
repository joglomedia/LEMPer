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

# Resolve GitHub's latest stable distribution once per new installation.
function lemper_site_release_spec() {
    lemper_load_module services/site/release_metadata || return 1
    lemper_site_release_metadata "$@" || {
        error "Unable to resolve a trusted latest distribution; complete GitHub assets require published SHA-256 digests."
        return 1
    }
}
function lemper_site_release_existing() {
    local type="$1" root="$2" receipt
    case "$type" in mautic | roundcube | snappymail | nextcloud | mybb | phplist | ojs | slim) ;; *) return 1 ;; esac
    [[ -f "$root/.lemper-release" && ! -L "$root/.lemper-release" ]] || return 1
    receipt=$(cat "$root/.lemper-release") || return 1
    [[ "$receipt" =~ ^${type}\|([0-9]+\.[0-9]+\.[0-9]+([.-][0-9]+)?)\|[a-f0-9]{64}$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}
function lemper_site_release_repository() {
    case "$1" in
        mautic) echo mautic/mautic ;;
        roundcube) echo roundcube/roundcubemail ;;
        snappymail) echo the-djmaze/snappymail ;;
        nextcloud) echo nextcloud/server ;;
        mybb) echo mybb/mybb ;;
        phplist) echo phpList/phplist3 ;;
        ojs) echo pkp/ojs ;;
        slim) echo slimphp/Slim-Skeleton ;;
        *) return 1 ;;
    esac
}
function lemper_site_release_target() {
    local root="$1" owner="$2" resolved
    [[ "$root" =~ ^/[A-Za-z0-9_./\ -]+$ && ! -L "$root" ]] || return 1
    resolved=$(realpath -m -- "$root") || return 1
    case "$resolved" in
        "/home/$owner/webapps/"* | /srv/*/* | /var/www/* | /opt/*/*) ;;
        *)
            error "Release projects need a dedicated directory under the runtime user's webapps, /srv, /var/www or /opt."
            return 1
            ;;
    esac
    [[ ! -e "$root" ]] || safe_webroot "$root" "$owner" >/dev/null || return 1
}
function lemper_site_release_preflight() {
    local type="$1" root="$2" owner="$3" php="$4" extensions command
    lemper_site_release_repository "$type" >/dev/null || return 1
    [[ "$php" =~ ^8\.[2-5]$ ]] && is_valid_username "$owner" && [[ "$owner" != root ]] || {
        error "Release applications require PHP 8.2-8.5 and a non-root runtime user."
        return 1
    }
    lemper_site_release_target "$root" "$owner" || return 1
    if [[ -d "$root" && -n "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        lemper_site_release_existing "$type" "$root" >/dev/null || {
            error "Release installation requires an empty project directory; existing data is retained."
            return 1
        }
    fi
    [[ "${DRYRUN:-false}" != true ]] || return 0
    for command in curl jq tar unzip zipinfo sha256sum sudo "php$php"; do
        command -v "$command" >/dev/null || {
            error "Missing application deployment prerequisite: $command"
            return 1
        }
    done
    if [[ "$type" == ojs ]]; then
        command -v xmllint >/dev/null || {
            error "OJS deployment requires libxml2-utils (xmllint)."
            return 1
        }
    fi
    getent passwd "$owner" >/dev/null || {
        error "Create the runtime account first."
        return 1
    }
    if [[ "$type" == phplist || "$type" == slim ]]; then
        command -v composer >/dev/null || {
            error "Composer is required for this source distribution."
            return 1
        }
        command -v git >/dev/null || {
            error "Git is required for Composer's source dependencies."
            return 1
        }
    fi
    if [[ "$type" == ojs && -e "$root-files" ]]; then
        [[ ! -L "$root-files" && -d "$root-files" && "$(stat -c %U "$root-files")" == "$owner" ]] || return 1
        [[ -f "$root/.lemper-release" || -z "$(find "$root-files" -mindepth 1 -print -quit)" ]] || {
            error "OJS submission storage already contains data; choose a fresh project."
            return 1
        }
    fi
    case "$type" in
        mautic) extensions=curl,dom,gd,iconv,imap,intl,mbstring,openssl,pdo_mysql,xml,zip,zlib ;;
        roundcube) extensions=ctype,dom,filter,intl,json,mbstring,openssl,pcre,session,sockets ;;
        snappymail) extensions=ctype,curl,dom,fileinfo,intl,mbstring,openssl ;;
        nextcloud) extensions=ctype,curl,dom,fileinfo,gd,intl,json,mbstring,openssl,session,xml,zip ;;
        mybb) extensions=ctype,json,mbstring,mysqli,xml ;;
        phplist) extensions=curl,dom,iconv,mbstring,mysqli,xml ;;
        ojs) extensions=bcmath,curl,dom,fileinfo,gd,intl,mbstring,xml,zip ;;
        slim) extensions=json ;;
    esac
    # shellcheck disable=SC2016 # Fixed PHP program; variables belong to PHP.
    "php$php" -r '
        $missing = array_filter(explode(",", $argv[1]), fn($e) => !extension_loaded($e));
        if (!in_array($argv[2], ["snappymail", "slim", "mybb", "phplist"]) && (!class_exists("PDO") || !PDO::getAvailableDrivers())) $missing[] = "PDO database driver";
        if ($missing) { fwrite(STDERR, "Missing PHP extensions: ".implode(", ", $missing)."\n"); exit(1); }
    ' "$extensions" "$type"
}
function lemper_site_release_permissions() {
    local type="$1" root="$2" owner="$3" path
    local private=()
    case "$type" in
        mautic) private=(app/config config var) ;;
        roundcube) private=(config logs temp) ;;
        snappymail) private=(data) ;;
        nextcloud) private=(config data) ;;
        mybb) private=(inc admin/inc) ;;
        phplist) private=(public_html/lists/config) ;;
        ojs) private=(cache/t_cache cache/t_compile cache/_db) ;;
        slim) private=(logs) ;;
        xenforo) private=(internal_data src library install/data install/templates) ;;
        *) return 1 ;;
    esac
    for path in "${private[@]}"; do
        [[ ! -d "$root/$path" || -L "$root/$path" ]] \
            || lemper_exec sudo -u "$owner" -- chmod -R go-rwx -- "$root/$path" || return 1
    done
    for path in "$root"/.env "$root"/.env.* "$root"/.lemper-release "$root"/.lemper-integrity "$root"/config.inc.php; do
        [[ ! -f "$path" || -L "$path" ]] \
            || lemper_exec sudo -u "$owner" -- chmod 0600 -- "$path" || return 1
    done
}
function lemper_site_release_publish() (
    local project="$1" root="$2" owner="$3" parent staged destination
    local -a publisher=()
    parent=$(dirname -- "$root") || return 1
    if sudo -u "$owner" -- test -w "$parent"; then
        # A hosted account may control this entire path. Keep all mutations in its identity.
        publisher=(sudo -u "$owner" --)
        staged=$("${publisher[@]}" mktemp -d "$parent/.lemper-publish.XXXXXXXX") || return 1
        trap '"${publisher[@]}" rm -rf -- "$staged"' EXIT
        destination="$staged"
    else
        # A site under a protected system directory may need root for the final rename.
        lemper_directory_trusted "$parent" || return 1
        staged=$(mktemp -d "$parent/.lemper-publish.XXXXXXXX") || return 1
        trap 'rm -rf -- "$staged"' EXIT
        destination="$staged/project"
        chgrp -- "$(id -gn "$owner")" "$staged" && chmod 0710 "$staged" || return 1
        install -d -o "$owner" -g "$(id -gn "$owner")" -m0755 "$destination" || return 1
    fi
    sudo -u "$owner" -- cp -a -- "$project/." "$destination/" || return 1
    # Stage beside the destination for a same-filesystem rename, including custom mounts.
    # Only remove an empty target and keep any tree that appears before publication.
    "${publisher[@]}" rmdir -- "$root" || return 1
    "${publisher[@]}" mv -Tn -- "$destination" "$root" || return 1
    [[ ! -e "$destination" ]] || {
        error "Project appeared during publication; existing data is retained."
        return 1
    }
)
function lemper_site_release_install() (
    local type="$1" root="$2" owner="$3" php="$4" domain="${5:-}" version url checksum kind prefix work actual helper repository spec tag integrity=published-sha256 platform
    local extract_options=()
    lemper_site_release_preflight "$type" "$root" "$owner" "$php" || return 1
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would resolve and deploy the latest stable $type complete release."
        return 0
    }
    lemper_load_module services/site/applications || return 1
    if version=$(lemper_site_release_existing "$type" "$root"); then
        lemper_site_application_check_files "$type" "$root" || return 1
        info "Keeping existing $type $version files and configuration."
        return 0
    fi
    [[ -d "$root" && -z "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
        error "Release installation requires an empty project directory; existing data is retained."
        return 1
    }
    lemper_directory_trusted /var/tmp || return 1
    work=$(mktemp -d /var/tmp/lemper-release-XXXXXXXX) || return 1
    trap 'rm -rf -- "$work"' EXIT
    # Extraction and upstream PHP validation run as the hosting account.
    lemper_exec chgrp "$(id -gn "$owner")" "$work" || return 1
    lemper_exec chmod 0710 "$work" || return 1
    lemper_exec install -d -o "$owner" -g "$(id -gn "$owner")" -m0755 "$work/project" || return 1
    repository=$(lemper_site_release_repository "$type") || return 1
    url="https://api.github.com/repos/$repository/releases/latest"
    [[ "$type" != ojs ]] || url=https://pkp.sfu.ca/ojs/xml/ojs-version.xml
    lemper_exec curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 \
        --max-filesize 2097152 -H 'Accept: application/vnd.github+json' \
        -o "$work/release.json" "$url" || return 1
    if [[ "$type" == nextcloud ]]; then
        tag=$(lemper_site_release_spec nextcloud-tag "$work/release.json") || return 1
        lemper_exec curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 \
            --max-filesize 2097152 -o "$work/distribution.json" "https://api.github.com/repos/nextcloud-releases/server/releases/tags/$tag" || return 1
        spec=$(lemper_site_release_spec nextcloud "$work/distribution.json" "$tag") || return 1
    else
        spec=$(lemper_site_release_spec "$type" "$work/release.json") || return 1
    fi
    IFS='|' read -r version url checksum kind prefix <<<"$spec" || return 1
    lemper_exec curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 \
        -o "$work/package" "$url" || return 1
    actual=$(sha256sum "$work/package") || return 1
    if [[ "$checksum" == https ]]; then
        integrity=verified-https
        checksum="${actual%% *}"
    fi
    [[ "${actual%% *}" == "$checksum" ]] || {
        error "Application release checksum mismatch."
        return 1
    }
    lemper_exec chmod 0644 "$work/package" || return 1
    helper=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_archive.sh
    [[ "$type" != nextcloud ]] || extract_options=(internal-files)
    # shellcheck disable=SC2016 # Fixed child shell; values are positional arguments.
    lemper_exec sudo -u "$owner" -- bash -c '. "$1"; shift; lemper_site_release_unpack "$@"' _ "$helper" "$kind" "$work/package" "$work/project" "$prefix" "${extract_options[@]}" || return 1
    if [[ "$type" == phplist || "$type" == slim ]]; then
        lemper_exec sudo -u "$owner" -- "php$php" "$(command -v composer)" install --no-dev --prefer-dist --no-interaction --no-progress \
            --working-dir "$work/project" || return 1
    fi
    if [[ "$type" == ojs ]]; then
        is_valid_domain "$domain" || return 1
        lemper_load_module services/accounts/permissions || return 1
        lemper_site_prepare_directory "$root-files" "$owner" 0700 || return 1
        helper=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_prepare.sh
        # shellcheck disable=SC2016 # Fixed child shell; values are positional arguments.
        lemper_exec sudo -u "$owner" -- bash -c '. "$1"; shift; lemper_site_release_prepare "$@"' _ "$helper" "$work/project" "$root" "$domain" || return 1
    fi
    if [[ "$type" == mybb && ! -e "$work/project/inc/config.php" ]]; then
        lemper_exec sudo -u "$owner" -- cp "$work/project/inc/config.default.php" "$work/project/inc/config.php" || return 1
    fi
    if [[ "$type" == nextcloud ]]; then
        lemper_exec sudo -u "$owner" -- touch "$work/project/.lemper-setup-pending" || return 1
        # Empty public-state marker: Nginx opens it to evaluate the file guard.
        lemper_exec sudo -u "$owner" -- chmod 0644 "$work/project/.lemper-setup-pending" || return 1
    fi
    lemper_site_application_check_files "$type" "$work/project" || return 1
    case "$type" in
        mybb | snappymail) lemper_exec sudo -u "$owner" -- "php$php" -l "$work/project/index.php" >/dev/null || return 1 ;;
        *)
            platform=vendor/composer/platform_check.php
            [[ "$type" != nextcloud ]] || platform=lib/versioncheck.php
            [[ "$type" != ojs ]] || platform=lib/pkp/lib/vendor/composer/platform_check.php
            lemper_exec sudo -u "$owner" -- "php$php" "$work/project/$platform" || return 1
            ;;
    esac
    if [[ "$type" == snappymail ]]; then
        [[ -s "$work/project/snappymail/v/$version/include.php" ]] || return 1
    fi
    printf '%s|%s|%s\n' "$type" "$version" "$checksum" >"$work/receipt" || return 1
    chmod 0644 "$work/receipt" || return 1
    lemper_exec sudo -u "$owner" -- install -m0600 "$work/receipt" "$work/project/.lemper-release" || return 1
    printf '%s\n' "$integrity" >"$work/integrity" || return 1
    chmod 0644 "$work/integrity" || return 1
    lemper_exec sudo -u "$owner" -- install -m0600 "$work/integrity" "$work/project/.lemper-integrity" || return 1
    lemper_site_release_permissions "$type" "$work/project" "$owner" || return 1
    lemper_site_release_publish "$work/project" "$root" "$owner" || return 1
    info "Deployed $type $version complete files. Finish upstream database/admin/mail setup."
)
