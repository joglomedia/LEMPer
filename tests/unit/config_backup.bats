#!/usr/bin/env bats
##
# Unit tests for the configuration backup/restore plugin.
#
# The plugin accepts an overridden backup root, so archives are created,
# verified, restored, and pruned entirely inside the test temporary directory.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TEST_TMPDIR}"
    export BACKUP_ROOT="${TEST_TMPDIR}/root"
    export BACKUP_DIR="${TEST_TMPDIR}/archives"

    mkdir -p "${BACKUP_ROOT}/etc/nginx" "${BACKUP_ROOT}/etc/lemper" "${BACKUP_DIR}"

    printf 'server { listen 80; }\n' > "${BACKUP_ROOT}/etc/nginx/nginx.conf"
    printf 'SERVER_HOSTNAME="old.example.test"\n' > "${BACKUP_ROOT}/etc/lemper/lemper.conf"
    printf 'LEGACY_SETTING=true\n' > "${BACKUP_ROOT}/etc/lemper/.env"
}

# Run a backup function in a child shell with CLI stubs.
backup_unit_exec() {
    run env \
        LEMPER_BACKUP_ROOT="${BACKUP_ROOT}" \
        LEMPER_BACKUP_DIR="${BACKUP_DIR}" \
        LEMPER_BACKUP_PATHS="etc/nginx etc/lemper" \
        LEMPER_BACKUP_LIB_ONLY=true \
        LEMPER_BACKUP_PLUGIN="${REAL_BASE_DIR}/lib/lemper-backup.sh" \
        bash -c '
            requires_root() { :; }
            error() { echo "ERROR: $*" >&2; }
            warning() { echo "WARN: $*" >&2; }
            info() { echo "$*" >&2; }
            success() { echo "SUCCESS: $*"; }
            run() { "$@"; }
            DRYRUN=false
            PROG_NAME="lemper-cli"
            PROG_VERSION="test"
            . "${LEMPER_BACKUP_PLUGIN}"
            "$@"
        ' backup-unit "$@"
}

# Create one archive and echo its path.
make_archive() {
    backup_unit_exec backup_create --output "${BACKUP_DIR}" >/dev/null
    [ "${status}" -eq 0 ]

    ls "${BACKUP_DIR}"/lemper-config-*.tar.gz 2>/dev/null | grep -v 'pre-restore' | tail -n 1
}

@test "backup create writes config members, manifest, and checksum" {
    backup_unit_exec backup_create --output "${BACKUP_DIR}"
    [ "${status}" -eq 0 ]

    local archive
    archive=$(find_archive)
    [ -f "${archive}" ]
    [ -f "${archive}.sha256" ]
    [ "$(ls -l "${archive}" | cut -c1-10)" = "-rw-------" ]

    run tar -tzf "${archive}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"etc/nginx/nginx.conf"* ]]
    [[ "${output}" == *"etc/lemper/lemper.conf"* ]]
    [[ "${output}" == *"LEMPER-BACKUP-MANIFEST"* ]]

    run tar -xzOf "${archive}" LEMPER-BACKUP-MANIFEST
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"FORMAT=1"* ]]
    [[ "${output}" == *"HOSTNAME="* ]]
    [[ "${output}" == *"LEGACY_ENV=etc/lemper/.env"* ]]
}

@test "backup verify rejects tampered checksums and missing manifests" {
    local archive
    archive=$(make_archive)

    backup_unit_exec backup_verify "${archive}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Archive verified"* ]]

    printf '%064d\n' 0 > "${archive}.sha256"
    backup_unit_exec backup_verify "${archive}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Checksum mismatch"* ]]
    rm -f "${archive}.sha256"

    tar -czf "${TEST_TMPDIR}/no-manifest.tar.gz" -C "${BACKUP_ROOT}" etc/nginx
    backup_unit_exec backup_verify "${TEST_TMPDIR}/no-manifest.tar.gz"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"no LEMPER-BACKUP-MANIFEST"* ]]
}

@test "backup member allow-list blocks traversal and binaries" {
    backup_unit_exec backup_member_allowed ../etc/passwd
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed /etc/passwd
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed etc/../passwd
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed usr/bin/evil
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed etc/lemper/cli-plugins/lemper-db
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed etc/modsecurity/crs/crs-setup.conf
    [ "${status}" -ne 0 ]

    backup_unit_exec backup_member_allowed etc/nginx/nginx.conf
    [ "${status}" -eq 0 ]

    backup_unit_exec backup_member_allowed root/lemper/.env
    [ "${status}" -eq 0 ]
}

@test "backup restore overwrites config and keeps a pre-restore snapshot" {
    local archive marker
    archive=$(make_archive)
    marker="CHANGED_${RANDOM}"

    printf '%s\n' "${marker}" > "${BACKUP_ROOT}/etc/nginx/nginx.conf"
    printf 'SERVER_HOSTNAME="broken.example.test"\n' > "${BACKUP_ROOT}/etc/lemper/lemper.conf"

    backup_unit_exec backup_restore --file "${archive}" --yes
    [ "${status}" -eq 0 ]

    run grep -q 'listen 80' "${BACKUP_ROOT}/etc/nginx/nginx.conf"
    [ "${status}" -eq 0 ]
    run grep -q 'old.example.test' "${BACKUP_ROOT}/etc/lemper/lemper.conf"
    [ "${status}" -eq 0 ]

    local snapshot
    snapshot=$(ls "${BACKUP_DIR}"/*pre-restore.tar.gz 2>/dev/null | head -n 1)
    [ -n "${snapshot}" ]

    run tar -xzOf "${snapshot}" etc/nginx/nginx.conf
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${marker}"* ]]
}

@test "backup restore --no-snapshot and --dry-run change nothing" {
    local archive
    archive=$(make_archive)

    printf 'DRY_RUN_MARKER\n' > "${BACKUP_ROOT}/etc/nginx/nginx.conf"

    backup_unit_exec backup_restore --file "${archive}" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Dry run"* ]]
    run grep -q 'DRY_RUN_MARKER' "${BACKUP_ROOT}/etc/nginx/nginx.conf"
    [ "${status}" -eq 0 ]

    backup_unit_exec backup_restore --file "${archive}" --yes --no-snapshot
    [ "${status}" -eq 0 ]
    run grep -q 'listen 80' "${BACKUP_ROOT}/etc/nginx/nginx.conf"
    [ "${status}" -eq 0 ]

    run bash -c "ls '${BACKUP_DIR}'/*pre-restore.tar.gz 2>/dev/null"
    [ "${status}" -ne 0 ]
}

@test "backup latest ignores pre-restore snapshots" {
    make_archive >/dev/null
    touch "${BACKUP_DIR}/lemper-config-test-29991231T235959Z-pre-restore.tar.gz"

    backup_unit_exec backup_latest_archive "${BACKUP_DIR}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"pre-restore"* ]]
    [[ "${output}" == *"lemper-config-"* ]]
}

@test "backup prune keeps the newest archives" {
    touch "${BACKUP_DIR}/lemper-config-host-20260101T000000Z.tar.gz"
    touch "${BACKUP_DIR}/lemper-config-host-20260102T000000Z.tar.gz"
    touch "${BACKUP_DIR}/lemper-config-host-20260103T000000Z.tar.gz"

    backup_unit_exec backup_prune --dir "${BACKUP_DIR}" --keep 1 --yes
    [ "${status}" -eq 0 ]

    local remaining=0 last="" f
    for f in "${BACKUP_DIR}"/lemper-config-*.tar.gz; do
        [ -f "${f}" ] || continue
        remaining=$((remaining + 1))
        last="${f}"
    done

    [ "${remaining}" -eq 1 ]
    [[ "${last}" == *"20260103T000000Z"* ]]
}

@test "backup plugin is installed and refreshed with the other plugins" {
    [ -f "${REAL_BASE_DIR}/lib/lemper-backup.sh" ]
    grep -q 'lemper-backup.sh /etc/lemper/cli-plugins/lemper-backup' \
        "${REAL_BASE_DIR}/scripts/install_tools.sh"
    grep -q 'lemper-backup:lemper-backup' "${REAL_BASE_DIR}/lib/lemper-update.sh"
    grep -q 'help_entry backup' "${REAL_BASE_DIR}/bin/lemper-cli.sh"
}

find_archive() {
    ls "${BACKUP_DIR}"/lemper-config-*.tar.gz 2>/dev/null | grep -v 'pre-restore' | head -n 1
}
