#!/usr/bin/env bats
##
# Regression tests for the FTP server installers (issues #135 and #146).
#
# The installer scripts are checked structurally: the fixes depend on system
# services, accounts, and certificates, which cannot be provisioned in a unit
# test run.
##

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/../.."
}

refute_grep() {
    run grep "$@"
    [ "${status}" -ne 0 ]
}

@test "pure-ftpd creates the ftp account and runtime directories" {
    grep -q 'getent passwd ftp' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'adduser --system' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'install -d -m 0755 -o root -g root /var/run/pure-ftpd' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q '/var/log/pure-ftpd' "${BASE_DIR}/scripts/install_pureftpd.sh"
}

@test "pure-ftpd TLS writes a combined certificate and key bundle" {
    grep -q 'bundle="/etc/ssl/private/pure-ftpd.pem"' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -qF "cat '\${cert_file}' '\${key_file}' > '\${bundle}'" \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'openssl req -x509 -nodes' "${BASE_DIR}/scripts/install_pureftpd.sh"

    # The old code pointed TLS at a certificate-only file, which pure-ftpd
    # cannot parse because it expects the key in the same PEM bundle.
    refute_grep -q 'CertFile' "${BASE_DIR}/scripts/install_pureftpd.sh"

    # Nor may it write the legacy config file the wrapper never reads
    # (comments that explain this are fine).
    refute_grep -q '^[^#]*pure-ftpd\.conf' "${BASE_DIR}/scripts/install_pureftpd.sh"
}

@test "pure-ftpd writes options the wrapper actually reads" {
    grep -q 'function set_pureftpd_option' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'set_pureftpd_option "TLS" "2"' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'set_pureftpd_option "PassivePortRange"' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'set_pureftpd_option "UnixAuthentication" "yes"' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q '/etc/pure-ftpd/auth/65unix' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q '/etc/pam.d/pure-ftpd' "${BASE_DIR}/scripts/install_pureftpd.sh"
}

@test "pure-ftpd source build pins 1.0.54 without the MySQL client" {
    grep -q 'pure-ftpd-1.0.54.tar.gz' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'download.pureftpd.org/pub/pure-ftpd/releases' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q -- '--with-tls --with-pam --with-privsep' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    # The wrapper copied for source installs is a Perl script.
    grep -q 'libpam0g-dev perl' "${BASE_DIR}/scripts/install_pureftpd.sh"

    refute_grep -q -- '--with-mysql' "${BASE_DIR}/scripts/install_pureftpd.sh"
}

@test "pure-ftpd ships a native systemd unit" {
    grep -q '^Type=simple' "${BASE_DIR}/etc/systemd/pure-ftpd.service"
    grep -q '^ExecStart=/usr/sbin/pure-ftpd-wrapper' "${BASE_DIR}/etc/systemd/pure-ftpd.service"
    refute_grep -q 'systemd-sysv-generator' "${BASE_DIR}/etc/systemd/pure-ftpd.service"

    # The unit belongs in /etc/systemd/system, not the volatile generator dir.
    grep -q 'cp -f etc/systemd/pure-ftpd.service /etc/systemd/system/pure-ftpd.service' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    refute_grep -q 'cp etc/systemd/pure-ftpd.service /run/systemd/generator.late' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
}

@test "vsftpd source build tolerates OpenSSL 3 deprecation warnings" {
    grep -q 'Wno-error=deprecated-declarations' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'libssl-dev' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'libpam0g-dev' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'libcap-dev' "${BASE_DIR}/scripts/install_vsftpd.sh"

    # Source builds must not silently switch to the repository package.
    refute_grep -q 'Fallback installer to repo' "${BASE_DIR}/scripts/install_vsftpd.sh"
    refute_grep -q 'libcapi20' "${BASE_DIR}/scripts/install_vsftpd.sh"

    # vsf_findlibs.sh misses the multiarch libdir for PAM on arm64.
    grep -q 'LIB_GNU_DIR}/libpam.so" /usr/lib/libpam.so' \
        "${BASE_DIR}/scripts/install_vsftpd.sh"
}

@test "vsftpd TLS enables 1.2/1.3 and falls back to a self-signed pair" {
    grep -q 'ssl_tlsv12=YES' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'ssl_tlsv13=YES' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'ssl_ciphers=HIGH:!aNULL:!MD5' "${BASE_DIR}/scripts/install_vsftpd.sh"
    grep -q 'vsftpd-selfsigned.pem' "${BASE_DIR}/scripts/install_vsftpd.sh"

    refute_grep -q 'ssl_tlsv1=YES' "${BASE_DIR}/scripts/install_vsftpd.sh"
}

@test "env template documents pure-ftpd 1.0.54" {
    grep -q '1.0.54 (pure-ftpd)' "${BASE_DIR}/.env.dist"
}

@test "removal cleans native units and FTP certificates" {
    grep -q '/etc/systemd/system/pure-ftpd.service' "${BASE_DIR}/scripts/remove_pureftpd.sh"
    grep -q 'pure-ftpd.pem' "${BASE_DIR}/scripts/remove_pureftpd.sh"
    grep -q 'vsftpd-selfsigned.pem' "${BASE_DIR}/scripts/remove_vsftpd.sh"
}

@test "re-running the installers reconciles existing installs" {
    grep -q 'already exists, re-applying configuration' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'already exists, re-applying configuration' \
        "${BASE_DIR}/scripts/install_vsftpd.sh"

    # A pre-existing (broken) pure-ftpd install must be repaired, not skipped.
    grep -q 'dpkg-query -W -f=.\${Status}. pure-ftpd' \
        "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'configure_pureftpd "repo"' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'configure_pureftpd "source"' "${BASE_DIR}/scripts/install_pureftpd.sh"
    grep -q 'configure_vsftpd' "${BASE_DIR}/scripts/install_vsftpd.sh"
}
