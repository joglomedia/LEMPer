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

# Official release binaries replace the unavailable historical APT endpoint.
function lemper_bun_install_binary() (
    local version="${BUNJS_VERSION:-latest}" arch asset work checksum tag prefix="${LEMPER_BUN_PREFIX:-}" destination marker selector
    case "$(uname -m)" in aarch64 | arm64) arch=aarch64 ;; x86_64 | amd64) arch=x64 ;; *)
        error "Unsupported Bun binary architecture."
        return 1
        ;;
    esac
    [[ "$version" == latest || "$version" =~ ^(bun-v|v)?[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        error "Invalid Bun release version."
        return 1
    }
    [[ -z "$prefix" || ("$prefix" == /* && "$prefix" != *..* && "$prefix" =~ ^/[A-Za-z0-9_/-]+$) ]] || return 1
    destination="$prefix/opt/bun"
    marker="$prefix/etc/lemper/installed/bun"
    selector="$prefix/usr/local/bin/bun"
    [[ ! -L "$destination" && ! -L "$prefix/opt" && ! -L "$prefix/usr/local/bin" ]] || return 1
    if [[ -d "$destination" && ! -f "$marker" ]]; then
        error "Refusing to replace an unowned Bun installation."
        return 1
    fi
    if [[ (-e "$selector" || -L "$selector") && ! -f "$marker" ]]; then
        error "Refusing to replace an unowned Bun executable."
        return 1
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would install a checksummed official Bun binary for $arch."
        return 0
    fi
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    if [[ "$version" == latest ]]; then
        curl -fsSL --proto '=https' --retry 3 -o "$work/release.json" https://api.github.com/repos/oven-sh/bun/releases/latest || return 1
        tag=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$work/release.json") || return 1
    else
        version="${version#bun-}"
        version="${version#v}"
        tag="bun-v$version"
    fi
    [[ "$tag" =~ ^bun-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    asset="bun-linux-$arch.zip"
    curl -fsSL --proto '=https' --retry 3 -o "$work/$asset" "https://github.com/oven-sh/bun/releases/download/$tag/$asset" || return 1
    curl -fsSL --proto '=https' --retry 3 -o "$work/checksums" "https://github.com/oven-sh/bun/releases/download/$tag/SHASUMS256.txt" || return 1
    checksum=$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset {print $1}' "$work/checksums")
    [[ "$checksum" =~ ^[a-fA-F0-9]{64}$ && "$(sha256sum "$work/$asset" | cut -d ' ' -f1)" == "${checksum,,}" ]] || {
        error "Bun release checksum mismatch."
        return 1
    }
    python3 -I - "$work/$asset" "$asset" "$work/bun" <<'PYTHON'
import sys,zipfile
from pathlib import Path
archive, asset, target = sys.argv[1:]
with zipfile.ZipFile(archive) as release:
    Path(target).write_bytes(release.read(asset[:-4] + '/bun'))
PYTHON
    [[ -s "$work/bun" ]] || return 1
    chmod 0755 "$work/bun" || return 1
    "$work/bun" --version >/dev/null || return 1
    lemper_exec install -d -m0755 "$destination" "$prefix/usr/local/bin" || return 1
    lemper_exec install -d -m0700 "$prefix/etc/lemper/installed" || return 1
    if [[ -f "$destination/bun" ]]; then lemper_exec cp -p "$destination/bun" "$destination/bun.previous" || return 1; fi
    lemper_exec install -m0755 "$work/bun" "$destination/.bun-next" || return 1
    lemper_exec mv -T "$destination/.bun-next" "$destination/bun" || return 1
    lemper_exec ln -sfn "$destination/bun" "$selector" || return 1
    lemper_exec touch "$marker" || return 1
    info "Installed official Bun $tag for $arch."
)
