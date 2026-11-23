#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }

@test "journal SSH jail works without requiring an auth log file" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        error() { printf "%s\n" "$*" >&2; }
        lemper_fail2ban_ssh_jail systemd 2269
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'backend = systemd'* && "$output" == *'port = ssh,2269'* ]]
    [[ "$output" != *logpath* ]]
}

@test "source SSH jail retains its file backend" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        lemper_fail2ban_ssh_jail auto 22
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'backend = auto'* && "$output" == *'logpath = /var/log/auth.log'* ]]
}

@test "invalid SSH jail backend and ports fail before configuration is emitted" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        error() { :; }
        ! lemper_fail2ban_ssh_jail "systemd;bad" 22 || exit 1
        for port in 0 65536 -1 "22;bad" "" 999999999999999999 $'\''22\n23'\''; do
            ! lemper_fail2ban_ssh_jail systemd "$port" || exit 1
        done
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "repository dry run requests journal bindings without starting or configuring services" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        AUTO_INSTALL=true INSTALL_FAIL2BAN=true FAIL2BAN_INSTALLER=repo DRYRUN=true
        run() { printf "RUN <%s>\n" "$*"; }
        info() { :; }; warning() { :; }
        fail2ban-client() { printf "UNEXPECTED_CLIENT\n"; return 99; }
        init_fail2ban_install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'apt-get install -q -y fail2ban python3-systemd'* ]]
    [[ "$output" != *UNEXPECTED_CLIENT* ]]
}

@test "readiness waits for the daemon rather than trusting a process name" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        calls=0
        fail2ban-client() { calls=$((calls + 1)); ((calls == 3)); }
        sleep() { :; }
        lemper_fail2ban_wait_ready || exit 1
        [[ "$calls" -eq 3 ]]
    '
    [ "$status" -eq 0 ]
}

@test "daemon readiness failure returns an error to the caller" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/security/fail2ban_install.sh"
        fail2ban-client() { return 1; }; sleep() { :; }; error() { :; }
        ! lemper_fail2ban_wait_ready || exit 1
        printf "SURVIVED\n"
    '
    [ "$status" -eq 0 ]
    [ "$output" = SURVIVED ]
}
