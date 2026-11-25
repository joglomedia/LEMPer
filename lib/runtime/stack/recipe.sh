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
    local action="$1" service installer remover _units _key _family component php_before version preexisting
    local PHP_VERSIONS="${PHP_VERSIONS:-8.5}" REDIS_BACKEND="${REDIS_BACKEND:-redis}"
    local FTP_SERVER_NAME="${FTP_SERVER_NAME:-pureftpd}"
    local selected_php="" marker nginx_removed=false
    # shellcheck source=/dev/null
    . "$BASE_DIR/lib/core/registry.sh" || return 1
    lemper_load_module services/inventory || return 1
    lemper_load_module core/progress || return 1
    local total=0
    while IFS= read -r service; do
        read -r installer remover _units _key _family < <(lemper_component_spec "$service")
        [[ "$action" != install || "$_key" == - || "${!_key:-false}" == true ]] || continue
        if [[ "$action" == remove && "${FORCE_REMOVE:-false}" != true ]]; then
            if [[ "$service" == php ]]; then
                compgen -G "${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}/php-*" >/dev/null || continue
            else lemper_provisioned "$service" || continue; fi
        fi
        total=$((total + 1))
    done < <(lemper_component_recipe "$action")
    lemper_progress_reset "$total" || return 1
    while IFS= read -r service; do
        [[ "$service" != ftp ]] || service="${FTP_SERVER_NAME:-pureftpd}"
        [[ "$action" != install || "$service" != redis ]] || service="$REDIS_BACKEND"
        read -r installer remover _units _key _family < <(lemper_component_spec "$service")
        [[ -n "$installer" ]] || return 1
        if [[ "$action" == install && "$_key" != - && "${!_key:-false}" != true ]]; then
            continue
        fi
        if [[ "$action" == remove && "${FORCE_REMOVE:-false}" != true ]]; then
            if [[ "$service" == php ]]; then
                selected_php=""
                for marker in "${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}"/php-*; do
                    [[ -f "$marker" && ! -L "$marker" ]] || continue
                    version="${marker##*/php-}"
                    [[ "$version" =~ ^[5-8]\.[0-9]$ ]] || continue
                    selected_php+=" $version"
                done
                [[ -n "$selected_php" ]] || continue
                PHP_VERSIONS="$selected_php"
                lemper_load_module services/php/lifecycle || return 1
                if [[ "$nginx_removed" == false ]]; then
                    for version in $PHP_VERSIONS; do
                        lemper_php_check_references "$version" || return 1
                    done
                fi
            elif ! lemper_provisioned "$service"; then
                info "Preserving component without provisioning marker: $service."
                continue
            fi
        fi
        preexisting=false
        if [[ "$action" == install && "$service" != php ]] && lemper_component_present "$service"; then
            preexisting=true
        fi
        [[ "$action" != remove || "$remover" != - ]] || continue
        if [[ "$action" == install ]]; then component="$installer"; else component="$remover"; fi
        case "$service" in
            redis | valkey) REDIS_BACKEND="$service" ;;
            pureftpd | vsftpd) FTP_SERVER_NAME="$service" ;;
        esac
        component="$BASE_DIR/scripts/${action}_$component.sh"
        [[ -f "$component" ]] || {
            error "Recipe component missing: $component"
            return 1
        }
        progress "$action $service"
        php_before=""
        if [[ "$action" == install && "$service" == php && "${INSTALL_PHP:-false}" == true ]]; then
            lemper_load_module services/php/lifecycle || return 1
            php_before=$(lemper_php_inventory all)
        fi
        # New drivers share component contracts; older/thin entrypoints remain compatible.
        if [[ -f "$BASE_DIR/lib/runtime/components/lifecycle.sh" ]] && lemper_component_driver "$action" "$service" >/dev/null; then
            lemper_load_module runtime/components/lifecycle || return 1
            lemper_component_apply "$action" "$service" || return 1
        else
            # shellcheck source=/dev/null
            . "$component" || return 1
        fi
        if [[ "$action" == remove && "$service" == nginx ]]; then
            # Keep ownership until the full recipe completes, including failed/retried teardown.
            mark_lemper_provisioned nginx || return 1
            if ! systemctl is-active --quiet nginx >/dev/null 2>&1 && ! pgrep -x nginx >/dev/null; then
                # Retained rollback configuration is not served by this stopped owned server.
                nginx_removed=true
            fi
        fi
        if [[ "$action" == install && "$service" != php && "$preexisting" == false &&
            "${DRYRUN:-false}" != true ]] && lemper_component_present "$service"; then
            mark_lemper_provisioned "$service" || return 1
        fi
        if [[ "$action" == install && "$service" == php && "${INSTALL_PHP:-false}" == true && "${DRYRUN:-false}" != true ]]; then
            while IFS= read -r version; do
                [[ -n "$version" ]] || continue
                if ! grep -Fxq "$version" <<<"$php_before"; then mark_lemper_provisioned "php-$version" || return 1; fi
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

    if [[ "${AUTO_INSTALL}" != true ]]; then
        sleep 3
        echo ""
        read -t 60 -rp "Press [Enter] to continue..." </dev/tty
    fi

    # Init log.
    if [[ "$LOG_FILE" == ./install.log ]]; then
        run mkdir -p /var/log/lemper
        LOG_FILE=/var/log/lemper/install.log
        set_env_value "$ENVFILE" LOG_FILE "$LOG_FILE" || return 1
    fi
    run init_log

    # Init config.
    core_store_install_profile "$ENVFILE" || return 1

    ### Install dependencies packages ###
    if [ -f "${BASE_DIR}/scripts/install_dependencies.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/install_dependencies.sh" || return 1
    fi

    ### Server clean-up ###
    if [ -f "${BASE_DIR}/scripts/server_cleanup.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_cleanup.sh" || return 1
    fi

    ### Create default account ###
    echo ""
    LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
    local account_present=false swap_present=false
    getent passwd "$LEMPER_USERNAME" >/dev/null && account_present=true
    [[ ! -e /swapfile ]] || swap_present=true
    create_account "${LEMPER_USERNAME}" || return 1
    [[ "$account_present" == true ]] || mark_lemper_provisioned "account-$LEMPER_USERNAME" || return 1

    lemper_recipe_components install || return 1

    if [ -f "${BASE_DIR}/scripts/server_optimization.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_optimization.sh" || return 1
        if [[ "$swap_present" == false && -e /swapfile && "${ENABLE_SWAP:-false}" == true ]]; then
            mark_lemper_provisioned swap || return 1
        fi
    fi

    ### Basic server security setup ###
    if [ -f "${BASE_DIR}/scripts/server_security.sh" ]; then
        echo ""
        # Component scripts are checked independently; keep this orchestrator lint bounded.
        # shellcheck source=/dev/null
        . "${BASE_DIR}/scripts/server_security.sh" || return 1
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
    # Quota ownership must remain recoverable until all tenants are detached.
    lemper_load_module services/hosting/plans || return 1
    local hosting_root assignment
    hosting_root=$(lemper_hosting_root) || return 1
    [[ ! -L "$hosting_root/assignments" ]] || return 1
    for assignment in "$hosting_root"/assignments/*.conf; do
        [[ ! -e "$assignment" && ! -L "$assignment" ]] || {
            error "Detach hosting accounts before removing LEMPer."
            return 1
        }
    done
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

    if [[ ("${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y*) &&
        -f "/etc/lemper/installed/account-$LEMPER_USERNAME" || "${FORCE_REMOVE}" == true ]]; then
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

    if [[ ("${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y*) &&
        -f /etc/lemper/installed/swap || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t remove_swap)" == "function" ]]; then
            remove_swap
        fi
    fi

    ### Remove web tools ###
    run rm -f /usr/local/bin/lemperctl /usr/local/bin/lemper-cli /usr/bin/lemper-cli
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper
    [ -d /usr/share/nginx/html/lcp ] && run rm -fr /usr/share/nginx/html/lcp

    # Clean up LEMPer state: credentials, encrypted config key, vhost metadata,
    # ACME account data, WAF snippets, update source, and provisioning markers.
    [ -d /etc/lemper ] && run rm -fr /etc/lemper

    ### Remove unnecessary packages ###
    echo -e "\nCleaning up unnecessary packages..."

    run apt-get autoremove -q -y \
        && run apt-get autoclean -q -y \
        && run apt-get clean -q -y

    echo -e "\nLEMPer Stack has been removed completely."
    warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer Stack or have
any other reasons to uninstall it, please let us know ^^

Submit your issue here: https://github.com/joglomedia/LEMPer/issues"
}
