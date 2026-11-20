#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+


function core_create_php_temp_dirs() {
    local POOLNAME="${1}"
    local TEMP_BASE="/var/lib/php/lemper/${POOLNAME}"

    run mkdir -p "${TEMP_BASE}/tmp" "${TEMP_BASE}/sessions" \
        "${TEMP_BASE}/wsdlcache" "${TEMP_BASE}/opcache" && \
    run chmod 700 "${TEMP_BASE}" "${TEMP_BASE}/tmp" "${TEMP_BASE}/sessions" \
        "${TEMP_BASE}/wsdlcache" "${TEMP_BASE}/opcache" && \
    run chown -hR "${POOLNAME}:${POOLNAME}" "${TEMP_BASE}"
}

function core_get_ram_size() {
    local RAM_SIZE_IN_MB=0

    # Calculate total RAM size in MB by summing all memory modules.
    # dmidecode may return multiple lines for systems with multiple RAM modules.
    while read -r size unit; do
        if [[ "${size}" =~ ^[0-9]+$ ]]; then
            case "${unit}" in
                "GB")
                    RAM_SIZE_IN_MB=$((RAM_SIZE_IN_MB + size * 1024))
                ;;
                "MB")
                    RAM_SIZE_IN_MB=$((RAM_SIZE_IN_MB + size))
                ;;
            esac
        fi
    done < <(dmidecode -t 17 2>/dev/null | awk '/Size/ && $2 ~ /^[0-9]+$/ { print $2, $3 }')

    # Fallback to /proc/meminfo if dmidecode returns 0 or fails
    if [[ "${RAM_SIZE_IN_MB}" -eq 0 ]]; then
        RAM_SIZE_IN_MB=$(awk '/MemTotal/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)
    fi

    echo "${RAM_SIZE_IN_MB:-0}"
}

function core_get_memory_mb() {
    if [[ "${LEMPER_MEMORY_MB:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "${LEMPER_MEMORY_MB}"
        return 0
    fi

    local MEM_MB
    MEM_MB=$(awk '/^MemTotal:/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)

    # Respect cgroup limits (containers and systemd slices).
    local CGROUP_LIMIT
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
    fi

    # Ignore "unlimited" sentinels (1 PiB and friends).
    awk -v total="${MEM_MB:-0}" -v limit="${CGROUP_LIMIT:-0}" 'BEGIN {
        if (limit ~ /^[0-9]+$/) {
            mb = int(limit / 1048576);
            if (mb > 0 && mb < 1048576 && (total == 0 || mb < total)) total = mb;
        }
        printf "%.0f\n", total;
    }'
}

function core_memory_to_mb() {
    local VALUE="${1:-256M}"

    if [[ ! "${VALUE}" =~ ^[0-9]+[GgMm]?$ ]]; then
        echo 256
        return 0
    fi

    case "${VALUE}" in
        *[Gg]) echo $(( ${VALUE%[Gg]} * 1024 )) ;;
        *[Mm]) echo $(( ${VALUE%[Mm]} )) ;;
        *)     echo $(( VALUE )) ;;
    esac
}

function core_detect_resource_profile() {
    local PROFILE="${LEMPER_PROFILE:-${SERVER_PROFILE:-auto}}"

    case "${PROFILE}" in
        micro|small|medium|large)
            echo "${PROFILE}"
            return 0
            ;;
        auto|"") ;;
        *)
            warning "Unknown resource profile '${PROFILE}', using auto-detection." >&2
            ;;
    esac

    local MEM_MB && MEM_MB=$(get_memory_mb)

    if (( MEM_MB <= 0 )); then
        # Unknown memory: assume the conservative middle.
        echo "small"
    elif (( MEM_MB < 1024 )); then
        echo "micro"
    elif (( MEM_MB < 2048 )); then
        echo "small"
    elif (( MEM_MB < 4096 )); then
        echo "medium"
    else
        echo "large"
    fi
}

function core_calc_php_max_children() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)
    local MEMLIMIT="${2:-256}"
    local CAP

    case "${PROFILE}" in
        micro)  CAP=4 ;;
        small)  CAP=6 ;;
        medium) CAP=10 ;;
        large)  CAP=16 ;;
        *)      CAP=6 ;;
    esac

    # A busy PHP worker typically holds 40-80 MiB. Budget a third of
    # memory_limit so the cap is realistic for small CMS workloads while
    # still bounding the worst case.
    local PER_CHILD=$(( MEMLIMIT / 3 ))
    (( PER_CHILD < 64 )) && PER_CHILD=64

    local TOTAL && TOTAL=$(get_memory_mb)
    if (( TOTAL > 0 )); then
        local BUDGET=$(( TOTAL * 35 / 100 ))
        local BY_MEM=$(( BUDGET / PER_CHILD ))
        (( BY_MEM < 2 )) && BY_MEM=2
        (( BY_MEM < CAP )) && CAP=${BY_MEM}
    fi

    (( CAP < 2 )) && CAP=2
    echo "${CAP}"
}

function core_calc_php_pool_sizing() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)
    local MEMLIMIT="${2:-256}"
    local MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-}"

    if [[ ! "${MAX_CHILDREN}" =~ ^[0-9]+$ || "${MAX_CHILDREN}" -lt 2 ]]; then
        MAX_CHILDREN=$(calc_php_max_children "${PROFILE}" "${MEMLIMIT}")
    fi

    local START=$(( MAX_CHILDREN / 2 ))
    (( START > 2 )) && START=2
    (( START < 1 )) && START=1

    local MAX_SPARE=$(( MAX_CHILDREN / 2 ))
    (( MAX_SPARE < START )) && MAX_SPARE=${START}

    echo "${MAX_CHILDREN} ${START} 1 ${MAX_SPARE}"
}

function core_tune_php_pool() {
    local POOL_FILE="${1}"
    local PROFILE="${2:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)

    [[ -f "${POOL_FILE}" ]] || return 0

    local MEMLIMIT_MB && MEMLIMIT_MB=$(memory_to_mb "${PHP_MEMORY_LIMIT:-256M}")
    local MAX_CHILDREN START MIN_SPARE MAX_SPARE
    read -r MAX_CHILDREN START MIN_SPARE MAX_SPARE <<< \
        "$(calc_php_pool_sizing "${PROFILE}" "${MEMLIMIT_MB}")"

    sed_inplace "s/^pm\.max_children = .*/pm.max_children = ${MAX_CHILDREN}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.start_servers = .*/pm.start_servers = ${START}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.min_spare_servers = .*/pm.min_spare_servers = ${MIN_SPARE}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.max_spare_servers = .*/pm.max_spare_servers = ${MAX_SPARE}/" "${POOL_FILE}"
    sed_inplace "s/^php_value\[memory_limit\] = .*/php_value[memory_limit] = ${PHP_MEMORY_LIMIT:-256M}/" "${POOL_FILE}"

    local COOKIE_SECURE=0
    [[ "${SESSION_COOKIE_SECURE:-false}" == true ]] && COOKIE_SECURE=1
    sed_inplace "s/^php_admin_value\[session\.cookie_secure\] = .*/php_admin_value[session.cookie_secure] = ${COOKIE_SECURE}/" "${POOL_FILE}"
}

function core_calc_mariadb_sizing() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)

    local BUFFER_POOL MAX_CONNECTIONS TABLE_CACHE PERF_SCHEMA

    case "${PROFILE}" in
        micro)  BUFFER_POOL=128;  MAX_CONNECTIONS=30;  TABLE_CACHE=64;  PERF_SCHEMA=OFF ;;
        small)  BUFFER_POOL=256;  MAX_CONNECTIONS=50;  TABLE_CACHE=128; PERF_SCHEMA=OFF ;;
        medium) BUFFER_POOL=512;  MAX_CONNECTIONS=75;  TABLE_CACHE=256; PERF_SCHEMA=ON ;;
        *)      BUFFER_POOL=1024; MAX_CONNECTIONS=100; TABLE_CACHE=512; PERF_SCHEMA=ON ;;
    esac

    # Large hosts can afford a bigger pool; cap it so the database does not
    # crowd out PHP-FPM and the web server.
    local TOTAL && TOTAL=$(get_memory_mb)
    if (( TOTAL >= 8192 )); then
        BUFFER_POOL=2048
    fi

    echo "${BUFFER_POOL} ${MAX_CONNECTIONS} ${TABLE_CACHE} ${PERF_SCHEMA}"
}

function create_php_temp_dirs() {
    core_create_php_temp_dirs "$@"
}

function get_ram_size() {
    core_get_ram_size
}

function get_memory_mb() {
    core_get_memory_mb
}

function memory_to_mb() {
    core_memory_to_mb "$@"
}

function detect_resource_profile() {
    core_detect_resource_profile
}

function calc_php_max_children() {
    core_calc_php_max_children "$@"
}

function calc_php_pool_sizing() {
    core_calc_php_pool_sizing "$@"
}

function tune_php_pool() {
    core_tune_php_pool "$@"
}

function calc_mariadb_sizing() {
    core_calc_mariadb_sizing "$@"
}
