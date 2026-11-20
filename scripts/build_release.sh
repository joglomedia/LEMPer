#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Release Archive Builder                                          |
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


# Build an immutable release from a clean, committed checkout.
set -e -o pipefail
version="${1:-}"
output="${2:-}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ && -n "${output}" ]] ||
    { echo "Usage: build_release.sh VERSION OUTPUT_DIRECTORY" >&2; exit 1; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${root}"
[[ -z "$(git status --porcelain)" ]] || { echo "Release builds require a clean committed checkout." >&2; exit 1; }
declared=$(sed -n 's/.*PROG_VERSION="\([^"]*\)".*/\1/p' bin/lemper-cli.sh | head -1)
[[ "${version}" == "${declared}" ]] || { echo "Release version does not match CLI version." >&2; exit 1; }
grep -qF "## [${version}]" CHANGELOG.md || { echo "Changelog entry is required." >&2; exit 1; }
mkdir -p "${output}"
output=$(cd "${output}" && pwd)
asset="lemper-v${version}.tar.gz"
# gzip -n removes the timestamp so repeated builds produce the same checksum.
git archive --format=tar --prefix="LEMPer-${version}/" HEAD | gzip -n > "${output}/${asset}"
( cd "${output}" && sha256sum "${asset}" > "${asset}.sha256" )
echo "${output}/${asset}"
