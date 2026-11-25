# Explicit test instrumentation, loaded only by scripts/test_coverage.sh.
# DEBUG metadata contains paths and function names, never arguments/commands.
if [[ -n "${LEMPER_COVERAGE_SOURCE:-}" ]]; then
    set -T
    trap 'case "${BASH_SOURCE[0]:-}" in */lib/*.sh) printf "%s\t%s\n" "${BASH_SOURCE[0]}" "${FUNCNAME[0]:-}" >&19 ;; esac' DEBUG
fi
