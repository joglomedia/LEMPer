#!/usr/bin/env bats

load env_helper
setup() {
    unit_setup
    export LEMPER_APT_ROOT="${TEST_TMPDIR}/apt"
    mkdir -p "${LEMPER_APT_ROOT}/sources.list.d" "${LEMPER_APT_ROOT}/keyrings"
}
apt_exec() {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/apt/repositories
        "$@"
    ' _ "$@"
}
@test "PHP migration scopes deb and deb-src while preserving unrelated lines and options" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/mixed.list"
    cat > "$list" <<'LIST'
deb [arch=arm64] https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main
deb-src http://ppa.launchpad.net/ondrej/php/ubuntu noble main
deb [signed-by=/other/key.gpg] https://example.test/repo noble main
LIST
    apt_exec lemper_apt_scope_sources php "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -eq 0 ]
    grep -qF "arch=arm64 signed-by=${LEMPER_APT_ROOT}/keyrings/php.gpg" "$list"
    grep -qF "deb-src [signed-by=${LEMPER_APT_ROOT}/keyrings/php.gpg]" "$list"
    grep -qx 'deb \[signed-by=/other/key.gpg\] https://example.test/repo noble main' "$list"
    [ -f "${list}.lemper-before-key-scope" ]
}
@test "deb822 migration replaces inline keys, preserves other stanzas and is idempotent" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/mixed.sources"
    cat > "$list" <<'SOURCES'
Types: deb deb-src
URIs: https://packages.sury.org/php/
Suites: bookworm
Components: main
Signed-By:
 -----BEGIN PGP PUBLIC KEY BLOCK-----
 .
 synthetic-inline-data
 -----END PGP PUBLIC KEY BLOCK-----

Types: deb
URIs: https://example.test/repo
Suites: bookworm
Components: main
Signed-By: /other/key.gpg
SOURCES
    apt_exec lemper_apt_scope_sources php "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -eq 0 ]
    grep -qx "Signed-By: ${LEMPER_APT_ROOT}/keyrings/php.gpg" "$list"
    grep -qx 'Signed-By: /other/key.gpg' "$list"
    run grep -q 'synthetic-inline-data' "$list"
    [ "${status}" -eq 1 ]
    local before
    before=$(sha256sum "$list")
    apt_exec lemper_apt_scope_sources php "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -eq 0 ]
    [ "$(sha256sum "$list")" = "$before" ]
}
@test "mixed folded deb822 URI stanzas fail without changing the source file" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/mixed.sources"
    printf '%s\n' 'Types: deb' 'uris: https://packages.sury.org/php/' \
        ' https://example.test/repo' 'Suites: bookworm' 'Components: main' > "$list"
    local before
    before=$(sha256sum "$list")
    apt_exec lemper_apt_scope_sources php "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -ne 0 ]
    [ "$(sha256sum "$list")" = "$before" ]
    [ ! -e "${list}.lemper-before-key-scope" ]
}
@test "unrelated deb822 files retain their exact bytes" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/other.sources"
    printf 'Types: deb\nURIs: https://example.test/repo\nSuites: bookworm' > "$list"
    local before
    before=$(sha256sum "$list")
    apt_exec lemper_apt_scope_sources php "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -eq 0 ]
    [ "$(sha256sum "$list")" = "$before" ]
    [ ! -e "${list}.lemper-before-key-scope" ]
}
@test "MariaDB scope preserves architecture and source URL" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/mariadb.list"
    printf 'deb [arch=arm64] https://deb.mariadb.org/11.4/ubuntu noble main\n' > "$list"
    apt_exec lemper_apt_scope_sources mariadb "${LEMPER_APT_ROOT}/keyrings/mariadb.gpg"
    [ "${status}" -eq 0 ]
    grep -qx "deb \[arch=arm64 signed-by=${LEMPER_APT_ROOT}/keyrings/mariadb.gpg\] https://deb.mariadb.org/11.4/ubuntu noble main" "$list"
}
@test "APT dry-run does not create source backups, keys or download files" {
    local list="${LEMPER_APT_ROOT}/sources.list.d/php.list"
    printf 'deb https://packages.sury.org/php/ bookworm main\n' > "$list"
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/apt/repositories
        DRYRUN=true
        curl() { echo UNEXPECTED_DOWNLOAD; return 1; }
        lemper_apt_install_key https://example.test/key "$1"
        lemper_apt_scope_sources php "$1"
    ' _ "${LEMPER_APT_ROOT}/keyrings/php.gpg"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"UNEXPECTED_DOWNLOAD"* ]]
    [ ! -e "${list}.lemper-before-key-scope" ]
    [ ! -e "${LEMPER_APT_ROOT}/keyrings/php.gpg" ]
}
@test "key installation rejects malformed downloads without replacing a working key" {
    local key="${LEMPER_APT_ROOT}/keyrings/php.gpg"
    printf 'original-key\n' > "$key"
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/apt/repositories
        curl() { local output; while [[ $# -gt 0 ]]; do if [[ "$1" == -o ]]; then output="$2"; shift; fi; shift; done; printf invalid > "$output"; }
        lemper_apt_install_key https://example.test/key "$1" EXPECTED
    ' _ "$key"
    [ "${status}" -ne 0 ]
    [ "$(cat "$key")" = original-key ]
}
@test "dedicated legacy-key retirement refuses a keyring containing unrelated identities" {
    local legacy="${LEMPER_APT_ROOT}/legacy.gpg" current="${LEMPER_APT_ROOT}/keyrings/php.gpg"
    printf old > "$legacy"
    printf current > "$current"
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/apt/repositories
        gpg() { case "${*: -1}" in *legacy.gpg) printf "fpr:::::::::OTHER:\\n" ;; *) printf "fpr:::::::::EXPECTED:\\n" ;; esac; }
        lemper_apt_retire_key "$1" "$2"
    ' _ "$legacy" "$current"
    [ "${status}" -ne 0 ]
    [ -f "$legacy" ]
    [ ! -e "${legacy}.lemper-retired" ]
}

@test "fingerprint-pinned downloads reject a trusted key bundled with another primary key" {
    local key="${LEMPER_APT_ROOT}/keyrings/php.gpg"
    printf 'original-key\n' > "$key"
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/apt/repositories
        curl() { local output; while [[ $# -gt 0 ]]; do if [[ "$1" == -o ]]; then output="$2"; shift; fi; shift; done; printf candidate > "$output"; }
        gpg() { printf "pub::::::::::\nfpr:::::::::EXPECTED:\npub::::::::::\nfpr:::::::::OTHER:\n"; }
        lemper_apt_install_key https://example.test/key "$1" EXPECTED
    ' _ "$key"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"fingerprint does not match"* ]]
    [ "$(cat "$key")" = original-key ]
}
