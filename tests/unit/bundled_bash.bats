#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child programs and literal hostile fixtures.
load env_helper
setup() {
    unit_setup
    mkdir -p "$TEST_TMPDIR/pure/etc/pure-ftpd/conf" "$TEST_TMPDIR/pure/etc/pure-ftpd/auth"
}
@test "Pure-FTPd Bash wrapper keeps ordered authentication, TLS and pair options" {
    printf yes >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/PAMAuthentication"
    printf no >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/UnixAuthentication"
    printf 3 >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/TLS"
    printf '30000 40000' >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/PassivePortRange"
    printf '077 027' >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/Umask"
    ln -s ../conf/PAMAuthentication "$TEST_TMPDIR/pure/etc/pure-ftpd/auth/10pam"
    ln -s ../conf/UnixAuthentication "$TEST_TMPDIR/pure/etc/pure-ftpd/auth/20unix"
    run env LEMPER_PUREFTPD_ROOT="$TEST_TMPDIR/pure" bash "$REAL_BASE_DIR/sbin/pure-ftpd-wrapper" --show-options
    [ "$status" -eq 0 ]
    [[ "$output" == *'-l pam'* && "$output" != *'-l unix'* && "$output" == *'-Y 3'* && "$output" == *'-p 30000:40000'* && "$output" == *'-U 077:027'* ]]
    printf 'not-a-number' >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/TLS"
    run env LEMPER_PUREFTPD_ROOT="$TEST_TMPDIR/pure" bash "$REAL_BASE_DIR/sbin/pure-ftpd-wrapper" --show-options
    [ "$status" -ne 0 ]
}
@test "Pure-FTPd wrapper passes filename values as one literal daemon argument" {
    printf database >"$TEST_TMPDIR/database with space"
    printf '%s' "$TEST_TMPDIR/database with space" >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/PureDB"
    ln -s ../conf/PureDB "$TEST_TMPDIR/pure/etc/pure-ftpd/auth/50pure"
    run bash -c '
        . "$REAL_BASE_DIR/sbin/pure-ftpd-wrapper"
        exec() { printf "%s\n" "$@" >"$TEST_TMPDIR/argv"; }
        LEMPER_PUREFTPD_ROOT="$TEST_TMPDIR/pure" pure_wrapper_main
    '
    [ "$status" -eq 0 ]
    grep -Fx "puredb:$TEST_TMPDIR/database with space" "$TEST_TMPDIR/argv"
    printf '$(touch forbidden)' >"$TEST_TMPDIR/pure/etc/pure-ftpd/conf/TLS"
    run env LEMPER_PUREFTPD_ROOT="$TEST_TMPDIR/pure" bash "$REAL_BASE_DIR/sbin/pure-ftpd-wrapper" --show-options
    [ "$status" -ne 0 ] && [ ! -e "$TEST_TMPDIR/forbidden" ]
}
@test "Memcached parser handles quoted values, escaped comments and literal shell syntax" {
    cat >"$TEST_TMPDIR/memcached.conf" <<'CONF'
-d
-m 64 # comment
-u nobody
-P /run/ignored.pid
-l "127.0.0.1"
logfile "/tmp/file with space"
-o literal\#value
CONF
    run bash -c '
        . "$REAL_BASE_DIR/share/memcached/scripts/config.bash"
        memcached_config "$TEST_TMPDIR/memcached.conf" || exit
        [[ "${parameters[*]}" == "-m 64 -u nobody -l 127.0.0.1 -o literal#value" && "$logfile" == "/tmp/file with space" ]] || exit 1
        memcached_words '\''-o "$(touch forbidden)"'\'' || exit
        [[ "${words[1]}" == '\''$(touch forbidden)'\'' ]]
    '
    [ "$status" -eq 0 ] && [ ! -e "$TEST_TMPDIR/forbidden" ]
    printf 'logfile "unterminated\n' >"$TEST_TMPDIR/memcached.conf"
    run bash -c '. "$REAL_BASE_DIR/share/memcached/scripts/config.bash"; memcached_config "$TEST_TMPDIR/memcached.conf"'
    [ "$status" -ne 0 ]
}
@test "systemd Memcached wrapper executes foreground arguments and rejects malformed configuration" {
    printf '%s\n' '-d' '-m 16' '-u nobody' '-P /run/ignored.pid' >"$TEST_TMPDIR/memcached.conf"
    run bash -c '
        . "$REAL_BASE_DIR/share/memcached/scripts/systemd-memcached-wrapper"
        exec() { printf "%s\n" "$@" >"$TEST_TMPDIR/argv"; }
        memcached_systemd_main "$TEST_TMPDIR/memcached.conf"
    '
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$TEST_TMPDIR/argv")" == /usr/bin/memcached ]
    run grep -Eq '^-d$|^-P$|ignored.pid' "$TEST_TMPDIR/argv"
    [ "$status" -eq 1 ]
    printf 'unknown-directive value\n' >"$TEST_TMPDIR/memcached.conf"
    run bash -c '. "$REAL_BASE_DIR/share/memcached/scripts/systemd-memcached-wrapper"; memcached_systemd_main "$TEST_TMPDIR/memcached.conf"'
    [ "$status" -ne 0 ]
}
@test "managed Memcached endpoints isolate Unix users and require explicit SASL for TCP" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/memcached/install.sh"
        templates="$REAL_BASE_DIR/etc/memcached"
        for instance in memcache www-data; do
            lemper_memcached_render_config "$instance" socket "$templates/$instance.conf" 32 > "$TEST_TMPDIR/config" || exit 1
            grep -Fx -- "-s /run/lemper-memcached-$instance/memcached.sock" "$TEST_TMPDIR/config" || exit 1
            for setting in "-p 0" "-U 0" "-a 0700"; do
                grep -Fx -- "$setting" "$TEST_TMPDIR/config" || exit 1
            done
            if grep -Eq "^-l |^-S$" "$TEST_TMPDIR/config"; then exit 1; fi
        done
        lemper_memcached_render_config memcache sasl "$templates/memcache.conf" 32 > "$TEST_TMPDIR/config" || exit 1
        for setting in "-l 127.0.0.1" "-p 11211" "-U 0" "-B binary" "-S"; do
            grep -Fx -- "$setting" "$TEST_TMPDIR/config" || exit 1
        done
        if grep -Eq "^-s |^-p 0" "$TEST_TMPDIR/config"; then exit 1; fi
        ! lemper_memcached_render_config www-data sasl "$templates/www-data.conf" 32
    '
    [ "$status" -eq 0 ]
}
@test "damemtop help is available without Perl, configuration or a running cache" {
    run bash "$REAL_BASE_DIR/share/memcached/scripts/damemtop" --help
    [ "$status" -eq 0 ] && [[ "$output" == *'--once'* ]]
}
