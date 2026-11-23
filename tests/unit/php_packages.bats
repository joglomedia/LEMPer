#!/usr/bin/env bats
setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
}

@test "bundled PHP module aliases resolve to packages belonging to the requested branch" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/php/packages.sh"
        apt-cache() { [[ "$1" == show && ( "$2" == php8.5-xml || "$2" == php8.5-common ) ]]; }
        [ "$(lemper_php_extension_package 8.5 xsl)" = php8.5-xml ] || exit 1
        [ "$(lemper_php_extension_package 8.5 tokenizer)" = php8.5-common ]
    '
    [ "$status" -eq 0 ]
}

@test "missing PHP extension packages do not fall back to another branch through a metapackage" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/php/packages.sh"
        apt-cache() { printf "%s\n" "$*" >> "$TEST_TMPDIR/queries"; [[ "$2" == php-geoip ]]; }
        ! lemper_php_extension_package 8.5 geoip || exit 1
        [ "$(cat "$TEST_TMPDIR/queries")" = "show php8.5-geoip" ]
    '
    [ "$status" -eq 0 ]
}

@test "PHP package selection rejects malformed input before querying apt" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/php/packages.sh"
        apt-cache() { echo CALLED; return 0; }
        ! lemper_php_extension_package "8.5;touch file" xml || exit 1
        ! lemper_php_extension_package 8.5 "../../etc" || exit 1
        ! lemper_php_extension_package 8.5 --option
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *CALLED* ]]
}

@test "fresh PHP installation requires versioned XML instead of a default-branch metapackage" {
    run grep -E 'php-common[[:space:]]+php-xml' "$REAL_BASE_DIR/lib/services/php/install.sh"
    [ "$status" -ne 0 ]
    run grep -F 'php-common "php${PHPv}-xml"' "$REAL_BASE_DIR/lib/services/php/install.sh"
    [ "$status" -eq 0 ]
}
