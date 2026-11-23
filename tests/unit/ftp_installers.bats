#!/usr/bin/env bats
##
# Regression tests for the FTP server installers (issues #135 and #146).
#
# The FTP service implementations are checked structurally: the fixes depend on system
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
    grep -q 'getent passwd ftp' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'adduser --system' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'install -d -m 0755 -o root -g root /var/run/pure-ftpd' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q '/var/log/pure-ftpd' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "pure-ftpd TLS writes a combined certificate and key bundle" {
    grep -q 'bundle="/etc/ssl/private/pure-ftpd.pem"' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -qF "cat '\${cert_file}' '\${key_file}' > '\${bundle}'" \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'openssl req -x509 -nodes' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"

    # The old code pointed TLS at a certificate-only file, which pure-ftpd
    # cannot parse because it expects the key in the same PEM bundle.
    refute_grep -q 'CertFile' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"

    # Nor may it write the legacy config file the wrapper never reads
    # (comments that explain this are fine).
    refute_grep -q '^[^#]*pure-ftpd\.conf' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "pure-ftpd writes options the wrapper actually reads" {
    grep -q 'function set_pureftpd_option' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'set_pureftpd_option "TLS" "2"' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'set_pureftpd_option "PassivePortRange"' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'set_pureftpd_option "UnixAuthentication" "yes"' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q '/etc/pure-ftpd/auth/65unix' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q '/etc/pam.d/pure-ftpd' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "pure-ftpd repository install forces standalone mode" {
    # The sysv init script shipped by the package only starts the daemon in
    # standalone mode; in inetd mode it exits 0 without listening on port 21.
    grep -q '/etc/default/pure-ftpd-common' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'STANDALONE_OR_INETD=standalone' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'cp -f etc/default/pure-ftpd-common' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "pure-ftpd source build pins 1.0.54 without the MySQL client" {
    grep -q 'pure-ftpd-1.0.54.tar.gz' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'download.pureftpd.org/pub/pure-ftpd/releases' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q -- '--with-tls --with-pam --with-privsep' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    # Source installs use the repository's Bash wrapper and need no Perl helper.
    grep -q '^#!/usr/bin/env bash' "${BASE_DIR}/sbin/pure-ftpd-wrapper"

    refute_grep -q -- '--with-mysql' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "pure-ftpd ships a native systemd unit" {
    grep -q '^Type=simple' "${BASE_DIR}/etc/systemd/pure-ftpd.service"
    grep -q '^ExecStart=/usr/sbin/pure-ftpd-wrapper' "${BASE_DIR}/etc/systemd/pure-ftpd.service"
    refute_grep -q 'systemd-sysv-generator' "${BASE_DIR}/etc/systemd/pure-ftpd.service"

    # The unit belongs in /etc/systemd/system, not the volatile generator dir.
    grep -q 'cp -f etc/systemd/pure-ftpd.service /etc/systemd/system/pure-ftpd.service' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    refute_grep -q 'cp etc/systemd/pure-ftpd.service /run/systemd/generator.late' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
}

@test "vsftpd source build tolerates OpenSSL 3 deprecation warnings" {
    grep -q 'Wno-error=deprecated-declarations' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'libssl-dev' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'libpam0g-dev' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'libcap-dev' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"

    # Source builds must not silently switch to the repository package.
    refute_grep -q 'Fallback installer to repo' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    refute_grep -q 'libcapi20' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"

    # vsf_findlibs.sh misses the multiarch libdir for PAM on arm64.
    grep -q 'LIB_GNU_DIR}/libpam.so" /usr/lib/libpam.so' \
        "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
}

@test "vsftpd TLS enables 1.2/1.3 and falls back to a self-signed pair" {
    grep -q 'ssl_tlsv12=YES' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'ssl_tlsv13=YES' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'ssl_ciphers=HIGH:!aNULL:!MD5' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
    grep -q 'vsftpd-selfsigned.pem' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"

    refute_grep -q 'ssl_tlsv1=YES' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
}

@test "env template documents pure-ftpd 1.0.54" {
    grep -q '1.0.54 (pure-ftpd)' "${BASE_DIR}/.env.dist"
}

@test "removal cleans native units and FTP certificates" {
    grep -q '/etc/systemd/system/pure-ftpd.service' "${BASE_DIR}/lib/services/ftp/pureftpd_remove.sh"
    grep -q 'pure-ftpd.pem' "${BASE_DIR}/lib/services/ftp/pureftpd_remove.sh"
    grep -q 'vsftpd-selfsigned.pem' "${BASE_DIR}/lib/services/ftp/vsftpd_remove.sh"
}

@test "re-running the installers reconciles existing installs" {
    grep -q 'already exists, re-applying configuration' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'already exists, re-applying configuration' \
        "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"

    # A pre-existing (broken) pure-ftpd install must be repaired, not skipped.
    grep -q 'dpkg-query -W -f=.\${Status}. pure-ftpd' \
        "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'configure_pureftpd "repo"' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'configure_pureftpd "source"' "${BASE_DIR}/lib/services/ftp/pureftpd_install.sh"
    grep -q 'configure_vsftpd' "${BASE_DIR}/lib/services/ftp/vsftpd_install.sh"
}
