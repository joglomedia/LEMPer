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

# Synthetic tests require root for trusted-directory and OpenSSH fixtures.
set -euo pipefail
[[ "$EUID" == 0 && "$(uname -s)" == Linux ]] || {
    echo 'Run tests as root in a disposable Linux environment; use scripts/test_podman.sh --test.' >&2
    exit 1
}
test_source=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for dependency in bats bc curl git gpg ip jq my_print_defaults nginx quota rsync sshd ssh-keygen visudo tar unzip zip zipinfo xmllint; do
    command -v "$dependency" >/dev/null || {
        echo "Missing test dependency: $dependency" >&2
        exit 1
    }
done
[[ -d /run/sshd ]] || {
    echo 'Run scripts/prepare_tests.sh first (/run/sshd is missing).' >&2
    exit 1
}
test_work=$(mktemp -d "${TMPDIR:-/tmp}/lemper-tests-XXXXXXXX")
trap 'rm -rf -- "$test_work"' EXIT
export BATS_TMPDIR="$test_work" TMPDIR="$test_work" LEMPER_OPERATION_LOCK="$test_work/operation.lock"
export TERM="${TERM:-xterm-256color}"
if [[ "${1:-}" == --coverage ]]; then
    shift
    bash "$test_source/scripts/test_coverage.sh" "$@"
else
    [[ $# != 0 ]] || set -- "$test_source/tests/" "$test_source/tests/unit/"
    bats "$@"
fi
