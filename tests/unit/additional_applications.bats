#!/usr/bin/env bats
# shellcheck disable=SC2016 # Child Bash/JSON programs retain literal variables.
load env_helper
load release_helper
setup() { unit_setup; }

@test "new automatic apps accept dry-run installation while XenForo rejects licensed downloads before mutation" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/site/commands
        error() { printf "%s\n" "$*" >&2; }
        info() { :; }
        for type in snappymail nextcloud mybb phplist ojs slim; do
            lemper_site_create example.test --type="$type" --runtime-user=lemper --install-skeleton --dry-run || exit
        done
        if lemper_site_create example.test --type=xenforo --install-skeleton --dry-run; then exit 1; fi
    '
    [ "$status" -eq 0 ]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}

@test "new release providers select full packages and explicitly distinguish source transport from published digests" {
    local app repo tag name version prefix
    while IFS='|' read -r app repo tag name version prefix; do
        release_fixture "$repo" "$tag" "$name"
        metadata_exec "$app" "$TEST_TMPDIR/metadata"
        [ "$status" -eq 0 ]
        [[ "$output" == "$version|"* && "$output" == *"|$prefix" ]]
        jq '.assets[1].digest=null' "$TEST_TMPDIR/metadata" >"$TEST_TMPDIR/bad"
        metadata_exec "$app" "$TEST_TMPDIR/bad"
        [ "$status" -ne 0 ]
    done <<'CASES'
snappymail|the-djmaze/snappymail|v9.2.1|snappymail-9.2.1.tar.gz|9.2.1|-
mybb|mybb/mybb|mybb_1899|mybb_1899.zip|1.8.99|only:Upload
nextcloud|nextcloud-releases/server|v99.0.1|nextcloud-99.0.1.tar.bz2|99.0.1|nextcloud
CASES
    for app in phplist slim; do
        if [[ "$app" == phplist ]]; then repo=phpList/phplist3; else repo=slimphp/Slim-Skeleton; fi
        jq -n --arg url "https://api.github.com/repos/$repo/tarball/v4.9.1" \
            '{tag_name:"v4.9.1",draft:false,prerelease:false,tarball_url:$url}' >"$TEST_TMPDIR/metadata"
        metadata_exec "$app" "$TEST_TMPDIR/metadata"
        [ "$status" -eq 0 ]
        [[ "$output" == *'|https|tar|github:'* ]]
        jq '.tarball_url="https://evil.test/archive"' "$TEST_TMPDIR/metadata" >"$TEST_TMPDIR/bad"
        metadata_exec "$app" "$TEST_TMPDIR/bad"
        [ "$status" -ne 0 ]
    done
}

@test "Nextcloud distribution must match the latest source release and PKP manifest URLs remain constrained" {
    jq -n '{tag_name:"v35.1.9",draft:false,prerelease:false,assets:[]}' >"$TEST_TMPDIR/metadata"
    metadata_exec nextcloud-tag "$TEST_TMPDIR/metadata"
    [ "$status" -eq 0 ] && [ "$output" == v35.1.9 ]
    metadata_exec nextcloud "$TEST_TMPDIR/metadata" v33.0.1
    [ "$status" -ne 0 ]
    printf '<version><application>ojs2</application><release>3.5.0.99</release><package>https://pkp.sfu.ca/ojs/download/ojs-3.5.0-99.tar.gz</package></version>' >"$TEST_TMPDIR/metadata"
    metadata_exec ojs "$TEST_TMPDIR/metadata"
    [ "$status" -eq 0 ]
    [ "$output" == '3.5.0-99|https://pkp.sfu.ca/ojs/download/ojs-3.5.0-99.tar.gz|https|tar|ojs-3.5.0-99' ]
    { printf '<!DOCTYPE version SYSTEM "../../lib/pkp/dtd/version.dtd">\n'; cat "$TEST_TMPDIR/metadata"; } >"$TEST_TMPDIR/official"
    metadata_exec ojs "$TEST_TMPDIR/official"
    [ "$status" -eq 0 ]
    sed 's,https://pkp.sfu.ca,https://evil.test,' "$TEST_TMPDIR/metadata" >"$TEST_TMPDIR/bad"
    metadata_exec ojs "$TEST_TMPDIR/bad"
    [ "$status" -ne 0 ]
    printf '<!DOCTYPE version [<!ENTITY secret SYSTEM "file:///etc/passwd">]><version><application>ojs2</application><release>&secret;</release></version>' >"$TEST_TMPDIR/bad"
    metadata_exec ojs "$TEST_TMPDIR/bad"
    [ "$status" -ne 0 ]
}

@test "DOS ZIP directory names and restrictive umasks produce usable regular package files" {
    mkdir "$TEST_TMPDIR/out"
    hostile_zip "$TEST_TMPDIR/dos.zip" tree/ tree/index.php
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/site/release_archive.sh"
        umask 077
        lemper_site_release_unpack zip "$TEST_TMPDIR/dos.zip" "$TEST_TMPDIR/out" tree
    '
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/out/index.php" ] && [ ! -L "$TEST_TMPDIR/out/index.php" ]
    [ "$(stat -c %a "$TEST_TMPDIR/out/index.php")" == 644 ]
}

@test "archive declared expansion limits and internal link cycles fail before writing" {
    mkdir -p "$TEST_TMPDIR/out" "$TEST_TMPDIR/nextcloud/dist"
    truncate -s 2147483649 "$TEST_TMPDIR/oversize"
    tar --sparse -cf "$TEST_TMPDIR/oversize.tar" -C "$TEST_TMPDIR" oversize
    archive_exec tar "$TEST_TMPDIR/oversize.tar" "$TEST_TMPDIR/out" -
    [ "$status" -ne 0 ] && [ -z "$(find "$TEST_TMPDIR/out" -mindepth 1 -print -quit)" ]
    ln -s second "$TEST_TMPDIR/nextcloud/dist/first"
    ln -s first "$TEST_TMPDIR/nextcloud/dist/second"
    tar -cf "$TEST_TMPDIR/cycle.tar" -C "$TEST_TMPDIR" nextcloud
    archive_exec tar "$TEST_TMPDIR/cycle.tar" "$TEST_TMPDIR/out" nextcloud internal-files
    [ "$status" -ne 0 ] && [ -z "$(find "$TEST_TMPDIR/out" -mindepth 1 -print -quit)" ]
}

@test "MyBB Upload filtering and GitHub source-root stripping keep unsafe archive paths rejected" {
    mkdir "$TEST_TMPDIR/out"
    mkdir -p "$TEST_TMPDIR/zip/Upload" "$TEST_TMPDIR/zip/Documentation" "$TEST_TMPDIR/phpList-phplist3-abc1234"
    printf '<?php' >"$TEST_TMPDIR/zip/Upload/index.php"
    printf documentation >"$TEST_TMPDIR/zip/Documentation/readme.html"
    (cd "$TEST_TMPDIR/zip"; zip -qr "$TEST_TMPDIR/mybb.zip" Upload Documentation)
    archive_exec zip "$TEST_TMPDIR/mybb.zip" "$TEST_TMPDIR/out" only:Upload
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/out/index.php" ] && [ ! -e "$TEST_TMPDIR/out/Documentation" ]
    rm "$TEST_TMPDIR/out/index.php"
    printf '<?php' >"$TEST_TMPDIR/phpList-phplist3-abc1234/index.php"
    tar -czf "$TEST_TMPDIR/source.tar.gz" -C "$TEST_TMPDIR" phpList-phplist3-abc1234
    archive_exec tar "$TEST_TMPDIR/source.tar.gz" "$TEST_TMPDIR/out" github:phpList-phplist3
    [ "$status" -eq 0 ] && [ -f "$TEST_TMPDIR/out/index.php" ]
    rm "$TEST_TMPDIR/out/index.php"
    hostile_zip "$TEST_TMPDIR/hostile.zip" Documentation/../../escape
    archive_exec zip "$TEST_TMPDIR/hostile.zip" "$TEST_TMPDIR/out" only:Upload
    [ "$status" -ne 0 ] && [ -z "$(find "$TEST_TMPDIR/out" -mindepth 1 -print -quit)" ]
}

@test "OJS preparation sets private external storage without inventing database credentials" {
    printf 'installed = Off\nfiles_dir = files\nbase_url = "https://pkp.sfu.ca"\n' > "$TEST_TMPDIR/config.TEMPLATE.inc.php"
    cp "$TEST_TMPDIR/config.TEMPLATE.inc.php" "$TEST_TMPDIR/config.inc.php"
    run bash -c '. "$REAL_BASE_DIR/lib/services/site/release_prepare.sh"; lemper_site_release_prepare "$@"' _ "$TEST_TMPDIR" /home/lemper/webapps/journal.test journal.test
    [ "$status" -eq 0 ]
    grep -Fx 'files_dir = "/home/lemper/webapps/journal.test-files"' "$TEST_TMPDIR/config.inc.php"
    grep -Fx 'installed = Off' "$TEST_TMPDIR/config.inc.php"
    [ "$(stat -c %a "$TEST_TMPDIR/config.inc.php")" = 600 ]
    run bash -c '. "$REAL_BASE_DIR/lib/services/site/release_prepare.sh"; lemper_site_release_prepare "$@"' _ "$TEST_TMPDIR" /home/lemper/webapps/journal.test journal.test
    [ "$status" -ne 0 ]
}
@test "Nextcloud internal file links are copied as regular files while escaping links remain rejected" {
    mkdir "$TEST_TMPDIR/out"
    local link
    mkdir -p "$TEST_TMPDIR/nextcloud/dist"
    printf license >"$TEST_TMPDIR/nextcloud/dist/base.license"
    for link in base.license /etc/passwd ../../outside; do
        ln -s "$link" "$TEST_TMPDIR/nextcloud/dist/alias.license"
        tar -czf "$TEST_TMPDIR/links.tar.gz" -C "$TEST_TMPDIR" nextcloud
        archive_exec tar "$TEST_TMPDIR/links.tar.gz" "$TEST_TMPDIR/out" nextcloud internal-files
        if [[ "$link" == base.license ]]; then
            [ "$status" -eq 0 ]
            [ "$(cat "$TEST_TMPDIR/out/dist/alias.license")" == license ]
            [ ! -L "$TEST_TMPDIR/out/dist/alias.license" ]
            rm "$TEST_TMPDIR/out/dist/alias.license" "$TEST_TMPDIR/out/dist/base.license"
            rmdir "$TEST_TMPDIR/out/dist"
        else
            [ "$status" -ne 0 ] && [ -z "$(find "$TEST_TMPDIR/out" -mindepth 1 -print -quit)" ]
        fi
        rm "$TEST_TMPDIR/nextcloud/dist/alias.license"
    done
}

@test "application-specific rendering uses Unix PHP sockets and correct private routes and document roots" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/site/releases
        lemper_load_module services/nginx/release-site
        for type in snappymail nextcloud mybb phplist ojs slim xenforo; do
            lemper_site_release_render "$type" example.test /srv/apps/project lemper 8.3 > "$TEST_TMPDIR/$type.conf" || exit
            grep -Fq "unix:/run/php/php8.3-fpm.lemper.sock" "$TEST_TMPDIR/$type.conf" || exit 1
            if grep -q "127.0.0.1:9000\|@[A-Z_]*@" "$TEST_TMPDIR/$type.conf"; then exit 1; fi
        done
    '
    [ "$status" -eq 0 ]
    grep -Fq 'root "/srv/apps/project/public";' "$TEST_TMPDIR/slim.conf"
    grep -Fq 'root "/srv/apps/project/public_html/lists";' "$TEST_TMPDIR/phplist.conf"
    grep -Fq 'location ^~ /.well-known' "$TEST_TMPDIR/nextcloud.conf"
    grep -Fq 'fastcgi_param PATH_INFO $saved_path_info;' "$TEST_TMPDIR/nextcloud.conf"
    grep -Fq 'try_files $uri $uri/ /index.php?$uri&$args;' "$TEST_TMPDIR/xenforo.conf"
    grep -Fq 'location ^~ /internal_data/' "$TEST_TMPDIR/xenforo.conf"
}
