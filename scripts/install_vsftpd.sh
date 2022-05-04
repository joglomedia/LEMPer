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
    . "${BASE_DIR}/helper.sh"

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
            1 | "repo")
                echo "Installing FTP server (VSFTPD) from repository..."
                run apt-get install -qq -y vsftpd
            ;;
            2 | "source")
                echo "Installing FTP server (VSFTPD) from source..."

                # Install libraries.
                case "${DISTRIB_NAME}" in
                    "debian")
                        case "${RELEASE_NAME}" in
                            "stretch")
                                run apt-get install -qq -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-common libtirpc-dev libtirpc1
                            ;;
                            "buster" | "bullseye")
                                run apt-get install -qq -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-common libtirpc-dev libtirpc3
                            ;;
                            *)
                                fail "Unsupported Debian release: ${RELEASE_NAME^}."
                            ;;
                        esac
                    ;;
                    "ubuntu")
                        case "${RELEASE_NAME}" in
                            "bionic")
                                run apt-get install -qq -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-dev libtirpc1
                            ;;
                            "focal")
                                run apt-get install -qq -y libpam0g libpam0g-dev libcapi20-3 libcapi20-dev \
                                    libcap-dev libcap2 libtirpc-common libtirpc-dev libtirpc3
                            ;;
                            *)
                                fail "Unsupported Ubuntu release: ${RELEASE_NAME^}."
                            ;;
                        esac
                    ;;
                    *)
                        fail "Unsupported OS distribution: ${DISTRIB_NAME^}."
                    ;;
                esac

                # Fix error: sysdeputil.o: In function `vsf_sysdep_has_capabilities'
                LIB_GNU_DIR="/lib/${ARCH}-linux-gnu"

                if [[ "${ARCH}" == "x86_64" ]]; then
                    LIB_DIR="/lib64"
                else
                    LIB_DIR="/lib"
                fi

                if [[ ! -f "${LIB_DIR}/libcap.so" ]]; then
                    if [[ -f "${LIB_GNU_DIR}/libcap.so.2" ]]; then
                        run ln -s "${LIB_GNU_DIR}/libcap.so.2" "${LIB_DIR}/libcap.so"
                    elif [[ -f "${LIB_GNU_DIR}/libcap.so.1" ]]; then
                        run ln -s "${LIB_GNU_DIR}/libcap.so.1" "${LIB_DIR}/libcap.so"
                    elif [[ -f "${LIB_GNU_DIR}/libcap.so" ]]; then
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

                run cd "${BUILD_DIR}" && \
                run wget -q "${VSFTPD_ZIP_URL}" && \
                run tar -zxf "${VSFTPD_FILENAME}" && \
                run cd "${VSFTPD_FILENAME%.*.*}" / || return 1

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
            if [[ -f /etc/vsftpd.conf ]]; then
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

pasv_enable=YES
pasv_min_port=${FTP_MIN_PORT}
pasv_max_port=${FTP_MAX_PORT}
#pasv_address=${SERVER_IP}
#pasv_addr_resolve=YES

user_sub_token=\$USER
local_root=/home/\$USER

userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
EOL

            # Enable SSL.
            # TODO: Change the self-signed certificate with a valid Let's Encrypt certificate.
            if [[ "${FTP_SSL_ENABLE}" == true ]]; then
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

rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
EOL
            fi

            # If using elastic IP (such as AWS EC2), set the server IP.
            if [[ "${SERVER_IP}" != "$(get_ip_private)" ]]; then
                run sed -i "s|^#pasv_address=.*|pasv_address=${SERVER_IP}|g" /etc/vsftpd.conf
                run sed -i "s|^#pasv_addr_resolve=.*|pasv_addr_resolve=YES|g" /etc/vsftpd.conf
            fi

            # If Let's Encrypt SSL certificate is issued for hostname, set the certificate.
            if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" ]]; then
                run sed -i "s|^rsa_cert_file=[^[:digit:]]*$|rsa_cert_file=${HOSTNAME_CERT_PATH}/fullchain.pem|g" /etc/vsftpd.conf
                run sed -i "s|^rsa_private_key_file=[^[:digit:]]*$|rsa_private_key_file=${HOSTNAME_CERT_PATH}/privkey.pem|g" /etc/vsftpd.conf
            fi

            # Add default LEMPer Stack user to vsftpd.userlist.
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
        run systemctl restart vsftpd
        run systemctl enable vsftpd

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c vsftpd) -gt 0 ]]; then
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
