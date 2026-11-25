#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    source "$REAL_BASE_DIR/tests/uat/helpers.bash"
}

@test "APT failure diagnostics classify errors without showing log values" {
    cat > "$TEST_TMPDIR/install.log" <<'LOG'
synthetic-secret-must-not-appear
E: Failed to fetch https://synthetic-secret-must-not-appear@example.test/pkg.deb 404 Not Found
E: Unable to locate package synthetic-secret-must-not-appear
LOG
    run uat_apt_failure_summary "$TEST_TMPDIR/install.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *'package not found'* ]]
    [[ "$output" == *'download failed'* ]]
    [[ "$output" == *'HTTP 404'* ]]
    [[ "$output" != *'synthetic-secret'* ]]
    [[ "$output" != *'https:'* ]]
}

@test "successful APT logs do not produce failure diagnostics" {
    printf 'Setting up a fixture package\n' > "$TEST_TMPDIR/install.log"
    run uat_apt_failure_summary "$TEST_TMPDIR/install.log"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
