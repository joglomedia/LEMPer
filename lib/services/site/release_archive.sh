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

# GNU tar/unzip are only allowed to write after a complete path/type audit.
function lemper_site_archive_path() {
    local name="$1" part canonical=""
    local parts=()
    [[ -n "$name" && "$name" != /* && "$name" != *\\* && ! "$name" =~ [[:cntrl:]] && "/$name/" != */../* ]] || return 1
    # Canonicalize dot components without filesystem lookups or subprocesses.
    IFS=/ read -r -a parts <<<"$name"
    for part in "${parts[@]}"; do
        [[ -n "$part" && "$part" != . ]] || continue
        canonical+="/$part"
    done
    printf '%s\n' "${canonical:-/}"
}
function lemper_site_release_unpack() (
    local kind="$1" archive="$2" destination="$3" prefix="$4" option="${5:-}" work line mode size name link canonical base root="" count=0 total=0 source selected
    local _ executable=() regular=()
    local -A types=() sizes=() modes=() links=() originals=() aliases=() seen=()
    # Ambient archive-tool options must not add extraction actions or rewrites.
    unset TAR_OPTIONS UNZIP UNZIPOPT ZIPINFO ZIPINFOOPT
    [[ $# == 4 || ($# == 5 && "$option" == internal-files && "$prefix" == nextcloud && "$kind" == tar) ]] || return 1
    [[ "$kind" == tar || "$kind" == zip ]] || return 1
    [[ -d "$destination" && ! -L "$destination" && -z "$(find "$destination" -mindepth 1 -print -quit)" ]] || return 1
    archive=$(realpath -e -- "$archive") && destination=$(realpath -e -- "$destination") || return 1
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    mkdir "$work/raw" || return 1
    if [[ "$kind" == tar ]]; then
        LC_ALL=C tar -tvf "$archive" --numeric-owner --full-time --quoting-style=escape >"$work/list" 2>"$work/errors" || return 1
        # GNU tar can strip absolute prefixes while listing; warnings invalidate it.
        [[ ! -s "$work/errors" ]] || return 1
    else
        LC_ALL=C zipinfo -l "$archive" >"$work/list" 2>"$work/errors" || return 1
        [[ ! -s "$work/errors" ]] || return 1
    fi
    while IFS= read -r line; do
        link=""
        if [[ "$kind" == tar ]]; then
            read -r mode _ size _ _ name <<<"$line"
            [[ "${#mode}" == 10 && "$size" =~ ^[0-9]+$ ]] || return 1
            case "${mode:0:1}" in
                l)
                    [[ "$name" == *' -> '* ]] || return 1
                    link="${name#* -> }"
                    name="${name%% -> *}"
                    ;;
                h)
                    [[ "$name" == *' link to '* ]] || return 1
                    link="${name#* link to }"
                    name="${name%% link to *}"
                    ;;
                - | d) ;;
                *) return 1 ;;
            esac
        else
            # zipinfo has two header lines and one summary; data starts with a mode.
            # FAT/DOS packages use seven-character modes (e.g. -rw-a--).
            [[ "$line" =~ ^[-dlcbps?][^[:space:]]{5,10}[[:space:]] ]] || continue
            read -r mode _ _ size _ _ _ _ _ name <<<"$line"
            [[ "$size" =~ ^[0-9]+$ && ("${mode:0:1}" == - || "${mode:0:1}" == d) ]] || return 1
            # ZIP directory identity is the trailing slash, including archives
            # whose DOS attributes omit the directory bit (MyBB releases).
            [[ "$name" != */ ]] || mode="d${mode:1}"
            # Newlines cannot hide entries in the line-oriented manifest.
            [[ "$name" != *'^'* ]] || return 1
        fi
        canonical=$(lemper_site_archive_path "$name") || return 1
        canonical="${canonical#/}"
        [[ -n "$canonical" ]] || {
            [[ "${mode:0:1}" == d ]] && continue
            return 1
        }
        [[ -z "${types[$canonical]:-}" ]] || return 1
        [[ ${#size} -le 10 ]] && ((size <= 2147483648)) || return 1
        count=$((count + 1)) total=$((total + size))
        ((count <= 100000 && total <= 2147483648)) || return 1
        types["$canonical"]="${mode:0:1}" sizes["$canonical"]="$size" modes["$canonical"]="$mode" originals["$canonical"]="$name"
        [[ -z "$link" ]] || links["$canonical"]="$link"
        base="${canonical%%/*}"
        case "$prefix" in
            github:*)
                [[ "$base" == "${prefix#github:}"-* && "${base#"${prefix#github:}"-}" =~ ^[a-f0-9]{7,40}$ ]] || return 1
                [[ -z "$root" || "$root" == "$base" ]] || return 1
                root="$base"
                ;;
            only:*) root="${prefix#only:}" ;;
            -) ;;
            *)
                [[ "$base" == "$prefix" ]] || return 1
                root="$prefix"
                ;;
        esac
    done <"$work/list"
    ((count > 0)) || return 1
    if [[ "$kind" == zip ]]; then
        # Cross-check names independently, including control characters/unparsed rows.
        LC_ALL=C zipinfo -1 "$archive" >"$work/names" || return 1
        count=0
        while IFS= read -r name; do
            canonical=$(lemper_site_archive_path "$name") || return 1
            canonical="${canonical#/}"
            [[ -n "$canonical" && -n "${types[$canonical]:-}" ]] || return 1
            count=$((count + 1))
        done <"$work/names"
        ((count == ${#types[@]})) || return 1
    fi
    for canonical in "${!types[@]}"; do
        # An ancestor file/link would redirect later writes or break extraction.
        base="$canonical"
        while [[ "$base" == */* ]]; do
            base="${base%/*}"
            [[ -z "${types[$base]:-}" || "${types[$base]}" == d ]] || return 1
        done
        [[ "${types[$canonical]}" != [lh] ]] || {
            [[ "$option" == internal-files && "$root" == nextcloud ]] || return 1
            source="$canonical"
            seen=()
            while [[ "${types[$source]:-}" == [lh] ]]; do
                [[ -z "${seen[$source]:-}" ]] || return 1
                seen["$source"]=1
                link="${links[$source]}"
                [[ "$link" != /* && "$link" != *\\* && ! "$link" =~ [[:cntrl:]] ]] || return 1
                base=""
                [[ "${types[$source]}" != l ]] || base="${source%/*}/"
                source=$(realpath -ms -- "/$base$link") || return 1
                source="${source#/}"
                [[ "$source" == nextcloud/* && -n "${types[$source]:-}" ]] || return 1
            done
            [[ "${types[$source]}" == - ]] || return 1
            aliases["$canonical"]="$source"
            total=$((total + sizes[$source]))
            ((total <= 2147483648)) || return 1
        }
    done
    # All selected tar entries are regular files/directories; never extract links.
    if [[ "$kind" == tar ]]; then
        for canonical in "${!types[@]}"; do
            [[ "${types[$canonical]}" != [lh] ]] || continue
            [[ "$prefix" != only:* || "$canonical" == "$root" || "$canonical" == "$root/"* ]] || continue
            printf '%s\0' "${originals[$canonical]}" >>"$work/selected"
        done
        [[ -s "$work/selected" ]] || return 1
        tar -xf "$archive" -C "$work/raw" --no-same-owner --no-same-permissions --keep-old-files \
            --delay-directory-restore --no-recursion --null --verbatim-files-from \
            -T "$work/selected" 2>"$work/errors" || return 1
        for canonical in "${!aliases[@]}"; do
            source="${aliases[$canonical]}"
            [[ -f "$work/raw/$source" && ! -L "$work/raw/$source" && ! -e "$work/raw/$canonical" ]] || return 1
            mkdir -p -- "$(dirname "$work/raw/$canonical")" || return 1
            cp -- "$work/raw/$source" "$work/raw/$canonical" || return 1
            modes["$canonical"]="${modes[$source]}"
        done
    else
        unzip -qq "$archive" -d "$work/raw" || return 1
    fi
    for canonical in "${!types[@]}"; do
        [[ -e "$work/raw/$canonical" ]] || continue
        [[ ! -d "$work/raw/$canonical" ]] || continue
        if [[ "${modes[$canonical]}" == *[xst]* ]]; then
            executable+=("$work/raw/$canonical")
        else regular+=("$work/raw/$canonical"); fi
        if ((${#executable[@]} >= 500)); then
            chmod 0755 -- "${executable[@]}" || return 1
            executable=()
        fi
        if ((${#regular[@]} >= 500)); then
            chmod 0644 -- "${regular[@]}" || return 1
            regular=()
        fi
    done
    [[ ${#executable[@]} == 0 ]] || chmod 0755 -- "${executable[@]}" || return 1
    [[ ${#regular[@]} == 0 ]] || chmod 0644 -- "${regular[@]}" || return 1
    find "$work/raw" -type d -exec chmod 0755 {} + || return 1
    selected="$work/raw"
    [[ -z "$root" ]] || selected="$selected/$root"
    [[ -d "$selected" ]] || return 1
    cp -a -- "$selected/." "$destination/"
)
