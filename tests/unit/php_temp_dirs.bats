#!/usr/bin/env bats
##
# Unit tests for SEC-12: PHP-FPM temp/session directories must live outside
# the user's home and the web root.
##

load env_helper

setup() {
    unit_setup
    mkdir -p "${TEST_TMPDIR}/bin"

    local cmd
    for cmd in mkdir chmod chown; do
        cat > "${TEST_TMPDIR}/bin/${cmd}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "${cmd}" "\$*" >> "${TEST_TMPDIR}/calls.log"
EOF
        chmod +x "${TEST_TMPDIR}/bin/${cmd}"
    done
}

@test "create_php_temp_dirs keeps PHP temp files outside the user home" {
    run env PATH="${TEST_TMPDIR}/bin:${PATH}" BASE_DIR="${BASE_DIR}" DRYRUN=false \
        bash -c '. "${REAL_BASE_DIR}/scripts/utils.sh"; create_php_temp_dirs lemper'
    [ "${status}" -eq 0 ]

    run cat "${TEST_TMPDIR}/calls.log"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"/var/lib/php/lemper/lemper/tmp"* ]]
    [[ "${output}" == *"/var/lib/php/lemper/lemper/sessions"* ]]
    [[ "${output}" == *"/var/lib/php/lemper/lemper/wsdlcache"* ]]
    [[ "${output}" == *"/var/lib/php/lemper/lemper/opcache"* ]]
    [[ "${output}" == *"chown -hR lemper:lemper /var/lib/php/lemper/lemper"* ]]
    [[ "${output}" != *"/home/"* ]]
}

@test "create_php_temp_dirs sets owner-only permissions" {
    run env PATH="${TEST_TMPDIR}/bin:${PATH}" BASE_DIR="${BASE_DIR}" DRYRUN=false \
        bash -c '. "${REAL_BASE_DIR}/scripts/utils.sh"; create_php_temp_dirs www-data'
    [ "${status}" -eq 0 ]

    run cat "${TEST_TMPDIR}/calls.log"
    [[ "${output}" == *"chmod 700 /var/lib/php/lemper/www-data"* ]]
}
