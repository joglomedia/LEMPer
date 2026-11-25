#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
}

@test "site welcome page uses the shared asset outside the checkout directory" {
    run bash -c '
        cd "$TEST_TMPDIR" || exit 1
        . "$REAL_BASE_DIR/lib/services/site/skeletons.sh"
        SERVERNAME=example.test
        create_index_file >"$TEST_TMPDIR/index.html"
    '
    [ "$status" -eq 0 ]
    grep -Fq '<title>Welcome to example.test | LEMPer</title>' "$TEST_TMPDIR/index.html"
    grep -Fq '<span id="site-name">example.test</span>' "$TEST_TMPDIR/index.html"
    sed -e 's|<title>Welcome to example.test \| LEMPer</title>|<title>Welcome \| LEMPer</title>|' \
        -e 's|<span id="site-name">example.test</span>|<span id="site-name">your website</span>|' \
        "$TEST_TMPDIR/index.html" >"$TEST_TMPDIR/normalized.html"
    cmp "$REAL_BASE_DIR/share/nginx/html/index.html" "$TEST_TMPDIR/normalized.html"
}

@test "site names remain escaped text in the page and title" {
    local name=$'<script>alert("fixture")</script>&\'$(printf INJECTION)'
    run bash -c '
        . "$REAL_BASE_DIR/lib/services/site/skeletons.sh"
        SERVERNAME="$1"
        create_index_file >"$TEST_TMPDIR/index.html"
    ' _ "$name"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016 # Command substitution must remain literal text.
    grep -Fq '&lt;script&gt;alert(&quot;fixture&quot;)&lt;/script&gt;&amp;&#39;$(printf INJECTION)' "$TEST_TMPDIR/index.html"
    run grep -Fq '<script>' "$TEST_TMPDIR/index.html"
    [ "$status" -eq 1 ]
}

@test "exported service symlinks resolve the selected release welcome asset" {
    mkdir -p "$TEST_TMPDIR/release/lib/services/site" "$TEST_TMPDIR/release/share/nginx/html"
    cp "$REAL_BASE_DIR/lib/services/site/skeletons.sh" "$TEST_TMPDIR/release/lib/services/site/"
    cp "$REAL_BASE_DIR/share/nginx/html/index.html" "$TEST_TMPDIR/release/share/nginx/html/"
    printf '<!-- selected release fixture -->\n' >>"$TEST_TMPDIR/release/share/nginx/html/index.html"
    ln -s "$TEST_TMPDIR/release/lib/services" "$TEST_TMPDIR/exported-services"
    run bash -c '
        . "$TEST_TMPDIR/exported-services/site/skeletons.sh"
        unset SERVERNAME
        create_index_file >"$TEST_TMPDIR/index.html"
    '
    [ "$status" -eq 0 ]
    grep -Fq '<!-- selected release fixture -->' "$TEST_TMPDIR/index.html"
    grep -Fq '<title>Welcome to your website | LEMPer</title>' "$TEST_TMPDIR/index.html"
}

@test "welcome page dry run emits no HTML without installed assets" {
    cp "$REAL_BASE_DIR/lib/services/site/skeletons.sh" "$TEST_TMPDIR/skeletons.sh"
    run bash -c '
        . "$TEST_TMPDIR/skeletons.sh"
        info() { printf "%s\n" "$*"; }
        DRYRUN=true
        create_index_file
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'dry run mode'* ]]
    [[ "$output" != *'<html'* ]]
    [ ! -e "$TEST_TMPDIR/index.html" ]
}

@test "missing welcome asset fails without publishing partial HTML" {
    mkdir -p "$TEST_TMPDIR/release/lib/services/site"
    cp "$REAL_BASE_DIR/lib/services/site/skeletons.sh" "$TEST_TMPDIR/release/lib/services/site/"
    run bash -c '
        . "$TEST_TMPDIR/release/lib/services/site/skeletons.sh"
        create_index_file >"$TEST_TMPDIR/index.html"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'Unable to read the welcome page template.'* ]]
    [ ! -s "$TEST_TMPDIR/index.html" ]
}
