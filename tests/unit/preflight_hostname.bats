#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
    mkdir -p "$TEST_TMPDIR/build"
}

# Fixed isolated child code. All host mutations and IP lookups are stubbed.
# shellcheck disable=SC2016
preflight_child='
    . "$REAL_BASE_DIR/scripts/utils.sh" || exit 1
    SERVER_HOSTNAME=fixture.test
    SERVER_IP=127.0.0.1
    ENVIRONMENT=development
    BUILD_DIR="$TEST_TMPDIR/build"
    get_ip_private() { printf "127.0.0.1\n"; }
    lemper_update_hosts() {
        [[ "$1" == fixture.test && "$2" == 127.0.0.1 ]] || return 1
        touch "$TEST_TMPDIR/hosts-updated"
    }
    cat() {
        if [[ "$1" == /etc/hostname ]]; then printf "fixture.test\n"
        else command cat "$@"; fi
    }
'

@test "preflight preserves an already configured hostname without mutation privileges" {
    run bash -c "$preflight_child"'
        hostname() { [[ $# == 0 ]] || exit 88; printf "fixture.test\n"; }
        run() { echo UNEXPECTED_MUTATION >&2; exit 88; }
        preflight_system_check || exit 1
        echo PREFLIGHT_OK
    '
    [ "$status" -eq 0 ]
    [ "$output" = PREFLIGHT_OK ]
    [ -f "$TEST_TMPDIR/hosts-updated" ]
}

@test "preflight still requests a changed kernel hostname without rewriting matching persistent data" {
    run bash -c "$preflight_child"'
        hostname() { printf "old.fixture.test\n"; }
        run() {
            [[ "$#" == 2 && "$1" == hostname && "$2" == fixture.test ]] || exit 89
            printf "%s %s\n" "$1" "$2" >"$TEST_TMPDIR/requested"
        }
        preflight_system_check
    '
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/requested")" = 'hostname fixture.test' ]
    [ -f "$TEST_TMPDIR/hosts-updated" ]
}

@test "failed hostname change returns before persistent or hosts updates" {
    run bash -c "$preflight_child"'
        hostname() { printf "old.fixture.test\n"; }
        run() { return 55; }
        preflight_system_check && exit 1
        echo REJECTED
    '
    [ "$status" -eq 0 ]
    [ "$output" = REJECTED ]
    [ ! -f "$TEST_TMPDIR/hosts-updated" ]
}
