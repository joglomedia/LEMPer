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

# Read metadata as data; download hosts are constrained to official providers.
function lemper_site_release_metadata() (
    local application="$1" metadata="$2" expected_tag="${3:-}" repository tag version name kind prefix url digest value normalized
    if [[ "$application" == ojs ]]; then
        # PKP publishes this fixed relative DTD declaration. Remove it without
        # loading it; all other DTD/entity declarations remain forbidden.
        if grep -Eiq '<!DOCTYPE' "$metadata"; then
            normalized=$(mktemp) || return 1
            trap 'rm -f -- "$normalized"' EXIT
            sed '\@^<!DOCTYPE version SYSTEM "\.\./\.\./lib/pkp/dtd/version\.dtd">$@d' "$metadata" >"$normalized" || return 1
            metadata="$normalized"
        fi
        ! grep -Eiq '<!DOCTYPE|<!ENTITY' "$metadata" || return 1
        [[ "$(xmllint --nonet --xpath 'count(/version/application) + count(/version/release) + count(/version/package)' "$metadata" 2>/dev/null)" == 3 ]] || return 1
        [[ "$(xmllint --nonet --xpath 'string(/version/application)' "$metadata" 2>/dev/null)" == ojs2 ]] || return 1
        value=$(xmllint --nonet --xpath 'string(/version/release)' "$metadata" 2>/dev/null) || return 1
        [[ "$value" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
        version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}-${BASH_REMATCH[4]}"
        url="https://pkp.sfu.ca/ojs/download/ojs-$version.tar.gz"
        [[ "$(xmllint --nonet --xpath 'string(/version/package)' "$metadata" 2>/dev/null)" == "$url" ]] || return 1
        printf '%s|%s|https|tar|ojs-%s\n' "$version" "$url" "$version"
        return
    fi
    case "$application" in
        mautic) repository=mautic/mautic ;;
        roundcube) repository=roundcube/roundcubemail ;;
        snappymail) repository=the-djmaze/snappymail ;;
        nextcloud) repository=nextcloud-releases/server ;;
        nextcloud-tag) repository=nextcloud/server ;;
        mybb) repository=mybb/mybb ;;
        phplist) repository=phpList/phplist3 ;;
        slim) repository=slimphp/Slim-Skeleton ;;
        *) return 1 ;;
    esac
    tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name | strings' "$metadata" 2>/dev/null) || return 1
    if [[ "$application" == mybb ]]; then
        [[ "$tag" =~ ^mybb_18[0-9]+$ ]] || return 1
        version="1.8.${tag:7}"
    else
        [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
        version="${tag#v}"
    fi
    if [[ "$application" == nextcloud-tag ]]; then
        printf '%s\n' "$tag"
        return
    fi
    [[ -z "$expected_tag" || "$tag" == "$expected_tag" ]] || return 1
    if [[ "$application" == phplist || "$application" == slim ]]; then
        url="https://api.github.com/repos/$repository/tarball/$tag"
        jq -e --arg url "$url" '.tarball_url == $url' "$metadata" >/dev/null 2>&1 || return 1
        printf '%s|%s|https|tar|github:%s\n' "$version" "$url" "${repository/\//-}"
        return
    fi
    case "$application" in
        mautic) name="$version.zip" kind=zip prefix=- ;;
        roundcube) name="roundcubemail-$version-complete.tar.gz" kind=tar prefix="roundcubemail-$version" ;;
        snappymail) name="snappymail-$version.tar.gz" kind=tar prefix=- ;;
        nextcloud) name="nextcloud-$version.tar.bz2" kind=tar prefix=nextcloud ;;
        mybb) name="$tag.zip" kind=zip prefix=only:Upload ;;
    esac
    url="https://github.com/$repository/releases/download/$tag/$name"
    digest=$(jq -er --arg name "$name" --arg url "$url" '
        .assets | arrays | map(select(type == "object" and .name == $name)) |
        select(length == 1) | .[0] |
        select(.browser_download_url == $url and ((has("state")|not) or .state == "uploaded")) |
        .digest | strings | select(test("^sha256:[a-fA-F0-9]{64}$")) | .[7:] | ascii_downcase
    ' "$metadata" 2>/dev/null) || return 1
    printf '%s|%s|%s|%s|%s\n' "$version" "$url" "$digest" "$kind" "$prefix"
)
