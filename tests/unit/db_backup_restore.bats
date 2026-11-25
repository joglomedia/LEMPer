#!/usr/bin/env bats
# shellcheck disable=SC2016 # Child shell scripts intentionally retain literal expansions.
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
            . "${REAL_BASE_DIR}/lib/core/loader.sh"
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

@test "dump failure leaves no successful or partial backup" {
    printf '#!/usr/bin/env bash\nprintf partial\nexit 7\n' > "${TEST_TMPDIR}/bin/mariadb-dump"
    db_unit_exec backup testdb "${TEST_TMPDIR}/backups"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"SUCCESS:"* ]]
    [ -z "$(ls -A "${TEST_TMPDIR}/backups")" ]
}

@test "backup files are private even with a permissive caller umask" {
    db_unit_exec backup testdb "${TEST_TMPDIR}/backups"
    [ "${status}" -eq 0 ]
    local backup_file
    backup_file=$(find "${TEST_TMPDIR}/backups" -name 'testdb_*.sql.gz' | head -n 1)
    [ "$(stat -c %a "${backup_file}")" = 600 ]
}

@test "restore rejects corrupt gzip before sending SQL to the client" {
    printf 'corrupt' > "${TEST_TMPDIR}/bad.sql.gz"
    db_unit_exec restore testdb "${TEST_TMPDIR}/bad.sql.gz"
    [ "${status}" -ne 0 ]
    [ ! -e "${TEST_TMPDIR}/db.log" ]
}

@test "restore reports database client failures" {
    printf '#!/usr/bin/env bash\nif [[ "$*" == *"SHOW DATABASES;"* ]]; then printf "testdb\\n"; else cat >/dev/null; exit 9; fi\n' > "${TEST_TMPDIR}/bin/mariadb"
    printf 'SELECT 1;\n' > "${TEST_TMPDIR}/dump.sql"
    db_unit_exec restore testdb "${TEST_TMPDIR}/dump.sql"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"SUCCESS:"* ]]
}

@test "DB aliases reject identifiers, hosts, privilege injection and arbitrary extra variables before commands" {
    local options
    for options in '--dbname=testdb;touch bad' '--dbhost=localhost\x27;DROP' '--dbport=65536' \
        '--dbprivileges=ALL PRIVILEGES;DROP USER x' '--extra-args=PATH=/untrusted' '--extra-args=MYSQLCLI=/untrusted'; do
        run env PATH="${TEST_TMPDIR}/bin:${PATH}" DB_UNIT_PLUGIN="${TEST_TMPDIR}/lemper-db-unit.sh" bash -c '
            . "${REAL_BASE_DIR}/lib/core/loader.sh"
            requires_root() { :; }
            . "$DB_UNIT_PLUGIN"
            init_lemper_db backup "$1"
        ' _ "$options"
        [ "${status}" -ne 0 ]
        [[ "${output}" != *"backed up"* ]]
    done
}

@test "dry-run export and backup create no directory or file and do not query the DB" {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        DRYRUN=true DBNAME=testdb DBFILE="$1/new/dump.sql"
        MYSQLCLI=/unavailable
        lemper_db_dump plain && DBFILE="$1/new/backups" lemper_db_dump gzip
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -eq 0 ]
    [ ! -e "${TEST_TMPDIR}/new" ]
}

@test "SQL dumps reject symlink destinations and untrusted writable parents" {
    ln -s "${TEST_TMPDIR}/backups" "${TEST_TMPDIR}/linked"
    db_unit_exec backup testdb "${TEST_TMPDIR}/linked"
    [ "${status}" -ne 0 ]
    chmod 0777 "${TEST_TMPDIR}/backups"
    db_unit_exec backup testdb "${TEST_TMPDIR}/backups"
    [ "${status}" -ne 0 ]
}

@test "backup and restore paths containing shell punctuation remain literal" {
    mkdir -p "${TEST_TMPDIR}/quoted ' dump"
    db_unit_exec backup testdb "${TEST_TMPDIR}/quoted ' dump"
    [ "${status}" -eq 0 ]
    printf 'SELECT 42;\n' > "${TEST_TMPDIR}/quoted ' dump/input.sql"
    db_unit_exec restore testdb "${TEST_TMPDIR}/quoted ' dump/input.sql"
    [ "${status}" -eq 0 ]
}

@test "numeric cron grammar accepts ranges and rejects injected or out-of-range fields" {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        lemper_db_schedule_valid "*/15 0-23 1,15 * 0-7" || exit 1
        for invalid in "60 2 * * *" "0 24 * * *" "0 2 0 * *" "0 2 * 13 *" "0 2 * * 8" "*/0 2 * * *" "0 2 * * * touch /tmp/bad" $"0 2 * * *%id"; do
            if lemper_db_schedule_valid "$invalid"; then exit 1; fi
        done
    '
    [ "${status}" -eq 0 ]
}

@test "invalid scheduling never writes credentials or invokes crontab" {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        crontab() { echo MUTATION; }
        DBNAME=testdb DBUSER=app DBPASS=synthetic DBSCHEDULE="0 2 * * *;id"
        LEMPER_DB_CREDENTIAL_DIR="$1/credentials"
        lemper_db_schedule
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"MUTATION"* ]]
    [ ! -e "${TEST_TMPDIR}/credentials" ]
}

@test "public export refuses an exposed password file" {
    printf 'synthetic\n' > "${TEST_TMPDIR}/password"
    chmod 0644 "${TEST_TMPDIR}/password"
    run env DB_UNIT_PLUGIN="${TEST_TMPDIR}/lemper-db-unit.sh" bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        requires_root() { :; }
        . "$DB_UNIT_PLUGIN"
        init_lemper_db export --dbname=testdb --dbpass-file="$1"
    ' _ "${TEST_TMPDIR}/password"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"private (0600)"* ]]
}

@test "public backup-schedule verb reaches the schedule driver without mutations in dry-run" {
    run env DB_UNIT_PLUGIN="${TEST_TMPDIR}/lemper-db-unit.sh" PATH="${TEST_TMPDIR}/bin:${PATH}" bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        requires_root() { :; }
        . "$DB_UNIT_PLUGIN"
        init_lemper_db backup-schedule --dbname=testdb --dbschedule="0 2 * * *" --dry-run
    '
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Would schedule backup"* ]]
}

@test "default localhost keeps socket auth and explicit remote ports are forwarded" {
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        connection=()
        DBHOST=localhost DBPORT=3306
        lemper_db_connection_args connection
        [[ "${connection[*]}" == "-h localhost" ]] || exit 1
        DBHOST=127.0.0.1 DBPORT=3307
        lemper_db_connection_args connection
        [[ "${connection[*]}" == "-h 127.0.0.1 -P 3307" ]]
    '
    [ "${status}" -eq 0 ]
}

@test "failed cron replacement restores existing credentials and removes temporary secret files" {
    mkdir -m 0700 "${TEST_TMPDIR}/credentials"
    printf 'old-secret\n' > "${TEST_TMPDIR}/credentials/testdb-app.pass"
    chmod 0600 "${TEST_TMPDIR}/credentials/testdb-app.pass"
    run bash -c '
        . "${REAL_BASE_DIR}/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        crontab() { if [[ "$1" == -l ]]; then printf "0 2 * * * /usr/local/bin/lemperctl db backup --dbname=testdb\n"; else return 8; fi; }
        DBNAME=testdb DBUSER=app DBPASS=new-secret
        LEMPER_DB_CREDENTIAL_DIR="$1/credentials"
        lemper_db_schedule
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -ne 0 ]
    [ "$(cat "${TEST_TMPDIR}/credentials/testdb-app.pass")" = old-secret ]
    [ "$(find "${TEST_TMPDIR}/credentials" -type f | wc -l)" -eq 1 ]
}
