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

# Scoped function-entry coverage; traces contain no command arguments.
set -euo pipefail
source_root=$(realpath -e -- "$1")
trace="$2"
output="$3"
declare -A observed=() normalized=()
while IFS=$'\t' read -r filename name extra; do
    [[ -n "$filename" && "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && -z "$extra" ]] || continue
    if [[ -z "${normalized[$filename]:-}" ]]; then
        normalized["$filename"]=$(realpath -m -- "$filename")
    fi
    observed["${normalized[$filename]}:$name"]=1
done <"$trace"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
entered=0 total=0
printf '| File | Function | Entered |\n|---|---|---|\n' >"$work/table"
while IFS= read -r filename || [[ -n "$filename" ]]; do
    [[ -n "$filename" && "$filename" != \#* ]] || continue
    [[ "$filename" != /* && "$filename" != *..* ]] || exit 1
    [[ -f "$source_root/$filename" ]] || {
        echo 'Declared coverage file is missing.' >&2
        exit 1
    }
    while IFS= read -r name; do
        state=false label=no
        if [[ -n "${observed["$source_root/$filename:$name"]:-}" ]]; then
            state=true label=yes
            entered=$((entered + 1))
        fi
        total=$((total + 1))
        jq -nc --arg file "$filename" --arg name "$name" --argjson entered "$state" \
            '{file:$file,function:$name,entered:$entered}' >>"$work/rows"
        printf '| %s | %s | %s |\n' "$filename" "$name" "$label" >>"$work/table"
    done < <(sed -nE 's/^function ([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/p' "$source_root/$filename")
done <"$source_root/tests/coverage_scope.txt"
[[ "$total" != 0 ]] || {
    echo 'No functions in the declared coverage scope' >&2
    exit 1
}
mkdir -p -- "$output"
jq -s --argjson entered "$entered" --argjson total "$total" \
    '{metric:"function entry",entered:$entered,total:$total,functions:.}' "$work/rows" >"$output/functions.json"
summary=$(LC_ALL=C awk -v entered="$entered" -v total="$total" \
    'BEGIN {printf "Scoped function-entry coverage: %d/%d (%.1f%%).",entered,total,100*entered/total}')
{
    printf '%s\n\n' "$summary"
    printf 'This reports function entry during synthetic Bats tests, not line/branch coverage or live installation proof.\n\n'
    cat "$work/table"
} >"$output/functions.md"
printf '%s\n' "$summary"
