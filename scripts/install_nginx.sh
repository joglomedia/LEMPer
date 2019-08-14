#!/usr/bin/env bash

# NGiNX Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 04/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Define scripts directory.
if echo "${BASEDIR}" | grep -qwE "scripts"; then
    SCRIPTS_DIR="${BASEDIR}"
else
    SCRIPTS_DIR="${BASEDIR}/scripts"
fi

# Make sure only root can run this installer script.
requires_root

function add_nginx_repo() {
    echo "Adding NGiNX repository..."

    export NGX_PACKAGE

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    DISTRIB_REPO=${DISTRIB_REPO:-$(get_release_name)}

    case "${DISTRIB_REPO}" in
        trusty)
            # NGiNX custom with ngx cache purge from rtCamp.
            # https://rtcamp.com/wordpress-nginx/tutorials/single-site/fastcgi-cache-with-purging/
            run add-apt-repository -y ppa:rtcamp/nginx
            NGX_PACKAGE="nginx-custom"
        ;;

        xenial)
            # NGiNX custom with ngx cache purge from rtCamp.
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3050AC3CD2AE6F03
            run bash -c "echo 'deb http://download.opensuse.org/repositories/home:/rtCamp:/EasyEngine/xUbuntu_16.04/ /' \
                >> /etc/apt/sources.list.d/nginx-xenial.list"
            NGX_PACKAGE="nginx-custom"
        ;;

        bionic)
            # NGiNX official repo.
            run apt-key fingerprint ABF5BD827BD9BF62
            run add-apt-repository -y ppa:nginx/stable
            NGX_PACKAGE="nginx-stable"
        ;;

        *)
            NGX_PACKAGE=""

            echo ""
            error "Unsupported distribution release: ${DISTRIB_REPO}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

function init_nginx_install() {
    if "${AUTO_INSTALL}"; then
        # Set default Iptables-based firewall configutor engine.
        SELECTED_NGINX_INSTALLER=${NGINX_INSTALLER:-"source"}
    else
        # Install NGiNX custom.
        echo "Available NGiNX installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_NGINX_INSTALLER} != "1" && ${SELECTED_NGINX_INSTALLER} != "2" \
            && ${SELECTED_NGINX_INSTALLER} != "repo" && ${SELECTED_NGINX_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${NGINX_INSTALLER}" -e SELECTED_NGINX_INSTALLER
    	done

        echo ""
    fi

    case "${SELECTED_NGINX_INSTALLER}" in
        1|"repo")
            add_nginx_repo

            echo "Installing NGiNX from package repository..."
            if hash dpkg 2>/dev/null; then
                if [[ -n "${NGX_PACKAGE}" ]]; then
                    {
                        run apt-get update
                        run apt-get install -y --allow-unauthenticated "${NGX_PACKAGE}"
                    }
                fi
            elif hash yum 2>/dev/null; then
                if [ "${VERSION_ID}" == "5" ]; then
                    yum -y update
                    #yum -y localinstall "${NGX_PACKAGE}" --nogpgcheck
                else
                    yum -y update
            	    #yum -y localinstall "${NGX_PACKAGE}"
                fi
            else
                fail "Unable to install LEMPer: this GNU/Linux distribution is not dpkg/yum enabled."
            fi
        ;;

        2|"source"|*)
            echo "Installing NGiNX from source..."

            if "${DRYRUN}"; then
                "${SCRIPTS_DIR}/install_nginx_from_source.sh" -v latest-stable \
                    -n stable --dynamic-module --extra-modules -y --dryrun
            else
                "${SCRIPTS_DIR}/install_nginx_from_source.sh" -v latest-stable \
                    -n stable --dynamic-module --extra-modules -y
            fi

            echo ""
            echo "Configuring NGiNX extra modules..."

            # Create NGiNX directories.
            if [ ! -d /etc/nginx/modules-available ]; then
                run mkdir /etc/nginx/modules-available
            fi

            if [ ! -d /etc/nginx/modules-enabled ]; then
                run mkdir /etc/nginx/modules-enabled
            fi

            # Custom NGiNX dynamic modules configuration.
            if [[ -f /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_brotli_filter_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-brotli-filter.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_brotli_static_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-brotli-static.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_brotli_static_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-brotli-static.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_cache_purge_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_cache_purge_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-cache-purge.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_fancyindex_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-fancyindex.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_fancyindex_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-fancyindex.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_geoip_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_geoip_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-geoip.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-headers-more-filter.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-headers-more-filter.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_image_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_image_filter_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-image-filter.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_naxsi_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-naxsi.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_naxsi_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-naxsi.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_vhost_traffic_status_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-vts.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_vhost_traffic_status_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-vts.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_xslt_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-xslt-filter.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_xslt_filter_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-xslt-filter.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_mail_module.so && \
                ! -f /etc/nginx/modules-available/mod-mail.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_mail_module.so\";' \
                    > /etc/nginx/modules-available/mod-mail.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_pagespeed.so && \
                ! -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_pagespeed.so\";' \
                    > /etc/nginx/modules-available/mod-pagespeed.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && \
                ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";' \
                    > /etc/nginx/modules-available/mod-stream.conf"
            fi

            # Enable NGiNX Dynamic Module.
            if "${NGINX_DYNAMIC_MODULE}"; then
                ENABLE_NGXDM=y
            else
                echo ""
                while [[ "${ENABLE_NGXDM}" != "y" && "${ENABLE_NGXDM}" != "n" ]]; do
                    read -rp "Enable NGiNX dynamic modules? [y/n]: " -i y -e ENABLE_NGXDM
                done
            fi

            if [[ "${ENABLE_NGXDM}" == Y* || "${ENABLE_NGXDM}" == y* ]]; then

                if [[ "${NGX_BROTLI}" && \
                    -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-brotli-filter.conf \
                        /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf
                fi

                if [[ "${NGX_BROTLI}" && \
                    -f /etc/nginx/modules-available/mod-http-brotli-static.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-brotli-static.conf \
                        /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf
                fi

                if [[ "${NGX_CACHE_PURGE}" && \
                    -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-cache-purge.conf \
                        /etc/nginx/modules-enabled/50-mod-http-cache-purge.conf
                fi

                if [[ "${NGX_FANCYINDEX}" && \
                    -f /etc/nginx/modules-available/mod-http-fancyindex.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-fancyindex.conf \
                        /etc/nginx/modules-enabled/50-mod-http-fancyindex.conf
                fi

                if [[ "${NGX_HTTP_GEOIP2}" && \
                    -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                    run ln -s /etc/nginx/modules-available/mod-http-geoip.conf \
                        /etc/nginx/modules-enabled/50-mod-http-geoip.conf
                fi

                if [[ "${NGX_PAGESPEED}" && \
                    -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-pagespeed.conf \
                        /etc/nginx/modules-enabled/50-mod-pagespeed.conf
                fi

            fi

            # NGiNX init script.
            if [ ! -f /etc/init.d/nginx ]; then
                run cp etc/init.d/nginx /etc/init.d/
                run chmod ugo+x /etc/init.d/nginx
            fi

            # NGiNX systemd script.
            if [ ! -f /lib/systemd/system/nginx.service ]; then
                run cp etc/systemd/nginx.service /lib/systemd/system/
            fi

            if [ ! -f /etc/systemd/system/nginx.service ]; then
                run ln -s /lib/systemd/system/nginx.service \
                    /etc/systemd/system/multi-user.target.wants/nginx.service
            fi

            # Try reloading daemon.
            run systemctl daemon-reload

            # Enable in start up.
            run systemctl enable nginx.service
        ;;
    esac

    echo -e "\nCreating NGiNX configuration..."

    if [ ! -d /etc/nginx/sites-available ]; then
        run mkdir /etc/nginx/sites-available
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        run mkdir /etc/nginx/sites-enabled
    fi

    # Copy custom NGiNX Config.
    if [ -f /etc/nginx/nginx.conf ]; then
        run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
    fi

    run cp -f etc/nginx/charset /etc/nginx/
    run cp -f etc/nginx/{comp_brotli,comp_gzip} /etc/nginx/
    run cp -f etc/nginx/{fastcgi_cache,fastcgi_https_map,fastcgi_params,proxy_cache,proxy_params} /etc/nginx/
    run cp -f etc/nginx/{http_cloudflare_ips,http_proxy_ips} /etc/nginx/
    run cp -f etc/nginx/nginx.conf /etc/nginx/
    run cp -f etc/nginx/upstream /etc/nginx/
    run cp -fr etc/nginx/{includes,vhost,ssl} /etc/nginx/

    if [ -f /etc/nginx/sites-available/default ]; then
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
    fi

    run cp -f etc/nginx/sites-available/default /etc/nginx/sites-available/

    if [ -f /etc/nginx/sites-enabled/default ]; then
        run unlink /etc/nginx/sites-enabled/default
    fi

    if [ -f /etc/nginx/sites-enabled/01-default ]; then
        run unlink /etc/nginx/sites-enabled/01-default
    fi

    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    if [ -d /usr/share/nginx/html ]; then
        run chown -hR www-data:root /usr/share/nginx/html
    fi

    # NGiNX cache directory.
    if [ ! -d /var/cache/nginx ]; then
        run mkdir /var/cache/nginx
        run chown -hR www-data:root /var/cache/nginx
    fi

    if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
        run mkdir /var/cache/nginx/fastcgi_cache
        run chown -hR www-data:root /var/cache/nginx/fastcgi_cache
    fi

    if [ ! -d /var/cache/nginx/proxy_cache ]; then
        run mkdir /var/cache/nginx/proxy_cache
        run chown -hR www-data:root /var/cache/nginx/proxy_cache
    fi

    # Adjust nginx to meet hardware resources.
    echo -e "\nAdjusting NGiNX configuration..."

    local CPU_CORES && \
    CPU_CORES=$(grep -c processor /proc/cpuinfo)

    run sed -i "s/worker_processes\ auto/worker_processes\ ${CPU_CORES}/g" /etc/nginx/nginx.conf

    local NGX_CONNECTIONS
    case ${CPU_CORES} in
        1)
            NGX_CONNECTIONS=4096
        ;;
        2|3)
            NGX_CONNECTIONS=2048
        ;;
        *)
            NGX_CONNECTIONS=1024
        ;;
    esac

    run sed -i "s/worker_connections\ 4096/worker_connections\ ${NGX_CONNECTIONS}/g" /etc/nginx/nginx.conf


    # Final test.
    echo ""
    if "${DRYRUN}"; then
        IP_SERVER="127.0.0.1"
        warning "NGiNX HTTP server installed in dryrun mode."
    else
        IP_SERVER=${IP_SERVER:-$(get_ip_addr)}

        # Make default server accessible from IP address.
        run sed -i "s/localhost.localdomain/${IP_SERVER}/g" /etc/nginx/sites-available/default

        # Restart NGiNX server
        echo "Starting NGiNX HTTP server..."
        if [[ $(pgrep -c nginx) -gt 0 ]]; then
            run service nginx reload -s
            status "NGiNX HTTP server restarted successfully."
        elif [[ -n $(command -v nginx) ]]; then
            run service nginx start

            if [[ $(pgrep -c nginx) -gt 0 ]]; then
                status "NgiNX HTTP server started successfully."
            else
                warning "Something wrong with NGiNX installation."
            fi
        fi
    fi
}

echo "[Welcome to NGiNX Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available ]]; then
    warning "Nginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
