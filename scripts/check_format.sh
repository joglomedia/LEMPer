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

# Opt-in formatting keeps historical files stable; add every new module here.
set -euo pipefail
format_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v shfmt >/dev/null || {
    echo 'Install shfmt (CI uses distribution package 3.8).' >&2
    exit 1
}
format_mode=-d
case "${1:---check}" in --check) ;; --write) format_mode=-w ;; *)
    echo 'Usage: check_format.sh [--check|--write]' >&2
    exit 1
    ;;
esac
format_files=()
while IFS= read -r format_file; do
    [[ -z "$format_file" || "$format_file" == \#* ]] && continue
    [[ "$format_file" != /* && "$format_file" != *..* && -f "$format_root/$format_file" ]] || exit 1
    format_files+=("$format_root/$format_file")
done <"$format_root/tools/shfmt-files.txt"
shfmt "$format_mode" -ln bash -i 4 -bn -ci "${format_files[@]}"
