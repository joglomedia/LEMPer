#!/usr/bin/env bats
##
# Unit tests for the benchmark plugin.
#
# Network calls use fake curl/wget executables so tests stay offline.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export BENCH_PLUGIN="${REAL_BASE_DIR}/lib/lemper-bench.sh"
    export FAKE_BIN="${BATS_TEST_TMPDIR}/bin"

    mkdir -p "${FAKE_BIN}"
}

write_fake_curl() {
    cat > "${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_CURL_SPEED:-0}"
exit "${FAKE_CURL_RC:-0}"
EOF
    chmod +x "${FAKE_BIN}/curl"
}

write_fake_wget() {
    cat > "${FAKE_BIN}/wget" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_WGET_RC:-1}"
EOF
    chmod +x "${FAKE_BIN}/wget"
}

bench_exec() {
    run env \
        PATH="${FAKE_BIN}:${PATH}" \
        BENCH_PLUGIN="${BENCH_PLUGIN}" \
        LEMPER_BENCH_LIB_ONLY=true \
        bash -c '
            requires_root() { :; }
            error() { echo "ERROR: $*" >&2; }
            info() { echo "INFO: $*" >&2; }
            PROG_NAME="lemper-cli"
            PROG_VERSION="test"
            . "${BENCH_PLUGIN}"
            "$@"
        ' _ "$@"
}

bench_sections() {
    run env \
        PATH="${FAKE_BIN}:${PATH}" \
        BENCH_PLUGIN="${BENCH_PLUGIN}" \
        LEMPER_BENCH_LIB_ONLY=true \
        bash -c '
            requires_root() { :; }
            error() { echo "ERROR: $*" >&2; }
            info() { echo "INFO: $*" >&2; }
            PROG_NAME="lemper-cli"
            PROG_VERSION="test"
            . "${BENCH_PLUGIN}"
            bench_hardware() { echo "HW"; }
            bench_disk() { echo "DISK"; }
            bench_network() { echo "NET"; }
            init_lemper_bench "$@"
        ' _ "$@"
}

@test "bench help documents sections and limits" {
    bench_exec init_lemper_bench --help

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: lemper-cli bench"* ]]
    [[ "${output}" == *"--network"* ]]
    [[ "${output}" == *"--size <MB>"* ]]
    [[ "${output}" == *"--timeout <seconds>"* ]]
}

@test "bench version is reported" {
    bench_exec init_lemper_bench --version

    [ "${status}" -eq 0 ]
    [ "${output}" = "lemper-cli bench version test" ]
}

@test "bench runs every section by default" {
    bench_sections

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"HW"* ]]
    [[ "${output}" == *"DISK"* ]]
    [[ "${output}" == *"NET"* ]]
}

@test "bench section flags select only requested tests" {
    bench_sections --network

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"NET"* ]]
    [[ "${output}" != *"HW"* ]]
    [[ "${output}" != *"DISK"* ]]
}

@test "bench rejects invalid option values" {
    bench_exec init_lemper_bench --size 0
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"--size must be a positive integer"* ]]

    bench_exec init_lemper_bench --timeout abc
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"--timeout must be a positive integer"* ]]
}

@test "bench formats bytes per second" {
    bench_exec bench_format_speed 125000000

    [ "${status}" -eq 0 ]
    [ "${output}" = "119.21 MB/s (1000.0 Mbit/s)" ]
}

@test "bench parses GNU, BusyBox, and BSD dd output" {
    run env BENCH_PLUGIN="${BENCH_PLUGIN}" LEMPER_BENCH_LIB_ONLY=true bash -c '
        requires_root() { :; }
        PROG_NAME="lemper-cli"
        PROG_VERSION="test"
        . "${BENCH_PLUGIN}"
        bench_parse_dd_speed
    ' <<< "1073741824 bytes (1.1 GB, 1.0 GiB) copied, 2.1 s, 500 MB/s"
    [ "${output}" = "500 MB/s" ]

    run env BENCH_PLUGIN="${BENCH_PLUGIN}" LEMPER_BENCH_LIB_ONLY=true bash -c '
        requires_root() { :; }
        PROG_NAME="lemper-cli"
        PROG_VERSION="test"
        . "${BENCH_PLUGIN}"
        bench_parse_dd_speed
    ' <<< "1048576 bytes (1.0MB) copied, 0.0123 seconds, 81.3MB/s"
    [ "${output}" = "81.3MB/s" ]

    run env BENCH_PLUGIN="${BENCH_PLUGIN}" LEMPER_BENCH_LIB_ONLY=true bash -c '
        requires_root() { :; }
        PROG_NAME="lemper-cli"
        PROG_VERSION="test"
        . "${BENCH_PLUGIN}"
        bench_parse_dd_speed
    ' <<< "1073741824 bytes transferred in 2.5 secs (429496729 bytes/sec)"
    [ "${output}" = "409.6 MB/s" ]
}

@test "bench download uses curl speed and fails cleanly" {
    write_fake_curl
    write_fake_wget

    FAKE_CURL_SPEED=125000000 bench_exec bench_download "http://example.test/file" 10 1048576 range
    [ "${status}" -eq 0 ]
    [ "${output}" = "119.21 MB/s (1000.0 Mbit/s)" ]

    FAKE_CURL_SPEED=0 FAKE_CURL_RC=1 bench_exec bench_download "http://example.test/file" 10 1048576 range
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

@test "bench disk probe reports speeds and cleans up" {
    local disk_dir="${BATS_TEST_TMPDIR}/disk"
    mkdir -p "${disk_dir}"

    run env \
        BENCH_PLUGIN="${BENCH_PLUGIN}" \
        LEMPER_BENCH_LIB_ONLY=true \
        LEMPER_BENCH_DISK_DIR="${disk_dir}" \
        LEMPER_BENCH_DISK_MB=8 \
        bash -c '
            requires_root() { :; }
            PROG_NAME="lemper-cli"
            PROG_VERSION="test"
            . "${BENCH_PLUGIN}"
            bench_disk
        '

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Write speed:"* ]]
    [[ "${output}" == *"Read speed:"* ]]

    run find "${disk_dir}" -name 'lemper-bench.*'
    [ -z "${output}" ]
}

@test "bench targets use current endpoints and support overrides" {
    bench_exec bench_targets

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"speed.cloudflare.com"* ]]
    [[ "${output}" == *"vultr.com"* ]]
    [[ "${output}" != *"linode"* ]]
    [[ "${output}" != *"cachefly"* ]]

    LEMPER_BENCH_TARGETS="Local|http://127.0.0.1/test.bin|range" bench_exec bench_targets
    [ "${output}" = "Local|http://127.0.0.1/test.bin|range" ]
}
