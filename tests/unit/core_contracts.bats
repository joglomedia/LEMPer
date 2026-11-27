#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }

core_child='
    . "${REAL_BASE_DIR}/lib/core/loader.sh"
    error() { printf "%s\n" "$*" >&2; }
    info() { :; }
'
@test "web administrator enrollment consumes stdin and replacement and revocation preserve other accounts" {
    [[ "$EUID" == 0 ]] || skip "requires the disposable root Linux test environment"
    run bash -c "$core_child"'
        directory="$TEST_TMPDIR/nginx"
        htpasswd() {
            [[ "$#" == 2 && "$1" == -nBi && -z "${LEMPER_PASSWORD:-}" ]] || return 1
            local secret
            IFS= read -r secret && [[ "$secret" == fixture-password ]] || return 1
            printf "%s:%s\n" "$2" "fixture-bcrypt-hash"
        }
        export LEMPER_PASSWORD=fixture-password
        for user in operatorone operatortwo operatorone; do
            lemper_account_admin_auth enroll "$user" "$directory" <<<fixture-password || exit 1
        done
        lemper_account_admin_auth revoke operatorone "$directory"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *fixture-password* ]]
    [ "$(stat -c '%U:%G:%a' "$TEST_TMPDIR/nginx/lemper-admin.htpasswd")" = root:www-data:640 ]
    [ "$(cat "$TEST_TMPDIR/nginx/lemper-admin.htpasswd")" = 'operatortwo:fixture-bcrypt-hash' ]
}

@test "web administrator enrollment refuses an unsafe existing verifier" {
    [[ "$EUID" == 0 ]] || skip "requires the disposable root Linux test environment"
    mkdir "$TEST_TMPDIR/nginx"
    printf '%s\n' retained >"$TEST_TMPDIR/existing"
    ln -s "$TEST_TMPDIR/existing" "$TEST_TMPDIR/nginx/lemper-admin.htpasswd"
    run bash -c "$core_child"'
        lemper_account_admin_auth enroll operatorone "$TEST_TMPDIR/nginx" <<<fixture-password
    '
    [ "$status" -ne 0 ]
    [ -L "$TEST_TMPDIR/nginx/lemper-admin.htpasswd" ]
    [ "$(cat "$TEST_TMPDIR/existing")" = retained ]
}

@test "web administrator enrollment works before Nginx or htpasswd is installed" {
    [[ "$EUID" == 0 ]] || skip "requires the disposable root Linux test environment"
    run bash -c "$core_child"'
        command() {
            if [[ "$*" == "-v htpasswd" ]]; then return 1; fi
            builtin command "$@"
        }
        lemper_account_admin_auth enroll bootstrap "$TEST_TMPDIR/nginx" <<<fixture-password
    '
    [ "$status" -eq 0 ]
    [ "$(stat -c '%U:%G:%a' "$TEST_TMPDIR/nginx/lemper-admin.htpasswd")" = root:www-data:640 ]
    grep -Eq '^bootstrap:\$6\$' "$TEST_TMPDIR/nginx/lemper-admin.htpasswd"
}

@test "account command selects administrator access only with the explicit role" {
    require_gnu_getopt
    run bash -c "$core_child"'
        lemper_load_module runtime/account/commands
        lemper_load_module() { :; }
        lemper_with_lock() { "$@"; }
        create_account() { printf "%s:%s\n" "$1" "$2"; }
        lemper_account_command hostinguser && lemper_account_command --admin operator
    '
    [ "$status" -eq 0 ]
    [ "$output" = $'hostinguser:hosting\noperator:admin' ]
}

@test "interactive account changes use the shared lock" {
    require_gnu_getopt
    run bash -c "$core_child"'
        lemper_load_module runtime/account/adduser
        header_msg() { :; }
        lemper_with_lock() { ( LOCK_HELD=true; "$@"; ); }
        prompt_for_user() { [[ "${LOCK_HELD:-}" == true ]] && echo inside-shared-lock; }
        init_lemper_adduser <<< "$(printf "y\nn\n")"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *inside-shared-lock* ]]
}

@test "shared parser preserves quoted values, short clusters and positional delimiters" {
    run bash -c "${core_child}"'
        lemper_parse_args "hvu:" "help,username:" -hv --username="value with spaces;\$()" -- "-literal"
        printf "<%s>\n" "${LEMPER_PARSED_ARGS[@]}"
    '
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "<-h>" ]
    [ "${lines[1]}" = "<-v>" ]
    [[ "${output}" == *"<value with spaces;"* ]]
    [ "${lines[5]}" = "<-literal>" ]
}
@test "shared parser rejects missing values and unknown options before dispatch" {
    run bash -c "${core_child}"' lemper_parse_args "" "directory:" --directory --unknown'
    [ "${status}" -ne 0 ]
    run bash -c "${core_child}"' lemper_parse_args "" "flag" --flag=value'
    [ "${status}" -ne 0 ]
}
@test "public defaults pass strict schema and invalid values never enter the environment" {
    run bash -c "${core_child}"'
        validate_config_file "${REAL_BASE_DIR}/.env.dist" strict
        printf "SSH_PORT=70000\n" > "$1"
        ! validate_config_file "$1" strict
        printf "PATH=/unsafe\n" > "$1"
        ! validate_config_file "$1" || exit 1
        printf "BASE_DIR=/unsafe\n" > "$1"
        ! validate_config_file "$1"
    ' _ "${TEST_TMPDIR}/invalid.env"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"/unsafe"* ]]
}
@test "schema rejects inverted FTP ranges and unknown strict keys, preserves legacy keys" {
    run bash -c "${core_child}"'
        printf "FTP_MIN_PORT=45099\nFTP_MAX_PORT=45000\n" > "$1"
        ! validate_config_file "$1" strict || exit 1
        printf "CUSTOM_LEGACY_SETTING=literal\n" > "$1"
        validate_config_file "$1" compatible || exit 1
        ! validate_config_file "$1" strict
    ' _ "${TEST_TMPDIR}/policy.env"
    [ "${status}" -eq 0 ]
}
@test "unattended key-only installation fails preflight when no key is provided" {
    run bash -c "${core_child}"'
        printf "AUTO_INSTALL=true\nSSH_PASSWORDLESS=true\nRSA_PUB_KEY=\n" > "$1"
        validate_config_file "$1" compatible || exit 1
        ! validate_config_file "$1" install
    ' _ "${TEST_TMPDIR}/ssh.env"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"before installation"* ]]
}
@test "SSH profile disables password and keyboard-interactive auth without legacy RSA directives" {
    run bash -c "${core_child}"'
        DRYRUN=false
        write_ssh_profile "$1" 2269 true false
        cat "$1"
    ' _ "${TEST_TMPDIR}/ssh.conf"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"AuthenticationMethods publickey"* ]]
    [[ "${output}" == *"KbdInteractiveAuthentication no"* ]]
    [[ "${output}" == *"PermitRootLogin no"* ]]
    [[ "${output}" != *"RSAAuthentication"* ]]
}
@test "restricted sudoers is validated before replacement and contains no wildcard service access" {
    run bash -c "${core_child}"'
        DRYRUN=false
        write_account_sudoers lemper "$1"
        [ "$(stat -c %a "$1/90-lemper")" = 440 ]
        ! grep -q "\*" "$1/90-lemper"
        grep -q "php8.5-fpm" "$1/90-lemper"
    ' _ "${TEST_TMPDIR}/sudoers"
    [ "${status}" -eq 0 ]
}
@test "legacy privilege migration creates protected backups and preserves other accounts" {
    mkdir -p "${TEST_TMPDIR}/root/etc/sudoers.d"
    printf 'lemper ALL=(ALL) NOPASSWD:ALL\notheruser ALL=(ALL) ALL\n' > "${TEST_TMPDIR}/root/etc/sudoers.d/90-lemper-users"
    run bash -c "${core_child}"'
        DRYRUN=false
        id() { if [[ "$1" == -u ]]; then echo 1001; else echo "lemper sudo"; fi; }
        # Record group changes in the fixture, never operate on a real user.
        gpasswd() { printf "%s\n" "$*" > "${TEST_TMPDIR}/groups"; }
        restrict_account_sudo lemper "$1" || exit 1
        [ -f "$1/etc/lemper/accounts/lemper.sudoers.bak" ]
        grep -q otheruser "$1/etc/sudoers.d/90-lemper-users"
        ! grep -q "^lemper " "$1/etc/sudoers.d/90-lemper-users"
    ' _ "${TEST_TMPDIR}/root"
    [ "${status}" -eq 0 ]
}
@test "key-file-derived local passwords are absent from failed-command diagnostics" {
    run bash -c "${core_child}"'
        DRYRUN=false
        local_test() { local pw=synthetic-config-key; run false -k "$pw"; }
        local_test
    '
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"synthetic-config-key"* ]]
}

@test "ed25519 keys validate, are installed in root-managed storage, and reject symlinks" {
    ssh-keygen -q -t ed25519 -N "" -f "${TEST_TMPDIR}/key"
    run bash -c "${core_child}"'
        key=$(cat "$1/key.pub")
        valid_ssh_key_material "$key" || exit 1
        install_managed_ssh_key lemper "$key" "$1/managed" || exit 1
        cmp "$1/key.pub" "$1/managed/lemper" || exit 1
        rm "$1/managed/lemper"
        ln -s "$1/key.pub" "$1/managed/lemper"
        ! install_managed_ssh_key lemper "$key" "$1/managed"
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -eq 0 ]
}
@test "OpenSSH accepts the generated key-only profile" {
    mkdir -p /run/sshd
    run bash -c "${core_child}"'
        DRYRUN=false
        write_ssh_profile "$1" 2269 true false
        sshd -t -f "$1"
        sshd -T -f "$1" | grep -qx "authenticationmethods publickey"
    ' _ "${TEST_TMPDIR}/sshd.conf"
    [ "${status}" -eq 0 ]
}

@test "SSH policy verification rejects an effective Match override" {
    mkdir -p /run/sshd
    run bash -c "${core_child}"'
        DRYRUN=false
        write_ssh_profile "$1" 2269 true false || exit 1
        verify_effective_ssh_policy nobody 2269 true false "$1" || exit 1
        printf "\nMatch User root\n    PermitRootLogin yes\n" >> "$1"
        sshd -t -f "$1" || exit 1
        ! verify_effective_ssh_policy nobody 2269 true false "$1"
    ' _ "${TEST_TMPDIR}/sshd.conf"
    [ "${status}" -eq 0 ]
}

@test "CLI refresh replaces a symlink without modifying its immutable version target" {
    printf 'old-release\n' > "${TEST_TMPDIR}/old"
    printf 'new-release\n' > "${TEST_TMPDIR}/new"
    ln -s "${TEST_TMPDIR}/old" "${TEST_TMPDIR}/cli"
    run bash -c "${core_child}"'
        DRYRUN=false
        install_cli_binary "$1/new" "$1/cli"
        [ "$(cat "$1/old")" = old-release ]
        [ "$(cat "$1/cli")" = new-release ]
        [ ! -L "$1/cli" ]
    ' _ "${TEST_TMPDIR}"
    [ "${status}" -eq 0 ]
}

@test "SSH transition retains previous and active ports, and rejects invalid port input" {
    run bash -c "${core_child}"'
        [ "$(ssh_transition_ports 2269 "22 2200" 2200)" = "22,2200,2269" ] || exit 1
        ! ssh_transition_ports 2269 "22;id"
    '
    [ "${status}" -eq 0 ]
}
@test "fatal firewall failures stay in a child and permit the parent rollback handler" {
    run bash -c "${core_child}"'
        DRYRUN=false
        install_firewall() { run false; }
        if ! (install_firewall); then echo ROLLBACK; fi
    '
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ROLLBACK"* ]]
}

@test "legacy firewall selection preserves an active native policy before installation" {
    run bash -c "${core_child}"'
        lemper_load_module services/system/security || exit 1
        AUTO_INSTALL=true INSTALL_FW=true FW_CONFIGURATOR=ufw
        systemctl() { [[ "$*" == "is-active --quiet lemper-nftables.service" ]]; }
        run() { echo MUTATED; }
        install_firewall
    '
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"native nftables policy"* ]]
    [[ "${output}" != *MUTATED* ]]
}

@test "legacy firewall selection does not silently replace an unknown backend with UFW" {
    run bash -c "${core_child}"'
        lemper_load_module services/system/security || exit 1
        AUTO_INSTALL=true INSTALL_FW=true FW_CONFIGURATOR=unknown
        run() { echo MUTATED; }
        install_firewall
    '
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown firewall backend"* ]]
    [[ "${output}" != *MUTATED* ]]
}

@test "hosts updates preserve the inode and other aliases and match names literally" {
    printf '127.0.0.1 localhost example.test\n192.0.2.2 examplextest\n' > "$TEST_TMPDIR/hosts"
    local inode
    inode=$(stat -c %i "$TEST_TMPDIR/hosts")
    run bash -c "${core_child}"'
        lemper_update_hosts example.test 127.0.0.2 "$1"
    ' _ "$TEST_TMPDIR/hosts"
    [ "$status" -eq 0 ]
    [ "$(stat -c %i "$TEST_TMPDIR/hosts")" = "$inode" ]
    grep -q 'localhost' "$TEST_TMPDIR/hosts"
    grep -q '192.0.2.2 examplextest' "$TEST_TMPDIR/hosts"
    grep -qx $'127.0.0.2\texample.test' "$TEST_TMPDIR/hosts"
    [ -f "$TEST_TMPDIR/hosts.backup" ]
}
@test "hosts dry-run does not write the destination or create a backup" {
    printf 'original\n' > "$TEST_TMPDIR/hosts"
    run bash -c "${core_child}"'
        DRYRUN=true
        lemper_update_hosts example.test 127.0.0.2 "$1"
    ' _ "$TEST_TMPDIR/hosts"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/hosts")" = original ]
    [ ! -e "$TEST_TMPDIR/hosts.backup" ]
}
