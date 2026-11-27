#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child programs and literal fixture values.
load env_helper
setup() {
    unit_setup
    export LEMPER_APT_ROOT="$TEST_TMPDIR/apt"
    export TEST_APT_CALLS="$TEST_TMPDIR/apt-calls"
    mkdir -p "$LEMPER_APT_ROOT/sources.list.d"
}
php_repository_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    lemper_load_module services/php/repository
    error() { printf "%s\n" "$*" >&2; }
    warning() { :; }
    info() { :; }
    DISTRIB_NAME=ubuntu RELEASE_NAME=resolute
    lemper_php_repository_keyring() { printf "%s/keyrings/sury.gpg\n" "$LEMPER_APT_ROOT"; }
    lemper_php_install_archive_keyring() { install -d "${1%/*}"; printf "synthetic-key" >"$1"; }
    apt-get() { printf "%s\n" "$*" >>"$TEST_APT_CALLS"; [[ "${TEST_APT_FAIL:-false}" != true ]]; }
'

@test "Sury bootstrap publishes only the verified package data member" {
    local root="$TEST_TMPDIR/key-package"
    mkdir -p "$root/DEBIAN" "$root/usr/share/keyrings"
    printf '%s\n' 'Package: debsuryorg-archive-keyring' 'Version: 1' 'Architecture: all' \
        'Maintainer: Fixture <fixture@example.test>' 'Description: Test fixture' >"$root/DEBIAN/control"
    printf 'fixture-public-key\n' >"$root/usr/share/keyrings/debsuryorg-archive-keyring.gpg"
    dpkg-deb --build "$root" "$TEST_TMPDIR/fixture.deb" >/dev/null
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/php/repository || exit 1
        LEMPER_APT_ROOT=/etc/apt
        key=/usr/share/keyrings/debsuryorg-archive-keyring.gpg
        published="$TEST_TMPDIR/published-key"
        expected="$TEST_TMPDIR/key-package$key"
        curl() {
            while [[ $# -gt 0 && "$1" != -o ]]; do shift; done
            [[ $# -ge 2 ]] && cp -- "$TEST_TMPDIR/fixture.deb" "$2"
        }
        mktemp() {
            if [[ "$1" == "$key.XXXXXXXX" ]]; then command mktemp "$TEST_TMPDIR/prepared.XXXXXXXX"
            else command mktemp "$@"; fi
        }
        lemper_php_repository_key_valid() {
            if [[ "$1" == "$key" ]]; then cmp -s -- "$published" "$expected"
            else cmp -s -- "$1" "$expected"; fi
        }
        lemper_exec() {
            case "$1" in
                install) command "$@" ;;
                mv) [[ "$4" == "$key" ]] && command mv -Tf -- "$3" "$published" ;;
                *) echo UNEXPECTED_EXEC; return 1 ;;
            esac
        }
        DRYRUN=false lemper_php_install_archive_keyring "$key" || exit 1
        cmp -- "$published" "$expected"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED_EXEC* ]]
}
@test "supported Ubuntu LTS versions resolve without lsb-release and interim releases remain rejected" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/distro.sh"
        for pair in 22.04:jammy 24.04:noble 26.04:resolute LM21:jammy LM22:noble 25.10:unsupported LM23:unsupported; do
            [[ "$(core_ubuntu_release_codename "${pair%:*}")" == "${pair#*:}" ]] || exit 1
        done
    '
    [ "$status" -eq 0 ]
}
@test "distribution detection tolerates missing optional metadata under nounset" {
    mkdir -p "$TEST_TMPDIR/os/etc"
    printf 'ID=debian\nVERSION_ID=12\nVERSION_CODENAME=bookworm\n' >"$TEST_TMPDIR/os/etc/os-release"
    LEMPER_OS_FIXTURE="$TEST_TMPDIR/os" awk '{gsub(/\/etc\//,ENVIRON["LEMPER_OS_FIXTURE"] "/etc/"); print}' \
        "$REAL_BASE_DIR/lib/core/distro.sh" >"$TEST_TMPDIR/distro.sh"
    run bash -eu -c '
        . "$TEST_TMPDIR/distro.sh"
        [[ "$(core_get_distrib_name)" == debian ]]
        [[ "$(core_get_release_name)" == bookworm ]]
        [[ "$(core_get_release_version)" == 12 ]]
    '
    [ "$status" -eq 0 ]
    printf 'ID=ubuntu\nVERSION_ID=26.04\nUBUNTU_CODENAME=resolute\n' >"$TEST_TMPDIR/os/etc/os-release"
    run bash -eu -c '
        . "$TEST_TMPDIR/distro.sh"
        [[ "$(core_get_distrib_name)" == ubuntu ]]
        [[ "$(core_get_release_name)" == resolute ]]
    '
    [ "$status" -eq 0 ]
}
@test "new PHP repositories use Sury for every supported Ubuntu release without legacy global trust" {
    run bash -c "$php_repository_child"'
        for RELEASE_NAME in jammy noble resolute; do
            rm -f "$LEMPER_APT_ROOT/sources.list.d/php.list"
            lemper_php_prepare_repository || exit
            grep -Fxq "deb [signed-by=$LEMPER_APT_ROOT/keyrings/sury.gpg] https://packages.sury.org/php/ $RELEASE_NAME main" "$LEMPER_APT_ROOT/sources.list.d/php.list" || exit 1
        done
        [[ ! -e "$LEMPER_APT_ROOT/trusted.gpg.d" ]]
    '
    [ "$status" -eq 0 ]
}
@test "PHP migration preserves source options and unrelated repositories across list and deb822 files" {
    cat >"$LEMPER_APT_ROOT/sources.list.d/old.list" <<'LIST'
deb [arch=arm64] https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main
deb-src http://ppa.launchpad.net/ondrej/php/ubuntu noble main
deb [signed-by=/other/key] https://example.test/repo noble main
LIST
    cat >"$LEMPER_APT_ROOT/sources.list.d/old.sources" <<'SOURCES'
Types: deb deb-src
URIs: https://ppa.launchpadcontent.net/ondrej/php/ubuntu
 https://packages.sury.org/php/
Suites: noble
Architectures: arm64
Components: main
Signed-By: /old/key

Types: deb
URIs: https://example.test/other
Suites: noble
Components: main
Signed-By: /unrelated/key
SOURCES
    run bash -c "$php_repository_child"'
        lemper_php_prepare_repository || exit
        grep -Fq "arch=arm64 signed-by=$LEMPER_APT_ROOT/keyrings/sury.gpg" "$LEMPER_APT_ROOT/sources.list.d/old.list" || exit 1
        grep -Fq "deb-src [signed-by=" "$LEMPER_APT_ROOT/sources.list.d/old.list" || exit 1
        grep -Fxq "Suites: resolute" "$LEMPER_APT_ROOT/sources.list.d/old.sources" || exit 1
        grep -Fxq "Architectures: arm64" "$LEMPER_APT_ROOT/sources.list.d/old.sources" || exit 1
        grep -Fxq "URIs: https://example.test/other" "$LEMPER_APT_ROOT/sources.list.d/old.sources" || exit 1
        grep -Fxq "Signed-By: /unrelated/key" "$LEMPER_APT_ROOT/sources.list.d/old.sources" || exit 1
        [[ ! -f "$LEMPER_APT_ROOT/sources.list.d/php.list" ]]
    '
    [ "$status" -eq 0 ]
    [ -f "$LEMPER_APT_ROOT/sources.list.d/old.list.lemper-before-php-repository" ]
    run grep -q 'ondrej/php' "$LEMPER_APT_ROOT/sources.list.d/old.sources"
    [ "$status" -eq 1 ]
}
@test "PHP repository repeat preserves existing source bytes and APT failure restores all originals" {
    printf 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main\n' >"$LEMPER_APT_ROOT/sources.list.d/old.list"
    run env TEST_APT_FAIL=true bash -c "$php_repository_child"'
        lemper_php_prepare_repository
    '
    [ "$status" -ne 0 ]
    grep -Fxq 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main' "$LEMPER_APT_ROOT/sources.list.d/old.list"
    run bash -c "$php_repository_child"'
        lemper_php_prepare_repository || exit
        before=$(sha256sum "$LEMPER_APT_ROOT/sources.list.d/old.list")
        lemper_php_prepare_repository || exit
        [[ "$(sha256sum "$LEMPER_APT_ROOT/sources.list.d/old.list")" == "$before" ]]
    '
    [ "$status" -eq 0 ]
}

@test "disabled or source-only PHP entries cannot prevent enabling the binary archive" {
    printf 'Types: deb-src\nURIs:\n https://ppa.launchpadcontent.net/ondrej/php/ubuntu\nSuites: noble\nComponents: main\nEnabled: no\n' >"$LEMPER_APT_ROOT/sources.list.d/old.sources"
    run bash -c "$php_repository_child"'lemper_php_prepare_repository'
    [ "$status" -eq 0 ]
    grep -Fxq 'Enabled: no' "$LEMPER_APT_ROOT/sources.list.d/old.sources"
    grep -Fq 'https://packages.sury.org/php/ resolute main' "$LEMPER_APT_ROOT/sources.list.d/php.list"
}
@test "PHP repository preflight rejects mixed URIs and signature bypasses before key installation" {
    cat >"$LEMPER_APT_ROOT/sources.list.d/mixed.sources" <<'SOURCES'
Types: deb
URIs: https://ppa.launchpadcontent.net/ondrej/php/ubuntu https://example.test/repo
Suites: noble
Components: main
SOURCES
    run bash -c "$php_repository_child"'lemper_php_prepare_repository'
    [ "$status" -ne 0 ] && [ ! -d "$LEMPER_APT_ROOT/keyrings" ]
    printf 'Types: deb\nURIs: https://packages.sury.org/php/\nSuites: resolute\nComponents: main\nTrusted: yes\n' >"$LEMPER_APT_ROOT/sources.list.d/mixed.sources"
    run bash -c "$php_repository_child"'lemper_php_prepare_repository'
    [ "$status" -ne 0 ] && [ ! -d "$LEMPER_APT_ROOT/keyrings" ]
}
@test "PHP repository dry-run has no downloads, source backups, key files or package-manager calls" {
    printf 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main\n' >"$LEMPER_APT_ROOT/sources.list.d/old.list"
    run bash -c "$php_repository_child"'
        DRYRUN=true
        lemper_php_install_archive_keyring() { echo UNEXPECTED; return 1; }
        lemper_php_prepare_repository
    '
    [ "$status" -eq 0 ] && [[ "$output" != *UNEXPECTED* ]]
    [ ! -d "$LEMPER_APT_ROOT/keyrings" ] && [ ! -e "$TEST_APT_CALLS" ]
    [ ! -e "$LEMPER_APT_ROOT/sources.list.d/old.list.lemper-before-php-repository" ]
}
@test "PHP source removal preserves shared keyrings and unrelated sources" {
    printf 'deb https://packages.sury.org/php/ resolute main\ndeb https://example.test/repo noble main\n' >"$LEMPER_APT_ROOT/sources.list"
    run bash -c "$php_repository_child"'
        install -d "$LEMPER_APT_ROOT/keyrings"
        printf shared >"$LEMPER_APT_ROOT/keyrings/sury.gpg"
        lemper_php_remove_repository || exit
        [[ "$(cat "$LEMPER_APT_ROOT/keyrings/sury.gpg")" == shared ]]
    '
    [ "$status" -eq 0 ]
    grep -Fxq 'deb https://example.test/repo noble main' "$LEMPER_APT_ROOT/sources.list"
    run grep -q packages.sury.org "$LEMPER_APT_ROOT/sources.list"
    [ "$status" -eq 1 ] && [ ! -e "$TEST_APT_CALLS" ]
}

@test "migration retains an Ondrej signing key still used by another archive" {
    mkdir -p "$LEMPER_APT_ROOT/trusted.gpg.d"
    printf old-key >"$LEMPER_APT_ROOT/trusted.gpg.d/ondrej-php-resolute.gpg"
    printf 'deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main\ndeb https://ppa.launchpadcontent.net/ondrej/apache2/ubuntu noble main\n' >"$LEMPER_APT_ROOT/sources.list"
    run bash -c "$php_repository_child"'
        gpg() {
            if [[ "$*" == *ondrej-php* ]]; then printf "pub::::::::::\nfpr:::::::::14AA40EC0831756756D7F66C4F4EA0AAE5267A6C:\n"
            else printf "pub::::::::::\nfpr:::::::::15058500A0235D97F5D10063B188E2B695BD4743:\n"; fi
        }
        lemper_php_prepare_repository
    '
    [ "$status" -eq 0 ]
    [ -f "$LEMPER_APT_ROOT/trusted.gpg.d/ondrej-php-resolute.gpg" ]
    grep -Fq 'ondrej/apache2/ubuntu noble main' "$LEMPER_APT_ROOT/sources.list"
}
@test "Sury fingerprint verification rejects extra primary keys and unsupported releases do not mutate" {
    printf synthetic >"$TEST_TMPDIR/key.gpg"
    run bash -c "$php_repository_child"'
        gpg() { printf "pub::::::::::\nfpr:::::::::15058500A0235D97F5D10063B188E2B695BD4743:\npub::::::::::\nfpr:::::::::OTHER:\n"; }
        lemper_php_repository_key_valid "$TEST_TMPDIR/key.gpg"
    '
    [ "$status" -ne 0 ]
    run bash -c "$php_repository_child"'
        RELEASE_NAME=questing
        lemper_php_prepare_repository
    '
    [ "$status" -ne 0 ] && [ ! -d "$LEMPER_APT_ROOT/keyrings" ]
}
