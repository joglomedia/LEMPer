#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child Bash/PHP programs keep literal variables.
load env_helper
load release_helper
setup() {
    unit_setup
    mkdir -p "$TEST_TMPDIR/root" "$TEST_TMPDIR/source/public_html" "$TEST_TMPDIR/source/program/include" "$TEST_TMPDIR/source/vendor/composer"
    printf '<?php\n' > "$TEST_TMPDIR/source/public_html/index.php"
    printf '<?php\n' > "$TEST_TMPDIR/source/program/include/rcmail.php"
    printf '<?php\n' > "$TEST_TMPDIR/source/vendor/autoload.php"
    printf '<?php\n' > "$TEST_TMPDIR/source/vendor/composer/platform_check.php"
    tar -czf "$TEST_TMPDIR/package" -C "$TEST_TMPDIR" --transform='s,^source,roundcubemail-1.7.6,' source
    release_fixture roundcube/roundcubemail 1.7.6 roundcubemail-1.7.6-complete.tar.gz "$(sha256sum "$TEST_TMPDIR/package" | cut -d ' ' -f1)"
}
release_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    lemper_load_module services/site/releases
    lemper_load_module services/nginx/release-site
    error() { printf "%s\n" "$*" >&2; }
    info() { printf "%s\n" "$*"; }
    # Host prerequisites and privilege switching are stubbed; every mutation
    # stays in the private fixture. Preflight itself is tested separately.
    lemper_site_release_preflight() { :; }
    sudo() { shift 2; [[ "$1" != -- ]] || shift; "$@"; }
    php8.3() { return "${TEST_PLATFORM_STATUS:-0}"; }
    curl() {
        [[ "${TEST_DOWNLOAD_STATUS:-0}" == 0 ]] || return "$TEST_DOWNLOAD_STATUS"
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == -o ]]; then
                case "${!#}" in
                    https://api.github.com/*) cp "$TEST_TMPDIR/metadata" "$2" ;;
                    *) cp "$TEST_TMPDIR/package" "$2" ;;
                esac
                return
            fi
            shift
        done
        return 1
    }
'
@test "complete release publication flattens the package and keeps existing configuration on repeat" {
    run bash -c "$release_child"'
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3 || exit
        printf "private configuration" > "$TEST_TMPDIR/root/config.inc.php"
        curl() { echo UNEXPECTED_DOWNLOAD; return 1; }
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED_DOWNLOAD* ]]
    [ -s "$TEST_TMPDIR/root/public_html/index.php" ]
    [ ! -d "$TEST_TMPDIR/root/roundcubemail-1.7.6" ]
    [ "$(cat "$TEST_TMPDIR/root/config.inc.php")" = 'private configuration' ]
    [ "$(stat -c %a "$TEST_TMPDIR/root/.lemper-release")" = 600 ]
}
@test "checksum or download failures leave the target empty and remove staging" {
    for scenario in checksum download; do
        run bash -c "$release_child"'
            case "$1" in
                checksum) printf tampered >> "$TEST_TMPDIR/package" ;;
                download) TEST_DOWNLOAD_STATUS=22 ;;
            esac
            lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
        ' _ "$scenario"
        [ "$status" -ne 0 ]
        [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
        [ -z "$(find "$TEST_TMPDIR" -maxdepth 1 -name '.lemper-release-*' -print -quit)" ]
    done
}
@test "missing application markers or an incompatible runtime prevents publication" {
    run bash -c "$release_child"'
        TEST_PLATFORM_STATUS=42
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -ne 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    run bash -c "$release_child"'
        lemper_load_module services/site/applications
        lemper_site_application_check_files() { return 1; }
        lemper_load_module() { :; }
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -ne 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
}
@test "existing unowned project files are retained without downloads" {
    printf retained > "$TEST_TMPDIR/root/index.php"
    run bash -c "$release_child"'
        curl() { echo MUTATION; }
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATION* ]]
    [ "$(cat "$TEST_TMPDIR/root/index.php")" = retained ]
}
@test "release dry-run creates no files and rejects unsafe targets and root pools" {
    run bash -c "$release_child"'
        DRYRUN=true
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -eq 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/site/releases
        error() { :; }
        DRYRUN=true
        for path in /etc/nginx /home/lemper/webapps /var/www /opt/lemper; do
            if lemper_site_release_preflight roundcube "$path" lemper 8.3; then exit 1; fi
        done
        if lemper_site_release_preflight mautic /home/root/webapps/example.test root 8.3; then exit 1; fi
        lemper_site_release_preflight mautic /home/lemper/webapps/example.test lemper 8.3
    '
    [ "$status" -eq 0 ]
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/site/create
        info() { printf "%s\n" "$*"; }
        check_required_packages() { echo MUTATION; return 1; }
        lemper_site_create_command -d example.test -f mautic -u lemper -p 8.3 -D -i
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATION* ]]
}
@test "archive traversal, absolute paths, links and duplicate entries fail before extraction" {
    local name
    for name in '../escape' '/absolute' 'a/../../escape' 'a\escape' $'line\nbreak'; do
        hostile_zip "$TEST_TMPDIR/hostile.zip" valid.php "$name"
        archive_exec zip "$TEST_TMPDIR/hostile.zip" "$TEST_TMPDIR/root" -
        [ "$status" -ne 0 ]
        [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    done
    mkdir "$TEST_TMPDIR/package-tree"
    ln -s /etc/passwd "$TEST_TMPDIR/package-tree/link"
    mkfifo "$TEST_TMPDIR/package-tree/pipe"
    tar -czf "$TEST_TMPDIR/hostile.tar.gz" -C "$TEST_TMPDIR" package-tree
    archive_exec tar "$TEST_TMPDIR/hostile.tar.gz" "$TEST_TMPDIR/root" package-tree
    [ "$status" -ne 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    hostile_zip "$TEST_TMPDIR/hostile.zip" same same
    archive_exec zip "$TEST_TMPDIR/hostile.zip" "$TEST_TMPDIR/root" -
    [ "$status" -ne 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    tar -cf "$TEST_TMPDIR/duplicate.tar" -C "$TEST_TMPDIR/source" vendor/autoload.php vendor/autoload.php
    archive_exec tar "$TEST_TMPDIR/duplicate.tar" "$TEST_TMPDIR/root" -
    [ "$status" -ne 0 ]
}
@test "release renderer keeps paths and route alternations literal and selects the public document root" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/site/releases
        lemper_load_module services/nginx/release-site
        error() { printf "%s\n" "$*" >&2; }
        lemper_site_release_render roundcube example.test "/srv/apps/site with space" lemper 8.3 > "$TEST_TMPDIR/roundcube.conf" || exit
        lemper_site_release_render mautic example.test "/srv/apps/site with space" lemper 8.3 > "$TEST_TMPDIR/mautic.conf"
    '
    [ "$status" -eq 0 ]
    grep -Fq 'root "/srv/apps/site with space/public_html";' "$TEST_TMPDIR/roundcube.conf"
    grep -Fq 'location ~ ^/(index|static)\.php(/|$)' "$TEST_TMPDIR/roundcube.conf"
    grep -Fq 'location ~ ^/(index\.php/)?installer(/|$)' "$TEST_TMPDIR/mautic.conf"
    grep -Fq 'fastcgi_param SCRIPT_FILENAME $document_root/index.php;' "$TEST_TMPDIR/mautic.conf"
    run grep -E '@[A-Z_]+@' "$TEST_TMPDIR/mautic.conf" "$TEST_TMPDIR/roundcube.conf"
    [ "$status" -eq 1 ]
}
@test "latest metadata selects complete assets dynamically and rejects unsafe or unverifiable releases" {
    local app repo tag name filter
    for app in mautic roundcube; do
        if [[ "$app" == mautic ]]; then repo=mautic/mautic tag=9.3.1 name=9.3.1.zip
        else repo=roundcube/roundcubemail tag=v2.4.9 name=roundcubemail-2.4.9-complete.tar.gz; fi
        release_fixture "$repo" "$tag" "$name"
        cp "$TEST_TMPDIR/metadata" "$TEST_TMPDIR/good"
        metadata_exec "$app" "$TEST_TMPDIR/metadata"
        [ "$status" -eq 0 ]
        [[ "$output" == "${tag#v}|"* ]]
        [[ "$output" == *'|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|'* ]]
        for filter in '.draft=true' '.prerelease=true' '.tag_name="../bad"' '.tag_name="9.3.1-rc1"' '.assets=[]' \
            '.assets[1].digest=null' '.assets[1].digest="sha1:invalid"' '.assets[1].browser_download_url="https://evil.test/app.zip"' \
            '.assets[1].state="new"' '.assets[1].state=null' '.assets += [.assets[1]]'; do
            jq "$filter" "$TEST_TMPDIR/good" >"$TEST_TMPDIR/metadata"
            metadata_exec "$app" "$TEST_TMPDIR/metadata"
            [ "$status" -ne 0 ]
        done
    done
}
@test "metadata failure never publishes a package or falls back to a fixed version" {
    printf '{broken-json' > "$TEST_TMPDIR/metadata"
    run bash -c "$release_child"'
        lemper_site_release_install roundcube "$TEST_TMPDIR/root" "$(id -un)" 8.3
    '
    [ "$status" -ne 0 ]
    [ -z "$(find "$TEST_TMPDIR/root" -mindepth 1 -print -quit)" ]
    [ -z "$(find "$TEST_TMPDIR" -maxdepth 1 -name '.lemper-release-*' -print -quit)" ]
}
