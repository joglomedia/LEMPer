#!/usr/bin/env bats

load env_helper
setup() {
    unit_setup
}
security_child='
    error() { printf "%s\n" "$*" >&2; }
    info() { :; }
    . "${REAL_BASE_DIR}/lib/core/security.sh"
'
@test "diagnostics redact passwords and tokens literally, preserving ordinary messages" {
    run bash -c "${security_child}"'
        MYSQL_ROOT_PASSWORD="a/b&c[secret]"
        ACME_DNS_API_TOKEN="different-token"
        redact_secrets "failed: ${MYSQL_ROOT_PASSWORD} ${ACME_DNS_API_TOKEN} ordinary"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "failed: [REDACTED] [REDACTED] ordinary" ]
}
@test "save_log excludes secret values and retains normal event details" {
    run bash -c '
        . "${REAL_BASE_DIR}/scripts/utils.sh"
        DRYRUN=false
        LOG_FILE="${TEST_TMPDIR}/events.log"
        MYSQL_ROOT_PASSWORD="synthetic-db-secret"
        save_log "database ready: ${MYSQL_ROOT_PASSWORD}"
        cat "${LOG_FILE}"
    '
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"database ready: [REDACTED]"* ]]
    [[ "${output}" != *"synthetic-db-secret"* ]]
}
@test "recursive deletion refuses system paths, traversal, symlinks and wrong owners" {
    mkdir -p "${TEST_TMPDIR}/site"
    ln -s /etc "${TEST_TMPDIR}/linked"
    run bash -c "${security_child}"'
        run() { printf "MUTATION"; }
        delete_site_webroot /etc
        delete_site_webroot /etc/../
        delete_site_webroot "$1/linked"
        delete_site_webroot "$1/site" "nonexistent-account"
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"MUTATION"* ]]
}
@test "recursive deletion permits an owned application directory and forwards one canonical target" {
    mkdir -p "${TEST_TMPDIR}/site/subdir"
    run bash -c "${security_child}"'
        run() { printf "<%s>\n" "$@"; }
        delete_site_webroot "$1/site/subdir/.." "$(id -un)"
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"<rm>"* ]]
    [[ "${output}" == *"<-->"* ]]
    local canonical
    canonical=$(cd "${TEST_TMPDIR}/site" && pwd -P)
    [[ "${output}" == *"<${canonical}>"* ]]
}
@test "DNS credentials use provider-specific keys with owner-only permissions" {
    run bash -c "${security_child}"'
        . "${REAL_BASE_DIR}/lib/core/acme.sh"
        DRYRUN=false
        file=$(dns01_credentials digitalocean "synthetic-token" "$1")
        grep -qx "dns_digitalocean_token = synthetic-token" "$file"
        if [[ "$(uname -s)" == Darwin ]]; then
            [ "$(stat -f %Lp "$file")" = 600 ]
        else
            [ "$(stat -c %a "$file")" = 600 ]
        fi
    ' _ "${TEST_TMPDIR}/acme"
    [ "${status}" -eq 0 ]
}
@test "wildcard issuance and renewal use provider credentials without manual or webroot auth" {
    run bash -c "${security_child}"'
        . "${REAL_BASE_DIR}/lib/core/acme.sh"
        DRYRUN=false
        ACME_DNS_PROVIDER=cloudflare
        ACME_DNS_API_TOKEN=synthetic-token
        acme_flush_dns_cache() { :; }
        certbot() { printf "<%s>\n" "$@"; }
        request_dns01_certificate example.test true "$1"
    ' _ "${TEST_TMPDIR}/acme"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"<--dns-cloudflare>"* ]]
    [[ "${output}" == *"<--force-renewal>"* ]]
    [[ "${output}" == *"<*.example.test>"* ]]
    [[ "${output}" != *"synthetic-token"* ]]
    [[ "${output}" != *"--manual"* ]]
    [[ "${output}" != *"--webroot"* ]]
}
@test "DNS issuance rejects malformed domains, unknown providers, and multiline credentials" {
    run bash -c "${security_child}"'
        . "${REAL_BASE_DIR}/lib/core/acme.sh"
        certbot() { echo MUTATION; }
        ACME_DNS_API_TOKEN=synthetic-token
        request_dns01_certificate "example.test;id" false "$1"
        ACME_DNS_PROVIDER=unknown
        request_dns01_certificate example.test false "$1"
        dns01_credentials cloudflare "$(printf "token\nextra")" "$1"
    ' _ "${TEST_TMPDIR}/acme"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"MUTATION"* ]]
    [ ! -e "${TEST_TMPDIR}/acme" ]
}
@test "failed DNS challenge still flushes resolver cache afterwards" {
    run bash -c "${security_child}"'
        . "${REAL_BASE_DIR}/lib/core/acme.sh"
        DRYRUN=false
        ACME_DNS_API_TOKEN=synthetic-token
        acme_flush_dns_cache() { echo FLUSH; }
        certbot() { return 42; }
        request_dns01_certificate example.test false "$1"
    ' _ "${TEST_TMPDIR}/acme"
    [ "${status}" -eq 42 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = FLUSH ]
    [ "${lines[1]}" = FLUSH ]
}

@test "changing a writable ancestor cannot redirect data removal into a root-owned tree" {
    [[ "$(id -u)" -eq 0 ]] || skip "requires the disposable root Linux test environment"
    run bash -c "${security_child}"'
        work=$(mktemp -d)
        trap "rm -rf \"$work\"" EXIT
        chmod 0755 "$work"
        mkdir -p "$work/app/parent/site" "$work/protected/site"
        chown -R nobody "$work/app"
        printf "protected\n" > "$work/protected/site/sentinel"
        run() {
            mv "$work/app/parent" "$work/app/old"
            ln -s "$work/protected" "$work/app/parent"
            "$@"
        }
        delete_site_webroot "$work/app/parent/site" nobody
        [ -f "$work/protected/site/sentinel" ]
    '
    [ "${status}" -eq 0 ]
}
