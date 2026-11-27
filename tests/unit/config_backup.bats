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
        LEMPER_BACKUP_PATHS="etc/nginx etc/lemper etc/mysql etc/lemper-mail etc/postgresql etc/dovecot" \
        LEMPER_BACKUP_LIB_ONLY=true \
        LEMPER_BACKUP_PLUGIN="${REAL_BASE_DIR}/lib/lemper-backup.sh" \
        bash -c '
            requires_root() { :; }
            error() { echo "ERROR: $*" >&2; }
            warning() { echo "WARN: $*" >&2; }
            info() { echo "$*" >&2; }
            success() { echo "SUCCESS: $*"; }
            run() { "$@"; }
            date() {
                if [[ "$1" == -u && "$2" == +%Y%m%dT%H%M%SZ ]]; then
                    printf "20260101T000000Z\n"
                else
                    command date "$@"
                fi
            }
            tar() {
                command tar "$@" || return $?
                if [[ "$1" == -xz ]]; then
                    case "${BACKUP_FIXTURE_FAIL_RESTORE:-}" in
                        once)
                            if [[ ! -e "$TEST_TMPDIR/restore-failed" ]]; then
                                touch "$TEST_TMPDIR/restore-failed"
                                return 1
                            fi
                            ;;
                        always) return 1 ;;
                    esac
                fi
            }
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

@test "custom legacy checkout backup verifies and restores only its exact env path" {
    export LEMPER_LEGACY_DIR=/checkout
    mkdir -p "${BACKUP_ROOT}/checkout"
    printf 'LEGACY_SETTING=original\n' > "${BACKUP_ROOT}/checkout/.env"
    local archive
    archive=$(make_archive)
    backup_unit_exec backup_verify "${archive}"
    [ "${status}" -eq 0 ]
    printf 'LEGACY_SETTING=changed\n' > "${BACKUP_ROOT}/checkout/.env"
    backup_unit_exec backup_restore --file "${archive}" --yes
    [ "${status}" -eq 0 ]
    grep -qx 'LEGACY_SETTING=original' "${BACKUP_ROOT}/checkout/.env"
    backup_unit_exec backup_member_allowed checkout/other/.env
    [ "${status}" -ne 0 ]
    backup_unit_exec backup_member_allowed checkout/../.env
    [ "${status}" -ne 0 ]
    backup_unit_exec backup_member_allowed checkout/script.sh
    [ "${status}" -ne 0 ]
    unset LEMPER_LEGACY_DIR
    backup_unit_exec backup_member_allowed checkout/.env
    [ "${status}" -ne 0 ]
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

@test "failed extraction reapplies the snapshot and reports files that may remain" {
    printf 'archive-only\n' > "$BACKUP_ROOT/etc/nginx/new.conf"
    local archive
    archive=$(make_archive)
    rm -- "$BACKUP_ROOT/etc/nginx/new.conf"
    printf 'BEFORE_RESTORE\n' > "$BACKUP_ROOT/etc/nginx/nginx.conf"

    export BACKUP_FIXTURE_FAIL_RESTORE=once
    backup_unit_exec backup_restore --file "$archive" --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"Reapplied the pre-restore snapshot. Files absent from that snapshot may remain."* ]]
    grep -qx BEFORE_RESTORE "$BACKUP_ROOT/etc/nginx/nginx.conf"
    [ -f "$BACKUP_ROOT/etc/nginx/new.conf" ]
}

@test "failed snapshot recovery reports incomplete recovery" {
    local archive
    archive=$(make_archive)
    export BACKUP_FIXTURE_FAIL_RESTORE=always
    backup_unit_exec backup_restore --file "$archive" --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"Recovery was incomplete."* ]]
    [[ "$output" != *"Reapplied the pre-restore snapshot."* ]]
    [ -n "$(find "$BACKUP_DIR" -name '*-pre-restore.tar.gz' -print -quit)" ]
}

@test "backup create refuses writable destinations and restores only protected archive inputs" {
    chmod 0777 "$BACKUP_DIR"
    backup_unit_exec backup_create --output "$BACKUP_DIR"
    [ "$status" -ne 0 ]
    [ -z "$(find "$BACKUP_DIR" -mindepth 1 -print -quit)" ]

    chmod 0755 "$BACKUP_DIR"
    local archive
    archive=$(make_archive)
    [ "$(stat -c %a "$archive")" = 600 ]
    [ "$(stat -c %a "$archive.sha256")" = 600 ]
    chmod 0666 "$archive.sha256"
    backup_unit_exec backup_restore --file "$archive" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"protected checksum file"* ]]
    chmod 0600 "$archive.sha256"
    chmod 0666 "$archive"
    backup_unit_exec backup_restore --file "$archive" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"protected archive"* ]]
}

@test "repeated backup creation keeps previous archive and checksum intact" {
    local archive checksum
    archive=$(make_archive)
    checksum=$(cat "$archive.sha256")
    printf 'UPDATED=true\n' > "$BACKUP_ROOT/etc/lemper/lemper.conf"
    backup_unit_exec backup_create --output "$BACKUP_DIR"
    [ "$status" -eq 0 ]
    [ "$(cat "$archive.sha256")" = "$checksum" ]
    [ "$(sha256sum "$archive" | awk '{print $1}')" = "$checksum" ]
    run find "$BACKUP_DIR" -name '*.tar.gz'
    [ "${#lines[@]}" -eq 2 ]
}

@test "backup restores managed links and format-1 duplicate legacy env entries" {
    mkdir -p "$BACKUP_ROOT/etc/nginx/sites-available" "$BACKUP_ROOT/etc/nginx/sites-enabled" \
        "$BACKUP_ROOT/etc/mysql"
    printf 'fixture\n' > "$BACKUP_ROOT/etc/nginx/sites-available/site fixture.conf"
    ln -s "../sites-available/site fixture.conf" "$BACKUP_ROOT/etc/nginx/sites-enabled/site fixture.conf"
    ln -s /etc/alternatives/my.cnf "$BACKUP_ROOT/etc/mysql/my.cnf"
    local archive="$BACKUP_DIR/old.tar.gz"
    printf 'FORMAT=1\n' > "$TEST_TMPDIR/LEMPER-BACKUP-MANIFEST"
    tar -czf "$archive" -C "$BACKUP_ROOT" etc/nginx etc/lemper etc/lemper/.env etc/mysql \
        -C "$TEST_TMPDIR" LEMPER-BACKUP-MANIFEST
    chmod 0600 "$archive"
    backup_unit_exec backup_verify "$archive"
    [ "$status" -eq 0 ]
    rm -- "$BACKUP_ROOT/etc/nginx/sites-enabled/site fixture.conf"
    printf 'CHANGED=true\n' > "$BACKUP_ROOT/etc/lemper/.env"
    backup_unit_exec backup_restore --file "$archive" --yes --no-snapshot
    [ "$status" -eq 0 ]
    [ "$(readlink "$BACKUP_ROOT/etc/nginx/sites-enabled/site fixture.conf")" = "../sites-available/site fixture.conf" ]
    [ "$(readlink "$BACKUP_ROOT/etc/mysql/my.cnf")" = /etc/alternatives/my.cnf ]
    grep -qx 'LEGACY_SETTING=true' "$BACKUP_ROOT/etc/lemper/.env"
}

@test "backup safely replaces managed service-owned directories from staging" {
    [ "$EUID" -eq 0 ] || skip "The service ownership fixture requires root"
    local keys="$BACKUP_ROOT/etc/lemper-mail/keys" cluster="$BACKUP_ROOT/etc/postgresql/17/main"
    mkdir -p "$keys/example.test" "$cluster"
    printf 'dummy archived key\n' > "$keys/example.test/lemper.private"
    printf 'dummy archived config\n' > "$cluster/postgresql.conf"
    chmod 0600 "$keys/example.test/lemper.private"
    ln -s /var/log/postgresql/postgresql-17-main.log "$cluster/log"
    chown -hR 65534:65534 "$keys" "$cluster"
    local archive
    archive=$(make_archive)
    printf 'dummy changed key\n' > "$keys/example.test/lemper.private"
    printf 'dummy changed config\n' > "$cluster/postgresql.conf"
    backup_unit_exec backup_restore --file "$archive" --yes
    [ "$status" -eq 0 ]
    grep -qx 'dummy archived key' "$keys/example.test/lemper.private"
    grep -qx 'dummy archived config' "$cluster/postgresql.conf"
    [ "$(stat -c '%u:%a' "$keys/example.test/lemper.private")" = 65534:600 ]
    [ "$(readlink "$cluster/log")" = /var/log/postgresql/postgresql-17-main.log ]
}

@test "backup preserves stock Debian Dovecot links as leaves" {
    local private_dir="$BACKUP_ROOT/etc/dovecot/private" archive
    mkdir -p "$private_dir"
    ln -s /etc/ssl/private/ssl-cert-snakeoil.key "$private_dir/dovecot.key"
    ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem "$private_dir/dovecot.pem"
    archive=$(make_archive)

    rm -- "$private_dir/dovecot.key" "$private_dir/dovecot.pem"
    printf 'fixture remains unchanged\n' > "$TEST_TMPDIR/external"
    ln -s "$TEST_TMPDIR/external" "$private_dir/dovecot.key"
    backup_unit_exec backup_restore --file "$archive" --yes --no-snapshot
    [ "$status" -eq 0 ]
    grep -qx 'fixture remains unchanged' "$TEST_TMPDIR/external"
    [ "$(readlink "$private_dir/dovecot.key")" = /etc/ssl/private/ssl-cert-snakeoil.key ]
    [ "$(readlink "$private_dir/dovecot.pem")" = /etc/ssl/certs/ssl-cert-snakeoil.pem ]

    ln -s /etc/ssl/private/ssl-cert-snakeoil.key "$private_dir/custom.key"
    backup_unit_exec backup_create --output "$BACKUP_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside the managed configuration"* ]]
}

@test "backup verification rejects unmanaged configuration members and special file types" {
    local archive="$BACKUP_DIR/test.tar.gz"
    printf 'FORMAT=1\n' > "$TEST_TMPDIR/LEMPER-BACKUP-MANIFEST"
    printf 'UNMANAGED\n' > "$BACKUP_ROOT/etc/unmanaged.conf"
    tar -czf "$archive" -C "$BACKUP_ROOT" etc/unmanaged.conf -C "$TEST_TMPDIR" LEMPER-BACKUP-MANIFEST
    backup_unit_exec backup_verify "$archive"
    [ "$status" -ne 0 ]
    [[ "$output" == *"will not restore"* ]]

    mkfifo "$BACKUP_ROOT/etc/lemper/sample.fifo"
    tar -czf "$archive" -C "$BACKUP_ROOT" etc/lemper/sample.fifo -C "$TEST_TMPDIR" LEMPER-BACKUP-MANIFEST
    backup_unit_exec backup_verify "$archive"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported configuration archive member type"* ]]
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
    grep -q 'lemper-backup:lemper-backup' \
        "${REAL_BASE_DIR}/lib/core/registry.sh"
    grep -q 'lemper_cli_snapshot' "${REAL_BASE_DIR}/lib/services/tools/update.sh"
    grep -q 'help_entry backup' "${REAL_BASE_DIR}/lib/runtime/help.sh"
}

find_archive() {
    ls "${BACKUP_DIR}"/lemper-config-*.tar.gz 2>/dev/null | grep -v 'pre-restore' | head -n 1
}

@test "config archives retain site ownership and exclude release-code compatibility links" {
    mkdir -p "$BACKUP_ROOT/etc/lemper/sites" "$TEST_TMPDIR/code"
    printf 'OWNER_MARKER=lemper-site-v1\n' > "$BACKUP_ROOT/etc/lemper/sites/example.com.conf"
    for module in runtime services compat; do
        ln -s "$TEST_TMPDIR/code" "$BACKUP_ROOT/etc/lemper/$module"
    done
    backup_unit_exec backup_create --output "$BACKUP_DIR"
    [ "$status" -eq 0 ]
    local archive
    archive=$(find_archive)
    run tar -tzf "$archive"
    [ "$status" -eq 0 ]
    [[ "$output" == *"etc/lemper/sites/example.com.conf"* ]]
    [[ "$output" != *"etc/lemper/runtime"* ]]
    [[ "$output" != *"etc/lemper/services"* ]]
    [[ "$output" != *"etc/lemper/compat"* ]]
    backup_unit_exec backup_verify "$archive"
    [ "$status" -eq 0 ]
}
