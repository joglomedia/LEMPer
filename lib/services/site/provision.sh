#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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

function lemper_site_required_packages() {
    local CMD
    local -a MISSING=()

    for CMD in curl git rsync unzip wget; do
        if ! command -v "${CMD}" &>/dev/null; then
            MISSING+=("${CMD}")
        fi
    done

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        error "${PROG_NAME} ${CMD_NAME} requires: ${MISSING[*]}, please install it first!"
        echo "help: run 'sudo apt-get install ${MISSING[*]}'"
        return 1
    fi
}

##
# Get server IP Address.
#
function get_ip_addr() {
    core_get_ip
}

##
# Check whether IPv4 is valid.
#
function validate_ipv4() {
    core_validate_ipv4 "$@"
}

##
# Check whether IPv6 is valid.
#
function validate_ipv6() {
    core_validate_ipv6 "$@"
}

##
# Validate FQDN domain.
# Uses ERE (grep -E) with a separate length check for portability.
# PCRE (grep -P) lookahead/lookbehind is not available on all platforms.
##
function validate_fqdn() {
    core_validate_fqdn "$@"
}

##
# Workaround for local domain (e.g. example.test)
# working on Local/Dev environment.
#
function add_local_domain() {
    local DOMAIN_IP && DOMAIN_IP=${1}
    local DOMAIN_NAME && DOMAIN_NAME=${2}

    if grep -qwE "${DOMAIN_NAME}" "/etc/hosts"; then
        LINE_EXISTS=$(grep "${DOMAIN_NAME}" /etc/hosts)
        warning "Domain hostname already exists: ${LINE_EXISTS}"
    else
        info "Adding ${DOMAIN_NAME} to your '/etc/hosts'..."
        run bash -c "echo -e '${DOMAIN_IP}\t${DOMAIN_NAME}' >> /etc/hosts"

        if grep -qwE "${DOMAIN_NAME}" "/etc/hosts"; then
            run service networking restart
            success "${DOMAIN_NAME} was added succesfully..."
        else
            error "Failed to add ${DOMAIN_NAME} to your '/etc/hosts', try again!"
        fi
    fi
}

function lemper_site_activate_vhost() {
    local staged="$1" available="$2" enabled="$3" start_attempted=false
    if [[ -e "$available" || -L "$available" || -e "$enabled" || -L "$enabled" ]]; then
        error "A configuration or selection already exists for this virtual host."
        return 1
    fi
    # Publish without replacing a path that appeared after the initial check.
    lemper_exec mv -Tn -- "$staged" "$available" && [[ ! -e "$staged" ]] || return 1
    if ! lemper_exec ln -sT -- "$available" "$enabled"; then
        lemper_exec rm -f -- "$available" || error "Unable to remove new configuration at $available."
        return 1
    fi
    if nginx -t; then
        start_attempted=true
        if lemper_exec systemctl reload-or-restart nginx; then
            return 0
        fi
    fi
    if lemper_exec rm -f -- "$enabled" "$available"; then
        error "Nginx rejected the new virtual host. Its configuration was removed."
        if [[ "$start_attempted" == true ]]; then
            if ! nginx -t || ! lemper_exec systemctl reload-or-restart nginx; then
                error "Unable to reload the previous Nginx configuration."
            fi
        fi
    else
        error "Unable to remove the new virtual host configuration after activation failed."
    fi
    return 1
}

function lemper_site_provision() (
    local available enabled VHOST_FILE
    [[ -n "$FRAMEWORK" ]] || FRAMEWORK=default
    lemper_load_module services/site/applications || return 1
    lemper_site_application_validate_request "$FRAMEWORK" "$INSTALL_APP" || return 1
    if [[ "$INSTALL_APP" == true ]] && lemper_site_application_uses_release "$FRAMEWORK"; then
        lemper_load_module services/site/releases || return 1
        lemper_site_release_preflight "$FRAMEWORK" "${WEBROOT:-/home/${USERNAME:-${LEMPER_USERNAME:-lemper}}/webapps/$SERVERNAME}" \
            "${USERNAME:-${LEMPER_USERNAME:-lemper}}" "$PHP_VERSION" || return 1
        if [[ "$DRYRUN" == true ]]; then
            info "Would deploy $FRAMEWORK complete files and configure $SERVERNAME."
            return 0
        fi
    elif lemper_site_application_custom_template "$FRAMEWORK"; then
        [[ "${USERNAME:-${LEMPER_USERNAME:-lemper}}" != root ]] || {
            error "Application pools must use a non-root user."
            return 1
        }
        lemper_load_module services/site/releases || return 1
        lemper_site_release_target "${WEBROOT:-/home/${USERNAME:-${LEMPER_USERNAME:-lemper}}/webapps/$SERVERNAME}" \
            "${USERNAME:-${LEMPER_USERNAME:-lemper}}" || return 1
        [[ "$DRYRUN" != true ]] || {
            info "Would configure $FRAMEWORK vhost for $SERVERNAME."
            return 0
        }
    fi

    if [[ -n "$IPv4" ]] && ! core_is_valid_ipv4 "$IPv4"; then
        error "Invalid site IPv4 address."
        return 1
    fi
    if [[ -n "$IPv6" ]] && ! core_is_valid_ipv6 "$IPv6"; then
        error "Invalid site IPv6 address."
        return 1
    fi

    if [[ "${MAIN_ARGS}" -ge 1 ]]; then
        lemper_site_required_packages || return 1

        # Additional Check - ensure that Nginx's configuration meets the requirements.
        if [[ ! -d /etc/nginx/sites-available && ! -d /etc/nginx/vhost ]]; then
            fail "Your Nginx installation does not meet the LEMPer stack requirements. The installation has been aborted."
        fi

        # Check domain parameter.
        if [[ -z "${SERVERNAME}" ]]; then
            fail -e "The domain name parameter should not be empty. \n       -d or --domain-name parameter is required!"
        else
            if [[ $(validate_fqdn "${SERVERNAME}") == false ]]; then
                fail "Invalid input: '${SERVERNAME}' is not a valid FQDN. Expected format: example.com."
            fi
        fi

        available="/etc/nginx/sites-available/${SERVERNAME}.conf"
        enabled="/etc/nginx/sites-enabled/${SERVERNAME}.conf"

        # A dangling selection is still administrator-managed state.
        if [[ ! -e "$available" && ! -L "$available" && ! -e "$enabled" && ! -L "$enabled" ]]; then
            if [[ "${DRYRUN:-false}" == true ]]; then
                info "Would configure $FRAMEWORK vhost for $SERVERNAME."
                return 0
            fi
            lemper_build_workspace "$TMPDIR" || return 1
            VHOST_FILE=$(mktemp -- "$available.XXXXXXXX") || return 1
            trap 'rm -f -- "$VHOST_FILE"' EXIT
            echo "Adding domain ${SERVERNAME} to the Nginx virtual host configuration."

            # Check for username.
            if [[ -z "${USERNAME}" ]]; then
                info "Username parameter is empty. Using default account: '${LEMPER_USERNAME}'."
                USERNAME=${LEMPER_USERNAME:-"lemper"}
            fi

            # Additional Check - are user account exist?
            if ! is_valid_username "${USERNAME}"; then
                fail "Invalid system username."
            fi

            if [[ -z $(getent passwd "${USERNAME}") ]]; then
                fail "User account '${USERNAME}' does not exist. Create the account first. Aborting..."
            fi

            # Check PHP runtime version is exists.
            if [[ -n $(command -v "php${PHP_VERSION}") && -d "/etc/php/${PHP_VERSION}/fpm" ]]; then
                # Request context consumed by lemper_site_setup_skeleton.
                # shellcheck disable=SC2034
                PHP_BIN=$(command -v "php${PHP_VERSION}")
                # shellcheck disable=SC2034
                PHP_COMPOSER_BIN=$(command -v "composer")

                # Additional check - if FPM user's pool doesn't exist.
                if [[ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]]; then
                    info "PHP ${PHP_VERSION} FPM pool configuration for user '${USERNAME}' does not exist."
                    echo "Creating new PHP ${PHP_VERSION} FPM pool configuration for '${USERNAME}'..."

                    # Create PHP FPM pool conf.
                    create_fpm_pool_conf "${USERNAME}" "${PHP_VERSION}" >"/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf"

                    # Create default directories & log files.
                    create_php_temp_dirs "${USERNAME}" \
                        && run runuser -u "$USERNAME" -- mkdir -p -- "/home/$USERNAME/cgi-bin" "/home/$USERNAME/logs/php" \
                        && run runuser -u "$USERNAME" -- touch -- "/home/$USERNAME/logs/php/php$PHP_VERSION-fpm_slow.log" \
                            "/home/$USERNAME/logs/php/php$PHP_VERSION-fpm_error.log" "/home/$USERNAME/logs/php/php$PHP_VERSION-opcache_error.log" \
                        && run runuser -u "$USERNAME" -- chmod 0755 -- "/home/$USERNAME" || return 1

                    # Restart PHP FPM.
                    echo "Restarting php${PHP_VERSION}-fpm configuration..."
                    run systemctl restart "php${PHP_VERSION}-fpm"
                    success "PHP ${PHP_VERSION} FPM pool '[${USERNAME}]' has been created."
                fi
            else
                fail "PHP ${PHP_VERSION} is not installed. Install it before proceeding. Aborting..."
            fi

            # Check web root parameter.
            if [[ -z "${WEBROOT}" ]]; then
                WEBROOT="/home/${USERNAME}/webapps/${SERVERNAME}"
                info "Web root path parameter is empty. Using default path: '${WEBROOT}'."
            fi

            WEBROOT=$(realpath -ms -- "$WEBROOT") || return 1
            lemper_load_module services/accounts/permissions || return 1
            lemper_site_prepare_directory "$WEBROOT" "$USERNAME" 0755 || {
                error "The site directory must be owned by its runtime account."
                return 1
            }

            # Set default application credential data.
            APP_UID="$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"
            APP_DB_USER="${USERNAME}_${APP_UID}"
            APP_DB_PASS="$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
            APP_DB_NAME="app_${APP_UID}"
            APP_ADMIN_USER="admin"
            APP_ADMIN_PASS="$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
            [[ -z "${APP_ADMIN_EMAIL}" ]] && APP_ADMIN_EMAIL=${LEMPER_ADMIN_EMAIL:-"admin@${SERVERNAME}"}

            # Check framework parameter.
            if [[ -z "${FRAMEWORK}" ]]; then
                FRAMEWORK="default"
                info "Framework parameter is empty. Using default: '${FRAMEWORK}'."
            fi

            echo "Configuring '${FRAMEWORK^}' framework..."

            local requested_type="$FRAMEWORK" project_root="$WEBROOT"
            # Existing renderers/installers remain behind this legacy boundary.
            lemper_site_setup_skeleton || return 1

            if [[ "$INSTALL_APP" == true && "$DRYRUN" != true ]]; then
                lemper_site_application_check_files "$requested_type" "$project_root" || return 1
            fi

            if [[ ${DRYRUN} != true ]]; then
                # Enable ModSecurity automatically when installed.
                if [[ "${INSTALL_MODSEC}" == true ]] && [[ -f /etc/nginx/includes/modsec.conf ]]; then
                    sed_inplace "/^[[:space:]]*server_name[[:space:]]/a\\    include /etc/nginx/includes/modsec.conf;" "${VHOST_FILE}"
                    info "ModSecurity enabled for ${SERVERNAME}."
                fi

                # Confirm virtual host.
                if grep -qwE "server_name ${SERVERNAME}" "${VHOST_FILE}"; then
                    success "New domain ${SERVERNAME} successfuly added to virtual host."
                fi

                # Creates Well-Known URIs: RFC 8615.
                echo "Creating .well-known directory (RFC8615)..."

                if [[ -d "${WEBROOT}/public" ]]; then
                    run runuser -u "$USERNAME" -- mkdir -p -- "${WEBROOT}/public/.well-known/acme-challenge" || return 1
                else
                    run runuser -u "$USERNAME" -- mkdir -p -- "${WEBROOT}/.well-known/acme-challenge" || return 1
                fi

                # Assign IPv4 to server vhost.
                if [[ $(validate_ipv4 "${IPv4}") == true ]]; then
                    echo "Assigning IPv4 ${IPv4} to ${SERVERNAME}..."

                    if grep -qwE "listen\ 80" "${VHOST_FILE}"; then
                        sed_inplace "s/^\    listen\ 80/\    listen ${IPv4}:80/g" "${VHOST_FILE}"

                        # Add local domain (e.g. example.test) to hosts file.
                        add_local_domain "${IPv4}" "${SERVERNAME}"
                    fi
                fi

                # Assign IPv6 to server vhost.
                if [[ $(validate_ipv6 "${IPv6}") == true ]]; then
                    echo "Assigning IPv6 ${IPv6} to ${SERVERNAME}..."

                    if grep -qwE "listen\ \[::\]:80" "${VHOST_FILE}"; then
                        sed_inplace "s/^\    listen\ \[::\]:80/\    listen [${IPv6}]:80/g" "${VHOST_FILE}"

                        # Add local domain (e.g. example.test) to hosts file.
                        add_local_domain "${IPv6}" "${SERVERNAME}"
                    fi
                fi

                # Enable Wildcard domain.
                if [[ ${ENABLE_WILDCARD_DOMAIN} == true ]]; then
                    echo "Enable wildcard domain for ${SERVERNAME}..."

                    if grep -qwE "server_name\ ${SERVERNAME};$" "${VHOST_FILE}"; then
                        sed_inplace "s/server_name\ ${SERVERNAME};/server_name\ ${SERVERNAME}\ \*.${SERVERNAME};/g" "${VHOST_FILE}"
                    fi
                fi

                # Enable FastCGI cache.
                if [[ ${ENABLE_FASTCGI_CACHE} == true ]]; then
                    echo "Enable FastCGI cache for ${SERVERNAME}..."

                    if [[ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]]; then
                        # enable cached directives
                        sed_inplace "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" "${VHOST_FILE}"
                        # enable fastcgi_cache conf
                        sed_inplace "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" "${VHOST_FILE}"
                    else
                        info "FastCGI cache is not enabled due to no cached version of ${FRAMEWORK^} directive."
                    fi
                fi

                # Fix document root permission.
                if lemper_site_application_uses_release "$requested_type" || [[ "$requested_type" == xenforo ]]; then
                    lemper_load_module services/site/releases || return 1
                    lemper_site_release_permissions "$requested_type" "$project_root" "$USERNAME" || return 1
                else
                    fixpermission "$WEBROOT" "$USERNAME" || return 1
                fi
            else
                info "New domain ${SERVERNAME} added in dry run mode."
            fi

            echo "Enable the ${SERVERNAME} virtual host."

            lemper_site_activate_vhost "$VHOST_FILE" "$available" "$enabled" || return 1
            echo "Nginx server reloaded with the new configuration."

            if [[ -f "$enabled" ]]; then
                success "Your ${SERVERNAME} was successfully added to the Nginx virtual host."

                if [[ "${ENABLE_FAIL2BAN}" == true && "${DRYRUN}" != true ]]; then
                    if ! lemper_load_module services/nginx/protection || ! lemper_nginx_fail2ban_enable "$SERVERNAME" "$FRAMEWORK" 30d; then
                        warning "Site created without the requested Fail2ban jail. Retry with lemperctl site update --enable-fail2ban $SERVERNAME."
                    fi
                fi

                # Enable HTTPS.
                APP_HTTP_PROTO="http"

                if [[ ${ENABLE_SSL} == true ]]; then
                    echo "Enabling HTTPS protocol using Let's Encrypt SSL for ${SERVERNAME}..."
                    #echo "You can enable HTTPS from lemper-cli after this setup!"
                    #echo "command: lemper-cli site mod --enable-ssl ${SERVERNAME}"
                    run lemper-cli site mod --enable-ssl "${SERVERNAME}" \
                        && APP_HTTP_PROTO="https"
                fi

                # WordPress MS notice.
                if [[ "${FRAMEWORK}" == "wordpress-ms" ]]; then
                    info "For legacy WordPress Multisite media routing, maintain the root-owned map in /etc/nginx/wpms/${SERVERNAME}/."
                fi

                # Save app installation details.
                if [[ ${INSTALL_APP} == true ]]; then
                    if lemper_site_application_uses_release "$requested_type"; then
                        info "Deployment metadata is saved in /etc/lemper/vhost.d/${SERVERNAME}.conf (root-only); finish upstream setup."
                    else
                        info "Application credentials are saved in /etc/lemper/vhost.d/${SERVERNAME}.conf (root-only)."
                    fi
                    echo -e "Site Address: ${APP_HTTP_PROTO}://${SERVERNAME}"
                    (
                        umask 077
                        cat >"/etc/lemper/vhost.d/${SERVERNAME}.conf" <<EOL
[${SERVERNAME}]
APP_UID="${APP_UID}"
APP_FRAMEWORK="${FRAMEWORK}"
APP_DB_USER="${APP_DB_USER}"
APP_DB_PASS="${APP_DB_PASS}"
APP_DB_NAME="${APP_DB_NAME}"
APP_ADMIN_USER="${APP_ADMIN_USER}"
APP_ADMIN_PASS="${APP_ADMIN_PASS}"
APP_ADMIN_EMAIL="${APP_ADMIN_EMAIL}"
APP_WEBROOT="${WEBROOT}"
EOL
                    )
                    run chmod 0600 "/etc/lemper/vhost.d/${SERVERNAME}.conf"
                fi
            else
                if [[ ${DRYRUN} == true ]]; then
                    info "Your ${SERVERNAME} was successfully added in dry run mode."
                else
                    fail "An error occurred while adding ${SERVERNAME} to the Nginx virtual host."
                fi
            fi
        else
            error "A configuration or selection already exists for $SERVERNAME."
            return 1
        fi
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
    fi
)
