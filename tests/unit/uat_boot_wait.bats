#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
    source "$REAL_BASE_DIR/tests/uat/helpers.bash"
    export UAT_BOOT_STATE=running UAT_WAIT_STATUS=0
    timeout() {
        [[ "$*" == '60 systemctl is-system-running --wait' ]] || return 2
        printf 'wait\n' > "$TEST_TMPDIR/boot-order"
        return "$UAT_WAIT_STATUS"
    }
    systemctl() {
        [[ "$*" == is-system-running && -f "$TEST_TMPDIR/boot-order" ]] || return 2
        printf '%s\n' "$UAT_BOOT_STATE"
        [[ "$UAT_BOOT_STATE" == running ]]
    }
}

@test "UAT waits for systemd before accepting a running fixture" {
    run uat_wait_systemd
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/boot-order" ]
}

@test "UAT accepts completed degraded boot despite systemctl nonzero status" {
    export UAT_BOOT_STATE=degraded UAT_WAIT_STATUS=1
    run uat_wait_systemd
    [ "$status" -eq 0 ]
}

@test "UAT rejects timed-out or unavailable systemd before fixture preparation" {
    export UAT_WAIT_STATUS=124
    local state
    for state in starting initializing offline unknown ''; do
        export UAT_BOOT_STATE="$state"
        run uat_wait_systemd
        [ "$status" -ne 0 ]
        [[ "$output" == *'initialization did not complete'* ]]
    done
}
