#!/usr/bin/env bash

# Certbot Let's Encrypt Installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 12/07/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Install Certbot Let's Encrypt.
function init_certbotle_install() {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_CERTBOT="y"
    else
        while [[ "${DO_INSTALL_CERTBOT}" != "y" && "${DO_INSTALL_CERTBOT}" != "n" ]]; do
            read -rp "Do you want to install Certbot Let's Encrypt client? [y/n]: " -i y -e DO_INSTALL_CERTBOT
        done
    fi

    if [[ ${DO_INSTALL_CERTBOT} == y* && ${INSTALL_CERTBOT} == true ]]; then
        echo "Installing Certbot Let's Encrypt client..."

        DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
        RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

        case "${DISTRIB_NAME}" in
            debian)
                case "${RELEASE_NAME}" in
                    jessie)
                        run apt install -qq -y certbot -t jessie-backports
                    ;;
                    stretch)
                        run apt install -qq -y certbot -t stretch-backports
                    ;;
                    buster)
                        run apt install -qq -y certbot
                    ;;
                    *)
                        error "Unable to add Certbot, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                        echo "Sorry your system is not supported yet, installing from source may fix the issue."
                        exit 1
                    ;;
                esac
            ;;
            ubuntu)
                run add-apt-repository -y ppa:certbot/certbot
                run apt update -qq -y
                run apt install -qq -y certbot
            ;;
        esac

        # Add Certbot auto renew command to cronjob.
        if "${DRYRUN}"; then
            info "Certbot auto-renew command added to cronjob in dryrun mode."
        else
            export EDITOR=nano
            CRONCMD='15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/usr/sbin/service nginx reload -s"'
            touch lemper.cron
            crontab -u root lemper.cron
            crontab -l > lemper.cron

            if ! grep -qwE "/usr/bin/certbot\ renew" lemper.cron; then
                cat >> lemper.cron <<EOL
# LEMPer Cronjob
# Certbot Auto-renew Let's Encrypt certificates
#SHELL=/bin/sh
#PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

${CRONCMD}
EOL

                crontab lemper.cron
                rm -f lemper.cron
            fi

            # Register a new account.
            local LE_EMAIL=${ADMIN_EMAIL:-"cert@lemper.sh"}

            if [ -d /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory ]; then
                run certbot update_account --email "${LE_EMAIL}" --no-eff-email --agree-tos
            else
                run certbot register --email "${LE_EMAIL}" --no-eff-email --agree-tos
            fi
        fi

        if "${DRYRUN}"; then
            info "Certbot installed in dryrun mode."
        else
            if certbot --version | grep -q "certbot"; then
                success "Certbot successfully installed."
            else
                info "Something went wrong with Certbot installation."
            fi
        fi
    fi
}

echo "[Certbot Let's Encrypt Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v certbot) ]]; then
    info "Certbot Let's Encrypt already exists. Installation skipped..."
else
    init_certbotle_install "$@"
fi
