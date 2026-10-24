#!/usr/bin/env bats
##
# Mock-based unit tests for database backup and restore (FUNC-04).
#
# The backup/restore functions are sourced from a copy of the DB plugin with
# its auto-init line removed, while mariadb/mariadb-dump are replaced by
# PATH-shadowing mocks. No real database server or root access is required.
##

load env_helper

setup() {
    unit_setup
    mkdir -p "${TEST_TMPDIR}/bin" "${TEST_TMPDIR}/backups"

    # Drop the auto-init call so the extracted functions can be tested directly.
    sed '$d' "${REAL_BASE_DIR}/lib/lemper-db.sh" > "${TEST_TMPDIR}/lemper-db-unit.sh"

    cat > "${TEST_TMPDIR}/bin/mariadb" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SHOW DATABASES;"* ]]; then
    printf 'Database\ntestdb\notherdb\n'
    exit 0
fi

if [[ -n "${MOCK_DB_LOG:-}" ]]; then
    printf 'ARGS: %s\n' "$*" >> "${MOCK_DB_LOG}"
    cat >> "${MOCK_DB_LOG}"
fi

exit 0
EOF

    cat > "${TEST_TMPDIR}/bin/mariadb-dump" <<'EOF'
#!/usr/bin/env bash
printf 'CREATE TABLE t (id int);\n'
EOF

    chmod +x "${TEST_TMPDIR}/bin/mariadb" "${TEST_TMPDIR}/bin/mariadb-dump"
}

# Invoke db_backup_database / db_restore_database in a child shell.
db_unit_exec() {
    run env PATH="${TEST_TMPDIR}/bin:${PATH}" \
        MOCK_DB_LOG="${TEST_TMPDIR}/db.log" \
        DB_UNIT_PLUGIN="${TEST_TMPDIR}/lemper-db-unit.sh" \
        bash -c '
            requires_root() { :; }
            fail() { echo "FAIL: $*" >&2; exit 1; }
            error() { echo "ERROR: $*" >&2; }
            info() { echo "$*" >&2; }
            success() { echo "SUCCESS: $*"; }
            run() { "$@"; }
            . "${DB_UNIT_PLUGIN}"
            MYSQLCLI=$(command -v mariadb)
            MYSQL_ROOT_PASSWORD="rootpass"
            DBUSER="root"
            DBPASS="rootpass"
            DBNAME="$2"
            DBFILE="$3"
            case "$1" in
                backup) db_backup_database ;;
                restore) db_restore_database ;;
            esac
        ' db-unit "$@"
}

@test "db backup writes a timestamped gzip dump" {
    db_unit_exec backup testdb "${TEST_TMPDIR}/backups"
    [ "${status}" -eq 0 ]

    local backup_file
    backup_file=$(find "${TEST_TMPDIR}/backups" -name 'testdb_*.sql.gz' | head -n 1)
    [ -n "${backup_file}" ]
    [ -f "${backup_file}" ]

    run gunzip -c "${backup_file}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"CREATE TABLE t (id int);"* ]]
}

@test "db backup fails for a database that does not exist" {
    db_unit_exec backup missingdb "${TEST_TMPDIR}/backups"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"does not exist"* ]]
}

@test "db restore pipes gzip dumps into the database client" {
    printf 'INSERT INTO t VALUES (42);\n' | gzip > "${TEST_TMPDIR}/dump.sql.gz"

    db_unit_exec restore testdb "${TEST_TMPDIR}/dump.sql.gz"
    [ "${status}" -eq 0 ]

    run cat "${TEST_TMPDIR}/db.log"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ARGS:"*"testdb"* ]]
    [[ "${output}" == *"INSERT INTO t VALUES (42);"* ]]
}

@test "db restore rejects a missing dump file" {
    db_unit_exec restore testdb "${TEST_TMPDIR}/missing.sql.gz"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Backup file not found"* ]]
}
