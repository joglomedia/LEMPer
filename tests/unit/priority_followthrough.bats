#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export LEMPER_APT_ROOT="$TEST_TMPDIR/apt"
    export LEMPER_SSL_ROOT="$TEST_TMPDIR/ssl"
    export LEMPER_SSL_TEMPLATE_DIR="$REAL_BASE_DIR/etc/openssl"
    export LEMPER_SITE_STATE_DIR="$TEST_TMPDIR/sites"
    export LEMPER_SITE_METADATA_ROOT="$TEST_TMPDIR/vhost.d"
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/operation.lock"
    mkdir -p "$LEMPER_APT_ROOT/sources.list.d" "$LEMPER_SITE_STATE_DIR" "$LEMPER_SITE_METADATA_ROOT"
}
priority_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    error() { printf "%s\n" "$*" >&2; }
    info() { :; }
    warning() { :; }
    DRYRUN=false
'
@test "repository migration covers PGDG Redis MongoDB and remaining PPA families without deleting unrelated sources" {
    run bash -c "$priority_child"'
        lemper_load_module services/apt/catalog
        DISTRIB_NAME=ubuntu RELEASE_NAME=noble
        lemper_apt_install_key() { install -d "${2%/*}"; printf "synthetic-public-key" > "$2"; }
        for family in pgdg redis mongodb deadsnakes maxmind golang; do
            row=$(lemper_apt_repository_spec "$family") || exit 1
            IFS=$'\''\t'\'' read -r uri suite _ _ _ <<< "$row"
            printf "deb %s %s main\n" "$uri" "$suite" > "$LEMPER_APT_ROOT/sources.list.d/$family.list"
            lemper_apt_prepare_repository "$family" || exit 1
            grep -q "signed-by=" "$LEMPER_APT_ROOT/sources.list.d/$family.list" || exit 1
            [[ -f "$LEMPER_APT_ROOT/sources.list.d/$family.list.lemper-before-key-scope" ]] || exit 1
        done
        echo "deb https://unrelated.test/apt noble main" > "$LEMPER_APT_ROOT/sources.list.d/other.list"
        before=$(sha256sum "$LEMPER_APT_ROOT/sources.list.d/other.list")
        lemper_apt_prepare_repository pgdg || exit 1
        [[ $(sha256sum "$LEMPER_APT_ROOT/sources.list.d/other.list") == "$before" ]]
    '
    [ "$status" -eq 0 ]
}
@test "repository dry-run performs no downloads and rejects mixed stanzas before mutations" {
    run bash -c "$priority_child"'
        lemper_load_module services/apt/catalog
        DISTRIB_NAME=ubuntu RELEASE_NAME=noble
        curl() { echo UNEXPECTED-DOWNLOAD; return 1; }
        DRYRUN=true lemper_apt_prepare_repository deadsnakes || exit 1
        [[ ! -e "$LEMPER_APT_ROOT/keyrings" ]] || exit 1
        printf "Types: deb\nURIs: https://apt.postgresql.org/pub/repos/apt https://unrelated.test/apt\nSuites: noble-pgdg\nComponents: main\n" > "$LEMPER_APT_ROOT/sources.list.d/mixed.sources"
        ! lemper_apt_prepare_repository pgdg || exit 1
        [[ ! -e "$LEMPER_APT_ROOT/keyrings" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED-DOWNLOAD* ]]
}
@test "MongoDB migration refuses a different selected major and repository arguments cannot inject paths" {
    run bash -c "$priority_child"'
        lemper_load_module services/apt/catalog
        DISTRIB_NAME=ubuntu RELEASE_NAME=noble MONGODB_VERSION=6.0
        echo "deb https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" > "$LEMPER_APT_ROOT/sources.list.d/mongo.list"
        ! lemper_apt_prepare_repository mongodb || exit 1
        RELEASE_NAME="noble;touch unsafe"
        ! lemper_apt_prepare_repository pgdg || exit 1
        [[ ! -e "$LEMPER_APT_ROOT/keyrings" ]]
    '
    [ "$status" -eq 0 ]
}
@test "canonical custom TLS flag reaches the builder and a failed TLS setup aborts Nginx compilation" {
    run bash -c "$priority_child"'
        . "$REAL_BASE_DIR/scripts/nginx/nginx_build.sh"
        get_cpu_cores() { echo 1; }
        run() { :; }
        get_nginx_base_configure_args() { :; }
        download_nginx_source() { :; }
        configure_nginx() { :; }
        compile_nginx() { echo COMPILED; }
        create_module_conf_files() { :; }
        enable_dynamic_modules() { :; }
        NGINX_RELEASE_VERSION=synthetic NGINX_BUILD_DIR=/tmp/unused NGINX_EXTRA_MODULE_DIR=/tmp/unused
        NGINX_WITH_CUSTOMSSL=true NGINX_CUSTOMSSL_VERSION=openssl-3.5.9 NGINX_PCRE_VERSION=""
        called=false
        build_custom_ssl() { called=true; }
        build_nginx_from_source || exit 1
        [[ "$called" == true ]] || exit 1
        build_custom_ssl() { return 1; }
        ! build_nginx_from_source
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *COMPILED* ]]
}
@test "OpenSSL dry-run configures Nginx source integration and HTTP3 without downloading or touching files" {
    run bash -c "$priority_child"'
        . "$REAL_BASE_DIR/scripts/nginx/nginx_ssl_builders.sh"
        DRYRUN=true NGINX_BUILD_DIR="$TEST_TMPDIR/source" NGINX_HTTP3=true
        curl() { echo UNEXPECTED; return 1; }
        NGX_CONFIGURE_ARGS=()
        build_openssl openssl-3.5.9 || exit 1
        [[ "${NGX_CONFIGURE_ARGS[*]}" == *"--with-openssl="* && "${NGX_CONFIGURE_ARGS[*]}" == *"--with-http_v3_module"* ]] || exit 1
        [[ ! -e "$NGINX_BUILD_DIR" ]] || exit 1
        ! build_openssl "openssl-3.5.9;touch unsafe"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED* ]]
}
@test "staged selfssl generation failure preserves existing credentials and shared templates" {
    mkdir -p "$LEMPER_SSL_ROOT/example.test"
    echo existing-cert > "$LEMPER_SSL_ROOT/example.test/cert.pem"
    run bash -c "$priority_child"'
        lemper_load_module services/ssl/certificates
        before=$(sha256sum "$LEMPER_SSL_TEMPLATE_DIR/ca.conf")
        openssl() { return 1; }
        ! lemper_ssl_generate_selfsigned example.test 127.0.0.1 ::1 || exit 1
        [[ $(cat "$LEMPER_SSL_ROOT/example.test/cert.pem") == existing-cert ]] || exit 1
        [[ $(sha256sum "$LEMPER_SSL_TEMPLATE_DIR/ca.conf") == "$before" ]]
    '
    [ "$status" -eq 0 ]
}
@test "domain DB shortcuts resolve recorded ownership and reject conflicts without invoking a database" {
    cat > "$LEMPER_SITE_STATE_DIR/example.test.conf" <<'META'
OWNER_MARKER=lemper-site-v1
DOMAIN=example.test
OWNER=alice
WEBROOT=/home/alice/webapps/example.test
DATABASE=app_example
META
    run bash -c "$priority_child"'
        lemper_load_module runtime/database/commands
        db_backup_database() { printf "BACKUP:%s\n" "$DBNAME"; }
        db_restore_database() { printf "RESTORE:%s:%s\n" "$DBNAME" "$DBFILE"; }
        lemper_db_schedule() { printf "SCHEDULE:%s\n" "$DBNAME"; }
        # The runtime reloads the DB driver before dispatch; intercept only the
        # selected callbacks while leaving input validation in the real driver.
        cmd_backup example.test --dry-run || exit 1
        cmd_restore example.test "$TEST_TMPDIR/archive.sql" --dry-run || exit 1
        cmd_backup_schedule example.test --dry-run || exit 1
        ! cmd_backup example.test --dbname=otherdb --dry-run || exit 1
        ! cmd_backup unknown.test --dry-run
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"BACKUP:app_example"* && "$output" == *"RESTORE:app_example:"* ]]
}
@test "domain resolution refuses conflicting legacy database metadata" {
    cat > "$LEMPER_SITE_STATE_DIR/example.test.conf" <<'META'
OWNER_MARKER=lemper-site-v1
DOMAIN=example.test
OWNER=alice
DATABASE=app_example
META
    printf '[example.test]\nAPP_DB_NAME=app_other\nAPP_DB_PASS=synthetic-hidden\n' > "$LEMPER_SITE_METADATA_ROOT/example.test.conf"
    run bash -c "$priority_child"'
        lemper_load_module services/site/database
        ! lemper_site_database_for_domain example.test
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-hidden* ]]
}

@test "Bun dry-run chooses the native architecture without downloading or replacing an unowned executable" {
    run bash -c "$priority_child"'
        lemper_load_module services/bun/binary
        LEMPER_BUN_PREFIX="$TEST_TMPDIR/bun" DRYRUN=true BUNJS_VERSION=1.4.5
        curl() { echo UNEXPECTED; return 1; }
        lemper_bun_install_binary || exit 1
        [[ ! -e "$LEMPER_BUN_PREFIX" ]] || exit 1
        mkdir -p "$LEMPER_BUN_PREFIX/usr/local/bin"
        ln -s /missing "$LEMPER_BUN_PREFIX/usr/local/bin/bun"
        ! lemper_bun_install_binary
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED* ]]
}

@test "invalid site IP arguments fail before package checks or vhost mutations" {
    run bash -c "$priority_child"'
        lemper_load_module runtime/site/create
        check_required_packages() { echo UNEXPECTED; }
        lemper_site_create_command --domain-name example.test --ipv6 :::
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *UNEXPECTED* ]]
}

@test "scoped key migration rejects signature bypass options without rewriting the source" {
    run bash -c "$priority_child"'
        lemper_load_module services/apt/catalog
        DISTRIB_NAME=ubuntu RELEASE_NAME=noble
        file="$LEMPER_APT_ROOT/sources.list.d/unsafe.list"
        echo "deb [trusted=yes] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" > "$file"
        before=$(sha256sum "$file")
        ! lemper_apt_prepare_repository pgdg || exit 1
        [[ $(sha256sum "$file") == "$before" && ! -e "$LEMPER_APT_ROOT/keyrings" ]]
    '
    [ "$status" -eq 0 ]
}
