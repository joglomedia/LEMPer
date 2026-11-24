#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }

# shellcheck disable=SC2016 # Evaluated in isolated child shells.
certbot_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    run() { "$@"; }
    info() { :; }
    success() { :; }
    AUTO_INSTALL=true
    FORCE_INSTALL=false
    INSTALL_CERTBOT=true
    DISTRIB_NAME=ubuntu
    DRYRUN=false
    ACME_WILDCARD=false
    LEMPER_ADMIN_EMAIL=fixture@example.test
    certbot() {
        case "$1" in
            --version) echo "certbot fixture" ;;
            show_account) return "${ACCOUNT_PRESENT:-1}" ;;
            register|update_account) printf "<%s>\n" "$@" ;;
        esac
    }
    . "$REAL_BASE_DIR/scripts/install_certbotle.sh"
    install_certbot_pip() { :; }
    add_certbot_cron() { echo SCHEDULED; }
    add_certbot_logrotate() { :; }
    add_certbot_deploy_hook() { :; }
    add_dns01_credentials() { :; }
'
@test "unattended Certbot account setup is noninteractive and follows the selected server account" {
    run bash -c "${certbot_child}"'
        ACME_REGISTER_ACCOUNT=true
        init_certbotle_install
        ACCOUNT_PRESENT=0
        init_certbotle_install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"<register>"* ]]
    [[ "$output" == *"<update_account>"* ]]
    [[ "$output" == *"<--non-interactive>"* ]]
}
@test "package-only Certbot installation configures renewal without registering an external account" {
    run bash -c "${certbot_child}"'
        ACME_REGISTER_ACCOUNT=false
        init_certbotle_install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *SCHEDULED* ]]
    [[ "$output" != *"<register>"* ]]
    [[ "$output" != *"<update_account>"* ]]
}
@test "MyGuard config packages alone cannot select an incompatible distro nginx binary" {
    run bash -c '
        . "$REAL_BASE_DIR/scripts/nginx/nginx_repo.sh"
        apt-cache() {
            if [[ "$1" == policy ]]; then echo "  Candidate: 1.24.0"; else
                echo "nginx | 1.24.0 | http://ports.ubuntu.com noble/main arm64 Packages"
            fi
        }
        ! nginx_myguard_binary_available || exit 1
        apt-cache() {
            if [[ "$1" == policy ]]; then echo "  Candidate: 3:1.31.9"; else
                echo "nginx | 3:1.31.9 | https://deb.myguard.nl/apt/nginx/noble noble/main amd64 Packages"
            fi
        }
        nginx_myguard_binary_available
    '
    [ "$status" -eq 0 ]
}

@test "Nginx source selection honors explicit versions and selects stable tags without HTML scraping" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        run() { "$@"; }
        requires_root() { :; }
        info() { :; }
        AUTO_INSTALL=true NGINX_INSTALLER=none
        . "$REAL_BASE_DIR/scripts/install_nginx.sh"
        curl() { echo REQUESTED >&2; return 1; }
        NGINX_VERSION=1.28.4
        echo "EXPLICIT:$(determine_nginx_version)" || exit 1
        curl() { printf "%s\n" "[{\"name\":\"release-1.31.9\"},{\"name\":\"release-1.30.7\"},{\"name\":\"release-1.30.6\"}]"; }
        NGINX_VERSION=stable
        echo "STABLE:$(determine_nginx_version)"
        NGINX_VERSION=mainline
        echo "MAINLINE:$(determine_nginx_version)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *EXPLICIT:1.28.4* ]]
    [[ "$output" == *STABLE:1.30.7* ]]
    [[ "$output" == *MAINLINE:1.31.9* ]]
    [[ "$output" != *REQUESTED* ]]
}
@test "official GitHub archive fallback builds with literal arguments through auto/configure" {
    mkdir -p "$TEST_TMPDIR/archive/nginx-release-1.30.7/auto" "$TEST_TMPDIR/build"
    cat > "$TEST_TMPDIR/archive/nginx-release-1.30.7/auto/configure" <<'CONFIGURE'
#!/usr/bin/env bash
printf '<%s>\n' "$@" > configure.args
CONFIGURE
    chmod +x "$TEST_TMPDIR/archive/nginx-release-1.30.7/auto/configure"
    tar -czf "$TEST_TMPDIR/source.tar.gz" -C "$TEST_TMPDIR/archive" nginx-release-1.30.7
    run bash -c '
        run() { "$@"; }
        warning() { :; }
        get_cpu_cores() { echo 1; }
        . "$REAL_BASE_DIR/scripts/nginx/nginx_build.sh"
        NGINX_BUILD_DIR="$TEST_TMPDIR/build"
        NGINX_RELEASE_VERSION=1.30.7
        DRYRUN=false
        curl() {
            local output="" url="" arg
            while [[ $# -gt 0 ]]; do
                arg="$1"; shift
                if [[ "$arg" == -o ]]; then output="$1"; shift; else url="$arg"; fi
            done
            [[ "$url" == https://github.com/nginx/nginx/* ]] || return 22
            cp "$TEST_TMPDIR/source.tar.gz" "$output"
        }
        download_nginx_source 1.30.7 || exit 1
        NGX_CONFIGURE_ARGS=("--add-dynamic-module=$TEST_TMPDIR/module path; touch $TEST_TMPDIR/executed")
        configure_nginx
    '
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/executed" ]
    [ "$(wc -l < "$TEST_TMPDIR/build/nginx-1.30.7/configure.args")" -eq 1 ]
    grep -q 'module path; touch' "$TEST_TMPDIR/build/nginx-1.30.7/configure.args"
}

@test "Nginx source resolver failure aborts before build directories or compilation" {
    run bash -c '
        . "$REAL_BASE_DIR/scripts/nginx/nginx_build.sh"
        get_cpu_cores() { echo 1; }
        determine_nginx_version() { return 1; }
        run() { echo UNEXPECTED-MUTATION; return 1; }
        NGINX_RELEASE_VERSION=""
        NGINX_BUILD_DIR="$TEST_TMPDIR/build"
        NGINX_EXTRA_MODULE_DIR="$TEST_TMPDIR/modules"
        ! build_nginx_from_source
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED-MUTATION* ]]
    [ ! -e "$TEST_TMPDIR/build" ]
}

@test "helper default BASE_DIR is the checkout root when sourced without an override" {
    mkdir -p "$TEST_TMPDIR/fixture/scripts"
    cp "$REAL_BASE_DIR/scripts/utils.sh" "$TEST_TMPDIR/fixture/scripts/"
    printf 'UAT_PROBE=literal\n' > "$TEST_TMPDIR/fixture/.env"
    # shellcheck disable=SC2016 # The child evaluates the fixture variables.
    run env -u BASE_DIR LEMPER_CORE_DIR="$REAL_BASE_DIR/lib/core" bash -c '
        cd /
        . "$1/scripts/utils.sh" || exit 1
        printf "ROOT=%s PROBE=%s\n" "$BASE_DIR" "$UAT_PROBE"
    ' _ "$TEST_TMPDIR/fixture"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ROOT=$TEST_TMPDIR/fixture PROBE=literal"* ]]
}
@test "installed configuration schema accepts installer-written hostname and SSH port metadata" {
    printf 'HOSTNAME=uat-container\nSERVER_SSH_PORT=2269\n' > "$TEST_TMPDIR/metadata"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        validate_config_file "$1" strict || exit 1
        printf "HOSTNAME=bad;command\n" > "$1"
        ! validate_config_file "$1" strict
    ' _ "$TEST_TMPDIR/metadata"
    [ "$status" -eq 0 ]
}
@test "fresh encrypted config seeds profile settings and preserves existing configuration on repeat init" {
    local core_fixture="$TEST_TMPDIR/config.sh"
    UAT_STATE="$TEST_TMPDIR/state" awk '{gsub(/\/etc\/lemper/,ENVIRON["UAT_STATE"]); print}' \
        "$REAL_BASE_DIR/lib/core/config.sh" >"$TEST_TMPDIR/config.sh"
    printf 'INSTALL_REDIS=false\nSERVER_PROFILE=small\nSSH_PORT=2269\n' > "$TEST_TMPDIR/profile"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$1/config.sh"
        success() { :; }
        save_log() { :; }
        ENVFILE="$1/profile"
        ENCRYPT_CONFIG_AT_REST=true
        DRYRUN=false
        core_init_config || exit 1
        before=$(sha256sum "$1/state/lemper.conf")
        openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 -pass file:"$1/state/.config_key" -in "$1/state/lemper.conf" -out "$1/decoded"
        grep -qx SERVER_PROFILE=small "$1/decoded" || exit 1
        grep -qx INSTALL_REDIS=false "$1/decoded" || exit 1
        printf "SERVER_PROFILE=large\n" > "$1/profile"
        core_init_config || exit 1
        [ "$(sha256sum "$1/state/lemper.conf")" = "$before" ] || exit 1
        [ "$(stat -c %a "$1/state/lemper.conf")" = 600 ]
    ' _ "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "operation lock remains private without leaking its umask into installer callbacks" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        LEMPER_OPERATION_LOCK="$TEST_TMPDIR/lock"
        DRYRUN=false
        umask 022
        callback() { printf "public\n" > "$TEST_TMPDIR/public"; }
        lemper_with_lock callback || exit 1
        [ "$(stat -c %a "$LEMPER_OPERATION_LOCK")" = 600 ] || exit 1
        [ "$(stat -c %a "$TEST_TMPDIR/public")" = 644 ] || exit 1
        [ "$(umask)" = 0022 ]
    '
    [ "$status" -eq 0 ]
}
@test "site state driver is idempotent and keeps enabled configuration linked to the source" {
    mkdir -p "$TEST_TMPDIR/nginx/sites-available" "$TEST_TMPDIR/nginx/sites-enabled"
    printf 'vhost\n' > "$TEST_TMPDIR/nginx/sites-available/example.test.conf"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        DRYRUN=false
        LEMPER_NGINX_DIR="$TEST_TMPDIR/nginx"
        lemper_nginx_site_set_enabled example.test true || exit 1
        lemper_nginx_site_set_enabled example.test true || exit 1
        [ -L "$LEMPER_NGINX_DIR/sites-enabled/example.test.conf" ] || exit 1
        lemper_nginx_site_set_enabled example.test false || exit 1
        lemper_nginx_site_set_enabled example.test false || exit 1
        [ ! -e "$LEMPER_NGINX_DIR/sites-enabled/example.test.conf" ]
    '
    [ "$status" -eq 0 ]
}
@test "SSH policy refresh updates socket-activated listeners without starting an idle daemon" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        DRYRUN=false
        systemctl() {
            if [[ "$1" == is-active ]]; then [[ "$3" == ssh.socket ]]; else printf "%s\n" "$*"; fi
        }
        apply_ssh_service_policy
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *daemon-reload* ]]
    [[ "$output" == *"restart ssh.socket"* ]]
    [[ "$output" == *"try-restart ssh.service"* ]]
}

@test "public backup help is command-specific without root or private configuration" {
    run test_run_public "$REAL_BASE_DIR" bin/lemper-cli.sh backup --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"configuration backup and restore"* ]]
    [[ "$output" == *"--dir"* ]]
}
