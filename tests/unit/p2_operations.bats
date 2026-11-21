#!/usr/bin/env bats
# shellcheck disable=SC2016 # Child shell expansion is intentional.
load env_helper
setup() { unit_setup; }
@test "SQL retention prunes only valid owned managed dumps for the selected database" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        mkdir -m0700 "$1/sql"
        for name in testdb_20260101_010101_aaaaaaaa testdb_20260102_010101_bbbbbbbb testdb_20260103_010101_cccccccc otherdb_20260101_010101_aaaaaaaa; do
            printf "SELECT 1;\n" | gzip > "$1/sql/$name.sql.gz"
            digest=$(sha256sum "$1/sql/$name.sql.gz")
            printf "%s\n" "${digest%% *}" > "$1/sql/$name.sql.gz.sha256"
            chmod 0600 "$1/sql/$name.sql.gz" "$1/sql/$name.sql.gz.sha256"
        done
        printf unmanaged > "$1/sql/testdb_legacy.sql.gz"
        DBNAME=testdb DBFILE="$1/sql" DBKEEP=2
        lemper_db_prune || exit 1
        [[ ! -e "$1/sql/testdb_20260101_010101_aaaaaaaa.sql.gz" ]] || exit 1
        [[ -e "$1/sql/testdb_20260102_010101_bbbbbbbb.sql.gz" && -e "$1/sql/otherdb_20260101_010101_aaaaaaaa.sql.gz" && -e "$1/sql/testdb_legacy.sql.gz" ]]
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}
@test "SQL pruning dry-run retains all archives and malformed counts fail before mutation" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/database
        DBNAME=testdb DBFILE="$1" DBKEEP=0 DRYRUN=true
        if lemper_db_prune; then exit 1; fi
        DBKEEP="1;id"
        if lemper_db_prune; then exit 1; fi
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}
@test "data backup driver keeps paths literal and refuses backing up its own repository" {
    mkdir -p "$TEST_TMPDIR/app" "$TEST_TMPDIR/repo"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/restic/backup
        DRYRUN=true RESTIC_REPOSITORY="$1/repo"
        lemper_restic_backup "$1/app" || exit 1
        if lemper_restic_backup "$1"; then exit 1; fi
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"restic backup"* ]]
}
@test "restore refuses nonempty and system targets while leaving data unchanged" {
    mkdir -p "$TEST_TMPDIR/stage"
    printf keep > "$TEST_TMPDIR/stage/sentinel"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/restic/backup
        DRYRUN=true
        if lemper_restic_restore latest /etc; then exit 1; fi
        if lemper_restic_restore latest "$1/stage"; then exit 1; fi
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/stage/sentinel")" = keep ]
}
@test "native rules include IPv4 and IPv6, current SSH ports, mail and optional HTTP3 without flushing foreign tables" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/firewall/nftables
        SSH_PORT=22 SSH_CONNECTION="198.18.0.2 4444 198.18.0.1 2222" INSTALL_MAILER=true NGINX_HTTP3=true
        lemper_nft_rules
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"inet lemper"* && "$output" == *"ipv6-icmp"* && "$output" == *"2222"* && "$output" == *"993"* && "$output" == *"udp dport 443"* ]]
    [[ "$output" != *"flush ruleset"* ]]
}
@test "native invalid ports and monitoring injected configuration fail before writes" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/firewall/nftables
        SSH_PORT="22;id" DRYRUN=true
        if lemper_nft_apply; then exit 1; fi
        lemper_load_module services/monitoring/monit
        MONITOR_ALERT_EMAIL="test@example.com;id"
        if lemper_monit_configure; then exit 1; fi
    '
    [ "$status" -eq 0 ]
}
@test "new runtime and service modules source without dispatch, host initialization or changing shell options" {
    run bash -c '
        before=$(set +o)
        for module in "$1"/lib/runtime/{account,database,ssl,tui,data,firewall}/*.sh "$1"/lib/services/{accounts,restic,firewall,monitoring}/*.sh; do . "$module" || exit 1; done
        [[ "$before" == "$(set +o)" ]] || exit 1
        echo SOURCED
    ' _ "$REAL_BASE_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = SOURCED ]
}
@test "optional configuration ownership is recorded without claiming a pre-existing package" {
    sed "s|/etc/lemper/optional|${TEST_TMPDIR}/optional|g" "$REAL_BASE_DIR/lib/services/optional.sh" > "$TEST_TMPDIR/optional.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$1/optional.sh"
        lemper_load_module() { :; }
        lemper_monit_configure() { return 0; }
        lemper_exec() { [[ "$1" == apt-get ]]; }
        dpkg-query() { printf "install ok installed\n"; }
        LEMPER_INSTALLED_DIR="$1/installed" DRYRUN=false
        lemper_optional_lifecycle install monit || exit 1
        [[ -f "$1/installed/monit" && ! -e "$1/optional/monit" ]]
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}
