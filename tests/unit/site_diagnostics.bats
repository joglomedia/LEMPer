#!/usr/bin/env bats

load env_helper
setup() {
    unit_setup
    # Rewrite only fixture roots; plugin behavior and public parser stay unchanged.
    sed -e '$d' -e "s|/etc/nginx|${TEST_TMPDIR}/nginx|g" \
        -e "s|/etc/lemper|${TEST_TMPDIR}/lemper|g" \
        -e "s|/etc/letsencrypt|${TEST_TMPDIR}/letsencrypt|g" \
        "${REAL_BASE_DIR}/lib/lemper-site-show.sh" > "${TEST_TMPDIR}/site-show.sh"
    mkdir -p "${TEST_TMPDIR}/lemper/vhost.d" "${TEST_TMPDIR}/nginx/sites-available"
    cat > "${TEST_TMPDIR}/lemper/vhost.d/example.test.conf" <<'INI'
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
    printf 'server_name example.test;\n' > "${TEST_TMPDIR}/nginx/sites-available/example.test.conf"
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
    printf 'APP_DB_PASS="malformed-secret"\n' > "${TEST_TMPDIR}/lemper/vhost.d/example.test.conf"
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
