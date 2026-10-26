#!/usr/bin/env bats
##
# Unit tests for the TUI plugin entry point.
#
# The CLI sources plugins instead of executing them, so the TUI must start
# when sourced and still handle --help/--version without opening the menu.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TUI_PLUGIN="${REAL_BASE_DIR}/lib/lemper-tui.sh"
}

tui_exec() {
    run env TUI_PLUGIN="${TUI_PLUGIN}" TUI_ARG="${1:-}" bash -c '
        requires_root() { :; }
        error() { echo "ERROR: $*" >&2; }
        info() { echo "$*" >&2; }
        PROG_NAME="lemper-cli"
        PROG_VERSION="test"

        if [[ -n "${TUI_ARG}" ]]; then
            . "${TUI_PLUGIN}" "${TUI_ARG}"
        else
            . "${TUI_PLUGIN}"
        fi
    '
}

@test "tui plugin starts when sourced with --help" {
    tui_exec --help

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: lemper-cli tui"* ]]
}

@test "tui plugin reports its version" {
    tui_exec --version

    [ "${status}" -eq 0 ]
    [ "${output}" = "lemper-cli tui version test" ]
}

@test "tui plugin rejects unknown options" {
    tui_exec --bogus

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Unknown tui option: --bogus"* ]]
    [[ "${output}" == *"Usage: lemper-cli tui"* ]]
}

@test "tui plugin refuses to open without a terminal" {
    tui_exec

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"TUI mode requires an interactive terminal."* ]]
}

@test "tui entry point is not guarded by BASH_SOURCE" {
    # The CLI sources plugins; a BASH_SOURCE guard would silence the TUI.
    run grep -c 'BASH_SOURCE\[0\]' "${TUI_PLUGIN}"
    [ "${output}" -eq 0 ]

    run tail -n 1 "${TUI_PLUGIN}"
    [ "${output}" = 'init_lemper_tui "$@"' ]
}

@test "tui exposes the performance benchmark menu" {
    run grep -q 'function tui_bench' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]

    run grep -q 'Benchmark|Hardware, disk I/O, and network speed' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]

    run grep -q 'tui_cli bench --network' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]
}

@test "tui dispatches commands through the CLI" {
    # Plugins are sourced by lemper-cli and refuse direct execution.
    run grep -c 'CLI_PLUGINS_DIR}/lemper-' "${TUI_PLUGIN}"
    [ "${output}" -eq 0 ]

    run grep -q 'function tui_cli' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]

    run grep -q 'tui_cli site-list --all' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]
}

@test "tui menu exit selection quits" {
    run grep -q '8 | 0)' "${TUI_PLUGIN}"
    [ "${status}" -eq 0 ]
}
