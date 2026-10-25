#!/usr/bin/env bats
##
# Unit tests for the PHP2Shell updater helpers (lib/lemper-update.sh) and
# the legacy bootstrap wiring (update.sh, CLI help, installer).
#
# Helpers run in a child shell so the plugin's top-level constants resolve
# from the test environment and the Bats `run` helper stays available.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export LEMPER_UPDATE_LIB_ONLY=true
    export PHP_ETC_DIR="${BATS_TEST_TMPDIR}/etc/php"
    export LEMPER_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
    export LEMPER_UPDATE_SOURCE_FILE="${BATS_TEST_TMPDIR}/update-source"
    export LEMPER_LOG_DIR="${BATS_TEST_TMPDIR}/log"

    mkdir -p "${PHP_ETC_DIR}" "${LEMPER_BACKUP_DIR}"
}

# shellcheck disable=SC2016 # Expansions must stay literal in the child shell.
load_update_lib='
    requires_root() { :; }
    PROG_NAME="lemper-cli"
    LEMPER_UPDATE_LIB_ONLY=true
    . "${REAL_BASE_DIR}/lib/lemper-update.sh"
    version_ge_out() { if version_ge "$1" "$2"; then echo true; else echo false; fi; }
'

run_lib() {
    bash -c "${load_update_lib}"' "$@"' _ "$@"
}

@test "version_ge matches upstream fixed releases and strips Debian suffixes" {
    run run_lib version_ge_out "8.2.35" "8.2.35"
    [ "${output}" = "true" ]

    run run_lib version_ge_out "8.2.35-1+deb12u1" "8.2.35"
    [ "${output}" = "true" ]

    run run_lib version_ge_out "1:8.3.36-1" "8.3.36"
    [ "${output}" = "true" ]

    run run_lib version_ge_out "8.4.26" "8.4.27"
    [ "${output}" = "false" ]

    run run_lib version_ge_out "" "8.4.27"
    [ "${output}" = "false" ]
}

@test "php_fixed_version maps supported branches and rejects EOL ones" {
    run run_lib php_fixed_version 8.2
    [ "${output}" = "8.2.35" ]

    run run_lib php_fixed_version 8.3
    [ "${output}" = "8.3.36" ]

    run run_lib php_fixed_version 8.4
    [ "${output}" = "8.4.27" ]

    run run_lib php_fixed_version 8.5
    [ "${output}" = "8.5.12" ]

    run run_lib php_fixed_version 8.1
    [ "${status}" -ne 0 ]
}

@test "php_branch_state classifies patched, vulnerable, and EOL branches" {
    run run_lib php_branch_state 8.4 "8.4.27-1+deb12u1"
    [ "${output}" = "patched" ]

    run run_lib php_branch_state 8.4 "8.4.26"
    [ "${output}" = "vulnerable" ]

    run run_lib php_branch_state 8.1 "8.1.33"
    [ "${output}" = "eol" ]

    run run_lib php_branch_state 8.4 ""
    [ "${output}" = "unknown" ]
}

@test "php_installed_branches discovers branches from the PHP etc tree" {
    mkdir -p "${PHP_ETC_DIR}/8.2/fpm/pool.d" "${PHP_ETC_DIR}/8.4/fpm/pool.d"

    run run_lib php_installed_branches
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"8.2"* ]]
    [[ "${output}" == *"8.4"* ]]
}

@test "php_mitigate_pool_file locks down PHP2Shell vectors idempotently" {
    local pool="${BATS_TEST_TMPDIR}/www.conf"
    cat > "${pool}" <<'EOF'
php_value[memory_limit] = 256M
php_flag[session.upload_progress.enabled] = 1
php_admin_value[post_max_size] = 64M
EOF

    run run_lib php_mitigate_pool_file "${pool}" 8.4
    [ "${status}" -eq 0 ]

    grep -qx 'php_admin_value\[memory_limit\] = -1' "${pool}"
    grep -qx 'php_admin_value\[post_max_size\] = 32M' "${pool}"
    grep -qx 'php_admin_flag\[session\.upload_progress\.enabled\] = 0' "${pool}"
    [ "$(grep -c 'php_admin_value\[memory_limit\]' "${pool}")" -eq 1 ]
    [ "$(grep -c 'LEMPer PHP2Shell mitigation' "${pool}")" -eq 1 ]

    run run_lib php_mitigation_present "${pool}"
    [ "${status}" -eq 0 ]

    # A second run must not duplicate directives or the marker.
    run run_lib php_mitigate_pool_file "${pool}" 8.4
    [ "$(grep -c 'php_admin_value\[memory_limit\]' "${pool}")" -eq 1 ]
    [ "$(grep -c 'LEMPer PHP2Shell mitigation' "${pool}")" -eq 1 ]
}

@test "php_mitigate_pool_file adds the PHP 8.5 fatal backtrace control" {
    local pool="${BATS_TEST_TMPDIR}/fpm85.conf"
    printf 'pm = dynamic\n' > "${pool}"

    run run_lib php_mitigate_pool_file "${pool}" 8.5
    [ "${status}" -eq 0 ]
    grep -qx 'php_admin_flag\[fatal_error_backtraces\] = 0' "${pool}"
}

@test "php_pool_count reports total and mitigated pools" {
    mkdir -p "${PHP_ETC_DIR}/8.2/fpm/pool.d"
    printf 'pm = dynamic\n' > "${PHP_ETC_DIR}/8.2/fpm/pool.d/www.conf"
    printf 'pm = dynamic\n' > "${PHP_ETC_DIR}/8.2/fpm/pool.d/site.conf"

    run run_lib php_pool_count 8.2
    [ "${output}" = "2" ]

    run run_lib php_mitigate_pool_file "${PHP_ETC_DIR}/8.2/fpm/pool.d/site.conf" 8.2

    run run_lib php_pool_count 8.2
    [ "${output}" = "2" ]

    run run_lib php_pool_count 8.2 true
    [ "${output}" = "1" ]
}

@test "update.sh exposes install-only, check, and help modes" {
    [ -x "${REAL_BASE_DIR}/update.sh" ]

    run grep -q -- '--install-only' "${REAL_BASE_DIR}/update.sh"
    [ "${status}" -eq 0 ]

    run grep -q -- '--check' "${REAL_BASE_DIR}/update.sh"
    [ "${status}" -eq 0 ]

    run grep -q 'UPDATE_SUBCOMMAND="all"' "${REAL_BASE_DIR}/update.sh"
    [ "${status}" -eq 0 ]
}

@test "installer ships the update plugin and records the source checkout" {
    run grep -q 'lib/lemper-update.sh /etc/lemper/cli-plugins/lemper-update' \
        "${REAL_BASE_DIR}/scripts/install_tools.sh"
    [ "${status}" -eq 0 ]

    run grep -q '/etc/lemper/update-source' "${REAL_BASE_DIR}/scripts/install_tools.sh"
    [ "${status}" -eq 0 ]
}

@test "CLI help documents the update command as a nested subcommand" {
    run grep -q 'help_subentry all "Run every update step\."' \
        "${REAL_BASE_DIR}/bin/lemper-cli.sh"
    [ "${status}" -eq 0 ]
}

@test "update_check aligns the PHP status table columns" {
    run bash -c '
        requires_root() { :; }
        PROG_NAME="lemper-cli"
        LEMPER_UPDATE_LIB_ONLY=true
        . "${REAL_BASE_DIR}/lib/lemper-update.sh"
        php_installed_branches() { echo "8.2"; }
        php_package_version() { echo "8.2.34-1+ubuntu22.04.1+deb.sury.org+1"; }
        php_branch_state() { echo "vulnerable"; }
        php_fixed_version() { echo "8.2.35"; }
        php_pool_count() { if [ "${2:-}" = "true" ]; then echo "0"; else echo "2"; fi; }
        update_check
    '
    [ "${status}" -eq 1 ]

    local header row
    header=$(printf '%s\n' "${output}" | grep '^  Branch')
    row=$(printf '%s\n' "${output}" | grep '^  php8.2')
    [ -n "${header}" ]
    [ -n "${row}" ]

    [ "$(printf '%s' "${header}" | awk '{ print index($0, "State") }')" \
        -eq "$(printf '%s' "${row}" | awk '{ print index($0, "vulnerable") }')" ]
    [ "$(printf '%s' "${header}" | awk '{ print index($0, "Fixed") }')" \
        -eq "$(printf '%s' "${row}" | awk '{ print index($0, "8.2.35") }')" ]
    [ "$(printf '%s' "${header}" | awk '{ print index($0, "Pools") }')" \
        -eq "$(printf '%s' "${row}" | awk '{ print index($0, "2 (0)") }')" ]
}
