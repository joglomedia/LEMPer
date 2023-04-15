#!/usr/bin/env bash

# VSFTPD Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

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

    # Fallback installer to repo due to OpenSSL 3 compatibility issue.
    if [[ "${RELEASE_NAME}" == "jammy" ]]; then
        FTP_SERVER_INSTALLER="repo"
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
                run apt-get install -q -y vsftpd
            ;;
            2 | source)
                echo "Installing FTP server (VSFTPD) from source..."

                # Install libraries.
                case "${DISTRIB_NAME}" in
                    debian)
                        case "${RELEASE_NAME}" in
                            stretch)
                                run apt-get install -q -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-dev libtirpc1 libmbedtls-dev
                            ;;
                            buster | bullseye)
                                run apt-get install -q -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-common libtirpc-dev libtirpc3 libmbedtls-dev
                            ;;
                            *)
                                fail "Unsupported Debian release: ${RELEASE_NAME^}."
                            ;;
                        esac
                    ;;
                    ubuntu)
                        case "${RELEASE_NAME}" in
                            bionic)
                                run apt-get install -q -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-dev libtirpc1 libmbedtls-dev
                            ;;
                            focal | jammy)
                                run apt-get install -q -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-common libtirpc-dev libtirpc3 libmbedtls-dev
                            ;;
                            *)
                                fail "Unsupported Ubuntu release: ${RELEASE_NAME^}."
                            ;;
                        esac
                    ;;
                    #centos | rocky*)
                    #    run dnf install -q -y pam pam_cap libcap libcap-devel pam-devel libcap-devel libtirpc-devel
                    #;;
                    *)
                        fail "Unsupported OS distribution: ${DISTRIB_NAME^}."
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
                    run wget "${VSFTPD_ZIP_URL}"
                fi

                run tar -zxf "${VSFTPD_FILENAME}" && \
                run cd "${VSFTPD_FILENAME%.*.*}" || return 1

                echo "Compile and install VSFTPD..."

                # If SSL Enabled, modify the builddefs.h file.
                if [[ "${FTP_SSL_ENABLE}" == true ]]; then
                    run sed -i 's/\#undef\ VSF_BUILD_SSL/\#define\ VSF_BUILD_SSL/g' ./builddefs.h
                fi

                # Fix error install: cannot create regular file.
                run mkdir -p /usr/local/man/man8 && \
                run mkdir -p /usr/local/man/man5

                # Make install.
                run make && \
                run make install && \
                run ldconfig /usr/local/lib && \
                run cd "${CURRENT_DIR}" || return 1

                # Move executable to /usr/sbin.
                [ -x /usr/local/sbin/vsftpd ] && \
                    run mv /usr/local/sbin/vsftpd /usr/sbin/
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. VSFTPD installation skipped."
            ;;
        esac

        # Configure Fal2ban.
        echo "Configuring FTP server (VSFTPD)..."

        if [[ "${DRYRUN}" != true ]]; then
            FTP_MIN_PORT=${FTP_MIN_PORT:-45000}
            FTP_MAX_PORT=${FTP_MAX_PORT:-45099}

            # Backup default vsftpd conf.
            if [ -f /etc/vsftpd.conf ]; then
                run mv /etc/vsftpd.conf /etc/vsftpd.conf.bak
            fi

            run touch /etc/vsftpd.conf

            # Enable jail mode.
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
                run sed -i 's/pasv_enable=NO/pasv_enable=YES/g' /etc/vsftpd.conf
                run sed -i 's/\#pasv_min_port/pasv_min_port/g' /etc/vsftpd.conf
                run sed -i 's/\#pasv_max_port/pasv_max_port/g' /etc/vsftpd.conf

                # If using elastic IP (such as AWS EC2), set the server IP.
                if [[ "${ENVIRONMENT}" == prod* && "${SERVER_IP}" != "$(get_ip_private)" ]]; then
                    run sed -i "s|^#pasv_address=.*|pasv_address=${SERVER_IP}|g" /etc/vsftpd.conf
                    run sed -i "s|^#pasv_addr_resolve=.*|pasv_addr_resolve=YES|g" /etc/vsftpd.conf
                fi
            fi

            # Enable SSL.
            if [[ "${FTP_SSL_ENABLE}" == true ]]; then
                # Certificate files.
                if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" ]]; then
                    RSA_CERT_FILE="${HOSTNAME_CERT_PATH}/fullchain.pem"
                    RSA_KEY_FILE="${HOSTNAME_CERT_PATH}/privkey.pem"
                elif [[ -f "/etc/lemper/ssl/${HOSTNAME}/cert.pem" ]]; then
                    RSA_CERT_FILE="/etc/lemper/ssl/${HOSTNAME}/cert.pem"
                    RSA_KEY_FILE="/etc/lemper/ssl/${HOSTNAME}/privkey.pem"
                else
                    RSA_CERT_FILE="/etc/ssl/certs/ssl-cert-snakeoil.pem"
                    RSA_KEY_FILE="/etc/ssl/private/ssl-cert-snakeoil.key"
                fi

                cat >> /etc/vsftpd.conf <<EOL

ssl_enable=YES
require_ssl_reuse=NO
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
ssl_ciphers=HIGH

rsa_cert_file=${RSA_CERT_FILE}
rsa_private_key_file=${RSA_KEY_FILE}
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
            run bash -c "echo '${LEMPER_USERNAME}' | tee -a /etc/vsftpd.userlist"
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
        run systemctl restart vsftpd

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c vsftpd) -gt 0 ]]; then
                run systemctl enable vsftpd
                success "FTP server (VSFTPD) started successfully."
            else
                info "Something went wrong with FTP server installation."
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
    info "FTP Server (VSFTPD) already exists, installation skipped."
else
    init_vsftpd_install "$@"
fi
