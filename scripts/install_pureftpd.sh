#!/usr/bin/env bash

# Pure-FTPd Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 07/04/2022
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
# Configure PureFTPd
##
function configure_pureftpd() {
    # Configure PureFTPd.
     echo "Configuring FTP server (Pure-FTPd)..."

    if [[ "${DRYRUN}" != true ]]; then
        FTP_MIN_PORT=${FTP_MIN_PORT:-45000}
        FTP_MAX_PORT=${FTP_MAX_PORT:-45999}

        # Backup original config.
        if [[ -f /etc/pure-ftpd/pure-ftpd.conf ]]; then
            run cp -f /etc/pure-ftpd/pure-ftpd.conf /etc/pure-ftpd/pure-ftpd.conf.bak
        elif [[ ! -d /etc/pure-ftpd ]]; then
            run mkdir -p /etc/pure-ftpd
        fi

        # PureFTPd configuration.
        run touch /etc/pure-ftpd/pure-ftpd.conf
        cat > /etc/pure-ftpd/pure-ftpd.conf <<EOL
ChrootEveryone               yes
BrokenClientsCompatibility   no
MaxClientsNumber             50
Daemonize                    yes
MaxClientsPerIP              8
VerboseLog                   no
DisplayDotFiles              yes
AnonymousOnly                no
NoAnonymous                  no
SyslogFacility               ftp
DontResolve                  yes
MaxIdleTime                  15

# MySQLConfigFile              /etc/pureftpd-mysql.conf
# PureDB                       /etc/pureftpd.pdb
PureDB                       /etc/pure-ftpd/pureftpd.pdb

# ExtAuth                      /var/run/ftpd.sock

# PAMAuthentication            yes
UnixAuthentication           yes

LimitRecursion               10000 8
AnonymousCanCreateDirs       no
MaxLoad                      4

# PassivePortRange             ${FTP_MIN_PORT} ${FTP_MAX_PORT}
# ForcePassiveIP               ${SERVER_IP}

# AntiWarez                    yes

# Bind                         127.0.0.1,21

Umask                        133:022
MinUID                       100
AllowUserFXP                 no
AllowAnonymousFXP            no
ProhibitDotFilesWrite        no
ProhibitDotFilesRead         no
AutoRename                   no
AnonymousCantUpload          no
# TrustedIP                    10.1.1.1

# CreateHomeDir                yes
# Quota                        1000:10

# PIDFile                      /var/run/pure-ftpd.pid
PIDFile                      /var/run/pure-ftpd/pure-ftpd.pid

# CallUploadScript             yes

MaxDiskUsage                   90
CustomerProof                yes

IPV4Only                     no

EOL

        # Enable passv mode.
        if [[ "${FTP_PASV_MODE}" == true ]]; then
            run sed -i "s|^#\ PassivePortRange|PassivePortRange|g" /etc/pure-ftpd/pure-ftpd.conf

            # If we are behind NAT (such as AWS, GCP, Azure), set the Public IP.
            if [[ "${SERVER_IP}" != "$(get_ip_private)" ]]; then
                run sed -i "s|^#\ ForcePassiveIP|ForcePassiveIP|g" /etc/pure-ftpd/pure-ftpd.conf
            fi
        fi

        # Enable SSL.
        if [[ "${FTP_SSL_ENABLE}" == true ]]; then
            # Certificate files.
            if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" ]]; then
                RSA_CERT_FILE="${HOSTNAME_CERT_PATH}/fullchain.pem"
            elif [[ -f "/etc/lemper/ssl/${HOSTNAME}/cert.pem" ]]; then
                RSA_CERT_FILE="/etc/lemper/ssl/${HOSTNAME}/cert.pem"
            else
                RSA_CERT_FILE="/etc/ssl/certs/ssl-cert-snakeoil.pem"
            fi

            cat >> /etc/pure-ftpd/pure-ftpd.conf <<EOL
TLS                          2
TLSCipherSuite               HIGH:MEDIUM:+TLSv1:!SSLv2:!SSLv3
CertFile                     ${RSA_CERT_FILE}

EOL
        fi

        if [[ ! -d /etc/pure-ftpd/conf ]]; then
            run cp -fr etc/pure-ftpd/conf /etc/pure-ftpd/
        fi

        if [[ ! -d /etc/pure-ftpd/auth ]]; then
            run mkdir -p /etc/pure-ftpd/auth
            run ln -s /etc/pure-ftpd/conf/UnixAuthentication /etc/pure-ftpd/auth/65unix
            run ln -s /etc/pure-ftpd/conf/PAMAuthentication /etc/pure-ftpd/auth/70pam
        fi

        if [[ ! -f /etc/default/pure-ftpd-common ]]; then
            run cp -f etc/default/pure-ftpd-common /etc/default/pure-ftpd-common
        fi

        # Add init.d script.
        if [[ ! -f /etc/init.d/pure-ftpd ]]; then
            run cp -f etc/init.d/pure-ftpd /etc/init.d/pure-ftpd
            run chmod +x /etc/init.d/pure-ftpd
            run update-rc.d pure-ftpd defaults
        fi

        if [[ ! -f /usr/sbin/pure-ftpd-wrapper ]]; then
            run cp -f sbin/pure-ftpd-wrapper /usr/sbin/pure-ftpd-wrapper
        fi

        # Add systemd service.
        [[ ! -f /run/systemd/generator.late/pure-ftpd.service ]] && \
            run cp etc/systemd/pure-ftpd.service /run/systemd/generator.late/pure-ftpd.service
        [[ ! -f /run/systemd/generator.late/multi-user.target.wants/pure-ftpd.service ]] && \
            run ln -s /run/systemd/generator.late/pure-ftpd.service /run/systemd/generator.late/multi-user.target.wants/pure-ftpd.service
        [[ ! -f /run/systemd/generator.late/graphical.target.wants/pure-ftpd.service ]] && \
            run ln -s /run/systemd/generator.late/pure-ftpd.service /run/systemd/generator.late/graphical.target.wants/pure-ftpd.service

        # Restart Pure-FTPd daemon.
        echo "Restarting FTP server (Pure-FTPd)..."

        run systemctl daemon-reload
        run systemctl restart pure-ftpd.service
    fi
}

##
# Install Pure-FTPd.
##
function init_pureftpd_install() {
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
            read -rp "Do you want to install FTP server (Pure-FTPd)? [y/n]: " -i y -e DO_INSTALL_FTP_SERVER
        done
    fi

    if [[ ${DO_INSTALL_FTP_SERVER} == y* || ${DO_INSTALL_FTP_SERVER} == Y* ]]; then
        echo "Available Pure-FTPd installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "--------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing FTP server (Pure-FTPd) from repository..."
                run apt-get install -y pure-ftpd-common pure-ftpd
                configure_pureftpd
            ;;
            2 | "source")
                echo "Installing FTP server (Pure-FTPd) from source..."

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)

                if [[ "${FTP_SERVER_VERSION}" == "latest" || "${FTP_SERVER_VERSION}" == "stable" ]]; then
                    PUREFTPD_FILENAME="pure-ftpd-1.0.50.tar.gz"
                    #PUREFTPD_ZIP_URL="https://download.pureftpd.org/pub/pure-ftpd/releases/${PUREFTPD_FILENAME}"
                    PUREFTPD_ZIP_URL="https://github.com/jedisct1/pure-ftpd/releases/download/1.0.50/${PUREFTPD_FILENAME}"
                else
                    PUREFTPD_FILENAME="pure-ftpd-${FTP_SERVER_VERSION}.tar.gz"
                    #PUREFTPD_ZIP_URL="https://download.pureftpd.org/pub/pure-ftpd/releases/${PUREFTPD_FILENAME}"
                    PUREFTPD_ZIP_URL="https://github.com/jedisct1/pure-ftpd/releases/download/${FTP_SERVER_VERSION}/${PUREFTPD_FILENAME}"
                fi

                run cd "${BUILD_DIR}" || return 1

                if [ ! -f "${PUREFTPD_FILENAME}" ]; then
                    if curl -sLI "${PUREFTPD_ZIP_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run wget "${PUREFTPD_ZIP_URL}"
                    else
                        error "Cannot download PureFTPd source: '${PUREFTPD_FILENAME}'."
                    fi
                fi

                if [ -f "${PUREFTPD_FILENAME}" ]; then
                    echo "Compile and install Pure-FTPd..."

                    run tar -zxf "${PUREFTPD_FILENAME}" && \
                    run cd "${PUREFTPD_FILENAME%.*.*}" || return 1

                    # Enable MySQL support.
                    run ./configure --prefix=/usr --with-tls --with-mysql --with-puredb --with-uploadscript \
                        --with-extauth --with-ftpwho --with-wrapper --with-virtualchroot --with-everything && \

                    # Make install.
                    run make && make check && \
                    run make install && \
                    run cd "${CURRENT_DIR}" || return 1

                    # Move executable to /usr/sbin.
                    if [[ -x /usr/local/sbin/pure-ftpd ]]; then
                        run ln -s /usr/local/sbin/pure-ftpd /usr/sbin/pure-ftpd
                    fi

                    configure_pureftpd
                fi
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. Pure-FTPd installation skipped."
            ;;
        esac

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c pure-ftpd) -gt 0 ]]; then
                run systemctl enable pure-ftpd.service
                success "FTP server (Pure-FTPd) started successfully."
            else
                run systemctl disable pure-ftpd.service
                info "Something went wrong with FTP server installation."
            fi
        else
            info "FTP server (Pure-FTPd) installed in dry run mode."
        fi
    else
        info "FTP server (Pure-FTPd) installation skipped."
    fi
}

echo "[FTP Server (Pure-FTPd) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v pure-ftpd) && "${FORCE_INSTALL}" != true ]]; then
    info "FTP Server (Pure-FTPd) already exists, installation skipped."
else
    init_pureftpd_install "$@"
fi
