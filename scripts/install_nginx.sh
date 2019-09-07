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
            NGX_PACKAGE="nginx-stable nginx-extras"
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
                    run apt-get -qq update
                    run apt-get -qq install -y --allow-unauthenticated "${NGX_PACKAGE}"
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
                run "${SCRIPTS_DIR}/install_nginx_from_source.sh" -v latest-stable \
                    -n stable --dynamic-module --extra-modules -y --dryrun
            else
                # Additional configure arguments.
                NGX_CONFIGURE_ARGS=""

                # Custom build name.
                NGX_CONFIGURE_ARGS="--build=LEMPer ${NGX_CONFIGURE_ARGS}"

                if "${NGINX_EXTRA_MODULES}"; then
                    echo "Build NGiNX with extra modules..."

                    local extra_module_dir="${BUILD_DIR}/nginx_modules"

                    if [ ! -d "$extra_module_dir" ]; then
                        run mkdir -p "$extra_module_dir"
                    else
                        delete_if_already_exists "$extra_module_dir"
                        run mkdir -p "$extra_module_dir"
                    fi

                    local CURRENT_DIR && \
                    CURRENT_DIR=$(pwd)
                    run cd "$extra_module_dir"

                    # Custom OpenSSL.
                    if [[ -n "${NGINX_CUSTOMSSL_VERSION}" ]]; then
                        echo "Downloading custom SSL version ${NGINX_CUSTOMSSL_VERSION}..."

                        if grep -q openssl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                            if wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" \
                                "https://www.openssl.org/source/${NGINX_CUSTOMSSL_VERSION}.tar.gz"; then
                                run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                                run rm -f "${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                                NGX_CONFIGURE_ARGS="--with-openssl=$extra_module_dir/${NGINX_CUSTOMSSL_VERSION} \
                                    --with-openssl-opt=enable-ec_nistp_64_gcc_128 --with-openssl-opt=no-nextprotoneg \
                                    --with-openssl-opt=no-weak-ssl-ciphers --with-openssl-opt=no-ssl3 ${NGX_CONFIGURE_ARGS}"
                            else
                                warning "Unable to determine Custom SSL source page."
                            fi
                        elif grep -q libressl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                            if wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" \
                                "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${NGINX_CUSTOMSSL_VERSION}.tar.gz"; then
                                run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                                run rm -f "${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                                NGX_CONFIGURE_ARGS="--with-openssl=$extra_module_dir/${NGINX_CUSTOMSSL_VERSION} ${NGX_CONFIGURE_ARGS}"
                            else
                                warning "Unable to determine Custom SSL source page."
                            fi
                        else
                            warning "Unable to determine Custom SSL version."
                            echo "Revert back to use default stack OpenSSL..."
                        fi
                    fi

                    # Brotli compression.
                    if "$NGX_HTTP_BROTLI"; then
                        echo "Downloading ngx_brotli module..."

                        run git clone -q https://github.com/eustas/ngx_brotli.git
                        run cd ngx_brotli || exit 1
                        run git checkout master -q
                        run git submodule update --init -q
                        run cd ../

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/ngx_brotli ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_brotli ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Cache Purge
                    if "$NGX_HTTP_CACHE_PURGE"; then
                        echo "Downloading ngx_cache_purge module..."
                        run git clone -q https://github.com/nginx-modules/ngx_cache_purge.git
                        #run git clone -q https://github.com/joglomedia/ngx_cache_purge.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/ngx_cache_purge ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_cache_purge ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # More Headers
                    if "$NGX_HTTP_HEADERS_MORE"; then
                        echo "Downloading headers-more-nginx-module..."
                        run git clone -q https://github.com/openresty/headers-more-nginx-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/headers-more-nginx-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/headers-more-nginx-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # GeoIP2
                    if "$NGX_HTTP_GEOIP2"; then
                        # install libmaxminddb
                        status "Installing MaxMind GeoIP library..."

                        run git clone -q https://github.com/maxmind/libmaxminddb.git
                        run cd libmaxminddb
                        run ./configure && \
                        make && \
                        make install && \
                        ldconfig && \

                        echo "Downloading MaxMind GeoIP database..."

                        run mkdir geoip-db && \
                        run cd geoip-db || exit 1
                        run wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz && \
                            tar -xf GeoLite2-Country.tar.gz
                        run wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz && \
                            tar -xf GeoLite2-City.tar.gz
                        run mkdir /opt/geoip
                        run cd GeoLite2-City_*/ && \
                        run mv GeoLite2-City.mmdb /opt/geoip/
                        run cd ../
                        run cd GeoLite2-Country_*/ && \
                        run mv GeoLite2-Country.mmdb /opt/geoip/
                        run cd "${BUILD_DIR}"

                        if [[ -f /opt/geoip/GeoLite2-City.mmdb && -f /opt/geoip/GeoLite2-Country.mmdb ]]; then
                            status "MaxMind GeoIP database successfully downloaded."
                        fi

                        echo "Downloading ngx_http_geoip2_module..."
                        run git clone -q https://github.com/leev/ngx_http_geoip2_module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/ngx_http_geoip2_module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_http_geoip2_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Echo Nginx
                    if "$NGX_ECHO"; then
                        echo "Downloading echo-nginx-module..."
                        run git clone -q https://github.com/openresty/echo-nginx-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/echo-nginx-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/echo-nginx-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Auth PAM
                    if "$NGX_HTTP_AUTH_PAM"; then
                        echo "Downloading ngx_http_auth_pam_module..."
                        run git clone -q https://github.com/sto/ngx_http_auth_pam_module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/ngx_http_auth_pam_module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_http_auth_pam_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # WebDAV
                    if "$NGX_WEB_DAV_EXT"; then
                        echo "Downloading nginx-dav-ext-module..."
                        run git clone -q https://github.com/arut/nginx-dav-ext-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-http_dav_module --add-module=${extra_module_dir}/nginx-dav-ext-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-http_dav_module --add-module=${extra_module_dir}/nginx-dav-ext-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Upstream Fair
                    if "$NGX_UPSTREAM_FAIR"; then
                        echo "Downloading nginx-upstream-fair module..."
                        run git clone -q https://github.com/gnosek/nginx-upstream-fair.git

                        echo "Downloading tengine-patches patch for nginx-upstream-fair module..."
                        run git clone -q https://github.com/alibaba/tengine-patches.git

                        status "Patching nginx-upstream-fair module..."
                        run cd nginx-upstream-fair
                        run patch -p1 < "${extra_module_dir}/tengine-patches/nginx-upstream-fair/upstream-fair-upstream-check.patch"
                        run cd "$extra_module_dir"

                        if "$NGINX_DYNAMIC_MODULE"; then
                            # Dynamic module not supported yet
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/nginx-upstream-fair ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/nginx-upstream-fair ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # A filter module which can do both regular expression and fixed string substitutions for nginx
                    if "$NGX_HTTP_SUBS_FILTER"; then
                        echo "Downloading ngx_http_substitutions_filter_module..."
                        run git clone -q https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            # Dynamic module not supported yet
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_http_substitutions_filter_module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx_http_substitutions_filter_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Nchan, pub/sub queuing server
                    if "$NGX_NCHAN"; then
                        echo "Downloading pub/sub nchan module..."
                        run git clone -q https://github.com/slact/nchan.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/nchan ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=$extra_module_dir/nchan ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # NGX_HTTP_NAXSI is an open-source, high performance, low rules maintenance WAF for NGINX
                    if "$NGX_HTTP_NAXSI"; then
                        echo "Downloading Naxsi Web Application Firewall module..."
                        run git clone -q https://github.com/nbs-system/naxsi.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/naxsi/naxsi_src ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/naxsi/naxsi_src ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Fancy indexes module for the Nginx web server
                    if "$NGX_HTTP_FANCYINDEX"; then
                        echo "Downloading ngx-fancyindex module..."
                        run git clone -q https://github.com/aperezdc/ngx-fancyindex.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/ngx-fancyindex ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/ngx-fancyindex ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Nginx Memc - An extended version of the standard memcached module.
                    if "$NGX_HTTP_MEMCACHED"; then
                        echo "Downloading extended Memcached module..."
                        run git clone -q https://github.com/openresty/memc-nginx-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/memc-nginx-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/memc-nginx-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Nginx upstream module for the Redis 2.0 protocol.
                    if "$NGX_HTTP_REDIS2"; then
                        echo "Downloading Redis 2.0 protocol module..."
                        run git clone -q https://github.com/openresty/redis2-nginx-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/redis2-nginx-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/redis2-nginx-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Nginx virtual host traffic status module
                    if "$NGX_HTTP_VTS"; then
                        echo "Downloading nginx-module-vts VHost traffic status module..."
                        run git clone -q https://github.com/vozlt/nginx-module-vts.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/nginx-module-vts ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/nginx-module-vts ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # NGINX-based Media Streaming Server.
                    if "$NGX_RTMP"; then
                        echo "Downloading RTMP Media Streaming Server module..."
                        run git clone -q https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--add-dynamic-module=$extra_module_dir/nginx-rtmp-module ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--add-module=${extra_module_dir}/nginx-rtmp-module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # HTTP Geoip module.
                    if "$NGX_HTTP_GEOIP"; then
                        echo "Adding Nginx GeoIP module..." 

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-http_geoip_module=dynamic ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-http_geoip_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # HTTP Image Filter module.
                    if "$NGX_HTTP_IMAGE_FILTER"; then
                        echo "Adding Nginx Image Filter module..." 

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-http_image_filter_module=dynamic ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-http_image_filter_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # HTTP XSLT module.
                    if "$NGX_HTTP_XSLT_FILTER"; then
                        echo "Adding Nginx XSLT module..." 

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-http_xslt_module=dynamic ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-http_xslt_module ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Mail module.
                    if "$NGX_MAIL"; then
                        echo "Adding Nginx mail module..." 

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-mail=dynamic ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-mail ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    # Stream module.
                    if "$NGX_STREAM"; then
                        echo "Adding Nginx stream module..." 

                        if "$NGINX_DYNAMIC_MODULE"; then
                            NGX_CONFIGURE_ARGS="--with-stream=dynamic ${NGX_CONFIGURE_ARGS}"
                        else
                            NGX_CONFIGURE_ARGS="--with-stream ${NGX_CONFIGURE_ARGS}"
                        fi
                    fi

                    run cd "${CURRENT_DIR}"
                fi

                # Execute nginx from source installer.
                "${SCRIPTS_DIR}/install_nginx_from_source.sh" -v latest-stable -n stable --dynamic-module \
                    --extra-modules -b "${BUILD_DIR}" -a "${NGX_CONFIGURE_ARGS}" -y
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

            if [[ -f /usr/lib/nginx/modules/ngx_http_memc_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-memc.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_memc_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-memc.conf"
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_redis2_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-redis2.conf ]]; then
                run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_redis2_module.so\";' \
                    > /etc/nginx/modules-available/mod-http-redis2.conf"
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

            # Enable Dynamic modules.
            if [[ "${ENABLE_NGXDM}" == Y* || "${ENABLE_NGXDM}" == y* ]]; then
                if [[ "${NGX_HTTP_BROTLI}" && \
                    -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-brotli-filter.conf \
                        /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf
                fi

                if [[ "${NGX_HTTP_BROTLI}" && \
                    -f /etc/nginx/modules-available/mod-http-brotli-static.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-brotli-static.conf \
                        /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf
                fi

                if [[ "${NGX_HTTP_CACHE_PURGE}" && \
                    -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-cache-purge.conf \
                        /etc/nginx/modules-enabled/50-mod-http-cache-purge.conf
                fi

                if [[ "${NGX_HTTP_FANCYINDEX}" && \
                    -f /etc/nginx/modules-available/mod-http-fancyindex.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-fancyindex.conf \
                        /etc/nginx/modules-enabled/50-mod-http-fancyindex.conf
                fi

                if [[ "${NGX_HTTP_HEADERS_MORE}" && \
                    -f /etc/nginx/modules-available/mod-http-headers-more-filter.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-headers-more-filter.conf \
                        /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf
                fi

                if [[ "${NGX_HTTP_GEOIP2}" && \
                    -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                    run ln -s /etc/nginx/modules-available/mod-http-geoip.conf \
                        /etc/nginx/modules-enabled/50-mod-http-geoip.conf
                fi

                if [[ "${NGX_HTTP_MEMCACHED}" && \
                    -f /etc/nginx/modules-available/mod-http-memc.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-memc.conf \
                        /etc/nginx/modules-enabled/50-mod-http-memc.conf
                fi

                if [[ "${NGX_HTTP_NAXSI}" && \
                    -f /etc/nginx/modules-available/mod-http-naxsi.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-naxsi.conf \
                        /etc/nginx/modules-enabled/50-mod-http-naxsi.conf
                fi

                if [[ "${NGX_HTTP_REDIS2}" && \
                    -f /etc/nginx/modules-available/mod-http-redis2.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-http-redis2.conf \
                        /etc/nginx/modules-enabled/50-mod-http-redis2.conf
                fi

                if [[ "${NGX_MAIL}" && \
                    -f /etc/nginx/modules-available/mod-mail.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-mail.conf \
                        /etc/nginx/modules-enabled/60-mod-mail.conf
                fi

                if [[ "${NGX_PAGESPEED}" && \
                    -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-pagespeed.conf \
                        /etc/nginx/modules-enabled/60-mod-pagespeed.conf
                fi

                if [[ "${NGX_STREAM}" && \
                    -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                    run ln -fs /etc/nginx/modules-available/mod-stream.conf \
                        /etc/nginx/modules-enabled/60-mod-stream.conf
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

            if [ ! -f /etc/systemd/system/multi-user.target.wants/nginx.service ]; then
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

    run cp -f etc/nginx/nginx.conf /etc/nginx/
    run cp -f etc/nginx/charset /etc/nginx/
    run cp -f etc/nginx/{comp_brotli,comp_gzip} /etc/nginx/
    run cp -f etc/nginx/{fastcgi_cache,fastcgi_https_map,fastcgi_params,mod_pagespeed,proxy_cache,proxy_params} \
        /etc/nginx/
    run cp -f etc/nginx/{http_cloudflare_ips,http_proxy_ips,upstream} /etc/nginx/
    run cp -fr etc/nginx/{includes,vhost,ssl} /etc/nginx/

    if [ -f /etc/nginx/sites-available/default ]; then
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default~
    fi
    run cp -f etc/nginx/sites-available/default /etc/nginx/sites-available/

    # Enable default virtual host (mandatory).
    if [ -f /etc/nginx/sites-enabled/default ]; then
        run unlink /etc/nginx/sites-enabled/default
    fi
    if [ -f /etc/nginx/sites-enabled/01-default ]; then
        run unlink /etc/nginx/sites-enabled/01-default
    fi
    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    # Custom error pages.
    if [ ! -d /usr/share/nginx/html ]; then
        run mkdir -p /usr/share/nginx/html
    fi
    run cp -fr share/nginx/html/error-pages /usr/share/nginx/html/
    if [ -d /usr/share/nginx/html ]; then
        run chown -hR www-data:www-data /usr/share/nginx/html
    fi

    # NGiNX cache directory.
    if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
        run mkdir -p /var/cache/nginx/fastcgi_cache
    fi
    if [ ! -d /var/cache/nginx/proxy_cache ]; then
        run mkdir -p /var/cache/nginx/proxy_cache
    fi

    # Fix ownership.
    run chown -hR www-data:www-data /var/cache/nginx
    
    # Adjust nginx to meet hardware resources.
    echo "Adjusting NGiNX configuration..."

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

    # Enable PageSpeed config.
    if [[ "${NGX_PAGESPEED}" && \
        -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then                    
        run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" \
            /etc/nginx/nginx.conf
    fi

    # Generate Diffie-Hellman parameters.
    DH_NUMBITS=${HASH_LENGTH:-2048}
    if [ ! -f "/etc/nginx/ssl/dhparam-${DH_NUMBITS}.pem" ]; then
        echo "Generating Diffie-Hellman parameters for enhanced HTTPS/SSL security,"
        echo "this is going to take a long time..."

        run openssl dhparam -out "/etc/nginx/ssl/dhparam-${DH_NUMBITS}.pem" "${DH_NUMBITS}"
    fi

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
            if nginx -t 2>/dev/null > /dev/null; then
                run service nginx reload -s
                status "NGiNX HTTP server restarted successfully."
            else
                error "Nginx configuration test failed."
            fi
        elif [[ -n $(command -v nginx) ]]; then
            if nginx -t 2>/dev/null > /dev/null; then
                run service nginx start
                
                if [[ $(pgrep -c nginx) -gt 0 ]]; then
                    status "NGiNX HTTP server started successfully."
                else
                    warning "Something wrong with NGiNX installation."
                fi
            else
                error "Nginx configuration test failed."
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
