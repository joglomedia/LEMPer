#!/usr/bin/env bash

# Mailer Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 14/02/2022
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

function init_postfix_removal() {
    if [[ $(pgrep -c postfix) -gt 0 ]]; then
        echo "Stopping postfix..."
        run systemctl stop postfix
    fi

    run systemctl disable postfix

    if dpkg-query -l | awk '/postfix/ { print $2 }' | grep -qwE "^postfix"; then
        echo "Found Postfix Mail-Transfer Agent package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y postfix mailutils
    else
        info "Postfix Mail-Transfer Agent package not found, possibly installed from source."
        echo "Remove it manually!!"

        POSTFIX_BIN=$(command -v postfix)

        echo "Deleting Postfix binary executable: ${POSTFIX_BIN}"

        [[ -n $(command -v postfix) ]] && run rm -f "${POSTFIX_BIN}"
    fi

    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_POSTFIX_CONFIG="y"
        else
            REMOVE_POSTFIX_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_POSTFIX_CONFIG}" != "y" && "${REMOVE_POSTFIX_CONFIG}" != "n" ]]; do
            read -rp "Remove Postfix database and configuration files? [y/n]: " -e REMOVE_POSTFIX_CONFIG
        done
    fi

    if [[ "${REMOVE_POSTFIX_CONFIG}" == Y* || "${REMOVE_POSTFIX_CONFIG}" == y* ]]; then
        if [[ -d /etc/postfix ]]; then
            run rm -fr /etc/postfix/
        fi

        echo "All your Postfix configuration files deleted permanently."
    fi

    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v postfix) ]]; then
            success "Postfix Mail-Transfer Agent removed succesfully."
        else
            info "Unable to remove Postfix Mail-Transfer Agent."
        fi
    else
        info "Postfix Mail-Transfer Agent removed in dry run mode."
    fi
}

function init_dovecot_removal() {
    if [[ $(pgrep -c dovecot) -gt 0 ]]; then
        echo "Stopping dovecot..."
        run systemctl stop dovecot
        run systemctl disable dovecot
    fi

    if dpkg-query -l | awk '/dovecot/ { print $2 }' | grep -qwE "^dovecot"; then
        echo "Found Dovecot IMAP server package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y dovecot-core dovecot-common dovecot-imapd dovecot-pop3d
    else
        info "Dovecot IMAP server package not found, possibly installed from source."
        echo "Remove it manually!!"

        DOVECOT_BIN=$(command -v dovecot)

        echo "Deleting Dovecot IMAP server executable: ${DOVECOT_BIN}"

        [[ -n "${DOVECOT_BIN}" ]] && run rm -f "${DOVECOT_BIN}"
    fi

    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_DOVECOT_CONFIG="y"
        else
            REMOVE_DOVECOT_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_DOVECOT_CONFIG}" != "y" && "${REMOVE_DOVECOT_CONFIG}" != "n" ]]; do
            read -rp "Remove Dovecot database and configuration files? [y/n]: " -e REMOVE_DOVECOT_CONFIG
        done
    fi

    if [[ "${REMOVE_DOVECOT_CONFIG}" == Y* || "${REMOVE_DOVECOT_CONFIG}" == y* ]]; then
        if [[ -d /etc/dovecot ]]; then
            run rm -fr /etc/dovecot/
        fi

        echo "All your Dovecot configuration files deleted permanently."
    fi

    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v dovecot) ]]; then
            success "Dovecot IMAP server removed succesfully."
        else
            info "Unable to remove Dovecot IMAP server."
        fi
    else
        info "Dovecot IMAP server removed in dry run mode."
    fi
}

function init_spfdkim_removal() {
    if [[ $(pgrep -c opendkim) -gt 0 ]]; then
        run systemctl stop opendkim
        run systemctl disable opendkim
    fi

    if dpkg-query -l | awk '/opendkim/ { print $2 }' | grep -qwE "^opendkim"; then
        echo "Found OpenDKIM + SPF package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y postfix-policyd-spf-python opendkim opendkim-tools
    else
        info "OpenDKIM + SPF package not found, possibly installed from source."
        echo "Remove it manually!!"

        OPENDKIM_BIN=$(command -v opendkim)

        echo "Deleting OpenDKIM executable: ${OPENDKIM_BIN}"

        [[ -x $(command -v opendkim) ]] && run rm -f "${OPENDKIM_BIN}"
    fi

    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_OPENDKIM_CONFIG="y"
        else
            REMOVE_OPENDKIM_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_OPENDKIM_CONFIG}" != "y" && "${REMOVE_OPENDKIM_CONFIG}" != "n" ]]; do
            read -rp "Remove OpenDKIM + SPF configuration files? [y/n]: " -e REMOVE_OPENDKIM_CONFIG
        done
    fi

    if [[ "${REMOVE_OPENDKIM_CONFIG}" == Y* || "${REMOVE_OPENDKIM_CONFIG}" == y* ]]; then
        if [[ -d /etc/opendkim ]]; then
            run rm -fr /etc/opendkim
        fi

        if [[ -f /etc/default/opendkim ]]; then
            run rm -f /etc/default/opendkim
        fi

        if [[ -f /etc/opendkim.conf ]]; then
            run rm -f /etc/opendkim.conf
        fi

        echo "All your OpenDKIM + SPF configuration files deleted permanently."
    fi

    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v opendkim) ]]; then
            success "OpenDKIM + SPF package removed succesfully."
        else
            info "Unable to remove OpenDKIM + SPF package."
        fi
    else
        info "OpenDKIM + SPF package removed in dry run mode."
    fi
}

echo "Uninstalling Mailer (Postfix and Dovecot)..."

if [[ -n $(command -v postfix) || -n $(command -v dovecot) || -n $(command -v opendkim) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_MAILER="y"
    else
        while [[ "${REMOVE_MAILER}" != "y" && "${REMOVE_MAILER}" != "n" ]]; do
            read -rp "Are you sure to remove mail server (Postfix + Dovecot)? [y/n]: " -e REMOVE_MAILER
        done
    fi

    if [[ "${REMOVE_MAILER}" == y* || "${REMOVE_MAILER}" == Y* ]]; then
        init_postfix_removal "$@"
        init_dovecot_removal "$@"
        init_spfdkim_removal "$@"
    else
        echo "Found mail server (Postfix + Dovecot), but not removed."
    fi
else
    info "Oops, mail server (Postfix + Dovecot) installation not found."
fi
