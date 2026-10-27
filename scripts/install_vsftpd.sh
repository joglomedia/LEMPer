#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | VSFTPD Installer                                                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Configure Vsftpd.
##
function configure_vsftpd() {
    echo "Configuring FTP server (VSFTPD)..."

    if [[ "${DRYRUN}" != true ]]; then
        FTP_MIN_PORT=${FTP_MIN_PORT:-45000}
        FTP_MAX_PORT=${FTP_MAX_PORT:-45099}

        # Backup default vsftpd conf.
        if [ -f /etc/vsftpd.conf ]; then
            run mv /etc/vsftpd.conf /etc/vsftpd.conf.bak
        fi

        # Enable jail mode.
        run touch /etc/vsftpd.conf
        cat > /etc/vsftpd.conf <<EOL
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
allow_writeable_chroot=YES
pam_service_name=vsftpd
force_dot_files=YES

pasv_enable=NO
#pasv_min_port=${FTP_MIN_PORT}
#pasv_max_port=${FTP_MAX_PORT}
#pasv_address=${SERVER_IP}
#pasv_addr_resolve=YES

user_sub_token=\$USER
local_root=/home/\$USER

userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
EOL

        # Enable passv mode.
        if [[ "${FTP_PASV_MODE}" == true ]]; then
            sed_inplace 's/pasv_enable=NO/pasv_enable=YES/g' /etc/vsftpd.conf
            sed_inplace 's/\#pasv_min_port/pasv_min_port/g' /etc/vsftpd.conf
            sed_inplace 's/\#pasv_max_port/pasv_max_port/g' /etc/vsftpd.conf

            # If using elastic IP (such as AWS EC2), set the server IP.
            if [[ "${ENVIRONMENT}" == prod* && "${SERVER_IP}" != "$(get_ip_private)" ]]; then
                sed_inplace "s|^#pasv_address=.*|pasv_address=${SERVER_IP}|g" /etc/vsftpd.conf
                sed_inplace "s|^#pasv_addr_resolve=.*|pasv_addr_resolve=YES|g" /etc/vsftpd.conf
            fi
        fi

        # Enable SSL.
        if [[ "${FTP_SSL_ENABLE}" == true ]]; then
            local cert_file="" key_file=""

            if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" \
                && -f "${HOSTNAME_CERT_PATH}/privkey.pem" ]]; then
                cert_file="${HOSTNAME_CERT_PATH}/fullchain.pem"
                key_file="${HOSTNAME_CERT_PATH}/privkey.pem"
            elif [[ -n "${HOSTNAME}" && -f "/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem" \
                && -f "/etc/letsencrypt/live/${HOSTNAME}/privkey.pem" ]]; then
                cert_file="/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem"
                key_file="/etc/letsencrypt/live/${HOSTNAME}/privkey.pem"
            elif [[ -n "${HOSTNAME}" && -f "/etc/lemper/ssl/${HOSTNAME}/fullchain.pem" \
                && -f "/etc/lemper/ssl/${HOSTNAME}/privkey.pem" ]]; then
                cert_file="/etc/lemper/ssl/${HOSTNAME}/fullchain.pem"
                key_file="/etc/lemper/ssl/${HOSTNAME}/privkey.pem"
            elif [[ -f /etc/ssl/certs/ssl-cert-snakeoil.pem \
                && -f /etc/ssl/private/ssl-cert-snakeoil.key ]]; then
                cert_file="/etc/ssl/certs/ssl-cert-snakeoil.pem"
                key_file="/etc/ssl/private/ssl-cert-snakeoil.key"
            fi

            if [[ -z "${cert_file}" || -z "${key_file}" ]]; then
                warning "No TLS certificate found for VSFTPD, generating a self-signed one."

                local key_length="${KEY_HASH_LENGTH:-2048}"
                local common_name="${HOSTNAME:-$(hostname)}"

                if [ ! -d /etc/ssl/private ]; then
                    run install -d -m 0700 -o root -g root /etc/ssl/private
                fi
                run openssl req -x509 -nodes -newkey "rsa:${key_length}" -sha256 -days 3650 \
                    -subj "/CN=${common_name}" \
                    -keyout /etc/ssl/private/vsftpd.key \
                    -out /etc/ssl/private/vsftpd.crt
                run bash -c "cat /etc/ssl/private/vsftpd.crt /etc/ssl/private/vsftpd.key \
                    > /etc/ssl/private/vsftpd-selfsigned.pem"
                run rm -f /etc/ssl/private/vsftpd.key /etc/ssl/private/vsftpd.crt
                run chmod 0600 /etc/ssl/private/vsftpd-selfsigned.pem

                cert_file="/etc/ssl/private/vsftpd-selfsigned.pem"
                key_file="${cert_file}"
            fi

            cat >> /etc/vsftpd.conf <<EOL

ssl_enable=YES
ssl_tlsv1=NO
ssl_tlsv11=NO
ssl_tlsv12=YES
ssl_tlsv13=YES
ssl_sslv2=NO
ssl_sslv3=NO
ssl_ciphers=HIGH:!aNULL:!MD5
require_ssl_reuse=NO
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES

rsa_cert_file=${cert_file}
rsa_private_key_file=${key_file}
EOL
        fi

        if [ ! -f /etc/pam.d/vsftpd ]; then
            run touch /etc/pam.d/vsftpd
            cat > /etc/pam.d/vsftpd <<EOL
# Standard behaviour for ftpd(8).
#auth    required        pam_listfile.so item=user sense=deny file=/etc/ftpusers onerr=succeed

# Note: vsftpd handles anonymous logins on its own. Do not enable pam_ftp.so.

# Standard pam includes
#@include common-account
#@include common-session
#@include common-auth
#auth    required        pam_shells.so


### Other fix for other login issue (tested on CentOS 8 / Rocky 8)

#%PAM-1.0
account    required    pam_listfile.so item=user sense=allow file=/etc/vsftpd.userlist onerr=fail
account    required    pam_unix.so
auth       required    pam_unix.so
EOL
        fi

        if [[ ! -f /etc/ftpusers ]]; then
            run touch /etc/ftpusers
            cat > /etc/ftpusers <<EOL
# /etc/ftpusers: list of users disallowed FTP access. See ftpusers(5).

root
daemon
bin
sys
sync
games
man
lp
mail
news
uucp
nobody
www-data
EOL
        fi

        # Add default LEMPer Stack user to vsftpd.userlist.
        echo -n "Adding default user to vsftpd.userlist: "

        LEMPER_USERNAME=${LEMPER_USERNAME:-lemper}
        run touch /etc/vsftpd.userlist

        if ! grep -qx "${LEMPER_USERNAME}" /etc/vsftpd.userlist 2>/dev/null; then
            run bash -c "echo '${LEMPER_USERNAME}' >> /etc/vsftpd.userlist"
        fi

        # Add systemd service.
        [[ ! -f /lib/systemd/system/vsftpd.service ]] && \
            run cp etc/systemd/vsftpd.service /lib/systemd/system/vsftpd.service
        [[ ! -f /etc/systemd/system/multi-user.target.wants/vsftpd.service ]] && \
            run ln -s /lib/systemd/system/vsftpd.service /etc/systemd/system/multi-user.target.wants/vsftpd.service

        # Restart vsftpd daemon.
        echo "Restarting FTP server (VSFTPD)..."

        run systemctl unmask vsftpd
        run systemctl daemon-reload
        run systemctl enable vsftpd
        run systemctl restart vsftpd

        sleep 1

        if ! systemctl is-active --quiet vsftpd; then
            error "FTP server (VSFTPD) failed to start."
            systemctl --no-pager --lines=15 status vsftpd || true
            journalctl -u vsftpd -n 15 --no-pager || true
            return 1
        fi

        success "FTP server (VSFTPD) is running."
    fi
}

##
# Install Vsftpd.
##
function init_vsftpd_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_FTP_SERVER}" == true ]]; then
            DO_INSTALL_FTP_SERVER="y"
            SELECTED_INSTALLER=${FTP_SERVER_INSTALLER:-"repo"}
        else
            DO_INSTALL_FTP_SERVER="n"
        fi
    else
        while [[ "${DO_INSTALL_FTP_SERVER}" != "y" && "${DO_INSTALL_FTP_SERVER}" != "n" ]]; do
            read -rp "Do you want to install FTP server (VSFTPD)? [y/n]: " -i y -e DO_INSTALL_FTP_SERVER
        done
    fi

    if [[ ${DO_INSTALL_FTP_SERVER} == y* || ${DO_INSTALL_FTP_SERVER} == Y* ]]; then
        echo "Available VSFTPD installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "--------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | repo)
                echo "Installing FTP server (VSFTPD) from repository..."
                run env DEBIAN_FRONTEND=noninteractive apt-get install -q -y vsftpd
                configure_vsftpd
            ;;
            2 | source)
                echo "Installing FTP server (VSFTPD) from source..."

                # Install build dependencies for the supported releases.
                case "${DISTRIB_NAME}/${RELEASE_NAME}" in
                    debian/bullseye | debian/bookworm | ubuntu/jammy | ubuntu/noble)
                        run env DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
                            build-essential libssl-dev libpam0g-dev libcap-dev
                    ;;
                    *)
                        fail "Unsupported OS distribution: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                    ;;
                esac

                echo "Preparing to compile VSFTPD..."

                # Fix error: sysdeputil.o: In function `vsf_sysdep_has_capabilities'
                LIB_GNU_DIR="/lib/${ARCH}-linux-gnu"

                if [[ "${ARCH}" == "x86_64" ]]; then
                    LIB_DIR="/lib64"
                else
                    LIB_DIR="/lib"
                fi

                if [ ! -f "${LIB_DIR}/libcap.so" ]; then
                    if [ -f "${LIB_GNU_DIR}/libcap.so.2" ]; then
                        run ln -s "${LIB_GNU_DIR}/libcap.so.2" "${LIB_DIR}/libcap.so"
                    elif [ -f "${LIB_GNU_DIR}/libcap.so.1" ]; then
                        run ln -s "${LIB_GNU_DIR}/libcap.so.1" "${LIB_DIR}/libcap.so"
                    elif [ -f "${LIB_GNU_DIR}/libcap.so" ]; then
                        run ln -s "${LIB_GNU_DIR}/libcap.so" "${LIB_DIR}/libcap.so"
                    else
                        echo "Cannot find libcap.so file."
                    fi
                fi

                # vsf_findlibs.sh only probes /usr/lib and /usr/lib64 for
                # libpam, which misses the multiarch directory on arm64.
                if [ ! -f /usr/lib/libpam.so ] && [ -f "${LIB_GNU_DIR}/libpam.so" ]; then
                    run ln -s "${LIB_GNU_DIR}/libpam.so" /usr/lib/libpam.so
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)

                if [[ "${FTP_SERVER_VERSION}" == "latest" || "${FTP_SERVER_VERSION}" == "stable" ]]; then
                    VSFTPD_FILENAME="vsftpd-3.0.5.tar.gz"
                    VSFTPD_ZIP_URL="https://security.appspot.com/downloads/${VSFTPD_FILENAME}"
                else
                    VSFTPD_FILENAME="vsftpd-${FTP_SERVER_VERSION}.tar.gz"
                    VSFTPD_ZIP_URL="https://security.appspot.com/downloads/${VSFTPD_FILENAME}"
                fi

                run cd "${BUILD_DIR}" || return 1

                if [ ! -f "${VSFTPD_FILENAME}" ]; then
                    echo "Downloading VSFTPD source code..."

                    if curl -sLI "${VSFTPD_ZIP_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sSL -o "${VSFTPD_FILENAME}" "${VSFTPD_ZIP_URL}"
                    else
                        error "Cannot download VSFTPD source: '${VSFTPD_FILENAME}'."
                    fi
                fi

                if [ -f "${VSFTPD_FILENAME}" ]; then
                    echo "Compile and install VSFTPD..."

                    run tar -zxf "${VSFTPD_FILENAME}" && \
                    run cd "${VSFTPD_FILENAME%.*.*}" || return 1

                    # If SSL Enabled, modify the builddefs.h file.
                    if [[ "${FTP_SSL_ENABLE}" == true ]]; then
                        sed_inplace 's/\#undef\ VSF_BUILD_SSL/\#define\ VSF_BUILD_SSL/g' ./builddefs.h
                    fi

                    # vsftpd 3.0.5 still calls APIs that OpenSSL 3 deprecates.
                    # Its Makefile builds with -Werror, so keep -Werror for every
                    # other warning but let deprecation warnings through.
                    sed_inplace 's/-Werror/-Werror -Wno-error=deprecated-declarations/' Makefile

                    # Fix error install: cannot create regular file.
                    run mkdir -p /usr/local/man/man8 && \
                    run mkdir -p /usr/local/man/man5

                    # Make install.
                    run make && \
                    run make install && \
                    run ldconfig /usr/local/lib && \
                    run cd "${CURRENT_DIR}" || return 1

                    # Move executable to /usr/sbin.
                    [ -x /usr/local/sbin/vsftpd ] && run mv /usr/local/sbin/vsftpd /usr/sbin/

                    configure_vsftpd
                fi
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. VSFTPD installation skipped."
            ;;
        esac

        if [[ "${DRYRUN}" != true ]]; then
            if ! systemctl is-active --quiet vsftpd; then
                error "FTP server (VSFTPD) is not running after installation."
            fi
        else
            info "FTP server (VSFTPD) installed in dry run mode."
        fi
    else
        info "FTP server (VSFTPD) installation skipped."
    fi
}

echo "[FTP Server (VSFTPD) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v vsftpd) && "${FORCE_INSTALL}" != true ]]; then
    if [[ "${INSTALL_FTP_SERVER}" == true ]]; then
        # Re-apply configuration so existing installs pick up the service and
        # TLS changes instead of staying on their old settings.
        info "FTP Server (VSFTPD) already exists, re-applying configuration."
        configure_vsftpd
    else
        info "FTP Server (VSFTPD) already exists, installation skipped."
    fi
else
    init_vsftpd_install "$@"
fi
