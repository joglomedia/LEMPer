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

##
# Output index.html skeleton for default index page
# To be outputted into new index.html file in document root.
#
function create_index_file() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<-EOL
<!DOCTYPE html>
<html lang="en">
<head>
<!--
Served by
 _     _____ __  __ ____
| |   | ____|  \/  |  _ \ ___ _ __
| |   |  _| | |\/| | |_) / _ \ '__|
| |___| |___| |  | |  __/  __/ |
|_____|_____|_|  |_|_|   \___|_|
-->
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Welcome to ${SERVERNAME}!</title>
<link href="https://fonts.googleapis.com/css?family=Cabin:400,700" rel="stylesheet">
<link href="https://fonts.googleapis.com/css?family=Montserrat:900" rel="stylesheet">
<style>
/**
 * Forked from Colorlib https://colorlib.com/etc/404/colorlib-error-404-3/
*/
*{-webkit-box-sizing:border-box;box-sizing:border-box}body{padding:0;margin:0}#errorpg{position:relative;height:100vh}#errorpg .errorpg{position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%)}.errorpg{max-width:520px;width:100%;line-height:1.4;/*text-align:center*/}.errorpg .errorpg-msg{position:relative;height:240px}.errorpg .errorpg-msg h1{font-family:Montserrat,sans-serif;position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%);font-size:252px;font-weight:900;margin:0;color:#262626;text-transform:uppercase;letter-spacing:-40px;margin-left:-20px}.errorpg .errorpg-msg h1>span{text-shadow:-8px 0 0 #fff}.errorpg .errorpg-msg h3{font-family:Cabin,sans-serif;position:relative;font-size:16px;font-weight:700;text-transform:uppercase;color:#262626;margin:0;letter-spacing:3px;padding-left:6px}.errorpg h2{font-family:Cabin,sans-serif;font-size:20px;font-weight:400;text-transform:uppercase;color:#000;margin-top:0;margin-bottom:25px}@media only screen and (max-width:767px){.errorpg .errorpg-msg{height:200px}.errorpg .errorpg-msg h1{font-size:200px}}@media only screen and (max-width:480px){.errorpg .errorpg-msg{height:162px}.errorpg .errorpg-msg h1{font-size:162px;height:150px;line-height:162px}.errorpg h2{font-size:16px}}
div.banner{color:#009639;font-family:Montserrat,sans-serif;position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%);font-size:180px;font-weight:900;margin:0;letter-spacing:-25px;margin-left:-10px}
</style>
<!--[if lt IE 9]>
<script src="https://oss.maxcdn.com/html5shiv/3.7.3/html5shiv.min.js"></script>
<script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
<![endif]-->
</head>
<body>
<div id="errorpg">
<div class="errorpg">
<div class="errorpg-msg">
<h3>Honest_Coder presents...</h3>
<div class="banner">
<span>L</span><span>E</span><span>M</span><span>P</span><span>er</span></div>
</div>
<h2>This is the default index page of your website.</h2>
<p>This file may be deleted or overwritten without any difficulty. This is produced by the file index.html in the web directory.</p>
<p>To disable this page, please remove the index.html file and replace it with your own. Our handy <a href="https://github.com/joglomedia/LEMPer/wiki">Quick Start Guide</a> can help you get up and running fast.</p>
<p>For questions or problems, please contact our support team.</p>
</div>
</div>
<script src="https://ajax.cloudflare.com/cdn-cgi/scripts/95c75768/cloudflare-static/rocket-loader.min.js" data-cf-settings="d841170f43ff1e03f58512ad-|49" defer=""></script>
</body>
</html>
EOL
    else
        info "index file created in dry run mode, no data written."
    fi
}

##
# Create new Database for application.
#
function create_app_db() {
    echo "Creating application database (SQL)..."

    APP_UID="$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"
    APP_DB_USER=${1:-"db_${APP_UID}"}
    APP_DB_PASS=${2:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}
    APP_DB_NAME=${3:-"app_${APP_UID}"}

    LEMPER_DB_PASSWORD="${APP_DB_PASS}" run lemper-cli db account create --dbuser="${APP_DB_USER}" \
        && run lemper-cli db create --dbname="${APP_DB_NAME}" --dbuser="${APP_DB_USER}"
}

##
# Install WordPress
# Installing WordPress skeleton.
#
function install_wordpress() {
    # Clone new WordPress skeleton files
    if [[ "${INSTALL_APP}" == true ]]; then
        # Check WordPress install directory.
        if [ ! -f "${WEBROOT}/wp-includes/class-wp.php" ]; then
            if [[ -z $(command -v "wp-cli") ]]; then
                info "WP CLI command not found, trying to install it first."
                run curl -sSL -o /usr/local/bin/wp-cli https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
                    && run chmod 0755 /usr/local/bin/wp-cli \
                    && run ln -sf /usr/local/bin/wp-cli /usr/bin/wp-cli
            fi

            # Download WordPress skeleton files.
            run sudo -u "${USERNAME}" -i -- wp-cli core download --path="${WEBROOT}"

            # create_app_db [app_db_username] [app_db_password] [app_db_name]
            create_app_db "${APP_DB_USER}" "${APP_DB_PASS}" "${APP_DB_NAME}"

            # wp-cli only accepts the password as an argument, so write a
            # placeholder and substitute it in the generated file to keep the
            # secret out of the process list. --skip-check avoids validating
            # the placeholder against the database.
            run sudo -u "${USERNAME}" -i -- wp-cli config create --dbname="${APP_DB_NAME}" \
                --dbuser="${APP_DB_USER}" --dbpass="__LEMPER_DB_PASS__" --dbprefix=ls_ \
                --skip-check --path="${WEBROOT}"

            if [[ "${DRYRUN}" != true && -f "${WEBROOT}/wp-config.php" ]]; then
                sed_inplace "s|__LEMPER_DB_PASS__|$(sanitize_sed_replacement "${APP_DB_PASS}")|g" "${WEBROOT}/wp-config.php"
                run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/wp-config.php"
                run chmod 640 "${WEBROOT}/wp-config.php"
            fi
        else
            info "It seems that WordPress files already exists."
        fi
    else
        # Create default index file.
        echo "Creating default WordPress index file..."

        if [ ! -e "${WEBROOT}/index.html" ]; then
            create_index_file >"${WEBROOT}/index.html"
        fi
    fi

    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"
}

# Framework setup and rendering share the validated site request context.
function lemper_site_setup_skeleton() {
    case "${FRAMEWORK}" in
        codeigniter)
            echo "Setting up CodeIgniter framework virtual host..."

            # Clone CodeIgniter skeleton files.
            if [[ ${INSTALL_APP} == true ]]; then
                # Checking CodeIgniter installation.
                if [[ ! -f "${WEBROOT}/spark" ]]; then
                    echo "Downloading CodeIgniter v4 skeleton files..."

                    if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                        run sudo -u "${USERNAME}" -i -- "${PHP_BIN}" "${PHP_COMPOSER_BIN}" \
                            create-project --prefer-dist --no-dev codeigniter4/appstarter "${WEBROOT}"
                    else
                        run git clone --depth=1 --branch=master "https://github.com/codeigniter4/appstarter.git" "${WEBROOT}" \
                            || error "Something went wrong while downloading CodeIgniter v4 files."
                    fi
                else
                    info "It seems that CodeIgniter v4 skeleton files already exists."
                fi
            else
                # Create default index file.
                if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                    echo "Creating default index file..."
                    run mkdir -p "${WEBROOT}/public"
                    create_index_file >"${WEBROOT}/public/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_laravel >"${VHOST_FILE}"
            ;;

        drupal)
            echo "Setting up Drupal virtual host..."

            # Clone Drupal skeleton files.
            if [[ ${INSTALL_APP} == true ]]; then
                # Checking Drupal installation.
                if [[ ! -d "${WEBROOT}/core/lib/Drupal" ]]; then
                    echo "Downloading Drupal latest skeleton files..."

                    if curl -sLI https://www.drupal.org/download-latest/zip | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sSL -o "${TMPDIR}/drupal.zip" https://www.drupal.org/download-latest/zip \
                            && run unzip -q "${TMPDIR}/drupal.zip" -d "${TMPDIR}" \
                            && run rsync -rq "${TMPDIR}"/drupal-*/ "${WEBROOT}" \
                            && run rm -f "${TMPDIR}/drupal.zip" \
                            && run rm -fr "${TMPDIR}"/drupal-*/
                    else
                        error "Something went wrong while downloading Drupal files."
                    fi
                else
                    info "It seems that Drupal files already exists."
                fi
            else
                # Create default index file.
                if [[ ! -e "${WEBROOT}/index.php" ]]; then
                    echo "Creating default index file..."
                    create_index_file >"${WEBROOT}/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_drupal >"${VHOST_FILE}"
            ;;

        laravel | lumen)
            echo "Setting up ${FRAMEWORK^} framework virtual host..."

            # Clone Laravel/Lumen skeleton files.
            if [[ ${INSTALL_APP} == true ]]; then
                # Checking Laravel installation.
                if [[ ! -f "${WEBROOT}/artisan" ]]; then
                    echo "Downloading ${FRAMEWORK^} skeleton files..."

                    if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                        run sudo -u "${USERNAME}" -i -- "${PHP_BIN}" "${PHP_COMPOSER_BIN}" \
                            create-project --prefer-dist "laravel/${FRAMEWORK}" "${WEBROOT}"
                    else
                        run git clone --depth=1 --branch=master "https://github.com/laravel/${FRAMEWORK}.git" "${WEBROOT}" \
                            || error "Something went wrong while downloading ${FRAMEWORK^} files."
                    fi

                    # create_app_db [app_db_username] [app_db_password] [app_db_name]
                    create_app_db "${APP_DB_USER}" "${APP_DB_PASS}" "${APP_DB_NAME}"
                else
                    info "It seems that ${FRAMEWORK^} skeleton files already exists."
                fi
            else
                # Create default index file.
                if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                    echo "Creating default index file..."
                    run mkdir -p "${WEBROOT}/public"
                    create_index_file >"${WEBROOT}/public/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Return Lumen framework as Laravel for vhost creation.
            [[ "${FRAMEWORK}" == "lumen" ]] && FRAMEWORK="laravel"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_laravel >"${VHOST_FILE}"
            ;;

        phalcon | phalcon-cli | phalcon-micro | phalcon-modules)
            echo "Setting up Phalcon framework virtual host..."

            # Clone Phalcon skeleton files.
            if [[ ${INSTALL_APP} == true ]]; then
                # Checking Phalcon installation.
                if [[ ! -f "${WEBROOT}/app/config/config.php" ]]; then
                    echo "Downloading ${FRAMEWORK} skeleton files..."

                    # Switch Phalcon framework type.
                    case "${FRAMEWORK}" in
                        phalcon-cli)
                            PHALCON_TYPE="cli"
                            ;;
                        phalcon-micro)
                            PHALCON_TYPE="micro"
                            ;;
                        phalcon-modules)
                            PHALCON_TYPE="modules"
                            ;;
                        *)
                            PHALCON_TYPE="simple"
                            ;;
                    esac

                    if [[ -n $(command -v phalcon) ]]; then
                        PHP_PHALCON_BIN=$(command -v phalcon)
                        run sudo -u "${USERNAME}" -i -- "${PHP_PHALCON_BIN}" project \
                            --name="${SERVERNAME}" --type="${PHALCON_TYPE}" --directory="/home/${USERNAME}/webapps"
                    else
                        run git clone --depth=1 --branch=master "https://github.com/joglomedia/${FRAMEWORK}-skeleton.git" "${WEBROOT}" \
                            || error "Something went wrong while downloading ${FRAMEWORK} files."
                    fi
                else
                    info "It seems that ${FRAMEWORK} skeleton files already exists."
                fi
            else
                # Create default index file.
                if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                    echo "Creating default index file..."
                    run mkdir -p "${WEBROOT}/public"
                    create_index_file >"${WEBROOT}/public/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Return Micro framework as Phalcon for vhost creation.
            [[ "${FRAMEWORK}" == "phalcon-cli" || "${FRAMEWORK}" == "phalcon-micro" || "${FRAMEWORK}" == "phalcon-modules" ]] \
                && FRAMEWORK="phalcon"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_phalcon >"${VHOST_FILE}"
            ;;

        symfony)
            echo "Setting up Symfony framework virtual host..."

            # Clone Symfony skeleton files.
            if [[ ${INSTALL_APP} == true ]]; then
                # Checking Symfony installation.
                if [ ! -f "${WEBROOT}/src/Kernel.php" ]; then
                    echo "Downloading Symfony skeleton files..."

                    if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                        run composer create-project --prefer-dist symfony/website-skeleton "${WEBROOT}"
                    else
                        warning "Symfony CLI not found, trying to install it first..."
                        run bash -c "curl -sSL https://get.symfony.com/cli/installer -o - | bash"

                        if [[ -f "${HOME}/.symfony/bin/symfony" ]]; then
                            run cp -f "${HOME}/.symfony/bin/symfony" /usr/local/bin/symfony
                            run chmod ugo+x /usr/local/bin/symfony
                        else
                            run export PATH="${HOME}/.symfony/bin:${PATH}"
                        fi

                        run sudo -u "${USERNAME}" -i -- symfony new "${WEBROOT}" --full
                    fi
                else
                    info "It seems that Symfony skeleton files already exists."
                fi
            else
                # Create default index file.
                if [[ ! -e "${WEBROOT}/index.php" ]]; then
                    echo "Creating default index file..."
                    create_index_file >"${WEBROOT}/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_default >"${VHOST_FILE}"
            ;;

        wordpress | woocommerce)
            echo "Setting up WordPress virtual host..."

            # Install WordPress skeleton.
            install_wordpress

            APP_ADMIN_USER="wpadmin"

            if [[ "$INSTALL_APP" == true ]] && command -v wp-cli &>/dev/null; then
                printf '%s\n' "${APP_ADMIN_PASS}" | run sudo -u "${USERNAME}" -i -- wp-cli core install --url="${SERVERNAME}" \
                    --title="WordPress Managed by LEMPer Stack" \
                    --admin_user="${APP_ADMIN_USER}" --prompt=admin_password \
                    --admin_email="${APP_ADMIN_EMAIL}" --path="${WEBROOT}" \
                    && run sudo -u "${USERNAME}" -i -- wp-cli plugin install \
                        akismet autoptimize nginx-helper redis-cache --activate --path="${WEBROOT}"
            fi

            # Install WooCommerce.
            if [[ "$INSTALL_APP" == true && "${FRAMEWORK}" == "woocommerce" ]]; then
                if [[ -d "${WEBROOT}/wp-content/plugins" &&
                    ! -d "${WEBROOT}/wp-content/plugins/woocommerce" ]]; then
                    echo "Add WooCommerce plugin into WordPress skeleton..."

                    if [[ "$INSTALL_APP" == true ]] && command -v wp-cli &>/dev/null; then
                        run sudo -u "${USERNAME}" -i -- wp-cli plugin install woocommerce --activate --path="${WEBROOT}"
                        run sudo -u "${USERNAME}" -i -- wp-cli theme install storefront --activate --path="${WEBROOT}"
                    else
                        if curl -sSL -o "${TMPDIR}/woocommerce.zip" \
                            https://downloads.wordpress.org/plugin/woocommerce.zip; then
                            run unzip -q "${TMPDIR}/woocommerce.zip" -d "${WEBROOT}/wp-content/plugins/"
                            run rm -f "${TMPDIR}/woocommerce.zip"
                        else
                            error "Something went wrong while downloading WooCommerce files."
                        fi
                    fi
                fi
            fi

            # Return WooCommerce as WordPress for vhost creation.
            [[ "${FRAMEWORK}" == "woocommerce" ]] && FRAMEWORK="wordpress"

            # Create vhost.
            echo "Create virtual host file: ${VHOST_FILE}"
            create_vhost_default >"${VHOST_FILE}"
            ;;

        wordpress-ms)
            echo "Setting up WordPress Multi-site virtual host..."

            # Install WordPress.
            install_wordpress

            APP_ADMIN_USER="wpadmin"

            if [[ "$INSTALL_APP" == true ]] && command -v wp-cli &>/dev/null; then
                printf '%s\n' "${APP_ADMIN_PASS}" | run sudo -u "${USERNAME}" -i -- wp-cli core multisite-install "${WPMS_SUBDOMAINS}" --url="${SERVERNAME}" \
                    --title="WordPress Multisite Managed by LEMPer Stack" --admin_user="${APP_ADMIN_USER}" \
                    --prompt=admin_password --admin_email="${APP_ADMIN_EMAIL}" --path="${WEBROOT}" \
                    && run sudo -u "${USERNAME}" -i -- wp-cli plugin install \
                        akismet autoptimize nginx-helper redis-cache --activate-network --path="${WEBROOT}"
            fi

            if [[ "$INSTALL_APP" == true ]]; then
                # Mercator domain mapping.
                run git clone --depth=1 --branch=master https://github.com/humanmade/Mercator.git "${WEBROOT}/wp-content/mu-plugins/mercator" \
                    && cat >"${WEBROOT}/wp-content/sunrise.php" <<EOL
<?php
// Default mu-plugins directory if you haven't set it
defined( 'WPMU_PLUGIN_DIR' ) or define( 'WPMU_PLUGIN_DIR', WP_CONTENT_DIR . '/mu-plugins' );

require WPMU_PLUGIN_DIR . '/mercator/mercator.php';
EOL

                # Enable sunrise. (insert new line before match)
                sed_inplace "/\/*\ That/i define( 'SUNRISE', true );\n" "${WEBROOT}/wp-config.php"

            fi

            # Pre-populate blog id mapping, used by Nginx vhost config.
            if [[ ! -d "${WEBROOT}/wp-content/uploads/nginx-helper" ]]; then
                run mkdir -p "${WEBROOT}/wp-content/uploads/nginx-helper"
            fi

            if [[ ! -f "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf" ]]; then
                run touch "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf"
            fi

            echo "Creating virtual host file: ${VHOST_FILE}..."

            # Prepare vhost specific rule for WordPress Multisite.
            prepare_vhost_wpms >"${VHOST_FILE}"

            # Create vhost.
            create_vhost_default >>"${VHOST_FILE}"

            # Enable wildcard host.
            if grep -qwE "server_name\ ${SERVERNAME};$" "${VHOST_FILE}"; then
                sed_inplace "s/server_name\ ${SERVERNAME};/server_name\ ${SERVERNAME}\ \*.${SERVERNAME};/g" \
                    "${VHOST_FILE}"
            fi
            ;;

        owncloud)
            echo "Setting up OwnCloud virtual host..."

            # Install OwnCloud skeleton.
            if [[ ${INSTALL_APP} == true ]]; then
                # Clone new OwnCloud files.
                if [[ ! -f "${WEBROOT}/occ" ]]; then
                    echo "Downloading OwnCloud skeleton files..."

                    OWNCLOUD_DOWNLOAD_URL="https://download.owncloud.com/server/stable/owncloud-complete-latest.zip"

                    if curl -sLI "${OWNCLOUD_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sSL -o "${TMPDIR}/owncloud.zip" "${OWNCLOUD_DOWNLOAD_URL}" \
                            && run unzip -q "${TMPDIR}/owncloud.zip" -d "${WEBROOT}"
                        run rm -f "${TMPDIR}/owncloud.zip"
                    else
                        error "Something went wrong while downloading OwnCloud files."
                    fi
                else
                    info "OwnCloud skeleton files already exists."
                fi
            else
                # Create default index file.
                echo "Creating default index files..."

                if [[ ! -e "${WEBROOT}/index.html" ]]; then
                    create_index_file >"${WEBROOT}/index.html"
                fi
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Create vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_default >"${VHOST_FILE}"
            ;;

        mautic | roundcube | snappymail | nextcloud | mybb | phplist | ojs | slim | xenforo)
            if [[ "$INSTALL_APP" == true ]]; then
                lemper_load_module services/site/releases || return 1
                lemper_site_release_install "$FRAMEWORK" "$WEBROOT" "$USERNAME" "$PHP_VERSION" "$SERVERNAME" || return 1
                lemper_load_module services/nginx/release-site || return 1
                lemper_site_release_render "$FRAMEWORK" "$SERVERNAME" "$WEBROOT" "$USERNAME" "$PHP_VERSION" >"$VHOST_FILE" || return 1
                # This is a complete-file deployment; upstream setup chooses
                # database/admin/mail settings. Do not record fictional DB ownership.
                APP_DB_USER="" APP_DB_PASS="" APP_DB_NAME=""
                APP_ADMIN_USER="" APP_ADMIN_PASS=""
            else
                [[ -e "$WEBROOT/index.html" ]] || create_index_file >"$WEBROOT/index.html"
                run chown -hR "$USERNAME:$USERNAME" "$WEBROOT"
                if [[ "$FRAMEWORK" == mautic || "$FRAMEWORK" == roundcube ]]; then
                    create_vhost_default >"$VHOST_FILE"
                else
                    lemper_load_module services/site/releases || return 1
                    lemper_load_module services/nginx/release-site || return 1
                    lemper_site_release_render "$FRAMEWORK" "$SERVERNAME" "$WEBROOT" "$USERNAME" "$PHP_VERSION" >"$VHOST_FILE" || return 1
                fi
            fi
            ;;

        default | sendy)
            # Generic PHP vhost; application deployment is managed separately.

            # Create default index file.
            if [[ ! -e "${WEBROOT}/index.html" ]]; then
                create_index_file >"${WEBROOT}/index.html"
            fi

            # Fix ownership.
            run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Create default vhost.
            echo "Creating virtual host file: ${VHOST_FILE}..."
            create_vhost_default >"${VHOST_FILE}"
            ;;

        *)
            # Not supported framework/cms, abort.
            fail "Sorry, your framework/cms '${FRAMEWORK^}' is not supported yet. Please submit an issue at Github..."
            return 1
            ;;
    esac
}
