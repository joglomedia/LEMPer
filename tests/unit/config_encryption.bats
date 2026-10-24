#!/usr/bin/env bats
##
# Unit tests for config-at-rest encryption helpers (lib/lemper-encrypt.sh).
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
}

@test "config encryption uses a supported cipher and detects base64 output" {
    local work="${BATS_TEST_TMPDIR}"
    printf 'MYSQL_ROOT_PASSWORD=secret\n' > "${work}/lemper.conf"

    run bash -c '
        success() { :; }
        fail() { echo "$1" >&2; exit 1; }
        . "${REAL_BASE_DIR}/lib/lemper-encrypt.sh"
        encrypt_config "$1" "test-key" >/dev/null
        is_config_encrypted "$1" || { echo "encrypted-header-not-detected"; exit 1; }
        LEMPER_CONFIG_PASSWORD="test-key" decrypt_config "$1" "$2" >/dev/null
    ' _ "${work}/lemper.conf" "${work}/plain.conf"

    [ "${status}" -eq 0 ]
    [ "$(cat "${work}/plain.conf")" = "MYSQL_ROOT_PASSWORD=secret" ]
}

@test "plaintext configs are not detected as encrypted" {
    local work="${BATS_TEST_TMPDIR}"
    printf 'MYSQL_ROOT_PASSWORD=secret\n' > "${work}/lemper.conf"

    run bash -c '
        success() { :; }
        fail() { exit 1; }
        . "${REAL_BASE_DIR}/lib/lemper-encrypt.sh"
        ! is_config_encrypted "$1"
    ' _ "${work}/lemper.conf"

    [ "${status}" -eq 0 ]
}
