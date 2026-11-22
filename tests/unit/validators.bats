#!/usr/bin/env bats
##
# Unit tests for validation and sanitization helpers in scripts/utils.sh.
#
# Each helper is exercised in a child shell so the Bats `run` helper stays
# available, and external commands are PATH-shadowed where the helper's
# behaviour depends on them.
##

load env_helper

setup() {
    unit_setup
}

# Source utils.sh without re-parsing the dotenv file: the top-of-file parser
# runs in a process substitution before the function is defined, which is
# racy in non-interactive shells.
load_utils_child='
    safe_parse_dotenv() { :; }
    . "${REAL_BASE_DIR}/scripts/utils.sh"
'

@test "validate_fqdn accepts valid domains" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_fqdn "$1"' _ example.com
    [ "${status}" -eq 0 ]
    [ "${output}" = "true" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_fqdn "$1"' _ sub.example.co.uk
    [ "${output}" = "true" ]
}

@test "validate_fqdn rejects injection and malformed input" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_fqdn "$1"' _ 'example.com; id'
    [ "${output}" = "false" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_fqdn "$1"' _ 'not a domain'
    [ "${output}" = "false" ]
}

@test "validate_ipv4 accepts valid addresses and rejects ranges" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_ipv4 "$1"' _ 192.168.1.10
    [ "${output}" = "true" ]

    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' validate_ipv4 "$1"' _ 256.1.1.1
    [ "${output}" = "false" ]
}

@test "sanitize_sed_replacement escapes regex metacharacters" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' sanitize_sed_replacement "$1"' _ 'a/b&c\d'
    [ "${status}" -eq 0 ]
    [ "${output}" = 'a\/b\&c\\d' ]
}

@test "sanitize_sed_pattern escapes opening brackets" {
    run env BASE_DIR="${BASE_DIR}" bash -c "${load_utils_child}"' sanitize_sed_pattern "$1"' _ 'a[b]'
    [ "${status}" -eq 0 ]
    [ "${output}" = 'a\[b]' ]
}

@test "validate_nginx_config reflects the nginx exit status" {
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/nginx" <<'EOF'
#!/usr/bin/env bash
exit "${MOCK_NGINX_EXIT:-0}"
EOF
    chmod +x "${TEST_TMPDIR}/bin/nginx"

    run env PATH="${TEST_TMPDIR}/bin:${PATH}" BASE_DIR="${BASE_DIR}" MOCK_NGINX_EXIT=0 \
        bash -c "${load_utils_child}"' validate_nginx_config'
    [ "${output}" = "true" ]

    run env PATH="${TEST_TMPDIR}/bin:${PATH}" BASE_DIR="${BASE_DIR}" MOCK_NGINX_EXIT=1 \
        bash -c "${load_utils_child}"' validate_nginx_config'
    [ "${output}" = "false" ]
}

@test "shared validators reject whole-value newline carriage-return and command syntax bypasses" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        for value in $'\''example.test\ninvalid-line'\'' $'\''invalid-line\nexample.test'\'' $'\''example.test\r'\'' "example.test%0aevil" "example.test;id"; do
            [[ $(core_validate_fqdn "$value") == false ]] || exit 1
            ! is_valid_domain "$value" || exit 1
        done
        [[ $(core_validate_ipv4 $'\''127.0.0.1\nevil'\'') == false ]] || exit 1
        [[ $(core_validate_username $'\''alice\nevil'\'') == false ]] || exit 1
        [[ $(core_validate_fqdn example.test.) == true ]] || exit 1
        ! is_valid_domain example.test. || exit 1
        is_valid_username alice
    '
    [ "$status" -eq 0 ]
}

@test "semantic IPv6 validator handles compression and IPv4 tails and rejects malformed addresses" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        for value in :: ::1 2001:db8::1 2001:db8:0:1:2:3:4:5 fe80::abcd ::ffff:192.0.2.1 1:2:3:4:5:6:192.0.2.1; do
            [[ $(core_validate_ipv6 "$value") == true ]] || { echo "Rejected valid $value"; exit 1; }
        done
        for value in ::: 1::2::3 1:2:3 1:2:3:4:5:6:7:8:: ::ffff:999.0.0.1 ::ffff:192.00.2.1 :1:2:3:4:5:6:7 ::1%eth0 $'\''::1\nevil'\''; do
            [[ $(core_validate_ipv6 "$value") == false ]] || { echo "Accepted invalid $value"; exit 1; }
        done
        [[ $(core_validate_ipv4 008.009.010.011) == true ]]
    '
    [ "$status" -eq 0 ]
}

@test "selfssl rejects hostile domains and malformed IPv6 before mutation and keeps valid dry-run behavior" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/ssl/commands
        fail() { echo REJECTED; exit 1; }
        info() { echo "$*"; }
        DRYRUN=true
        generate_selfsigned_ssl example.test 127.0.0.1 2001:db8::1
    '
    [ "$status" -eq 0 ]
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/ssl/commands
        fail() { echo REJECTED; exit 1; }
        mkdir() { echo MUTATION; }
        sed_inplace() { echo MUTATION; }
        generate_selfsigned_ssl "$1" 127.0.0.1 "$2"
    ' _ $'example.test\ninvalid-line' ::1
    [ "$status" -ne 0 ]
    [[ "$output" == *REJECTED* && "$output" != *MUTATION* ]]
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/ssl/commands
        fail() { echo REJECTED; exit 1; }
        mkdir() { echo MUTATION; }
        sed_inplace() { echo MUTATION; }
        generate_selfsigned_ssl example.test 127.0.0.1 :::
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *REJECTED* && "$output" != *MUTATION* ]]
}
