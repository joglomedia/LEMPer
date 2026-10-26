#!/usr/bin/env bats
##
# Convention tests for LEMPer CLI plugins.
#
# Every command plugin must share the canonical header, declare command
# metadata, refuse direct execution, and expose --help/--version.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
}

plugin_exec() {
    local name="${1}"
    shift
    local plugin="${REAL_BASE_DIR}/lib/lemper-${name}.sh"

    run env PLUGIN="${plugin}" bash -c '
        requires_root() { :; }
        error() { echo "Error: $*" >&2; }
        info() { echo "Info: $*" >&2; }
        warning() { echo "Warning: $*" >&2; }
        success() { echo "Success: $*" >&2; }
        fail() { echo "Error: $*" >&2; exit 1; }
        run() { "$@"; }
        cmd_help() { echo "Usage: ${PROG_NAME} ${CMD_NAME}"; exit 0; }
        cmd_version() { echo "${PROG_NAME} ${CMD_NAME} version ${PROG_VERSION}"; exit 0; }
        create_php_temp_dirs() { :; }
        useradd() { echo "USERADD-CALLED"; }
        PROG_NAME="lemper-cli"
        PROG_VERSION="test"
        DRYRUN=false
        . "${PLUGIN}" "$@"
    ' _ "$@"
}

skip_if_no_gnu_getopt() {
    [[ "$(getopt -o a -l all -- --all 2>/dev/null)" == *"--all --"* ]] || \
        skip "GNU getopt required"
}

command_plugins() {
    printf '%s\n' account adduser backup bench create db fixpermission \
        manage modsec selfssl site site-list site-show tui update
}

@test "every CLI file carries the 2014-2026 copyright banner" {
    local f
    for f in "${REAL_BASE_DIR}"/lib/lemper-*.sh "${REAL_BASE_DIR}/bin/lemper-cli.sh"; do
        run grep -q 'Copyright (c) 2014-2026 MasEDI.Net' "$f"
        [ "${status}" -eq 0 ]

        run grep -q 'GNU General Public License' "$f"
        [ "${status}" -eq 0 ]

        run grep -q 'Authors: Edi Septriyanto' "$f"
        [ "${status}" -eq 0 ]

        run grep -q '2014-2024' "$f"
        [ "${status}" -ne 0 ]
    done
}

@test "plugin header boxes are 77 columns wide" {
    local f
    for f in "${REAL_BASE_DIR}"/lib/lemper-*.sh "${REAL_BASE_DIR}/bin/lemper-cli.sh"; do
        run awk 'NR <= 40 && /^# [|+]/ && length($0) != 77 { print FILENAME ":" NR; bad=1 } END { exit bad }' "$f"
        [ "${status}" -eq 0 ]
    done
}

@test "command plugins declare metadata, a root guard, and an init call" {
    local name f
    while IFS= read -r name; do
        f="${REAL_BASE_DIR}/lib/lemper-${name}.sh"

        run grep -q '^CMD_PARENT=' "$f"
        [ "${status}" -eq 0 ]

        run grep -q '^CMD_NAME=' "$f"
        [ "${status}" -eq 0 ]

        run grep -q 'type -t requires_root' "$f"
        [ "${status}" -eq 0 ]

        run grep -qE "init_lemper_${name//-/_} " "$f"
        [ "${status}" -eq 0 ]
    done < <(command_plugins)
}

@test "every command plugin exposes --help" {
    skip_if_no_gnu_getopt

    local name expected
    while IFS= read -r name; do
        case "${name}" in
            account)       expected="Create a system user account" ;;
            adduser)       expected="Interactively add a system user" ;;
            backup)        expected="configuration backup and restore" ;;
            bench)         expected="Usage: lemper-cli bench" ;;
            create)        expected="Usage: lemper-cli create" ;;
            db)            expected="Usage: lemper-cli db" ;;
            fixpermission) expected="Recursively set directories" ;;
            manage)        expected="lemper-cli manage [OPTION]" ;;
            modsec)        expected="Usage: lemper-cli modsec" ;;
            selfssl)       expected="Generates self-signed SSL certificate" ;;
            site)          expected="Usage: lemper-cli site" ;;
            site-list)     expected="Lists all configured virtual hosts" ;;
            site-show)     expected="Displays the full configuration" ;;
            tui)           expected="Usage: lemper-cli tui" ;;
            update)        expected="patch PHP2Shell" ;;
        esac

        plugin_exec "${name}" --help
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"${expected}"* ]]
    done < <(command_plugins)
}

@test "every command plugin exposes --version" {
    skip_if_no_gnu_getopt

    local name
    while IFS= read -r name; do
        plugin_exec "${name}" --version
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"version test"* ]]
    done < <(command_plugins)
}

@test "account --help does not create a user" {
    skip_if_no_gnu_getopt

    plugin_exec account --help
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"USERADD-CALLED"* ]]
}

@test "adduser --help does not prompt or create a user" {
    skip_if_no_gnu_getopt

    plugin_exec adduser --help
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"Username:"* ]]
    [[ "${output}" != *"USERADD-CALLED"* ]]
}

@test "fixpermission requires a path and refuses system roots" {
    skip_if_no_gnu_getopt

    plugin_exec fixpermission
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"lemper-cli fixpermission <directory>"* ]]

    plugin_exec fixpermission /
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Refusing to change permissions"* ]]

    plugin_exec fixpermission /etc
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Refusing to change permissions"* ]]
}

@test "fixpermission repairs a regular web directory" {
    skip_if_no_gnu_getopt

    local dir="${BATS_TEST_TMPDIR}/webroot"
    mkdir -p "${dir}/uploads"
    touch "${dir}/index.php"

    plugin_exec fixpermission "${dir}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Permissions fixed for"* ]]
}

@test "CLI aliases are wired to the installed site plugins" {
    local f alias
    for f in scripts/install_tools.sh lib/lemper-update.sh; do
        for alias in create add manage mod site-db site-database; do
            run grep -q "lemper-${alias}" "${REAL_BASE_DIR}/${f}"
            [ "${status}" -eq 0 ]
        done
    done
}

@test "encrypt module is library-only" {
    run grep -q 'lemper-encrypt' "${REAL_BASE_DIR}/scripts/install_tools.sh"
    [ "${status}" -ne 0 ]

    run grep -q 'lemper-encrypt:lemper-encrypt' "${REAL_BASE_DIR}/lib/lemper-update.sh"
    [ "${status}" -ne 0 ]

    run grep -q 'library module' "${REAL_BASE_DIR}/lib/lemper-encrypt.sh"
    [ "${status}" -eq 0 ]
}

@test "CLI help describes account and adduser accurately" {
    run grep -q 'help_entry account "Create a system user account."' "${REAL_BASE_DIR}/bin/lemper-cli.sh"
    [ "${status}" -eq 0 ]

    run grep -q "help_entry adduser \"Interactively add a system user.\"" "${REAL_BASE_DIR}/bin/lemper-cli.sh"
    [ "${status}" -eq 0 ]
}
