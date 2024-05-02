#!/usr/bin/env bash

# Certbot Let's Encrypt Installer
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
# Install Certbot Let's Encrypt.
##
function init_certbotle_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_CERTBOT}" == true ]]; then
            DO_INSTALL_CERTBOT="y"
        else
            DO_INSTALL_CERTBOT="n"
        fi
    else
        while [[ "${DO_INSTALL_CERTBOT}" != "y" && "${DO_INSTALL_CERTBOT}" != "n" ]]; do
            read -rp "Do you want to install Certbot Let's Encrypt client? [y/n]: " -i y -e DO_INSTALL_CERTBOT
        done
    fi

    if [[ ${DO_INSTALL_CERTBOT} == y* || ${DO_INSTALL_CERTBOT} == Y* ]]; then
        echo "Installing Certbot Let's Encrypt client..."

        DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
        RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

        case "${DISTRIB_NAME}" in
            debian)
                case "${RELEASE_NAME}" in
                    jessie)
                        run apt-get install -q -y certbot -t jessie-backports
                    ;;
                    stretch | buster | bullseye | bookworm)
                        install_certbot_pip
                    ;;
                    *)
                        error "Unable to add Certbot, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                        echo "Sorry your system is not supported yet, installing from source may fix the issue."
                        exit 1
                    ;;
                esac
            ;;
            ubuntu)
                install_certbot_pip
            ;;
            *)
                error "Unable to add Certbot, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                echo "Sorry your system is not supported yet, installing from source may fix the issue."
                exit 1
            ;;
        esac

        # Add Certbot auto renew command to cronjob.
        if [[ "${DRYRUN}" != true ]]; then
            export EDITOR=nano
            CRONCMD='0 */6 * * * /usr/bin/certbot renew --quiet --pre-hook "/usr/sbin/service nginx stop" --post-hook "/usr/sbin/service nginx start"'
            touch lemper.cron
            crontab -u root lemper.cron
            crontab -l > lemper.cron

            if ! grep -qwE "/usr/bin/certbot\ renew" lemper.cron; then
                cat >> lemper.cron <<EOL
# LEMPer Cronjob
# Certbot Auto-renew Let's Encrypt certificates.
SHELL=/bin/bash
PATH=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root

${CRONCMD}
EOL

                crontab lemper.cron
                rm -f lemper.cron
                #service cron reload
            else
                info "Certbot auto-renew command added to cronjob in dry run mode."
            fi

            # Register a new account.
            local LE_EMAIL=${LEMPER_ADMIN_EMAIL:-"cert@lemper.cloud"}

            if [[ -d /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory ]]; then
                run certbot update_account --email "${LE_EMAIL}" --no-eff-email --agree-tos
            else
                run certbot register --email "${LE_EMAIL}" --no-eff-email --agree-tos
            fi
        fi

        # Self-signed OpenSSL cert config.
        run mkdir -p "/etc/lemper/ssl/${HOSTNAME}" && \
        run cp -f etc/openssl/ca.conf /etc/lemper/ssl/ca.conf && \
        run cp -f etc/openssl/csr.conf /etc/lemper/ssl/csr.conf && \
        run cp -f etc/openssl/cert.conf /etc/lemper/ssl/cert.conf

        if [[ "${DRYRUN}" != true ]]; then
            if certbot --version | grep -q "certbot"; then
                success "Certbot successfully installed."
            else
                info "Something went wrong with Certbot installation."
            fi
        else
            info "Certbot installed in dry run mode."
        fi
    fi
}

##
# Install Python Venv for Certbot.
##
function install_certbot_pip() {
    run python -m venv /opt/certbot/ && \
    run /opt/certbot/bin/pip install --upgrade pip setuptools cffi && \
    run /opt/certbot/bin/pip install --upgrade certbot certbot-nginx && \
    run ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
}

echo "[Certbot Let's Encrypt Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v certbot) && "${FORCE_INSTALL}" != true ]]; then
    info "Certbot Let's Encrypt already exists, installation skipped."
else
    init_certbotle_install "$@"
fi
