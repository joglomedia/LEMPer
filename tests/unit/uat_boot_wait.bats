#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
    source "$REAL_BASE_DIR/tests/uat/helpers.bash"
    export UAT_BOOT_STATE=running UAT_WAIT_STATUS=0 UAT_BOOT_POLLS=0
    export UAT_BOOT_SEQUENCE=false
    timeout() {
        [[ "$*" == '5 systemctl is-system-running' ]] || return 2
        printf 'poll\n' >> "$TEST_TMPDIR/boot-order"
        [[ "$UAT_WAIT_STATUS" -eq 0 ]] || return "$UAT_WAIT_STATUS"
        systemctl is-system-running
    }
    systemctl() {
        [[ "$*" == is-system-running && -f "$TEST_TMPDIR/boot-order" ]] || return 2
        if [[ "$UAT_BOOT_SEQUENCE" == true && "$UAT_BOOT_POLLS" -lt 2 ]]; then
            [[ "$UAT_BOOT_POLLS" -ne 0 ]] || return 1
            printf 'starting\n'
            return 1
        fi
        printf '%s\n' "$UAT_BOOT_STATE"
        [[ "$UAT_BOOT_STATE" == running ]]
    }
    sleep() {
        UAT_BOOT_POLLS=$((UAT_BOOT_POLLS + 1))
        [[ "$UAT_BOOT_POLLS" -lt 3 ]] || SECONDS=$((SECONDS + 60))
    }
}

@test "UAT polls until the system bus exists and systemd completes boot" {
    export UAT_BOOT_SEQUENCE=true
    run uat_wait_systemd
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_TMPDIR/boot-order")" -eq 3 ]
}

@test "UAT accepts completed degraded boot despite systemctl nonzero status" {
    export UAT_BOOT_STATE=degraded
    run uat_wait_systemd
    [ "$status" -eq 0 ]
}

@test "UAT rejects timed-out or unavailable systemd before fixture preparation" {
    local state
    for state in starting initializing offline unknown ''; do
        export UAT_BOOT_STATE="$state"
        SECONDS=0
        run uat_wait_systemd
        [ "$status" -ne 0 ]
        [[ "$output" == *'initialization did not complete'* ]]
    done
    export UAT_WAIT_STATUS=124 UAT_BOOT_STATE=running
    SECONDS=0
    run uat_wait_systemd
    [ "$status" -ne 0 ]
}
