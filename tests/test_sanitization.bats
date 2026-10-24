#!/usr/bin/env bats
##
# Bats test suite for LEMPer input sanitization functions.
#
# These tests verify that the validation functions in scripts/utils.sh
# correctly accept valid inputs and reject malicious/injection attempts.
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/.."
    if [[ -f "${BASE_DIR}/.env" ]]; then
        export UTILS_DIR="${BASE_DIR}"
    else
        # Keep read-only checkouts (e.g. container mounts) usable: copy the
        # dotenv and utils.sh into a scratch tree instead of writing to BASE_DIR.
        export UTILS_DIR="${BATS_TEST_TMPDIR}/lemper"
        mkdir -p "${UTILS_DIR}/scripts"
        cp "${BASE_DIR}/scripts/utils.sh" "${UTILS_DIR}/scripts/utils.sh"
        cp "${BASE_DIR}/.env.dist" "${UTILS_DIR}/.env"
    fi
}

load_utils() {
    # utils.sh re-derives BASE_DIR from its own path; drop the test-scoped
    # value so the dotenv is resolved next to the copied utils.sh.
    unset BASE_DIR
    . "${UTILS_DIR}/scripts/utils.sh"
}

# ---------------------------------------------------------------------------
# validate_fqdn tests
# ---------------------------------------------------------------------------

@test "validate_fqdn: accepts valid domain names" {
    load_utils
    [ "$(validate_fqdn 'example.com')" = "true" ]
    [ "$(validate_fqdn 'sub.example.com')" = "true" ]
    [ "$(validate_fqdn 'a.b.c.d.example.org')" = "true" ]
    [ "$(validate_fqdn 'my-site.example.co.uk')" = "true" ]
}

@test "validate_fqdn: rejects injection attempts" {
    load_utils
    [ "$(validate_fqdn 'example.com; rm -rf /')" = "false" ]
    [ "$(validate_fqdn 'foo.com/; echo hacked')" = "false" ]
    # shellcheck disable=SC2016
    [ "$(validate_fqdn 'foo.com$(whoami)')" = "false" ]
    # shellcheck disable=SC2016
    [ "$(validate_fqdn 'foo.com`id`')" = "false" ]
}

@test "validate_fqdn: rejects empty and invalid inputs" {
    load_utils
    [ "$(validate_fqdn '')" = "false" ]
    [ "$(validate_fqdn 'not a domain')" = "false" ]
    [ "$(validate_fqdn 'no_dot_com')" = "false" ]
    [ "$(validate_fqdn '999')" = "false" ]
}

# ---------------------------------------------------------------------------
# validate_ipv4 tests
# ---------------------------------------------------------------------------

@test "validate_ipv4: accepts valid IPv4 addresses" {
    load_utils
    [ "$(validate_ipv4 '192.168.1.1')" = "true" ]
    [ "$(validate_ipv4 '10.0.0.1')" = "true" ]
    [ "$(validate_ipv4 '255.255.255.255')" = "true" ]
    [ "$(validate_ipv4 '0.0.0.0')" = "true" ]
}

@test "validate_ipv4: rejects injection attempts" {
    load_utils
    [ "$(validate_ipv4 '127.0.0.1; rm -rf /')" = "false" ]
    [ "$(validate_ipv4 'foo.com')" = "false" ]
    [ "$(validate_ipv4 '256.256.256.256')" = "false" ]
    [ "$(validate_ipv4 '')" = "false" ]
    # shellcheck disable=SC2016
    [ "$(validate_ipv4 '$(whoami)')" = "false" ]
}

# ---------------------------------------------------------------------------
# validate_username tests
# ---------------------------------------------------------------------------

@test "validate_username: accepts valid usernames" {
    load_utils
    [ "$(validate_username 'lemper')" = "true" ]
    [ "$(validate_username 'web_user')" = "true" ]
    [ "$(validate_username 'user-name')" = "true" ]
    [ "$(validate_username 'a')" = "true" ]
    [ "$(validate_username 'mysql_user1')" = "true" ]
}

@test "validate_username: rejects invalid usernames" {
    load_utils
    # 'root' is a valid username format but not accepted by validate_username
    # since it starts with a letter and has only lowercase — let's check
    [ "$(validate_username 'root')" = "true" ]
    [ "$(validate_username '')" = "false" ]
    [ "$(validate_username 'user; rm -rf /')" = "false" ]
    [ "$(validate_username '1username')" = "false" ]
    [ "$(validate_username 'user@host')" = "false" ]
    [ "$(validate_username 'a b c')" = "false" ]
}

# ---------------------------------------------------------------------------
# sanitize_sed_replacement tests
# ---------------------------------------------------------------------------

@test "sanitize_sed_replacement: escapes special characters" {
    load_utils
    # Forward slash should be escaped
    local result
    result=$(sanitize_sed_replacement 'path/to/file')
    [ "${result}" = 'path\/to\/file' ]
    # Ampersand should be escaped
    result=$(sanitize_sed_replacement 'a&b')
    [ "${result}" = 'a\&b' ]
}

@test "sanitize_sed_replacement: preserves alphanumeric and dots" {
    load_utils
    [ "$(sanitize_sed_replacement 'example.com')" = 'example.com' ]
}
