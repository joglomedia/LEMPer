#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Installer & Uninstaller - Shared Logic                     |
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



function lemper_recipe_components() {
    local action="$1" service installer remover _units _key _family component php_before version
    # shellcheck source=/dev/null
    . "$BASE_DIR/lib/core/registry.sh" || return 1
    while IFS= read -r service; do
        [[ "$service" != ftp ]] || service="${FTP_SERVER_NAME:-pureftpd}"
        read -r installer remover _units _key _family < <(lemper_component_spec "$service")
        [[ -n "$installer" ]] || return 1
        [[ "$action" != remove || "$remover" != - ]] || continue
        if [[ "$action" == install ]]; then component="$installer"; else component="$remover"; fi
        component="$BASE_DIR/scripts/${action}_$component.sh"
        [[ -f "$component" ]] || { error "Recipe component missing: $component"; return 1; }
        php_before=""
        if [[ "$action" == install && "$service" == php && "${INSTALL_PHP:-false}" == true ]]; then
            lemper_load_module services/php/lifecycle || return 1
            php_before=$(lemper_php_inventory all)
        fi
        # Components are checked independently; existing enable flags remain authoritative.
        # shellcheck source=/dev/null
        . "$component" || return 1
        if [[ "$action" == install && "$service" == php && "${INSTALL_PHP:-false}" == true && "${DRYRUN:-false}" != true ]]; then
            while IFS= read -r version; do
                [[ -n "$version" ]] || continue
                if ! grep -Fxq "$version" <<< "$php_before"; then mark_lemper_provisioned "php-$version" || return 1; fi
            done < <(lemper_php_inventory all)
        fi
    done < <(lemper_component_recipe "$action")
}

##
# Main LEMPer Installer
##
function lemper_install() {
    validate_config_file "${ENVFILE}" install || return 1
    echo "Starting LEMPer Stack installation..."
    echo "Please ensure that you're on a fresh install!"
    echo -e "\nPress [Ctrl+C] to abort the installation process."

    sleep 3

    if [[ "${AUTO_INSTALL}" != true ]]; then
        echo ""
        read -t 60 -rp "Press [Enter] to continue..." </dev/tty
    fi

    # Init log.
    run init_log

    # Init config.
    run init_config

    ### Install dependencies packages ###
    if [ -f "${BASE_DIR}/scripts/install_dependencies.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/install_dependencies.sh"
    fi

    ### Server clean-up ###
    if [ -f "${BASE_DIR}/scripts/server_cleanup.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_cleanup.sh"
    fi

    ### Create default account ###
    echo ""
    LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
    create_account "${LEMPER_USERNAME}"

    lemper_recipe_components install || return 1

    if [ -f "${BASE_DIR}/scripts/server_optimization.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_optimization.sh"
    fi

    ### Basic server security setup ###
    if [ -f "${BASE_DIR}/scripts/server_security.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_security.sh"
    fi

    ### FINAL SETUP ###
    if [[ "${FORCE_REMOVE}" == true ]]; then
        # Cleaning up all build dependencies hanging around on production server?
        echo -e "\nClean up installation process..."
        run apt-get autoremove -q -y

        # Cleanup build dir
        echo "Clean up build directory..."
        if [ -d "${BUILD_DIR}" ]; then
            run rm -fr "${BUILD_DIR}"
        fi
    fi

    if [[ "${DRYRUN}" != true ]]; then
        status -e "\nCongrats, your LEMPer Stack installation has been completed."

        ### Recap (SEC-08: credentials NOT printed to stdout) ###
        if [[ -n "${LEMPER_PASSWORD}" ]]; then
            info "Installation credentials have been saved to /etc/lemper/lemper.conf (root-only, mode 0600)."
            info "To view them, run: sudo cat /etc/lemper/lemper.conf"

            echo ""
            echo "LEMPer Stack installed successfully:"
            echo "  Hostname: ${HOSTNAME}"
            echo "  Server IP: ${SERVER_IP}"
            echo "  SSH Port: ${SSH_PORT}"
            echo "  Admin User: ${LEMPER_USERNAME}"
            echo ""
            echo "Service URLs:"
            if [[ "${INSTALL_NGINX}" == true ]]; then
                echo "  Web Server: http://${SERVER_IP}/ (Nginx)"
                echo "  Database Admin: http://${SERVER_IP}:8082/lcp/dbadmin/"
                echo "  File Manager: http://${SERVER_IP}:8082/lcp/filemanager/"
            fi
            info "All sensitive credentials are in /etc/lemper/lemper.conf (root-only)."
        fi
    else
        warning -e "\nLEMPer installation has been completed in dry-run mode."
    fi

    echo -e "\nSee the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!\n"

    info "SECURITY: Credentials are stored in /etc/lemper/lemper.conf (mode 0600, root-only).
Keep this file secure and delete the installation log after setup."
}

##
# Main LEMPer Uninstaller
##
function lemper_remove() {
    echo "Are you sure to remove LEMPer Stack installation?"
    echo "Please ensure that you've backed up your critical data!"
    echo ""

    if [[ "${AUTO_REMOVE}" == false ]]; then
        read -rt 20 -p "Press [Enter] to continue..." </dev/tty
    fi

    # Fix broken install, first?
    if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
        run dpkg --configure -a
        run apt-get install -q -y --fix-broken
    fi

    lemper_recipe_components remove || return 1

    ### Remove server security setup ###
    if [ -f "${BASE_DIR}/scripts/server_security.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_security.sh" --remove
    fi

    ### Remove default user account ###
    echo ""
    echo "Removing created default account..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_ACCOUNT="y"
    else
        while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
            read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
        done
    fi

    if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t delete_account)" == "function" ]]; then
            delete_account "${LEMPER_USERNAME}"
        fi
    fi

    ### Remove created swap ###
    echo ""
    echo "Removing created swap..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_SWAP="y"
    else
        while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
            read -rp "Remove created Swap? [y/n]: " -e REMOVE_SWAP
        done
    fi

    if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t remove_swap)" == "function" ]]; then
            remove_swap
        fi
    fi

    ### Remove web tools ###
    [ -L /usr/local/bin/lemperctl ] && run rm -f /usr/local/bin/lemperctl
    [ -e /usr/bin/lemper-cli ] && run rm -f /usr/bin/lemper-cli
    [ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper
    [ -d /usr/share/nginx/html/lcp ] && run rm -fr /usr/share/nginx/html/lcp

    # Clean up LEMPer state: credentials, encrypted config key, vhost metadata,
    # ACME account data, WAF snippets, update source, and provisioning markers.
    [ -d /etc/lemper ] && run rm -fr /etc/lemper

    ### Remove unnecessary packages ###
    echo -e "\nCleaning up unnecessary packages..."

    run apt-get autoremove -q -y && \
    run apt-get autoclean -q -y && \
    run apt-get clean -q -y

    echo -e "\nLEMPer Stack has been removed completely."
    warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer Stack or have
any other reasons to uninstall it, please let us know ^^

Submit your issue here: https://github.com/joglomedia/LEMPer/issues"
}
