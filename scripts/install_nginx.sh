#!/usr/bin/env bash

# NGiNX Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 02/11/2019
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
if grep -q "scripts" <<< "${BASEDIR}"; then
    SCRIPTS_DIR="${BASEDIR}"
else
    SCRIPTS_DIR="${BASEDIR}/scripts"
fi

# Make sure only root can run this installer script.
requires_root

function add_nginx_repo() {
    echo "Add NGiNX repository..."

    # Nginx version.
    local NGX_VERSION=${NGINX_VERSION:-"stable"}
    export NGX_PACKAGE

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

    case "${DISTRIB_NAME}" in
        debian)
            # Recommended install from source.
            NGX_PACKAGE="nginx-extras"
        ;;
        ubuntu)
            case "${RELEASE_NAME}" in
                xenial|bionic|disco)
                    # NGiNX custom with ngx cache purge from Ondrej repo.
                    run wget -qO /etc/apt/trusted.gpg.d/nginx.gpg https://packages.sury.org/nginx/apt.gpg

                    if [[ ${NGX_VERSION} == "mainline" || ${NGX_VERSION} == "latest" ]]; then
                        run add-apt-repository -y ppa:ondrej/nginx-mainline
                    else
                        run add-apt-repository -y ppa:ondrej/nginx
                    fi

                    NGX_PACKAGE="nginx-extras"
                ;;
                *)
                    NGX_PACKAGE=""

                    error "Unable to add NGiNX, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                    echo "Sorry your system is not supported yet, installing from source may be fix the issue."
                    exit 1
                ;;
            esac
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

function init_nginx_install() {
    local SELECTED_INSTALLER=""

    if "${AUTO_INSTALL}"; then
        if [[ -z "${NGINX_INSTALLER}" || "${NGINX_INSTALLER}" == "none" ]]; then
            DO_INSTALL_NGINX="n"
        else
            DO_INSTALL_NGINX="y"
            SELECTED_INSTALLER=${NGINX_INSTALLER:-"source"}
        fi
    else
        while [[ ${DO_INSTALL_NGINX} != "y" && ${DO_INSTALL_NGINX} != "n" ]]; do
            read -rp "Do you want to install NGiNX HTTP (web) server? [y/n]: " \
            -i y -e DO_INSTALL_NGINX
        done
        echo ""
    fi

    # Install NGiNX custom.
    if [[ ${DO_INSTALL_NGINX} == y* && ${INSTALL_NGINX} == true ]]; then
        echo "Available NGiNX installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        echo ""

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                add_nginx_repo

                echo "Installing NGiNX from package repository..."

                if hash apt-get 2>/dev/null; then
                    if [[ -n "${NGX_PACKAGE}" ]]; then
                        run apt-get -qq update -y
                        run apt-get -qq install -y "${NGX_PACKAGE}"
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
                    fail "Unable to install NGiNX, this GNU/Linux distribution is not supported."
                fi
            ;;
            2|"source")
                echo "Installing NGiNX from source..."

                if "${DRYRUN}"; then
                    run "${SCRIPTS_DIR}/build_nginx.sh" -v latest-stable \
                        -n stable --dynamic-module --extra-modules -y --dryrun
                else
                    # Nginx version.
                    local NGX_VERSION=${NGINX_VERSION:-"stable"}
                    if [[ ${NGX_VERSION} == "mainline" || ${NGX_VERSION} == "latest" ]]; then
                        NGX_VERSION="latest"
                    else
                        NGX_VERSION="stable"
                    fi

                    # Additional configure arguments.
                    NGX_CONFIGURE_ARGS=""

                    # Custom build name.
                    NGX_CONFIGURE_ARGS="--build=LEMPer ${NGX_CONFIGURE_ARGS}"

                    if "${NGINX_EXTRA_MODULES}"; then
                        echo "Build NGiNX with extra modules..."

                        local EXTRA_MODULE_DIR="${BUILD_DIR}/nginx_modules"

                        if [ ! -d "${EXTRA_MODULE_DIR}" ]; then
                            run mkdir -p "${EXTRA_MODULE_DIR}"
                        else
                            delete_if_already_exists "${EXTRA_MODULE_DIR}"
                            run mkdir -p "${EXTRA_MODULE_DIR}"
                        fi

                        local CURRENT_DIR && \
                        CURRENT_DIR=$(pwd)
                        run cd "${EXTRA_MODULE_DIR}"

                        # Custom OpenSSL.
                        if [[ -n "${NGINX_CUSTOMSSL_VERSION}" ]]; then
                            echo "Add custom SSL ${NGINX_CUSTOMSSL_VERSION^}..."

                            if grep -iq openssl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                                OPENSSL_DOWNLOAD_URL="https://www.openssl.org/source/${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                                #OPENSSL_DOWNLOAD_URL="https://github.com/openssl/openssl/archive/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                                if curl -sL --head "${OPENSSL_DOWNLOAD_URL}" | grep -q "HTTP/[12].[01] [23].."; then
                                    run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${OPENSSL_DOWNLOAD_URL}" && \
                                    run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz" && \
                                    #run rm -f "${NGINX_CUSTOMSSL_VERSION}.tar.gz" && \
                                    NGX_CONFIGURE_ARGS="--with-openssl=${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION} \
                                        --with-openssl-opt=enable-ec_nistp_64_gcc_128 --with-openssl-opt=no-nextprotoneg \
                                        --with-openssl-opt=no-weak-ssl-ciphers ${NGX_CONFIGURE_ARGS}"
                                else
                                    warning "Unable to determine Custom SSL source page."
                                fi
                            elif grep -iq libressl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                                LIBRESSL_DOWNLOAD_URL="https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                                if curl -sL --head "${LIBRESSL_DOWNLOAD_URL}" | grep -q "HTTP/[12].[01] [23].."; then
                                    run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${LIBRESSL_DOWNLOAD_URL}" && \
                                    run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz" && \
                                    #run rm -f "${NGINX_CUSTOMSSL_VERSION}.tar.gz" && \
                                    NGX_CONFIGURE_ARGS="--with-openssl=${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION} ${NGX_CONFIGURE_ARGS}"
                                else
                                    warning "Unable to determine Custom SSL source page."
                                fi
                            elif grep -iq boringssl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                                # BoringSSL requires Golang, install it first.
                                if [[ -z $(command -v go) ]]; then
                                    case "${DISTRIB_NAME}" in
                                        debian)
                                            GOLANG_DOWNLOAD_URL="https://dl.google.com/go/go1.13.4.linux-amd64.tar.gz"

                                            if curl -sL --head "${GOLANG_DOWNLOAD_URL}" | grep -q "HTTP/[12].[01] [23].."; then
                                                run wget -q -O golang.tar.gz "${GOLANG_DOWNLOAD_URL}" && \
                                                run tar -C /usr/local -zxf golang.tar.gz && \
                                                run bash -c "echo -e '\nexport PATH=\"\$PATH:/usr/local/go/bin\"' >> ~/.profile" && \
                                                run source ~/.profile
                                            else
                                                warning "Unable to determine Golang source page."
                                            fi
                                        ;;
                                        ubuntu)
                                            run add-apt-repository -y ppa:longsleep/golang-backports && \
                                            run apt-get -qq update -y && \
                                            run apt-get -qq install -y golang-go
                                        ;;
                                        *)
                                            fail "Unsupported distribution."
                                        ;;
                                    esac
                                fi

                                # Split version.
                                SAVEIFS=${IFS} # Save current IFS
                                IFS='- ' read -r -a BSPARTS <<< "${NGINX_CUSTOMSSL_VERSION}"
                                IFS=${SAVEIFS} # Restore IFS
                                BORINGSSL_VERSION=${BSPARTS[1]}
                                [[ -z ${BORINGSSL_VERSION} || ${BORINGSSL_VERSION} = "latest" ]] && BORINGSSL_VERSION="master"
                                BORINGSSL_DOWNLOAD_URL="https://boringssl.googlesource.com/boringssl/+archive/refs/heads/${BORINGSSL_VERSION}.tar.gz"

                                if curl -sL --head "${BORINGSSL_DOWNLOAD_URL}" | grep -q "HTTP/[12].[01] [23].."; then
                                    run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${BORINGSSL_DOWNLOAD_URL}" && \
                                    run mkdir "${NGINX_CUSTOMSSL_VERSION}" && \
                                    run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz" -C "${NGINX_CUSTOMSSL_VERSION}" && \
                                    run rm -f "${NGINX_CUSTOMSSL_VERSION}.tar.gz" && \
                                    run cd "${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}"

                                    # Make an .openssl directory for nginx and then symlink BoringSSL's include directory tree.
                                    run mkdir -p build .openssl/lib .openssl/include && \
                                    run ln -sf "${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/include/openssl" .openssl/include/openssl && \

                                    # Build BoringSSL.
                                    run cmake -B"${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/build" -H"${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}" && \
                                    run make -C"${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/build" -j"$(getconf _NPROCESSORS_ONLN)" && \

                                    # Copy the BoringSSL crypto libraries to .openssl/lib so nginx can find them.
                                    run cp build/crypto/libcrypto.a .openssl/lib && \
                                    run cp build/ssl/libssl.a .openssl/lib && \

                                    # Fix "Error 127" during build.
                                    run touch "${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/include/openssl/ssl.h" && \

                                    # Back to extra module dir.
                                    run cd "${EXTRA_MODULE_DIR}" && \

                                    #NGX_CONFIGURE_ARGS="--with-openssl=${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION} ${NGX_CONFIGURE_ARGS}"
                                    NGX_CONFIGURE_ARGS="--with-cc-opt=-I${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/include ${NGX_CONFIGURE_ARGS}" && \
                                    NGX_CONFIGURE_ARGS="--with-ld-opt=-L${EXTRA_MODULE_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/lib ${NGX_CONFIGURE_ARGS}"
                                else
                                    warning "Unable to determine Custom SSL source page."
                                fi
                            else
                                error "Unable to determine Custom SSL version."
                                echo "Revert back to use stack's default OpenSSL..."
                            fi
                        fi

                        # Auth PAM
                        if "$NGX_HTTP_AUTH_PAM"; then
                            echo "Add ngx_http_auth_pam_module..."
                            run git clone -q https://github.com/sto/ngx_http_auth_pam_module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Brotli compression.
                        if "$NGX_HTTP_BROTLI"; then
                            echo "Add ngx_brotli module..."

                            run git clone -q https://github.com/eustas/ngx_brotli.git
                            run cd ngx_brotli || exit 1
                            run git checkout master -q
                            run git submodule update --init -q
                            run cd ../

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_brotli ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_brotli ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Cache Purge
                        if "$NGX_HTTP_CACHE_PURGE"; then
                            echo "Add ngx_cache_purge module..."
                            run git clone -q https://github.com/nginx-modules/ngx_cache_purge.git
                            #run git clone -q https://github.com/joglomedia/ngx_cache_purge.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_cache_purge ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_cache_purge ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Echo Nginx
                        if "$NGX_HTTP_ECHO"; then
                            echo "Add echo-nginx-module..."
                            run git clone -q https://github.com/openresty/echo-nginx-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/echo-nginx-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/echo-nginx-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Fancy indexes module for the Nginx web server
                        if "$NGX_HTTP_FANCYINDEX"; then
                            echo "Add ngx-fancyindex module..."
                            run git clone -q https://github.com/aperezdc/ngx-fancyindex.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/ngx-fancyindex ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx-fancyindex ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # HTTP Geoip module.
                        if "$NGX_HTTP_GEOIP"; then
                            echo "Add Nginx GeoIP module..."

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-http_geoip_module=dynamic ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-http_geoip_module ${NGX_CONFIGURE_ARGS}"
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

                            echo "Download MaxMind GeoIP database..."

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

                            echo "Add ngx_http_geoip2_module..."
                            run git clone -q https://github.com/leev/ngx_http_geoip2_module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Headers more module.
                        if "$NGX_HTTP_HEADERS_MORE"; then
                            echo "Add headers-more-nginx-module..."
                            run git clone -q https://github.com/openresty/headers-more-nginx-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/headers-more-nginx-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/headers-more-nginx-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # HTTP Image Filter module.
                        if "$NGX_HTTP_IMAGE_FILTER"; then
                            echo "Build with Nginx Image Filter module..."

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-http_image_filter_module=dynamic ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-http_image_filter_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Nginx Memc - An extended version of the standard memcached module.
                        if "$NGX_HTTP_MEMCACHED"; then
                            echo "Add extended Memcached module..."
                            run git clone -q https://github.com/openresty/memc-nginx-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/memc-nginx-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/memc-nginx-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # NGX_HTTP_NAXSI is an open-source, high performance, low rules maintenance WAF for NGINX
                        if "$NGX_HTTP_NAXSI"; then
                            echo "Add Naxsi Web Application Firewall module..."
                            run git clone -q https://github.com/nbs-system/naxsi.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/naxsi/naxsi_src ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/naxsi/naxsi_src ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Nginx mod HTTP Passenger.
                        if "$NGX_HTTP_PASSENGER"; then
                            echo "Add Passenger module..."

                            if [[ -n $(command -v passenger-config) ]]; then
                                if "$NGINX_DYNAMIC_MODULE"; then
                                    NGX_CONFIGURE_ARGS="--add-dynamic-module=$(passenger-config --nginx-addon-dir) ${NGX_CONFIGURE_ARGS}"
                                else
                                    NGX_CONFIGURE_ARGS="--add-module=$(passenger-config --nginx-addon-dir) ${NGX_CONFIGURE_ARGS}"
                                fi
                            else
                                error "Passenger module not found. Skipped..."
                            fi
                        fi

                        # Nginx upstream module for the Redis 2.0 protocol.
                        if "$NGX_HTTP_REDIS2"; then
                            echo "Add Redis 2.0 protocol module..."
                            run git clone -q https://github.com/openresty/redis2-nginx-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/redis2-nginx-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/redis2-nginx-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # A filter module which can do both regular expression and fixed string substitutions for nginx
                        if "$NGX_HTTP_SUBS_FILTER"; then
                            echo "Add ngx_http_substitutions_filter_module..."
                            run git clone -q https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                # Dynamic module not supported yet
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_http_substitutions_filter_module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/ngx_http_substitutions_filter_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Nginx virtual host traffic status module
                        if "$NGX_HTTP_VTS"; then
                            echo "Add nginx-module-vts VHost traffic status module..."
                            run git clone -q https://github.com/vozlt/nginx-module-vts.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-module-vts ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/nginx-module-vts ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # HTTP XSLT module.
                        if "$NGX_HTTP_XSLT_FILTER"; then
                            echo "Add Nginx XSLT module..."

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-http_xslt_module=dynamic ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-http_xslt_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Mail module.
                        if "$NGX_MAIL"; then
                            echo "Add Nginx mail module..."

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-mail=dynamic --with-mail_ssl_module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-mail --with-mail_ssl_module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Nchan, pub/sub queuing server
                        if "$NGX_NCHAN"; then
                            echo "Add pub/sub nchan module..."
                            run git clone -q https://github.com/slact/nchan.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/nchan ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/nchan ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # NGINX-based Media Streaming Server.
                        if "$NGX_RTMP"; then
                            echo "Add RTMP Media Streaming Server module..."
                            run git clone -q https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-rtmp-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/nginx-rtmp-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Stream module.
                        if "$NGX_STREAM"; then
                            echo "Add Nginx stream module..."

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-stream=dynamic --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module --with-stream_geoip_module=dynamic ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module --with-stream_geoip_module=dynamic ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # Upstream Fair
                        if "$NGX_UPSTREAM_FAIR"; then
                            echo "Add nginx-upstream-fair module..."
                            run git clone -q https://github.com/gnosek/nginx-upstream-fair.git

                            echo "Download tengine-patches patch for nginx-upstream-fair module..."
                            run git clone -q https://github.com/alibaba/tengine-patches.git

                            status "Patching nginx-upstream-fair module..."
                            run cd nginx-upstream-fair
                            run patch -p1 < "${EXTRA_MODULE_DIR}/tengine-patches/nginx-upstream-fair/upstream-fair-upstream-check.patch"
                            run cd "${EXTRA_MODULE_DIR}"

                            if "$NGINX_DYNAMIC_MODULE"; then
                                # Dynamic module not supported yet
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/nginx-upstream-fair ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--add-module=${EXTRA_MODULE_DIR}/nginx-upstream-fair ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        # WebDAV
                        if "$NGX_WEB_DAV_EXT"; then
                            echo "Add nginx-dav-ext-module..."
                            run git clone -q https://github.com/arut/nginx-dav-ext-module.git

                            if "$NGINX_DYNAMIC_MODULE"; then
                                NGX_CONFIGURE_ARGS="--with-http_dav_module --add-module=${EXTRA_MODULE_DIR}/nginx-dav-ext-module ${NGX_CONFIGURE_ARGS}"
                            else
                                NGX_CONFIGURE_ARGS="--with-http_dav_module --add-module=${EXTRA_MODULE_DIR}/nginx-dav-ext-module ${NGX_CONFIGURE_ARGS}"
                            fi
                        fi

                        run cd "${CURRENT_DIR}"
                    fi

                    # Execute nginx from source installer.
                    if [ -f "${SCRIPTS_DIR}/build_nginx.sh" ]; then
                        run "${SCRIPTS_DIR}/build_nginx.sh" -v latest-stable -n "${NGX_VERSION}" --dynamic-module \
                            --extra-modules -b "${BUILD_DIR}" -a "${NGX_CONFIGURE_ARGS}" -y
                    elif [ -f ".${SCRIPTS_DIR}/build_nginx.sh" ]; then
                        run ".${SCRIPTS_DIR}/build_nginx.sh" -v latest-stable -n "${NGX_VERSION}" --dynamic-module \
                            --extra-modules -b "${BUILD_DIR}" -a "${NGX_CONFIGURE_ARGS}" -y
                    else
                        error "Nginx from source installer not found."
                    fi
                fi

                echo "Configuring NGiNX extra modules..."

                # Create NGiNX directories.
                if [ ! -d /etc/nginx/modules-available ]; then
                    run mkdir /etc/nginx/modules-available
                    run chmod 755 /etc/nginx/modules-available
                fi

                if [ ! -d /etc/nginx/modules-enabled ]; then
                    run mkdir /etc/nginx/modules-enabled
                    run chmod 755 /etc/nginx/modules-enabled
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

                if [[ -f /usr/lib/nginx/modules/ngx_http_naxsi_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-naxsi.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_naxsi_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-naxsi.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_passenger_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-passenger.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_passenger_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-passenger.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_redis2_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-redis2.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_redis2_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-redis2.conf"
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

                    if [[ "${NGX_HTTP_PASSENGER}" && \
                        -f /etc/nginx/modules-available/mod-http-passenger.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-passenger.conf \
                            /etc/nginx/modules-enabled/50-mod-http-passenger.conf
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

                # Unmask (?).
                run systemctl unmask nginx.service
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. NGiNX installation skipped."
            ;;
        esac

        echo "Creating NGiNX configuration..."

        if [ ! -d /etc/nginx/sites-available ]; then
            run mkdir /etc/nginx/sites-available
        fi

        if [ ! -d /etc/nginx/sites-enabled ]; then
            run mkdir /etc/nginx/sites-enabled
        fi

        # Copy custom NGiNX Config.
        if [ -f /etc/nginx/nginx.conf ]; then
            run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf~
        fi

        run cp -f etc/nginx/nginx.conf /etc/nginx/
        run cp -f etc/nginx/charset /etc/nginx/
        run cp -f etc/nginx/{comp_brotli,comp_gzip} /etc/nginx/
        run cp -f etc/nginx/{fastcgi_cache,fastcgi_https_map,fastcgi_params,mod_pagespeed,proxy_cache,proxy_params} \
            /etc/nginx/
        run cp -f etc/nginx/{http_cloudflare_ips,http_proxy_ips,upstream} /etc/nginx/
        run cp -fr etc/nginx/{includes,vhost} /etc/nginx/

        if [ -f /etc/nginx/sites-available/default ]; then
            run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default~
        fi
        run cp -f etc/nginx/sites-available/default /etc/nginx/sites-available/

        # Enable default virtual host (mandatory).
        if [ -f /etc/nginx/sites-enabled/default ]; then
            run unlink /etc/nginx/sites-enabled/default
        fi
        if [ -f /etc/nginx/sites-enabled/00-default ]; then
            run unlink /etc/nginx/sites-enabled/00-default
        fi
        run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/00-default

        # Custom pages.
        if [ ! -d /usr/share/nginx/html ]; then
            run mkdir -p /usr/share/nginx/html
        fi
        run cp -fr share/nginx/html/error-pages /usr/share/nginx/html/
        run cp -f share/nginx/html/index.html /usr/share/nginx/html/

        # Custom tmp dir.
        run mkdir -p /usr/share/nginx/html/.lemper/tmp

        # Custom PHP opcache dir.
        run mkdir -p /usr/share/nginx/html/.lemper/php/opcache

        # Custom PHP sessions dir.
        run mkdir -p /usr/share/nginx/html/.lemper/php/sessions

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

        # Adjust worker processes.
        #run sed -i "s/worker_processes\ auto/worker_processes\ ${CPU_CORES}/g" /etc/nginx/nginx.conf

        local NGX_CONNECTIONS
        case ${CPU_CORES} in
            1)
                NGX_CONNECTIONS=1024
            ;;
            2|3)
                NGX_CONNECTIONS=2048
            ;;
            *)
                NGX_CONNECTIONS=4096
            ;;
        esac

        # Adjust worker connections.
        run sed -i "s/worker_connections\ 4096/worker_connections\ ${NGX_CONNECTIONS}/g" /etc/nginx/nginx.conf

        # Enable PageSpeed config.
        if [[ "${NGX_PAGESPEED}" && \
            -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
            run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" \
                /etc/nginx/nginx.conf
        fi

        # Generate Diffie-Hellman parameters.
        local DH_LENGTH=${HASH_LENGTH:-2048}
        if [ ! -f "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" ]; then
            echo "Enhance HTTPS/SSL security with DH key."

            [ ! -d /etc/nginx/ssl ] && mkdir -p /etc/nginx/ssl
            run openssl dhparam -out "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" "${DH_LENGTH}"
        fi

        # Final test.
        if "${DRYRUN}"; then
            warning "NGiNX HTTP server installed in dryrun mode."
        else
            # Make default server accessible from hostname or IP address.
            if [[ $(dig "${HOSTNAME}" +short) = "${SERVER_IP}" ]]; then
                run sed -i "s/localhost.localdomain/${HOSTNAME}/g" /etc/nginx/sites-available/default
            else
                run sed -i "s/localhost.localdomain/${SERVER_IP}/g" /etc/nginx/sites-available/default
            fi

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
    else
        warning "NGiNX HTTP (web) server installation skipped..."
    fi
}

echo "[NGiNX HTTP (Web) Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available ]]; then
    warning "Nginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
