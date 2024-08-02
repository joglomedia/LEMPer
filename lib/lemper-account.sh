#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - System's User Account Generator                            |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
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

# Create default system account.
function create_account() {
    export USERNAME=${1:-"lemper"}
    export PASSWORD && \
    PASSWORD=${LEMPER_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

    echo "Add new system account..."

    if [[ -z $(getent passwd "${USERNAME}") ]]; then
        if [[ ${DRYRUN} != true ]]; then
            useradd -d "/home/${USERNAME}" -m -s /bin/bash "${USERNAME}"
            echo "${USERNAME}:${PASSWORD}" | chpasswd
            usermod -aG sudo "${USERNAME}"

            # Create default directories.
            mkdir -p "/home/${USERNAME}/webapps" && \
            mkdir -p "/home/${USERNAME}/logs" && \
            mkdir -p "/home/${USERNAME}/logs/nginx" && \
            mkdir -p "/home/${USERNAME}/logs/php" && \
            mkdir -p "/home/${USERNAME}/.lemper" && \
            mkdir -p "/home/${USERNAME}/.ssh" && \
            chmod 700 "/home/${USERNAME}/.ssh" && \
            touch "/home/${USERNAME}/.ssh/authorized_keys" && \
            chmod 600 "/home/${USERNAME}/.ssh/authorized_keys" && \
            chown -hR "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

            # Add account credentials to /srv/.htpasswd.
            [ ! -f "/srv/.htpasswd" ] && touch /srv/.htpasswd

            # Protect .htpasswd file.
            chmod 0600 /srv/.htpasswd
            chown www-data:www-data /srv/.htpasswd

            # Generate password hash.
            if [[ -n $(command -v mkpasswd) ]]; then
                PASSWORD_HASH=$(mkpasswd --method=sha-256 "${PASSWORD}")
                sed -i "/^${USERNAME}:/d" /srv/.htpasswd
                echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            elif [[ -n $(command -v htpasswd) ]]; then
                htpasswd -b /srv/.htpasswd "${USERNAME}" "${PASSWORD}"
            else
                PASSWORD_HASH=$(openssl passwd -1 "${PASSWORD}")
                sed -i "/^${USERNAME}:/d" /srv/.htpasswd
                echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            fi

            # Save config.
            echo -e "LEMPER_USERNAME=${USERNAME}\nLEMPER_PASSWORD=${PASSWORD}\nLEMPER_ADMIN_EMAIL=${LEMPER_ADMIN_EMAIL}"

            # Save data to log file.
            echo -e "Your default system account information:\nUsername: ${USERNAME}\nPassword: ${PASSWORD}"

            echo "Username ${USERNAME} created."
        else
            echo "Create ${USERNAME} account in dry mode."
        fi
    else
        echo "Unable to create account, username ${USERNAME} already exists."
    fi
}

create_account $@
