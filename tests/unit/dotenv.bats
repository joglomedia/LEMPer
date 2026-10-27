#!/usr/bin/env bats
##
# Regression tests for .env parsing and updates (issues #42, #144).
#
# OpenSSH public keys contain spaces and base64 '=' padding. The parser must
# keep the value intact instead of evaluating it or splitting it again.
##

load env_helper

setup() {
    unit_setup
}

# The reported 4096-bit RSA key: spaces separate the type, body, and comment.
RSA_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDMh+TeSOd/iTYgAbO0r+6ZWEPvow== lemper@test.com'
ED25519_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKq7vQ4d8Yy2y4Hf1Xo3Jc1p9Wz6uT5sR0aB2cD3eF4g deploy@host'

@test "LEMPER_ENV_FILE is loaded instead of the checkout .env" {
    local custom="${TEST_TMPDIR}/installed.conf"
    printf 'LEMPER_TEST_FROM_FILE=from-custom\n' > "${custom}"
    printf 'LEMPER_TEST_FROM_FILE=from-dot\n' >> "${TEST_TMPDIR}/.env"

    run env BASE_DIR="${BASE_DIR}" LEMPER_ENV_FILE="${custom}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; printf "%s\n" "${LEMPER_TEST_FROM_FILE}"'

    [ "${status}" -eq 0 ]
    [ "${output}" = "from-custom" ]
}

@test "safe_parse_dotenv keeps spaces and '=' in SSH public keys" {
    local envfile="${TEST_TMPDIR}/policy.env"
    printf 'RSA_PUB_KEY=%s\n' "${RSA_KEY}" > "${envfile}"

    run env BASE_DIR="${BASE_DIR}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; safe_parse_dotenv "$1"' _ "${envfile}"

    [ "${status}" -eq 0 ]
    [ "${output}" = "RSA_PUB_KEY"$'\t'"${RSA_KEY}" ]
}

@test "safe_parse_dotenv strips surrounding quotes without losing spaces" {
    local envfile="${TEST_TMPDIR}/quoted.env"
    printf 'RSA_PUB_KEY="%s"\n' "${RSA_KEY}" > "${envfile}"

    run env BASE_DIR="${BASE_DIR}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; safe_parse_dotenv "$1"' _ "${envfile}"

    [ "${output}" = "RSA_PUB_KEY"$'\t'"${RSA_KEY}" ]
}

@test "safe_parse_dotenv ignores CRLF line endings and malformed lines" {
    local envfile="${TEST_TMPDIR}/crlf.env"
    printf 'RSA_PUB_KEY=%s\r\nnot-a-pair\r\n' "${ED25519_KEY}" > "${envfile}"

    run env BASE_DIR="${BASE_DIR}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; safe_parse_dotenv "$1"' _ "${envfile}"

    [ "${output}" = "RSA_PUB_KEY"$'\t'"${ED25519_KEY}" ]
}

@test "set_env_value replaces a key without sed or shell expansion" {
    local envfile="${TEST_TMPDIR}/update.env"
    printf 'RSA_PUB_KEY="old"\nOTHER=1\n' > "${envfile}"

    run env BASE_DIR="${BASE_DIR}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; set_env_value "$1" RSA_PUB_KEY "$2" && cat "$1"' \
        _ "${envfile}" "${RSA_KEY}"

    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "RSA_PUB_KEY=${RSA_KEY}" ]
    [ "${lines[1]}" = "OTHER=1" ]
}

@test "set_env_value appends a missing key" {
    local envfile="${TEST_TMPDIR}/append.env"
    printf 'OTHER=1\n' > "${envfile}"

    run env BASE_DIR="${BASE_DIR}" bash -c \
        '. "${REAL_BASE_DIR}/scripts/utils.sh"; set_env_value "$1" RSA_PUB_KEY "$2"' \
        _ "${envfile}" "${ED25519_KEY}"

    [ "${status}" -eq 0 ]
    [ "$(tail -n 1 "${envfile}")" = "RSA_PUB_KEY=${ED25519_KEY}" ]
    [ "$(head -n 1 "${envfile}")" = "OTHER=1" ]
}

check_key_expr='
    . "${REAL_BASE_DIR}/scripts/utils.sh"
    if is_ssh_public_key "$1"; then echo yes; else echo no; fi
'

@test "is_ssh_public_key accepts supported key types" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ "${RSA_KEY}"
    [ "${output}" = "yes" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ "${ED25519_KEY}"
    [ "${output}" = "yes" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ \
        'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBExample= user@host'
    [ "${output}" = "yes" ]
}

@test "is_ssh_public_key rejects placeholders and injection" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ \
        'copy your ssh public rsa key here'
    [ "${output}" = "no" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ \
        'ssh-rsa; rm -rf /'
    [ "${output}" = "no" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${check_key_expr}" _ ''
    [ "${output}" = "no" ]
}
