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

# Function-entry coverage from synthetic Bats tests. Never trace command values.
set -euo pipefail
coverage_source=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
coverage_output="${1:-$coverage_source/coverage}"
[[ $# == 0 ]] || shift
coverage_tests=("$@")
[[ ${#coverage_tests[@]} != 0 ]] || coverage_tests=("$coverage_source/tests/" "$coverage_source/tests/unit/")
if ! command -v bats >/dev/null || ! command -v jq >/dev/null; then
    echo 'Coverage requires Bats and jq.' >&2
    exit 1
fi
coverage_work=$(mktemp -d)
trap 'rm -rf "$coverage_work"' EXIT
chmod 0700 "$coverage_work"
exec 19>"$coverage_work/functions.tsv"
coverage_status=0
BASH_ENV="$coverage_source/tests/coverage_hook.bash" LEMPER_COVERAGE_SOURCE="$coverage_source" \
    bats "${coverage_tests[@]}" || coverage_status=$?
exec 19>&-
bash "$coverage_source/tests/report_coverage.sh" "$coverage_source" "$coverage_work/functions.tsv" "$coverage_output"
exit "$coverage_status"
