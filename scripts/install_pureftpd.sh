#!/usr/bin/env bash

# Pure-FTPd Installer
# Min. Requirement  : GNU/Linux Ubuntu 22.04
# Last Build        : 25/10/2026
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
# Write a single option to the Pure-FTPd wrapper configuration directory.
#
# Debian and Ubuntu run pure-ftpd through pure-ftpd-wrapper, which reads
# /etc/pure-ftpd/conf instead of /etc/pure-ftpd/pure-ftpd.conf. Writing the
# option here is what actually configures the packaged daemon.
##
function set_pureftpd_option() {
    local name="${1}"
    local value="${2}"

    printf '%s\n' "${value}" > "/etc/pure-ftpd/conf/${name}"
}

##
# Make sure the ftp system account exists.
#
# Pure-FTPd aborts at startup with "Unable to find the 'ftp' account" when
# the account is missing (common on minimal images and after hardening).
##
function ensure_pureftpd_account() {
    if ! getent group ftp >/dev/null 2>&1; then
        run addgroup --system ftp
    fi

    if ! getent passwd ftp >/dev/null 2>&1; then
        run adduser --system --quiet --home /var/run/pure-ftpd \
            --shell /usr/sbin/nologin --ingroup ftp --gecos "FTP server" ftp
    fi

    run install -d -m 0755 -o root -g root /var/run/pure-ftpd
    run install -d -m 0750 -o ftp -g ftp /var/log/pure-ftpd
}

##
# Build the certificate + key bundle that Pure-FTPd expects.
#
# Pure-FTPd reads a single PEM file containing both the certificate and its
# private key (/etc/ssl/private/pure-ftpd.pem by default). Pointing it at a
# certificate-only file such as the snakeoil PEM makes the daemon abort with
# "PEM routines:get_name:no start line".
##
function ensure_pureftpd_certificate() {
    local bundle="/etc/ssl/private/pure-ftpd.pem"
    local cert_file="" key_file=""
    local common_name="${HOSTNAME:-$(hostname)}"
    local key_length="${KEY_HASH_LENGTH:-2048}"

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

    if [[ ! -d /etc/ssl/private ]]; then
        run install -d -m 0700 -o root -g root /etc/ssl/private
    fi

    if [[ -n "${cert_file}" && -n "${key_file}" ]]; then
        run bash -c "cat '${cert_file}' '${key_file}' > '${bundle}'"
    else
        warning "No TLS certificate found for Pure-FTPd, generating a self-signed one."
        run openssl req -x509 -nodes -newkey "rsa:${key_length}" -sha256 -days 3650 \
            -subj "/CN=${common_name}" \
            -keyout /etc/ssl/private/pure-ftpd.key \
            -out /etc/ssl/private/pure-ftpd.crt
        run bash -c "cat /etc/ssl/private/pure-ftpd.crt /etc/ssl/private/pure-ftpd.key > '${bundle}'"
        run rm -f /etc/ssl/private/pure-ftpd.key /etc/ssl/private/pure-ftpd.crt
    fi

    run chmod 0600 "${bundle}"
    run chown root:root "${bundle}"
}

##
# Configure PureFTPd
##
function configure_pureftpd() {
    local installer="${1:-repo}"

    echo "Configuring FTP server (Pure-FTPd)..."

    if [[ "${DRYRUN}" != true ]]; then
        FTP_MIN_PORT=${FTP_MIN_PORT:-45000}
        FTP_MAX_PORT=${FTP_MAX_PORT:-45099}

        if [[ ! -d /etc/pure-ftpd/conf ]]; then
            run install -d -m 0755 -o root -g root /etc/pure-ftpd/conf
        fi

        if [[ ! -d /etc/pure-ftpd/auth ]]; then
            run install -d -m 0755 -o root -g root /etc/pure-ftpd/auth
        fi

        ensure_pureftpd_account

        # General daemon settings. Only directives understood by
        # pure-ftpd-wrapper are written here; anything else makes the wrapper
        # refuse to start the daemon.
        set_pureftpd_option "ChrootEveryone" "yes"
        set_pureftpd_option "BrokenClientsCompatibility" "no"
        set_pureftpd_option "MaxClientsNumber" "50"
        set_pureftpd_option "MaxClientsPerIP" "8"
        set_pureftpd_option "MaxIdleTime" "15"
        set_pureftpd_option "MaxLoad" "4"
        set_pureftpd_option "MaxDiskUsage" "90"
        set_pureftpd_option "CustomerProof" "yes"
        set_pureftpd_option "DontResolve" "yes"
        set_pureftpd_option "NoAnonymous" "yes"
        set_pureftpd_option "VerboseLog" "no"
        set_pureftpd_option "AltLog" "clf:/var/log/pure-ftpd/transfer.log"

        # Allow the site users created by LEMPer to authenticate.
        set_pureftpd_option "UnixAuthentication" "yes"
        set_pureftpd_option "PAMAuthentication" "yes"

        run ln -sfn /etc/pure-ftpd/conf/UnixAuthentication /etc/pure-ftpd/auth/65unix
        run ln -sfn /etc/pure-ftpd/conf/PAMAuthentication /etc/pure-ftpd/auth/70pam

        # The packaged PAM stack is missing on source installs.
        if [[ ! -f /etc/pam.d/pure-ftpd ]]; then
            run cp -f etc/pam.d/pure-ftpd /etc/pam.d/pure-ftpd
            run chmod 0644 /etc/pam.d/pure-ftpd
        fi

        # Debian and Ubuntu start pure-ftpd from a sysv init script, which
        # only launches the daemon in standalone mode. debconf normally
        # writes this file, but minimal images can leave it out or in inetd
        # mode, where the init script exits successfully without listening.
        if [[ "${installer}" == "repo" ]]; then
            if [[ ! -f /etc/default/pure-ftpd-common ]]; then
                run cp -f etc/default/pure-ftpd-common /etc/default/pure-ftpd-common
                run chmod 0644 /etc/default/pure-ftpd-common
            fi

            if grep -Eq '^[[:space:]]*STANDALONE_OR_INETD=' /etc/default/pure-ftpd-common; then
                run sed_inplace 's/^[[:space:]]*STANDALONE_OR_INETD=.*/STANDALONE_OR_INETD=standalone/' \
                    /etc/default/pure-ftpd-common
            else
                run bash -c "printf '\nSTANDALONE_OR_INETD=standalone\n' >> /etc/default/pure-ftpd-common"
            fi
        fi

        # Enable passive mode.
        if [[ "${FTP_PASV_MODE}" == true ]]; then
            set_pureftpd_option "PassivePortRange" "${FTP_MIN_PORT} ${FTP_MAX_PORT}"

            # If we are behind NAT (such as AWS, GCP, Azure), set the public IP.
            if [[ -n "${SERVER_IP}" && "${SERVER_IP}" != "$(get_ip_private)" ]]; then
                set_pureftpd_option "ForcePassiveIP" "${SERVER_IP}"
            else
                run rm -f /etc/pure-ftpd/conf/ForcePassiveIP
            fi
        else
            run rm -f /etc/pure-ftpd/conf/PassivePortRange
            run rm -f /etc/pure-ftpd/conf/ForcePassiveIP
        fi

        # Enable TLS.
        if [[ "${FTP_SSL_ENABLE}" == true ]]; then
            ensure_pureftpd_certificate

            set_pureftpd_option "TLS" "2"
            set_pureftpd_option "TLSCipherSuite" "HIGH:!aNULL:!MD5"
        else
            run rm -f /etc/pure-ftpd/conf/TLS
        fi

        if [[ "${installer}" == "source" ]]; then
            if [[ ! -x /usr/sbin/pure-ftpd-wrapper ]]; then
                run cp -f sbin/pure-ftpd-wrapper /usr/sbin/pure-ftpd-wrapper
                run chmod 0755 /usr/sbin/pure-ftpd-wrapper
            fi

            # A source install has no packaged systemd unit, so ship a native one.
            run cp -f etc/systemd/pure-ftpd.service /etc/systemd/system/pure-ftpd.service
            run chmod 0644 /etc/systemd/system/pure-ftpd.service
        fi

        # Older LEMPer versions copied a generated sysv unit into /run. Drop
        # those copies so they cannot shadow the packaged or native unit.
        run rm -f /run/systemd/generator.late/pure-ftpd.service
        run rm -f /run/systemd/generator.late/multi-user.target.wants/pure-ftpd.service
        run rm -f /run/systemd/generator.late/graphical.target.wants/pure-ftpd.service

        # Restart Pure-FTPd daemon.
        echo "Restarting FTP server (Pure-FTPd)..."

        run systemctl daemon-reload
        run systemctl enable pure-ftpd.service
        run systemctl restart pure-ftpd.service

        sleep 1

        if ! systemctl is-active --quiet pure-ftpd.service; then
            error "FTP server (Pure-FTPd) failed to start."
            systemctl --no-pager --lines=15 status pure-ftpd.service || true
            journalctl -u pure-ftpd.service -n 15 --no-pager || true
            return 1
        fi

        success "FTP server (Pure-FTPd) is running."
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
                run env DEBIAN_FRONTEND=noninteractive apt-get install -q -y pure-ftpd-common pure-ftpd
                configure_pureftpd "repo"
            ;;
            2 | "source")
                echo "Installing FTP server (Pure-FTPd) from source..."

                if ! dpkg -s build-essential libssl-dev libpam0g-dev perl >/dev/null 2>&1; then
                    run env DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
                        build-essential libssl-dev libpam0g-dev perl
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)

                if [[ "${FTP_SERVER_VERSION}" == "latest" || "${FTP_SERVER_VERSION}" == "stable" ]]; then
                    PUREFTPD_FILENAME="pure-ftpd-1.0.54.tar.gz"
                else
                    PUREFTPD_FILENAME="pure-ftpd-${FTP_SERVER_VERSION}.tar.gz"
                fi
                PUREFTPD_ZIP_URL="https://download.pureftpd.org/pub/pure-ftpd/releases/${PUREFTPD_FILENAME}"

                run cd "${BUILD_DIR}" || return 1

                if [ ! -f "${PUREFTPD_FILENAME}" ]; then
                    if curl -sLI "${PUREFTPD_ZIP_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sSL -o "${PUREFTPD_FILENAME}" "${PUREFTPD_ZIP_URL}"
                    else
                        error "Cannot download PureFTPd source: '${PUREFTPD_FILENAME}'."
                        return 1
                    fi
                fi

                if [ -f "${PUREFTPD_FILENAME}" ]; then
                    echo "Compile and install Pure-FTPd..."

                    run tar -zxf "${PUREFTPD_FILENAME}" && \
                    run cd "${PUREFTPD_FILENAME%.*.*}" || return 1

                    # --with-everything covers PureDB, upload script, FTP who,
                    # virtual chroot and dir aliases. MySQL/PGSQL support is
                    # omitted: LEMPer authenticates system users, not SQL users.
                    run ./configure --prefix=/usr --with-tls --with-pam --with-privsep \
                        --with-everything && \
                    run make && \
                    run make install && \
                    run cd "${CURRENT_DIR}" || return 1

                    # Move executable to /usr/sbin if it was installed elsewhere.
                    if [[ -x /usr/local/sbin/pure-ftpd && ! -x /usr/sbin/pure-ftpd ]]; then
                        run ln -sfn /usr/local/sbin/pure-ftpd /usr/sbin/pure-ftpd
                    fi

                    configure_pureftpd "source"
                fi
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. Pure-FTPd installation skipped."
            ;;
        esac
    else
        info "FTP server (Pure-FTPd) installation skipped."
    fi
}

echo "[FTP Server (Pure-FTPd) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v pure-ftpd) && "${FORCE_INSTALL}" != true ]]; then
    if [[ "${INSTALL_FTP_SERVER}" == true ]]; then
        # Re-apply configuration so existing installs pick up the #135 fixes
        # (ftp account, wrapper options, combined certificate bundle).
        info "FTP Server (Pure-FTPd) already exists, re-applying configuration."

        if dpkg-query -W -f='${Status}' pure-ftpd 2>/dev/null | grep -q "install ok installed"; then
            configure_pureftpd "repo"
        else
            configure_pureftpd "source"
        fi
    else
        info "FTP Server (Pure-FTPd) already exists, installation skipped."
    fi
else
    init_pureftpd_install "$@"
fi
