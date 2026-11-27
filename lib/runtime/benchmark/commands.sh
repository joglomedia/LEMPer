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

##
# Show benchmark help.
##
function bench_help() {
    cat <<-EOL
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
  LEMPER_BENCH_DISK_DIR  Root-controlled directory for the disk test (default: /var/tmp).
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

    case "${1:-}" in help)
        bench_help
        return 0
        ;;
    version)
        echo "${PROG_VERSION}"
        return 0
        ;;
    esac
    lemper_parse_args 'hv' 'help,version,hardware,disk,network,size:,disk-size:,timeout:' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --)
                shift
                [[ $# -eq 0 ]] || {
                    error "Unexpected positional arguments."
                    return 1
                }
                break
                ;;
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

# shellcheck disable=SC2034 # State is shared with the named service driver.
function lemper_bench_initialize() {
    BENCH_TIMEOUT="${LEMPER_BENCH_TIMEOUT:-60}"
    BENCH_DOWNLOAD_MB="${LEMPER_BENCH_DOWNLOAD_MB:-32}"
    BENCH_DISK_MB="${LEMPER_BENCH_DISK_MB:-512}"
}
