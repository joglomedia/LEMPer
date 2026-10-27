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
