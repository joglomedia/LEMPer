#!/usr/bin/env bats

load env_helper
setup() {
    unit_setup
    export LEMPER_SITE_INSPECT_ROOT="$TEST_TMPDIR"
    # Load the actual adapter/driver against an isolated diagnostics root.
    sed '$d' "${REAL_BASE_DIR}/lib/lemper-site-show.sh" > "$TEST_TMPDIR/site-show.sh"
    mkdir -p "${TEST_TMPDIR}/etc/lemper/vhost.d" "${TEST_TMPDIR}/etc/nginx/sites-available"
    cat > "${TEST_TMPDIR}/etc/lemper/vhost.d/example.test.conf" <<'INI'
[example.test]
APP_FRAMEWORK="laravel"
APP_DB_PASS="synthetic-database-secret"
APP_ADMIN_PASS="synthetic-admin-secret"
APP_WEBROOT="/home/app/a%path"
UNRECOGNIZED_SECRET="another-secret"
[second.test]
APP_FRAMEWORK="wordpress"
APP_DB_PASS="second-secret"
INI
    printf 'server_name example.test;\n' > "${TEST_TMPDIR}/etc/nginx/sites-available/example.test.conf"
}
site_exec() {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        requires_root() { :; }
        PROG_NAME=lemperctl PROG_VERSION=4.0.0
        . "$1"
        shift
        init_lemper_site_show "$@"
    ' _ "${TEST_TMPDIR}/site-show.sh" "$@"
}
@test "application diagnostics redact stored passwords and exclude unknown secret fields" {
    site_exec example.test --app
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"laravel"* ]]
    [[ "${output}" == *"[REDACTED]"* ]]
    [[ "${output}" != *"synthetic-"* && "${output}" != *"another-secret"* && "${output}" != *"second-secret"* ]]
}
@test "JSON long option emits one parseable object with all metadata sections redacted" {
    site_exec example.test --json
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"synthetic-"* && "${output}" != *"second-secret"* ]]
    run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["domain"]=="example.test"; assert len(d["app_metadata"])==2; assert d["app_metadata"]["example.test"]["app_db_pass"]=="[REDACTED]"' "${output}"
    [ "${status}" -eq 0 ]
}
@test "JSON short and long flags have equivalent behavior" {
    site_exec example.test -Aj
    [ "${status}" -eq 0 ]
    local short_output="${output}"
    site_exec example.test --all --json
    [ "${status}" -eq 0 ]
    [ "${output}" = "${short_output}" ]
}
@test "malformed metadata JSON fails without printing secret-bearing parse errors" {
    printf 'APP_DB_PASS="malformed-secret"\n' > "${TEST_TMPDIR}/etc/lemper/vhost.d/example.test.conf"
    site_exec example.test --json
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"malformed-secret"* ]]
}
@test "site show rejects invalid domains and extra positional arguments" {
    site_exec '../private' --json
    [ "${status}" -ne 0 ]
    site_exec example.test --json -- unwanted
    [ "${status}" -ne 0 ]
}

@test "site JSON includes FPM content and modern ownership and nested mounts while redacting configuration credentials" {
    mkdir -p "$TEST_TMPDIR/etc/php/8.4/fpm/pool.d" "$TEST_TMPDIR/etc/lemper/sites" "$TEST_TMPDIR/etc/lemper/site-apps/example.test/demo"
    printf 'server_name example.test;\nfastcgi_pass unix:/run/php/php8.4-fpm.alice.sock;\nproxy_set_header Authorization "Bearer synthetic-proxy-secret";\n' > "$TEST_TMPDIR/etc/nginx/sites-available/example.test.conf"
    printf '[alice]\nlisten=/var/run/php/php8.4-fpm.alice.sock\npm.max_children=10\nenv[DATABASE_URL]=mysql://alice:synthetic-fpm-secret@localhost/app\n' > "$TEST_TMPDIR/etc/php/8.4/fpm/pool.d/alice.conf"
    printf 'OWNER_MARKER=lemper-site-v1\nDOMAIN=example.test\nOWNER=alice\nDATABASE=app_example\n' > "$TEST_TMPDIR/etc/lemper/sites/example.test.conf"
    printf 'OWNER_MARKER=lemper-app-v1\nDOMAIN=example.test\nTYPE=laravel\nMOUNT=/demo/nested\nOWNER=alice\n' > "$TEST_TMPDIR/etc/lemper/site-apps/example.test/demo/nested.conf"
    site_exec example.test --json
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-proxy-secret* && "$output" != *synthetic-fpm-secret* ]]
    run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "pm.max_children=10" in d["fpm_pool"]["content"]; assert d["site_metadata"]["owner"]=="alice"; assert d["apps"][0]["mount"]=="/demo/nested"; assert "fastcgi_pass" in d["nginx_config"]["content"]' "$output"
    [ "$status" -eq 0 ]
}

@test "site SSL discovery reports a configured certificate path rather than guessing the domain directory" {
    printf 'server_name example.test;\nssl_certificate /custom/certs/example.pem;\n' > "$TEST_TMPDIR/etc/nginx/sites-available/example.test.conf"
    site_exec example.test --json
    [ "$status" -eq 0 ]
    run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ssl"]["cert_path"]=="/custom/certs/example.pem"; assert d["ssl"]["status"]=="missing"' "$output"
    [ "$status" -eq 0 ]
}

@test "read-only site JSON remains available when global dry-run is enabled" {
    DRYRUN=true site_exec example.test --json
    [ "$status" -eq 0 ]
    run python3 -c 'import json,sys; assert json.loads(sys.argv[1])["domain"]=="example.test"' "$output"
    [ "$status" -eq 0 ]
}

@test "configuration view ignores unrelated malformed metadata and app recovery remains readable after unregistering a vhost" {
    printf 'APP_DB_PASS="malformed-hidden-secret"\n' > "$TEST_TMPDIR/etc/lemper/vhost.d/example.test.conf"
    site_exec example.test --config
    [ "$status" -eq 0 ]
    [[ "$output" == *server_name* && "$output" != *malformed-hidden-secret* ]]
    printf '[example.test]\nAPP_FRAMEWORK=laravel\n' > "$TEST_TMPDIR/etc/lemper/vhost.d/example.test.conf"
    rm "$TEST_TMPDIR/etc/nginx/sites-available/example.test.conf"
    site_exec example.test --app
    [ "$status" -eq 0 ]
    [[ "$output" == *laravel* ]]
}

@test "diagnostics ignore Python import-path injection while preserving normal JSON output" {
    mkdir -p "$TEST_TMPDIR/python-shadow"
    printf 'raise RuntimeError("unexpected import")\n' > "$TEST_TMPDIR/python-shadow/json.py"
    PYTHONPATH="$TEST_TMPDIR/python-shadow" site_exec example.test --json
    [ "$status" -eq 0 ]
    [[ "$output" != *"unexpected import"* ]]
    run python3 -I -c 'import json,sys; assert json.loads(sys.argv[1])["domain"]=="example.test"' "$output"
    [ "$status" -eq 0 ]
}
