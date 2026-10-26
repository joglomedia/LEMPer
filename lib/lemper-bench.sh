#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Hardware, Disk, and Network Benchmark                      |
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

# shellcheck disable=SC2034
CMD_PARENT="${PROG_NAME}"
# shellcheck disable=SC2034
CMD_NAME="bench"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

BENCH_TIMEOUT="${LEMPER_BENCH_TIMEOUT:-60}"
BENCH_DOWNLOAD_MB="${LEMPER_BENCH_DOWNLOAD_MB:-32}"
BENCH_DISK_MB="${LEMPER_BENCH_DISK_MB:-512}"

##
# Return the CPU model, including ARM boards and virtual machines.
##
function bench_cpu_model() {
    local model=""

    if [[ -r /proc/cpuinfo ]]; then
        model=$(awk -F: '/^[[:space:]]*model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' \
            /proc/cpuinfo 2>/dev/null || true)
        if [[ -z "${model}" ]]; then
            model=$(awk -F: '/^[[:space:]]*(Hardware|Model|cpu model)/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' \
                /proc/cpuinfo 2>/dev/null || true)
        fi
    fi
    if [[ -z "${model}" && -r /proc/device-tree/model ]]; then
        model=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)
    fi
    if [[ -z "${model}" ]] && command -v lscpu >/dev/null 2>&1; then
        model=$(lscpu 2>/dev/null | awk -F: '/Model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' || true)
    fi
    if [[ -z "${model}" ]] && command -v sysctl >/dev/null 2>&1; then
        model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
    fi

    printf '%s\n' "${model:-Unknown}"
}

##
# Return the number of online CPU cores.
##
function bench_cpu_cores() {
    local cores=""

    if command -v nproc >/dev/null 2>&1; then
        cores=$(nproc 2>/dev/null || true)
    fi
    if [[ -z "${cores}" ]] && command -v getconf >/dev/null 2>&1; then
        cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    fi
    if [[ -z "${cores}" && -r /proc/cpuinfo ]]; then
        cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || true)
    fi
    if [[ -z "${cores}" ]] && command -v sysctl >/dev/null 2>&1; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || true)
    fi

    printf '%s\n' "${cores:-unknown}"
}

##
# Return the current or maximum CPU frequency in MHz.
##
function bench_cpu_freq() {
    local freq=""

    if command -v lscpu >/dev/null 2>&1; then
        freq=$(lscpu 2>/dev/null | \
            awk -F: '/CPU max MHz|CPU MHz/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' || true)
    fi
    if [[ -z "${freq}" && -r /proc/cpuinfo ]]; then
        freq=$(awk -F: '/cpu MHz/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' \
            /proc/cpuinfo 2>/dev/null || true)
    fi
    if [[ -z "${freq}" ]] && command -v sysctl >/dev/null 2>&1; then
        freq=$(sysctl -n hw.cpufrequency_max 2>/dev/null || true)
        if [[ -n "${freq}" ]]; then
            freq=$(awk -v hz="${freq}" 'BEGIN { printf "%.0f", hz / 1000000 }')
        fi
    fi

    printf '%s\n' "${freq:-unknown}"
}

##
# Return memory size in MB.
# Arguments: key in `free` output, key in /proc/meminfo, macOS sysctl key.
##
function bench_mem_mb() {
    local free_key="${1}"
    local info_key="${2}"
    local sysctl_key="${3}"
    local mb=""

    if command -v free >/dev/null 2>&1; then
        mb=$(free -m 2>/dev/null | awk -v k="${free_key}" '$1 == k {print $2; exit}' || true)
    fi
    if [[ -z "${mb}" && -r /proc/meminfo ]]; then
        mb=$(awk -v k="${info_key}" '$1 == k {print int($2 / 1024); exit}' \
            /proc/meminfo 2>/dev/null || true)
    fi
    if [[ -z "${mb}" && -n "${sysctl_key}" ]] && command -v sysctl >/dev/null 2>&1; then
        mb=$(sysctl -n "${sysctl_key}" 2>/dev/null | \
            awk '{printf "%d", $1 / 1048576}' || true)
    fi

    printf '%s\n' "${mb:-0}"
}

##
# Return a human-readable uptime.
##
function bench_uptime() {
    local up=""

    if command -v uptime >/dev/null 2>&1; then
        up=$(uptime -p 2>/dev/null || true)
        if [[ -n "${up}" ]]; then
            printf '%s\n' "${up#up }"
            return 0
        fi
    fi
    if [[ -r /proc/uptime ]]; then
        local seconds days hours minutes
        read -r seconds _ < /proc/uptime || true
        seconds=${seconds%%.*}
        days=$((seconds / 86400))
        hours=$(((seconds % 86400) / 3600))
        minutes=$(((seconds % 3600) / 60))
        printf '%s days, %s hours, %s minutes\n' "${days}" "${hours}" "${minutes}"
        return 0
    fi

    printf 'unknown\n'
}

##
# Return the 1/5/15 minute load average.
##
function bench_load() {
    local load=""

    if [[ -r /proc/loadavg ]]; then
        local l1 l5 l15
        read -r l1 l5 l15 _ < /proc/loadavg || true
        printf '%s, %s, %s\n' "${l1}" "${l5}" "${l15}"
        return 0
    fi
    if command -v uptime >/dev/null 2>&1; then
        load=$(uptime 2>/dev/null | sed -n 's/.*load averages*: *//p' || true)
        if [[ -n "${load}" ]]; then
            printf '%s\n' "${load}"
            return 0
        fi
    fi

    printf 'unknown\n'
}

##
# Print hardware information.
##
function bench_hardware() {
    local freq

    freq=$(bench_cpu_freq)

    echo "### Hardware Information ###"
    printf '  %-20s %s\n' "CPU model:" "$(bench_cpu_model)"
    printf '  %-20s %s\n' "CPU cores:" "$(bench_cpu_cores)"
    if [[ "${freq}" == "unknown" ]]; then
        printf '  %-20s %s\n' "CPU frequency:" "unknown"
    else
        printf '  %-20s %s MHz\n' "CPU frequency:" "${freq}"
    fi
    printf '  %-20s %s MB\n' "Total RAM:" "$(bench_mem_mb 'Mem:' 'MemTotal:' hw.memsize)"
    printf '  %-20s %s MB\n' "Total swap:" "$(bench_mem_mb 'Swap:' 'SwapTotal:' '')"
    printf '  %-20s %s\n' "System uptime:" "$(bench_uptime)"
    printf '  %-20s %s\n' "Load average:" "$(bench_load)"
}

##
# Extract a transfer rate from dd output (GNU, BusyBox, and BSD formats).
##
function bench_parse_dd_speed() {
    awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9.]+(kB|MB|GB)\/s$/) {
                    print $i
                    exit
                }
                if ($(i + 1) ~ /^(kB|MB|GB)\/s$/) {
                    print $i " " $(i + 1)
                    exit
                }
                if ($(i + 1) ~ /^bytes\/sec\)?$/) {
                    value = $i
                    gsub(/[()]/, "", value)
                    if (value + 0 > 0) {
                        printf "%.1f MB/s", value / 1048576
                        exit
                    }
                }
            }
        }
    '
}

##
# Run write and read probes in a throwaway directory.
# Arguments: size in MB, parent directory
##
function bench_disk_probe() {
    local size_mb="${1}"
    local parent="${2}"
    local tmp out write_speed read_speed read_note

    tmp=$(mktemp -d "${parent%/}/lemper-bench.XXXXXX" 2>/dev/null) || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" EXIT

    printf 'path|%s\n' "${tmp}"

    out=$(dd if=/dev/zero of="${tmp}/test.bin" bs=1M count="${size_mb}" conv=fdatasync 2>&1 || true)
    if [[ -z "${out}" ]] || ! grep -qE 'copied|bytes transferred' <<< "${out}"; then
        out=$(dd if=/dev/zero of="${tmp}/test.bin" bs=1M count="${size_mb}" 2>&1 || true)
    fi
    write_speed=$(bench_parse_dd_speed <<< "${out}")
    printf 'write|%s\n' "${write_speed:-unknown}"

    read_note=""
    out=$(dd if="${tmp}/test.bin" of=/dev/null bs=1M iflag=direct 2>&1 || true)
    if [[ -z "${out}" ]] || ! grep -qE 'copied|bytes transferred' <<< "${out}"; then
        out=$(dd if="${tmp}/test.bin" of=/dev/null bs=1M 2>&1 || true)
        read_note=" (cached)"
    fi
    read_speed=$(bench_parse_dd_speed <<< "${out}")
    if [[ -n "${read_speed}" ]]; then
        printf 'read|%s%s\n' "${read_speed}" "${read_note}"
    else
        printf 'read|unknown\n'
    fi
}

##
# Print disk I/O results.
##
function bench_disk() {
    local dir="${LEMPER_BENCH_DISK_DIR:-}"
    local size_mb="${BENCH_DISK_MB}"
    local key value path="" fs_type=""

    if ! command -v dd >/dev/null 2>&1; then
        echo "### Disk I/O Benchmark ###"
        echo "  Skipped: dd is not available."
        return 0
    fi

    if [[ -z "${dir}" ]]; then
        if [[ -d /var/tmp && -w /var/tmp ]]; then
            dir="/var/tmp"
        else
            dir="${TMPDIR:-/tmp}"
        fi
    fi

    echo "### Disk I/O Benchmark ###"
    if [[ ! -d "${dir}" || ! -w "${dir}" ]]; then
        echo "  Skipped: ${dir} is not writable."
        return 0
    fi

    if command -v stat >/dev/null 2>&1; then
        fs_type=$(stat -f -c %T "${dir}" 2>/dev/null || true)
    fi

    printf '  %-20s %s (%s MB test file)\n' "Test directory:" "${dir}" "${size_mb}"
    if [[ "${fs_type}" == "tmpfs" || "${fs_type}" == "ramfs" ]]; then
        echo "  Note: ${dir} is RAM-backed; results reflect memory speed."
    fi

    while IFS='|' read -r key value; do
        case "${key}" in
            path)
                path="${value}"
            ;;
            write)
                printf '  %-20s %s\n' "Write speed:" "${value}"
            ;;
            read)
                printf '  %-20s %s\n' "Read speed:" "${value}"
            ;;
        esac
    done < <(bench_disk_probe "${size_mb}" "${dir}")

    if [[ -n "${path}" ]]; then
        rm -rf "${path}"
    else
        echo "  Disk benchmark could not run in ${dir}."
    fi
}

##
# List download targets as "label|url|mode" lines.
##
function bench_targets() {
    local bytes=$((BENCH_DOWNLOAD_MB * 1024 * 1024))
    local -a targets

    if [[ -n "${LEMPER_BENCH_TARGETS:-}" ]]; then
        printf '%s\n' "${LEMPER_BENCH_TARGETS}"
        return 0
    fi

    targets=(
        "Cloudflare (global)|https://speed.cloudflare.com/__down?bytes=${bytes}|full"
        "Vultr New Jersey, US|https://nj-us-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Los Angeles, US|https://lax-ca-us-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Amsterdam, NL|https://ams-nl-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Frankfurt, DE|https://fra-de-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr London, UK|https://lhr-gb-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Singapore, SG|https://sgp-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Tokyo, JP|https://hnd-jp-ping.vultr.com/vultr.com.100MB.bin|range"
        "Vultr Sydney, AU|https://syd-au-ping.vultr.com/vultr.com.100MB.bin|range"
        "OVH, Europe|https://proof.ovh.net/files/100Mb.dat|range"
    )

    printf '%s\n' "${targets[@]}"
}

##
# Format a byte-per-second value as MB/s and Mbit/s.
##
function bench_format_speed() {
    awk -v bps="${1}" 'BEGIN {
        printf "%.2f MB/s (%.1f Mbit/s)", bps / 1048576, bps * 8 / 1000000
    }'
}

##
# Download one target and print its transfer rate.
# Arguments: url, timeout seconds, bytes, mode (full|range)
##
function bench_download() {
    local url="${1}"
    local timeout="${2}"
    local bytes="${3}"
    local mode="${4:-range}"
    local bps=""

    if command -v curl >/dev/null 2>&1; then
        if [[ "${mode}" == "range" ]]; then
            if bps=$(curl -fsSL --connect-timeout 5 --max-time "${timeout}" \
                -r "0-$((bytes - 1))" -o /dev/null -w '%{speed_download}' "${url}" 2>/dev/null); then
                if awk -v b="${bps}" 'BEGIN { exit !(b > 0) }'; then
                    bench_format_speed "${bps}"
                    return 0
                fi
            fi
        else
            if bps=$(curl -fsSL --connect-timeout 5 --max-time "${timeout}" \
                -o /dev/null -w '%{speed_download}' "${url}" 2>/dev/null); then
                if awk -v b="${bps}" 'BEGIN { exit !(b > 0) }'; then
                    bench_format_speed "${bps}"
                    return 0
                fi
            fi
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        local out speed header=()
        if [[ "${mode}" == "range" ]]; then
            header=(--header="Range: bytes=0-$((bytes - 1))")
        fi
        out=$(wget -O /dev/null --progress=dot:giga --timeout="${timeout}" --tries=1 \
            "${header[@]}" "${url}" 2>&1 || true)
        speed=$(printf '%s\n' "${out}" | grep -oE '\([0-9.]+ [kKMG]B/s\)' | tail -n 1 | tr -d '()')
        if [[ -n "${speed}" ]]; then
            printf '%s (wget)\n' "${speed}"
            return 0
        fi
    fi

    return 1
}

##
# Print network download results.
##
function bench_network() {
    local label url mode speed
    local bytes=$((BENCH_DOWNLOAD_MB * 1024 * 1024))
    local failed=0 total=0

    echo "### Network Download Benchmark ###"
    printf '  %-20s %s MB per endpoint, %s s timeout\n' "Test size:" "${BENCH_DOWNLOAD_MB}" "${BENCH_TIMEOUT}"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "  Skipped: install curl or wget to run network tests."
        return 0
    fi

    while IFS='|' read -r label url mode; do
        if [[ -z "${label}" || -z "${url}" ]]; then
            continue
        fi
        total=$((total + 1))
        printf '  %-28s ' "${label}"
        if speed=$(bench_download "${url}" "${BENCH_TIMEOUT}" "${bytes}" "${mode:-range}"); then
            printf '%s\n' "${speed}"
        else
            printf 'unavailable or timeout\n'
            failed=$((failed + 1))
        fi
    done < <(bench_targets)

    if [[ "${failed}" -gt 0 ]]; then
        info "${failed} of ${total} endpoint(s) did not respond within ${BENCH_TIMEOUT}s."
    fi
}

##
# Show benchmark help.
##
function bench_help() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer hardware, disk I/O, and network download benchmark.

Usage: ${CMD_PARENT} ${CMD_NAME} [options]

Options:
  --hardware             Hardware information only.
  --disk                 Disk I/O benchmark only.
  --network              Network download benchmark only.
  --size <MB>            Download size per endpoint (default: ${BENCH_DOWNLOAD_MB}).
  --disk-size <MB>       Disk test file size (default: ${BENCH_DISK_MB}).
  --timeout <seconds>    Per-endpoint download timeout (default: ${BENCH_TIMEOUT}).
  -h, --help             Show this help.
  -v, --version          Show the benchmark version.

Without a section option, all three benchmarks run. Network tests download
the test size from each endpoint, so they use bandwidth.

Environment:
  LEMPER_BENCH_TARGETS   Newline-separated "label|url|mode" endpoint overrides.
  LEMPER_BENCH_DISK_DIR  Directory for the disk test (default: /var/tmp).
  LEMPER_BENCH_TIMEOUT   Default download timeout in seconds.
  LEMPER_BENCH_DOWNLOAD_MB
  LEMPER_BENCH_DISK_MB

Examples:
  ${CMD_PARENT} ${CMD_NAME}
  ${CMD_PARENT} ${CMD_NAME} --network --size 100
  ${CMD_PARENT} ${CMD_NAME} --disk --disk-size 1024
EOL
}

##
# Main entry point.
##
function init_lemper_bench() {
    local run_hardware=false
    local run_disk=false
    local run_network=false
    local explicit=false

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            help | -h | --help)
                bench_help
                return 0
            ;;
            version | -v | --version)
                echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
                return 0
            ;;
            --hardware)
                run_hardware=true
                explicit=true
            ;;
            --disk)
                run_disk=true
                explicit=true
            ;;
            --network)
                run_network=true
                explicit=true
            ;;
            --size | --disk-size | --timeout)
                if [[ $# -lt 2 ]]; then
                    error "Missing value for ${1}."
                    return 1
                fi
                case "${1}" in
                    --size) BENCH_DOWNLOAD_MB="${2}" ;;
                    --disk-size) BENCH_DISK_MB="${2}" ;;
                    --timeout) BENCH_TIMEOUT="${2}" ;;
                esac
                shift
            ;;
            *)
                error "Unknown ${CMD_NAME} option: ${1}"
                bench_help
                return 1
            ;;
        esac
        shift
    done

    if [[ ! "${BENCH_DOWNLOAD_MB}" =~ ^[0-9]+$ ]] || [[ "${BENCH_DOWNLOAD_MB}" -lt 1 ]]; then
        error "--size must be a positive integer (MB)."
        return 1
    fi
    if [[ ! "${BENCH_DISK_MB}" =~ ^[0-9]+$ ]] || [[ "${BENCH_DISK_MB}" -lt 1 ]]; then
        error "--disk-size must be a positive integer (MB)."
        return 1
    fi
    if [[ ! "${BENCH_TIMEOUT}" =~ ^[0-9]+$ ]] || [[ "${BENCH_TIMEOUT}" -lt 1 ]]; then
        error "--timeout must be a positive integer (seconds)."
        return 1
    fi

    if [[ "${explicit}" == "false" ]]; then
        run_hardware=true
        run_disk=true
        run_network=true
    fi

    echo "[LEMPer Benchmark]"
    echo ""

    if [[ "${run_hardware}" == "true" ]]; then
        bench_hardware
        echo ""
    fi
    if [[ "${run_disk}" == "true" ]]; then
        bench_disk
        echo ""
    fi
    if [[ "${run_network}" == "true" ]]; then
        bench_network
    fi

    return 0
}

# Start running unless this is a sourced library.
if [[ "${LEMPER_BENCH_LIB_ONLY:-false}" != "true" ]]; then
    init_lemper_bench "$@"
fi
