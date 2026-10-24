#!/usr/bin/env bats
##
# Bats tests for resource-profile detection and adaptive sizing.
#
# These run without root and without touching the host: RAM detection can be
# overridden with LEMPER_MEMORY_MB, and profile selection with LEMPER_PROFILE.
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/../.."

    if [[ -f "${BASE_DIR}/.env" ]]; then
        export UTILS_DIR="${BASE_DIR}"
    else
        # Keep read-only checkouts usable: copy utils.sh and the dotenv into a
        # scratch tree instead of writing to BASE_DIR.
        export UTILS_DIR="${BATS_TEST_TMPDIR}/lemper"
        mkdir -p "${UTILS_DIR}/scripts"
        cp "${BASE_DIR}/scripts/utils.sh" "${UTILS_DIR}/scripts/utils.sh"
        cp "${BASE_DIR}/.env.dist" "${UTILS_DIR}/.env"
    fi

    unset LEMPER_PROFILE LEMPER_MEMORY_MB PHP_FPM_MAX_CHILDREN
}

load_utils() {
    # utils.sh re-derives BASE_DIR from its own path; drop the test-scoped
    # value so the dotenv resolves next to the copied utils.sh.
    unset BASE_DIR
    . "${UTILS_DIR}/scripts/utils.sh"
}

@test "memory_to_mb normalizes PHP memory values" {
    load_utils
    [ "$(memory_to_mb '256M')" = "256" ]
    [ "$(memory_to_mb '1G')" = "1024" ]
    [ "$(memory_to_mb '512')" = "512" ]
    [ "$(memory_to_mb '1024m')" = "1024" ]
    # Invalid input falls back to a safe 256 MiB.
    [ "$(memory_to_mb 'lots')" = "256" ]
}

@test "detect_resource_profile honors an explicit override" {
    load_utils
    export LEMPER_PROFILE="micro"
    [ "$(detect_resource_profile)" = "micro" ]

    export LEMPER_PROFILE="large"
    [ "$(detect_resource_profile)" = "large" ]
}

@test "detect_resource_profile classifies RAM automatically" {
    load_utils
    export SERVER_PROFILE="auto"

    export LEMPER_MEMORY_MB=512
    [ "$(detect_resource_profile)" = "micro" ]

    export LEMPER_MEMORY_MB=1536
    [ "$(detect_resource_profile)" = "small" ]

    export LEMPER_MEMORY_MB=3072
    [ "$(detect_resource_profile)" = "medium" ]

    export LEMPER_MEMORY_MB=8192
    [ "$(detect_resource_profile)" = "large" ]
}

@test "calc_php_pool_sizing bounds workers by profile and RAM" {
    load_utils

    local sizing
    LEMPER_MEMORY_MB=1024
    sizing=$(calc_php_pool_sizing "micro" 256)
    [ "${sizing%% *}" = "4" ]

    # 512 MiB host: the memory budget lowers the micro cap to two workers.
    LEMPER_MEMORY_MB=512
    sizing=$(calc_php_pool_sizing "micro" 256)
    [ "${sizing%% *}" = "2" ]

    unset LEMPER_MEMORY_MB
    LEMPER_MEMORY_MB=4096
    sizing=$(calc_php_pool_sizing "medium" 256)
    [ "${sizing%% *}" = "10" ]

    # An explicit override always wins.
    export PHP_FPM_MAX_CHILDREN=3
    sizing=$(calc_php_pool_sizing "medium" 256)
    [ "${sizing%% *}" = "3" ]
}

@test "tune_php_pool applies sizing, memory_limit and cookie policy" {
    load_utils

    export LEMPER_PROFILE="small"
    export LEMPER_MEMORY_MB=2048
    export PHP_MEMORY_LIMIT="512M"
    export SESSION_COOKIE_SECURE="true"

    local pool="${BATS_TEST_TMPDIR}/pool.conf"
    cat > "${pool}" <<'EOF'
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_value[memory_limit] = 256M
php_admin_value[session.cookie_secure] = 0
EOF

    tune_php_pool "${pool}" "${LEMPER_PROFILE}"

    # small on 2 GiB: budget 716 MiB / 170 MiB per child = 4 workers.
    grep -qx 'pm.max_children = 4' "${pool}"
    grep -qx 'pm.start_servers = 2' "${pool}"
    grep -qx 'pm.min_spare_servers = 1' "${pool}"
    grep -qx 'pm.max_spare_servers = 2' "${pool}"
    grep -qx 'php_value\[memory_limit\] = 512M' "${pool}"
    grep -qx 'php_admin_value\[session.cookie_secure\] = 1' "${pool}"
}

@test "calc_mariadb_sizing scales with the resource profile" {
    load_utils

    LEMPER_MEMORY_MB=512
    [ "$(calc_mariadb_sizing "micro")" = "128 30 64 OFF" ]

    LEMPER_MEMORY_MB=1536
    [ "$(calc_mariadb_sizing "small")" = "256 50 128 OFF" ]

    LEMPER_MEMORY_MB=3072
    [ "$(calc_mariadb_sizing "medium")" = "512 75 256 ON" ]

    # Large hosts still cap the buffer pool so PHP and nginx keep room.
    LEMPER_MEMORY_MB=8192
    [ "$(calc_mariadb_sizing "large")" = "2048 100 512 ON" ]
}
