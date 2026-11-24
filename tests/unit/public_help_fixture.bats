#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }

@test "public help works from a private checkout without opening its ancestors" {
    local sealed="$TEST_TMPDIR/sealed"
    mkdir -m 0700 "$sealed"
    cp -R "$REAL_BASE_DIR/bin" "$REAL_BASE_DIR/lib" "$sealed/"
    printf 'PRIVATE_FIXTURE=must-not-be-read\n' > "$sealed/.env"
    run runuser -u nobody -- bash "$sealed/bin/lemper-cli.sh" --version
    [ "$status" -ne 0 ]
    run test_run_public "$sealed" bin/lemper-cli.sh --version
    [ "$status" -eq 0 ]
    [[ "$output" == *'version 4.0.0'* ]]
    [ "$(stat -c %a "$sealed")" = 700 ]
}

@test "public help fixture excludes private profiles and cleans up its code copy" {
    local source="$TEST_TMPDIR/source"
    mkdir -p "$source/bin" "$source/lib"
    printf 'PRIVATE_FIXTURE=must-not-be-copied\n' > "$source/.env"
    cp "$source/.env" "$source/lib/private.env"
    cat > "$source/install.sh" <<'PROBE'
#!/usr/bin/env bash
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ ! -e "$root/.env" && ! -e "$root/lib/private.env" ]] || exit 1
printf '%s\n' "$root"
PROBE
    run test_run_public "$source" install.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == /var/tmp/lemper-public-* ]]
    [ ! -e "$output" ]
    [ -f "$source/.env" ]
}

@test "bootstrap location diagnostics never record commands or argument values" {
    cat > "$TEST_TMPDIR/probe.sh" <<'PROBE'
#!/usr/bin/env bash
probe() { local password="$1"; printf '%s' "$password" >/dev/null; }
probe 'synthetic-secret-must-not-appear'
false || :
PROBE
    run bash -c '
        exec 19>"$TEST_TMPDIR/locations"
        BASH_ENV="$REAL_BASE_DIR/tests/uat/bootstrap_trace.bash" \
          LEMPER_UAT_BOOTSTRAP_TRACE=true bash "$TEST_TMPDIR/probe.sh"
    '
    [ "$status" -eq 0 ]
    grep -q ':probe' "$TEST_TMPDIR/locations"
    grep -q ':1$' "$TEST_TMPDIR/locations"
    ! grep -q 'synthetic-secret\|password=\|printf' "$TEST_TMPDIR/locations"
}
