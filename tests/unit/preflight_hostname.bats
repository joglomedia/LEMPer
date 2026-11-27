#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
    mkdir -m0700 "$TEST_TMPDIR/build"
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

@test "build cleanup is confined to a workspace the installer created" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        umask 077
        mkdir -- "$TEST_TMPDIR/preexisting" || exit 1
        DRYRUN=false
        lemper_build_workspace "$TEST_TMPDIR/preexisting" || exit 1
        lemper_remove_build_workspace "$TEST_TMPDIR/preexisting" || exit 1
        [[ -d "$TEST_TMPDIR/preexisting" ]] || exit 1
        lemper_build_workspace "$TEST_TMPDIR/managed" || exit 1
        [[ "$(stat -c %a -- "$TEST_TMPDIR/managed")" == 700 ]] || exit 1
        lemper_remove_build_workspace "$TEST_TMPDIR/managed" || exit 1
        [[ ! -e "$TEST_TMPDIR/managed" ]]
    '
    [ "$status" -eq 0 ]
}

@test "build workspace rejects mutable directories and symlink paths" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        mkdir -m 0777 -- "$TEST_TMPDIR/mutable" || exit 1
        ln -s -- "$TEST_TMPDIR" "$TEST_TMPDIR/link" || exit 1
        ! lemper_build_workspace "$TEST_TMPDIR/mutable/child" &&
            ! lemper_build_workspace "$TEST_TMPDIR/mutable" &&
            ! lemper_build_workspace "$TEST_TMPDIR/link" &&
            [[ ! -e "$TEST_TMPDIR/mutable/child" ]]
    '
    [ "$status" -eq 0 ]
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
