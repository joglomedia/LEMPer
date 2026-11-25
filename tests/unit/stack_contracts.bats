#!/usr/bin/env bats
setup() { export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."; }
stack_child='
    requires_root() { :; }
    PROG_NAME=lemper-cli
    PROG_VERSION=test
    . "${REAL_BASE_DIR}/lib/lemper-stack.sh" --help >/dev/null
    DRYRUN=false
    dpkg-query() { printf "php8.4-fpm\tinstall ok installed\n"; }
    lemper_exec() { printf "<%s>\n" "$@"; }
    systemctl() { printf "<%s>\n" "$@"; }
'
@test "stack rejects unknown services and absent PHP instances before system control" {
    run bash -c "${stack_child}"' init_lemper_stack restart ../../etc'
    [ "${status}" -ne 0 ]
    run bash -c "${stack_child}"' dpkg-query() { :; }; init_lemper_stack restart php'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"No installed PHP fpm instances"* ]]
}
@test "stack PHP control uses the selected unit and validates its FPM config" {
    run bash -c "${stack_child}"'
        php-fpm8.4() { [ "$1" = -t ]; }
        init_lemper_stack restart php --php-version 8.4
    '
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"<php8.4-fpm>"* ]]
}
@test "stack dry-run does not source any component installer" {
    run bash -c "${stack_child}"'
        stack_run_component() { [ "${DRYRUN}" = true ]; }
        init_lemper_stack install nginx --dry-run --source-dir "${REAL_BASE_DIR}"
    '
    [ "${status}" -eq 0 ]
}
@test "stack status uses a non-paging systemctl invocation" {
    run bash -c "${stack_child}"' init_lemper_stack status valkey'
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"<--no-pager>"* ]]
    [[ "${output}" == *"<valkey-server>"* ]]
}
@test "stack refuses a pre-existing service removal without explicit force" {
    run bash -c "${stack_child}"' init_lemper_stack remove nginx --yes --source-dir "${REAL_BASE_DIR}"'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"provisioning marker"* ]]
}
