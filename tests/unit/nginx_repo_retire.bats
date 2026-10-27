#!/usr/bin/env bats
##
# Retired Ondřej nginx APT sources are disabled without touching the PHP PPA,
# and the MyGuard nginx source line stays on the nginx-only tree.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export LEMPER_UPDATE_LIB_ONLY=true
    export PHP_ETC_DIR="${BATS_TEST_TMPDIR}/etc/php"
    export LEMPER_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
    export LEMPER_UPDATE_SOURCE_FILE="${BATS_TEST_TMPDIR}/update-source"
    export LEMPER_LOG_DIR="${BATS_TEST_TMPDIR}/log"
    mkdir -p "${PHP_ETC_DIR}" "${LEMPER_BACKUP_DIR}"
}

# shellcheck disable=SC2016 # Expansions stay literal until the child shell runs.
load_update_lib='
    requires_root() { :; }
    info() { printf "INFO %s\n" "$*"; }
    warning() { printf "WARN %s\n" "$*"; }
    error() { printf "ERR %s\n" "$*"; }
    success() { printf "OK %s\n" "$*"; }
    PROG_NAME="lemper-cli"
    LEMPER_UPDATE_LIB_ONLY=true
    . "${REAL_BASE_DIR}/lib/lemper-update.sh"
    nginx_line_retired_out() {
        if nginx_line_is_retired_ondrej "$1"; then
            echo yes
        else
            echo no
        fi
    }
'

run_lib() {
    bash -c "${load_update_lib}"' "$@"' _ "$@"
}

@test "retired ondrej nginx lines match and the php archive does not" {
    run run_lib nginx_line_retired_out "deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu jammy main"
    [ "${status}" -eq 0 ]
    [ "${output}" = "yes" ]

    run run_lib nginx_line_retired_out "deb https://ppa.launchpadcontent.net/ondrej/nginx-mainline/ubuntu jammy main"
    [ "${output}" = "yes" ]

    run run_lib nginx_line_retired_out "deb https://packages.sury.org/nginx/ bookworm main"
    [ "${output}" = "yes" ]

    run run_lib nginx_line_retired_out "deb https://packages.sury.org/nginx-mainline/ bookworm main"
    [ "${output}" = "yes" ]

    run run_lib nginx_line_retired_out "deb http://ppa.launchpad.net/ondrej/nginx/ubuntu jammy main"
    [ "${output}" = "yes" ]

    run run_lib nginx_line_retired_out "deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main"
    [ "${output}" = "no" ]

    run run_lib nginx_line_retired_out "deb https://packages.sury.org/php/ bookworm main"
    [ "${output}" = "no" ]

    run run_lib nginx_line_retired_out "deb https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main"
    [ "${output}" = "no" ]

    run run_lib nginx_line_retired_out "deb https://example.invalid/ondrej/nginx-module jammy main"
    [ "${output}" = "no" ]

    run run_lib nginx_line_retired_out "# deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu jammy main"
    [ "${output}" = "no" ]
}

@test "retired ondrej nginx sources are disabled and the php ppa is kept" {
    local root="${BATS_TEST_TMPDIR}/apt"
    mkdir -p "${root}/sources.list.d"
    printf '%s\n' 'deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu jammy main' \
        > "${root}/sources.list.d/ondrej-ubuntu-nginx-jammy.list"
    printf '%s\n' 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main' \
        > "${root}/sources.list.d/ondrej-ubuntu-php-jammy.list"
    printf '%s\n' 'deb https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main' \
        > "${root}/sources.list.d/deadsnakes-ppa-jammy.list"
    printf '%s\n' \
        'deb http://archive.ubuntu.com/ubuntu jammy main' \
        'deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu jammy main' \
        'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main' \
        'deb https://example.invalid/ondrej/nginx-module jammy main' \
        > "${root}/sources.list"
    printf '%s\n' \
        'Types: deb' \
        'URIs: https://packages.sury.org/nginx/' \
        'Suites: bookworm' \
        'Components: main' \
        > "${root}/sources.list.d/sury-nginx.sources"
    printf '%s\n\n%s\n' \
        "$(printf '%s\n' \
            'Types: deb' \
            'URIs: https://ppa.launchpadcontent.net/ondrej/php/ubuntu' \
            'Suites: jammy' \
            'Components: main')" \
        "$(printf '%s\n' \
            'Types: deb' \
            'URIs: https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu' \
            'Suites: jammy' \
            'Components: main')" \
        > "${root}/sources.list.d/ondrej-mixed.sources"

    export LEMPER_APT_ROOT="${root}"
    run run_lib retire_ondrej_nginx_sources
    [ "${status}" -eq 0 ]

    [ -f "${root}/sources.list.d/ondrej-ubuntu-nginx-jammy.list.disabled" ]
    [ ! -f "${root}/sources.list.d/ondrej-ubuntu-nginx-jammy.list" ]
    [ -f "${root}/sources.list.d/sury-nginx.sources.disabled" ]
    [ -f "${root}/sources.list.d/ondrej-ubuntu-php-jammy.list" ]
    [ ! -f "${root}/sources.list.d/ondrej-ubuntu-php-jammy.list.disabled" ]
    [ -f "${root}/sources.list.d/deadsnakes-ppa-jammy.list" ]

    grep -qx 'deb http://archive.ubuntu.com/ubuntu jammy main' "${root}/sources.list"
    grep -qx '# lemper-retired-ondrej-nginx: deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu jammy main' "${root}/sources.list"
    grep -qx 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main' "${root}/sources.list"
    grep -qx 'deb https://example.invalid/ondrej/nginx-module jammy main' "${root}/sources.list"
    grep -qx 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main' "${root}/sources.list.d/ondrej-ubuntu-php-jammy.list"

    grep -q 'ondrej/php/ubuntu' "${root}/sources.list.d/ondrej-mixed.sources"
    if grep -q 'ondrej/nginx/ubuntu' "${root}/sources.list.d/ondrej-mixed.sources"; then
        return 1
    fi

    run run_lib retire_ondrej_nginx_sources
    [ "${status}" -eq 0 ]
    [ -f "${root}/sources.list.d/ondrej-ubuntu-php-jammy.list" ]
    [ -f "${root}/sources.list.d/ondrej-ubuntu-nginx-jammy.list.disabled" ]
}

@test "myguard nginx source line is the nginx-only signed-by repository" {
    export LEMPER_APT_ROOT="/etc/apt"
    export LEMPER_NGINX_CODENAME="jammy"
    export LEMPER_NGINX_ARCH="amd64"
    run run_lib myguard_nginx_source_line
    [ "${status}" -eq 0 ]
    [ "${output}" = "deb [arch=amd64 signed-by=/etc/apt/keyrings/deb.myguard.nl.gpg] https://deb.myguard.nl/apt/nginx/jammy jammy main" ]
}

@test "myguard nginx pin covers nginx packages from deb.myguard.nl" {
    run run_lib myguard_nginx_pin_text
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q 'Pin: origin "deb.myguard.nl"'
    echo "${output}" | grep -q 'Pin-Priority: 501'
    echo "${output}" | grep -q 'Package: nginx nginx-common'
    echo "${output}" | grep -q 'libnginx-mod-\*'
    echo "${output}" | grep -q 'libssl-nginx'
    if printf '%s\n' "${output}" | grep -F -q 'Package: *'; then
        return 1
    fi
}

@test "myguard module rename keeps libnginx-mod-rtmp and rewrites brotli" {
    run run_lib nginx_myguard_module_target libnginx-mod-brotli
    [ "${status}" -eq 0 ]
    [ "${output}" = "libnginx-mod-http-brotli" ]

    run run_lib nginx_myguard_module_target libnginx-mod-rtmp
    [ "${output}" = "libnginx-mod-rtmp" ]

    run run_lib nginx_myguard_module_target libnginx-mod-http-echo
    [ "${output}" = "libnginx-mod-http-echo" ]
}

@test "jammy is a published myguard nginx suite and an unknown codename is not" {
    run run_lib nginx_codename_supported jammy
    [ "${status}" -eq 0 ]

    run run_lib nginx_codename_supported xenial
    [ "${status}" -ne 0 ]
}

@test "stack apt refresh retires the nginx ppa before apt-get update" {
    local update="${REAL_BASE_DIR}/lib/lemper-update.sh"
    local stack nginx_refresh retire_at apt_at ensure_at
    stack=$(awk '/^function refresh_stack_apt\(\)/,/^}$/' "${update}")
    nginx_refresh=$(awk '/^function refresh_nginx_apt\(\)/,/^}$/' "${update}")

    echo "${stack}" | grep -q 'retire_ondrej_nginx_sources'
    echo "${stack}" | grep -q 'apt-get update'
    retire_at=$(echo "${stack}" | grep -n 'retire_ondrej_nginx_sources' | head -n 1 | cut -d: -f1)
    apt_at=$(echo "${stack}" | grep -n 'apt-get update' | head -n 1 | cut -d: -f1)
    [ "${retire_at}" -lt "${apt_at}" ]

    echo "${nginx_refresh}" | grep -q 'ensure_myguard_nginx_repo'
    retire_at=$(echo "${nginx_refresh}" | grep -n 'retire_ondrej_nginx_sources' | head -n 1 | cut -d: -f1)
    ensure_at=$(echo "${nginx_refresh}" | grep -n 'ensure_myguard_nginx_repo' | head -n 1 | cut -d: -f1)
    apt_at=$(echo "${nginx_refresh}" | grep -n 'apt-get update' | head -n 1 | cut -d: -f1)
    [ "${retire_at}" -lt "${ensure_at}" ]
    [ "${ensure_at}" -lt "${apt_at}" ]

    grep -qF 'https://deb.myguard.nl/apt/nginx/' "${update}"
    grep -qF 'Dpkg::Options::=--force-confold' "${update}"
    grep -qF 'https://deb.myguard.nl/apt/nginx/' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"
    grep -qF 'gpg --batch --with-colons --show-keys' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"
    grep -qF 'gpg --batch --with-colons --show-keys' "${update}"
    grep -qF 'key="/etc/apt/keyrings/deb.myguard.nl.gpg"' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"
    grep -qF 'signed-by=${key}' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"
    if grep -qF 'http://deb.myguard.nl ${RELEASE_NAME}' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"; then
        return 1
    fi
    if grep -q 'add-apt-repository' "${REAL_BASE_DIR}/scripts/nginx/nginx_repo.sh"; then
        return 1
    fi
    if grep -q 'add_nginx_repo_ondrej' "${REAL_BASE_DIR}/scripts/install_nginx.sh"; then
        return 1
    fi
}
