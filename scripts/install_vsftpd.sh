#!/usr/bin/env bash

# VSFTPD Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 24/10/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Make sure only supported distribution can run this installer script.
preflight_system_check

##
# Install Vsftpd.
##
function init_vsftpd_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_VSFTPD}" == true ]]; then
            DO_INSTALL_VSFTPD="y"
            SELECTED_INSTALLER=${VSFTPD_INSTALLER:-"repo"}
        else
            DO_INSTALL_VSFTPD="n"
        fi
    else
        while [[ "${DO_INSTALL_VSFTPD}" != "y" && "${DO_INSTALL_VSFTPD}" != "n" ]]; do
            read -rp "Do you want to install FTP server (VSFTPD)? [y/n]: " -i y -e DO_INSTALL_VSFTPD
        done
    fi

    if [[ ${DO_INSTALL_VSFTPD} == y* || ${DO_INSTALL_VSFTPD} == Y* ]]; then
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

                # Backup original config.
                run cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
            ;;
            2 | "source")
                echo "Installing FTP server (VSFTPD) from source..."

                #https://www.linuxfromscratch.org/blfs/view/svn/server/vsftpd.html

                DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
                RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

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

                if [[ -f "${LIB_GNU_DIR}/libcap.so.2" ]]; then
                    run ln -s "${LIB_GNU_DIR}/libcap.so.2" "${LIB_DIR}/libcap.so"
                elif [[ -f "${LIB_GNU_DIR}/libcap.so.1" ]]; then
                    run ln -s "${LIB_GNU_DIR}/libcap.so.1" "${LIB_DIR}/libcap.so"
                elif [[ -f "${LIB_GNU_DIR}/libcap.so" ]]; then
                    run ln -s "${LIB_GNU_DIR}/libcap.so" "${LIB_DIR}/libcap.so"
                else
                    error "Cannot find libcap.so file."
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)

                if [[ "${VSFTPD_VERSION}" == "latest" ]]; then
                    VSFTPD_FILENAME="vsftpd-3.0.5.tar.gz"
                    VSFTPD_ZIP_URL="https://security.appspot.com/downloads/${VSFTPD_FILENAME}"
                else
                    VSFTPD_FILENAME="vsftpd-${VSFTPD_VERSION}.tar.gz"
                    VSFTPD_ZIP_URL="https://security.appspot.com/downloads/${VSFTPD_FILENAME}"
                fi

                run cd "${BUILD_DIR}" && \
                run wget -q "${VSFTPD_ZIP_URL}" && \
                run tar -zxf "${VSFTPD_FILENAME}" && \
                run cd vsftpd-*/ && \
                run make && \
                run make install && \
                run ldconfig /usr/local/lib && \
                run cd "${CURRENT_DIR}" || return 1
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. VSFTPD installation skipped."
            ;;
        esac

        # Configure Fal2ban.
        echo "Configuring FTP server (VSFTPD)..."

        if [[ "${DRYRUN}" != true ]]; then
            # Backup default vsftpd conf.
            [[ -f /etc/vsftpd.conf ]] && \
                run mv /etc/vsftpd.conf /etc/vsftpd.conf.bak
    
            run touch /etc/vsftpd.conf

            # Enable jail
            cat > /etc/vsftpd.conf <<EOL
listen=NO
listen_ipv6=YES
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
pasv_min_port=40000
pasv_max_port=50000

user_sub_token=$USER
local_root=/home/$USER

rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=Yes
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
ssl_ciphers=HIGH
require_ssl_reuse=NO
EOL
        fi

        # Add systemd service.
        [[ ! -f /lib/systemd/system/vsftpd.service ]] && \
            run cp etc/systemd/vsftpd.service /lib/systemd/system/vsftpd.service
        [[ ! -f /etc/systemd/system/multi-user.target.wants/vsftpd.service ]] && \
            run ln -s /lib/systemd/system/vsftpd.service /etc/systemd/system/multi-user.target.wants/vsftpd.service

        # Restart Fail2ban daemon.
        echo "Restarting FTP server (VSFTPD)..."
        run systemctl unmask vsftpd
        run systemctl restart vsftpd

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
