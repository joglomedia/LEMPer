#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child programs retain literal variables.
load env_helper
setup() { unit_setup; }

@test "MariaDB automatic defaults select native Resolute 11.8 and preserve explicit older-platform series" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/repository
        [[ "$(lemper_mariadb_default_version ubuntu resolute auto)" == 11.8 ]] || exit 1
        [[ "$(lemper_mariadb_default_version ubuntu noble auto)" == 11.4 ]] || exit 1
        [[ "$(lemper_mariadb_default_version debian bookworm auto)" == 11.4 ]] || exit 1
        [[ "$(lemper_mariadb_default_version ubuntu noble 11.4.9)" == 11.4.9 ]] || exit 1
        ! lemper_mariadb_default_version ubuntu resolute "11.8;touch invalid"
    '
    [ "$status" -eq 0 ]
}
@test "native MariaDB refuses other requested or installed database series before package mutations" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/repository
        lemper_load_module services/apt/repositories
        lemper_load_module() { :; }
        lemper_apt_has_source() { return 1; }
        dpkg-query() { case "$*" in *Status*) printf "install ok installed" ;; *) printf "1:11.4.9-ubuntu" ;; esac; }
        apt-get() { echo MUTATION; return 1; }
        error() { :; }
        if lemper_mariadb_prepare_native 11.4; then exit 1; fi
        if lemper_mariadb_prepare_native 11.8; then exit 1; fi
    '
    [ "$status" -eq 0 ] && [[ "$output" != *MUTATION* ]]
}
@test "native MariaDB rejects an external repository and preserves dry-run package-manager safety" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/repository
        lemper_load_module services/apt/repositories
        lemper_load_module() { :; }
        lemper_apt_has_source() { return 0; }
        apt-get() { echo MUTATION; return 1; }
        error() { :; }
        if lemper_mariadb_prepare_native 11.8; then exit 1; fi
        lemper_apt_has_source() { return 1; }
        dpkg-query() { return 1; }
        DRYRUN=true lemper_mariadb_prepare_native 11.8
    '
    [ "$status" -eq 0 ] && [[ "$output" != *MUTATION* ]]
}
@test "Resolute MariaDB package selection omits the retired client compatibility package" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/repository
        DISTRIB_NAME=ubuntu RELEASE_NAME=resolute lemper_mariadb_install_packages
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *mariadb-server* && "$output" != *libmariadbclient18* ]]
}
@test "MariaDB data defaults follow Resolute packaging and initialization delegates data ownership" {
    sed '/^echo "\[MariaDB /,$d' "$REAL_BASE_DIR/scripts/install_mariadb.sh" >"$TEST_TMPDIR/installer-functions.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/repository
        DISTRIB_NAME=ubuntu RELEASE_NAME=resolute
        [[ "$(lemper_mariadb_default_data_directory)" == /var/lib/mariadb ]] || exit 1
        [[ "$(RELEASE_NAME=noble lemper_mariadb_default_data_directory)" == /var/lib/mysql ]] || exit 1
        run() { printf "CALL %s\n" "$*"; }
        . "$TEST_TMPDIR/installer-functions.sh"
        run_spinner() { :; }
        add_mariadb_repo() { :; }
        tune_mariadb_config() { :; }
        allow_remote_client_access() { :; }
        enable_mariabackup() { :; }
        mysql() { :; }
        mariadb-install-db() { :; }
        pgrep() { printf "1\n"; }
        INSTALL_MYSQL=true AUTO_INSTALL=true MYSQL_SECURE_INSTALL=false DRYRUN=false
        init_mariadb_install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'CALL mariadb-install-db --user=mysql'* ]]
    [[ "$output" != *'CALL chown -hR mysql:mysql /var/lib/mysql'* && "$output" != *'CALL cp -f etc/mysql/debian-start'* ]]
}
@test "forced database removal selects only the default directory and dry-run preserves data" {
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/mysql" "$TEST_TMPDIR/mariadb" "$TEST_TMPDIR/custom"
    touch "$TEST_TMPDIR/mysql/record" "$TEST_TMPDIR/mariadb/record" "$TEST_TMPDIR/custom/record"
    LEMPER_REMOVE_FIXTURE="$TEST_TMPDIR" awk '
        /^echo "Uninstalling MariaDB/ {exit}
        {gsub(/\/etc\/mysql/,ENVIRON["LEMPER_REMOVE_FIXTURE"] "/config")
         gsub(/\/var\/lib\/mysql/,ENVIRON["LEMPER_REMOVE_FIXTURE"] "/mysql")
         gsub(/\/var\/lib\/mariadb/,ENVIRON["LEMPER_REMOVE_FIXTURE"] "/mariadb"); print}
    ' "$REAL_BASE_DIR/scripts/remove_mariadb.sh" >"$TEST_TMPDIR/remove-functions.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        run() { lemper_exec "$@"; }
        . "$TEST_TMPDIR/remove-functions.sh"
        AUTO_REMOVE=true FORCE_REMOVE=true DRYRUN=true
        mariadb_remove_config "$TEST_TMPDIR/mariadb" || exit 1
        [[ -f "$TEST_TMPDIR/mariadb/record" ]] || exit 1
        DRYRUN=false
        if mariadb_remove_config "$TEST_TMPDIR/custom"; then exit 1; fi
        mariadb_remove_config "$TEST_TMPDIR/mariadb"
    '
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/mariadb" ]
    [ -f "$TEST_TMPDIR/mysql/record" ] && [ -f "$TEST_TMPDIR/custom/record" ]
}
@test "legacy site removal drops a listed database without a data-directory assumption and rejects SQL input" {
    awk '
        /^    # Drop MySQL database[.]/ {active=1; print "function legacy_drop_db_fixture() {"}
        active && /^    echo "Virtual host.*has been removed[.]"/ {print "}"; exit}
        active {print}
    ' "$REAL_BASE_DIR/lib/lemper-manage.sh" >"$TEST_TMPDIR/legacy-db-functions.sh"
    for database in resolute_db 'resolute_db;SELECT 1'; do
        run env LEGACY_DB_NAME="$database" bash -c '
            . "$REAL_BASE_DIR/lib/core/loader.sh"
            . "$TEST_TMPDIR/legacy-db-functions.sh"
            read() { if [[ "${@: -1}" == DROP_DB ]]; then DROP_DB=y; else builtin read "$@"; fi; }
            mysql() { printf "mysql\ninformation_schema\nresolute_db\n"; }
            run() { printf "SQL_CALL %s\n" "$*"; }
            MYSQL_USER=synthetic MYSQL_PASS=synthetic DBNAME=$LEGACY_DB_NAME
            legacy_drop_db_fixture
        '
        if [[ "$database" == resolute_db ]]; then
            [ "$status" -eq 0 ]
            [[ "$output" == *'SQL_CALL mysql -u synthetic -e DROP DATABASE `resolute_db`'* ]]
        else
            [ "$status" -ne 0 ]
            [[ "$output" != *SQL_CALL* ]]
        fi
    done
}
@test "Dovecot selects compatible templates and refuses unknown future configuration versions" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mail/configure
        [[ "$(lemper_mail_dovecot_template "2.3.21 (release)")" == dovecot.conf ]] || exit 1
        [[ "$(lemper_mail_dovecot_template "2.4.2 (release)")" == dovecot-2.4.conf ]] || exit 1
        ! lemper_mail_dovecot_template 2.5.0
    '
    [ "$status" -eq 0 ]
}
@test "Dovecot 2.4 rendering preserves TLS-only authentication and domain-isolated Maildir storage" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mail/configure
        lemper_mail_template "$REAL_BASE_DIR/etc/mail/dovecot-2.4.conf" "$TEST_TMPDIR/dovecot.conf" \
            /srv/fixture-cert mail.example.test example.test /srv/fixture-root /srv/fixture-mail 999
    '
    [ "$status" -eq 0 ]
    grep -Fxq 'auth_allow_cleartext = no' "$TEST_TMPDIR/dovecot.conf"
    grep -Fxq 'ssl = required' "$TEST_TMPDIR/dovecot.conf"
    grep -Fxq 'ssl_server_key_file = /srv/fixture-cert/privkey.pem' "$TEST_TMPDIR/dovecot.conf"
    grep -Fxq '    home = /srv/fixture-mail/%{user | domain}/%{user | username}' "$TEST_TMPDIR/dovecot.conf"
    run grep -Eq '@[A-Z_]+@|%[dnu]|disable_plaintext_auth|mail_location' "$TEST_TMPDIR/dovecot.conf"
    [ "$status" -eq 1 ]
}
