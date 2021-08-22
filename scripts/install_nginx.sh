#!/usr/bin/env bash

# Nginx Installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 23/12/2020
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASEDIR}/helper.sh"
fi

# Define scripts directory.
#if grep -q "scripts" <<< "${BASEDIR}"; then
#    SCRIPTS_DIR="${BASEDIR}"
#else
#    SCRIPTS_DIR="${BASEDIR}/scripts"
#fi

# Make sure only root can run this installer script.
requires_root

function add_nginx_repo() {
    echo "Add Nginx repository..."

    # Nginx version.
    local NGINX_VERSION=${NGINX_VERSION:-"stable"}
    export NGX_PACKAGE

    if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
        local NGINX_REPO="nginx-mainline"
    else
        local NGINX_REPO="nginx"
    fi

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

    #local ALTERNATIVE_REPO=false
    #[[ "${RELEASE_NAME}" == "jessie" || "${RELEASE_NAME}" == "xenial" ]] && ALTERNATIVE_REPO=true

    case "${DISTRIB_NAME}" in
        debian)
            if [ ! -f "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb https://packages.sury.org/${NGINX_REPO}/ ${RELEASE_NAME} main' > /etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
                run wget -qO "/etc/apt/trusted.gpg.d/${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg"
                run apt-get update -qq -y
            else
                info "${NGINX_REPO} repository already exists."
            fi

            NGINX_PKG="nginx-extras"
        ;;
        ubuntu)
            # Nginx custom with ngx cache purge from Ondrej repo.
            #run wget -qO "/etc/apt/trusted.gpg.d/${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg"
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C
            run add-apt-repository -y "ppa:ondrej/${NGINX_REPO}"
            run apt-get update -qq -y

            NGINX_PKG="nginx-extras"
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
            read -rp "Do you want to install Nginx HTTP server? [y/n]: " -i y -e DO_INSTALL_NGINX
        done
    fi

    # Install Nginx custom.
    if [[ ${DO_INSTALL_NGINX} == y* && ${INSTALL_NGINX} == true ]]; then
        echo "Available Nginx installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        # NgxPageSpeed module currently available from source install.
        if [[ ${NGX_PAGESPEED} == true ]]; then
            SELECTED_INSTALLER="source"
            info "NGX_PAGESPEED module requires Nginx to be installed from source."
        fi

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                add_nginx_repo

                echo "Installing Nginx from package repository..."

                if hash apt-get 2>/dev/null; then
                    if [[ -n "${NGINX_PKG}" ]]; then
                        local EXTRA_MODULE_PKGS=()

                        if "${NGINX_EXTRA_MODULES}"; then
                            echo "Installing Nginx with extra modules..."

                            # Auth PAM
                            if "${NGX_HTTP_AUTH_PAM}"; then
                                echo "Adding ngx-http-auth-pam module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-auth-pam")
                            fi

                            # Brotli compression
                            if "${NGX_HTTP_BROTLI}"; then
                                echo "Adding ngx-http-brotli module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-brotli")
                            fi

                            # Cache Purge
                            if "${NGX_HTTP_CACHE_PURGE}"; then
                                echo "Adding ngx-http-cache-purge module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-cache-purge")
                            fi

                            # Fancy indexes module for the Nginx web server
                            if "${NGX_HTTP_DAV_EXT}"; then
                                echo "Adding ngx-http-dav-ext module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-dav-ext")
                            fi

                            # Echo Nginx
                            if "${NGX_HTTP_ECHO}"; then
                                echo "Adding ngx-http-echo module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-echo")
                            fi

                            # Fancy indexes module for the Nginx web server
                            if "${NGX_HTTP_FANCYINDEX}"; then
                                echo "Adding ngx-http-fancyindex module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-fancyindex")
                            fi

                            # HTTP Geoip module.
                            if "${NGX_HTTP_GEOIP}"; then
                                echo "Adding ngx-http-geoip module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libmaxminddb" "libnginx-mod-http-geoip" "libnginx-mod-stream-geoip")
                            fi

                            # GeoIP2
                            if "${NGX_HTTP_GEOIP2}"; then
                                echo "Adding ngx-http-geoip2 module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libmaxminddb" "libnginx-mod-http-geoip2" "libnginx-mod-stream-geoip2")
                            fi

                            # Headers more module.
                            if "${NGX_HTTP_HEADERS_MORE}"; then
                                echo "Adding ngx-http-headers-more-filter module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-headers-more-filter")
                            fi

                            # HTTP Image Filter module.
                            if "${NGX_HTTP_IMAGE_FILTER}"; then
                                echo "Adding ngx-http-image-filter module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-image-filter")
                            fi

                            # Embed the power of Lua into Nginx HTTP Servers.
                            if "${NGX_HTTP_LUA}"; then
                                echo "Adding ngx-http-lua module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-lua")
                            fi

                            # Nginx Memc - An extended version of the standard memcached module.
                            if "${NGX_HTTP_MEMCACHED}"; then
                                echo "Adding ngx-http-memcached module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-memcached")
                            fi

                            # NGX_HTTP_NAXSI is an open-source, high performance, low rules maintenance WAF for NGINX.
                            if "${NGX_HTTP_NAXSI}"; then
                                echo "Adding ngx-http-naxsi (Web Application Firewall) module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-naxsi")
                            fi

                            # NDK adds additional generic tools that module developers can use in their own modules.
                            if "${NGX_HTTP_NDK}"; then
                                echo "Adding ngx-http-ndk Nginx Devel Kit module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-ndk")
                            fi

                            # NJS is a subset of the JavaScript language that allows extending nginx functionality.
                            # shellcheck disable=SC2153
                            if "${NGX_HTTP_JS}"; then
                                echo "Adding ngx-http-js module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-js")
                            fi

                            # Nginx mod HTTP Passenger.
                            if "${NGX_HTTP_PASSENGER}"; then
                                echo "Adding ngx-http-passenger module..."

                                if [[ -n $(command -v passenger-config) ]]; then
                                    echo "Passenger found..."
                                    #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-passenger")
                                else
                                    error "Passenger not found. Skipped..."
                                fi
                            fi

                            # Nginx upstream module for the Redis 2.0 protocol.
                            if "${NGX_HTTP_REDIS2}"; then
                                echo "Adding ngx-http-redis module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-redis2")
                            fi

                            # A filter module which can do both regular expression and fixed string substitutions for nginx
                            if "${NGX_HTTP_SUBS_FILTER}"; then
                                echo "Adding ngx-http-subs-filter module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-subs-filter")
                            fi

                            # Upstream Fair
                            if "${NGX_HTTP_UPSTREAM_FAIR}"; then
                                echo "Adding ngx-http-nginx-upstream-fair module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-upstream-fair")
                            fi

                            # Nginx virtual host traffic status module
                            if "${NGX_HTTP_VTS}"; then
                                echo "Adding ngx-http-module-vts (VHost traffic status) module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-vts")
                            fi

                            # HTTP XSLT module.
                            if "${NGX_HTTP_XSLT_FILTER}"; then
                                echo "Adding ngx-http-xslt-filter module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-xslt-filter")
                            fi

                            # Mail module.
                            if "${NGX_MAIL}"; then
                                echo "Adding ngx-mail module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-mail")
                            fi

                            # Nchan, pub/sub queuing server
                            if "${NGX_NCHAN}"; then
                                echo "Adding ngx-nchan (Pub/Sub) module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-nchan")
                            fi

                            # NGINX-based Media Streaming Server.
                            if "${NGX_RTMP}"; then
                                echo "Adding ngx-rtmp (Media Streaming Server) module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-rtmp")
                            fi

                            # Stream module.
                            if "${NGX_STREAM}"; then
                                echo "Adding ngx-stream module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-stream")
                            fi
                        fi

                        # Install Nginx and its modules.
                        run apt-get install -qq -y "${NGINX_PKG}" "${EXTRA_MODULE_PKGS[@]}"
                    fi
                else
                    fail "Unable to install Nginx, this GNU/Linux distribution is not supported."
                fi
            ;;

            2|"source")
                echo "Installing Nginx from source, please wait..."

                # CPU core numbers, for building faster.
                local NB_PROC && \
                NB_PROC=$(getconf _NPROCESSORS_ONLN)
                #NB_PROC=$(grep -c ^processor /proc/cpuinfo)

                # Nginx version.
                local NGINX_VERSION=${NGINX_VERSION:-"stable"}
                if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
                    # Nginx mainline version.
                    NGINX_RELEASE_VERSION=$(determine_latest_nginx_version)
                elif [[ ${NGINX_VERSION} == "stable" || ${NGINX_VERSION} == "lts" ]]; then
                    # Nginx stable version.
                    NGINX_RELEASE_VERSION=$(determine_stable_nginx_version)
                else
                    # Fallback to default stable version.
                    NGINX_RELEASE_VERSION="${NGINX_VERSION}"
                fi

                if "${DRYRUN}"; then
                    run "${BUILD_DIR}/build_nginx" -v latest-stable \
                        -n "${NGINX_RELEASE_VERSION}" --dynamic-module --extra-modules -y --dryrun
                else
                    # Nginx configure arguments.
                    NGX_CONFIGURE_ARGS=""

                    # Is gcc > 8.x?
                    #if gcc --version | grep -q "\ [8.]"; then
                    #    NGX_CONFIGURE_ARGS="CFLAGS=\"-Wno-stringop-truncation -Wno-stringop-overflow -Wno-size-of-pointer-memaccess\""
                    #fi

                    # Additional configure arguments.
                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                        --prefix=/usr/share/nginx \
                        --sbin-path=/usr/sbin/nginx \
                        --modules-path=/usr/lib/nginx/modules \
                        --conf-path=/etc/nginx/nginx.conf \
                        --error-log-path=/var/log/nginx/error.log \
                        --http-log-path=/var/log/nginx/access.log \
                        --pid-path=/run/nginx.pid \
                        --lock-path=/var/lock/nginx.lock \
                        --user=www-data \
                        --group=www-data \
                        --with-compat \
                        --with-file-aio \
                        --with-http_addition_module \
                        --with-http_auth_request_module \
                        --with-http_dav_module \
                        --with-http_flv_module \
                        --with-http_gunzip_module \
                        --with-http_gzip_static_module \
                        --with-http_mp4_module \
                        --with-http_random_index_module \
                        --with-http_realip_module \
                        --with-http_secure_link_module \
                        --with-http_slice_module \
                        --with-http_ssl_module \
                        --with-http_stub_status_module \
                        --with-http_sub_module \
                        --with-http_v2_module \
                        --with-threads"

                    # Custom build name.
                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} --build=LEMPer"

                    local CURRENT_DIR && \
                    CURRENT_DIR=$(pwd)

                    run cd "${BUILD_DIR}" && \

                    # Build with custom OpenSSL.
                    if "${NGINX_WITH_CUSTOMSSL}"; then
                        # Custom SSL version.
                        NGINX_CUSTOMSSL_VERSION=${NGINX_CUSTOMSSL_VERSION:-"openssl-1.1.1d"}

                        echo "Build Nginx with custom SSL ${NGINX_CUSTOMSSL_VERSION^}..."

                        # OpenSSL
                        if grep -iq openssl <<<"${NGINX_CUSTOMSSL_VERSION}"; then
                            OPENSSL_SOURCE="https://www.openssl.org/source/${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                            #OPENSSL_SOURCE="https://github.com/openssl/openssl/archive/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                            if curl -sLI "${OPENSSL_SOURCE}" | grep -q "HTTP/[.12]* [2].."; then
                                run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${OPENSSL_SOURCE}" && \
                                run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                                [ -d "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" ] && \
                                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                        --with-openssl=${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION} \
                                        --with-openssl-opt=enable-ec_nistp_64_gcc_128 \
                                        --with-openssl-opt=no-nextprotoneg \
                                        --with-openssl-opt=no-weak-ssl-ciphers"
                            else
                                error "Unable to determine OpenSSL source page."
                            fi

                        # LibreSSL
                        elif grep -iq libressl <<<"${NGINX_CUSTOMSSL_VERSION}"; then
                            LIBRESSL_SOURCE="https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                            if curl -sLI "${LIBRESSL_SOURCE}" | grep -q "HTTP/[.12]* [2].."; then
                                run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${LIBRESSL_SOURCE}" && \
                                run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                                [ -d "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" ] && \
                                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                        --with-openssl=${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION} \
                                        --with-openssl-opt=no-weak-ssl-ciphers"
                            else
                                error "Unable to determine LibreSSL source page."
                            fi

                        # BoringSSL
                        elif grep -iq boringssl <<< "${NGINX_CUSTOMSSL_VERSION}"; then
                            # BoringSSL requires Golang, install it first.
                            if [[ -z $(command -v go) ]]; then
                                case "${DISTRIB_NAME}" in
                                    debian)
                                        GOLANG_DOWNLOAD_URL="https://dl.google.com/go/go1.13.4.linux-amd64.tar.gz"

                                        if curl -sLI "${GOLANG_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                                            run wget -q -O golang.tar.gz "${GOLANG_DOWNLOAD_URL}" && \
                                            run tar -C /usr/local -zxf golang.tar.gz && \
                                            run bash -c "echo -e '\nexport PATH=\"\$PATH:/usr/local/go/bin\"' >> ~/.profile" && \
                                            run source ~/.profile
                                        else
                                            info "Unable to determine Golang source page."
                                        fi
                                    ;;
                                    ubuntu)
                                        run add-apt-repository -y ppa:longsleep/golang-backports && \
                                        run apt-get update -qq -y && \
                                        run apt-get install -qq -y golang-go
                                    ;;
                                    *)
                                        fail "Unsupported distribution."
                                    ;;
                                esac
                            fi

                            # Split BoringSSL version.
                            SAVEIFS=${IFS} # Save current IFS
                            IFS='- ' read -r -a BSPARTS <<< "${NGINX_CUSTOMSSL_VERSION}"
                            IFS=${SAVEIFS} # Restore IFS
                            BORINGSSL_VERSION=${BSPARTS[1]}
                            [[ -z ${BORINGSSL_VERSION} || ${BORINGSSL_VERSION} = "latest" ]] && BORINGSSL_VERSION="master"
                            BORINGSSL_DOWNLOAD_URL="https://boringssl.googlesource.com/boringssl/+archive/refs/heads/${BORINGSSL_VERSION}.tar.gz"

                            if curl -sLI "${BORINGSSL_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                                run wget -q -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${BORINGSSL_DOWNLOAD_URL}" && \
                                run mkdir -p "${NGINX_CUSTOMSSL_VERSION}" && \
                                run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz" -C "${NGINX_CUSTOMSSL_VERSION}" && \
                                run cd "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" && \

                                # Make an .openssl directory for nginx and then symlink BoringSSL's include directory tree.
                                run mkdir -p build .openssl/lib .openssl/include && \
                                run ln -sf "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/include/openssl" .openssl/include/openssl && \

                                # Fix "Error 127" during build.
                                run touch "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/include/openssl/ssl.h" && \

                                # Build BoringSSL static.
                                run cmake -B"${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/build" -H"${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" && \
                                run make -C"${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/build" -j"${NB_PROC}" && \

                                # Copy the BoringSSL crypto libraries to .openssl/lib so nginx can find them.
                                run cp build/crypto/libcrypto.a .openssl/lib && \
                                run cp build/ssl/libssl.a .openssl/lib && \

                                # Back to extra module dir.
                                run cd "${EXTRA_MODULE_DIR}" && \

                                #NGX_CONFIGURE_ARGS="--with-openssl=${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION} ${NGX_CONFIGURE_ARGS}"
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-cc-opt=\"-I${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/include\" \
                                    --with-ld-opt=\"-L${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}/.openssl/lib\""
                            else
                                info "Unable to determine BoringSSL source page."
                            fi
                        else
                            error "Unable to determine CustomSSL version."
                            echo "Revert back to use default system's OpenSSL..."
                        fi
                    fi

                    # Build with PCRE.
                    if "${NGINX_WITH_PCRE}"; then
                        # Custom PCRE JIT source.
                        NGINX_PCRE_VERSION=${NGINX_PCRE_VERSION:-"pcre-8.43"}
                        SOURCE_PCRE="https://ftp.pcre.org/pub/pcre/${NGINX_PCRE_VERSION}.tar.gz"

                        echo "Build Nginx with PCRE-${NGINX_PCRE_VERSION} JIT..."

                        if curl -sLI "${SOURCE_PCRE}" | grep -q "HTTP/[.12]* [2].."; then
                            run wget -q -O "${NGINX_PCRE_VERSION}.tar.gz" "${SOURCE_PCRE}" && \
                            run tar -zxf "${NGINX_PCRE_VERSION}.tar.gz"

                            [ -d "${BUILD_DIR}/${NGINX_PCRE_VERSION}" ] && \
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} --with-pcre=${BUILD_DIR}/${NGINX_PCRE_VERSION} --with-pcre-jit"
                        else
                            error "Unable to determine PCRE-${NGINX_PCRE_VERSION} source."
                        fi
                    fi

                    if "${NGINX_EXTRA_MODULES}"; then
                        echo "Build Nginx with extra modules..."

                        local EXTRA_MODULE_DIR="${BUILD_DIR}/nginx_modules"

                        if [ ! -d "${EXTRA_MODULE_DIR}" ]; then
                            run mkdir -p "${EXTRA_MODULE_DIR}"
                        else
                            delete_if_already_exists "${EXTRA_MODULE_DIR}"
                            run mkdir -p "${EXTRA_MODULE_DIR}"
                        fi

                        run cd "${EXTRA_MODULE_DIR}" || return 1

                        # Auth PAM module.
                        if "${NGX_HTTP_AUTH_PAM}"; then
                            echo "Adding ngx-http-auth-pam module..."

                            run git clone -q https://github.com/sto/ngx_http_auth_pam_module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module"
                            fi

                            # Requires libpam-dev
                            echo "Building Auth PAM module requires libpam-dev package, install now..."
                            if hash apt-get 2>/dev/null; then
                                run apt-get install -qq -y libpam-dev
                            fi
                        fi

                        # Brotli compression module.
                        if "${NGX_HTTP_BROTLI}"; then
                            echo "Adding ngx-http-brotli module..."

                            run git clone -q https://github.com/google/ngx_brotli.git && \
                            run cd ngx_brotli && \
                            run git checkout master -q && \
                            run git submodule update --init -q && \
                            run cd ../ && \

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_brotli"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_brotli"
                            fi
                        fi

                        # Cache purge module.
                        if "${NGX_HTTP_CACHE_PURGE}"; then
                            echo "Adding ngx-http-cache-purge module..."

                            run git clone -q https://github.com/nginx-modules/ngx_cache_purge.git
                            #run git clone -q https://github.com/joglomedia/ngx_cache_purge.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_cache_purge"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_cache_purge"
                            fi
                        fi

                        # Web DAV module.
                        if "${NGX_HTTP_DAV_EXT}"; then
                            echo "Adding ngx-http-dav-ext module..."

                            run git clone -q https://github.com/arut/nginx-dav-ext-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-dav-ext-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/nginx-dav-ext-module"
                            fi
                        fi

                        # Openresty Echo module.
                        if "${NGX_HTTP_ECHO}"; then
                            echo "Adding ngx-http-echo module..."

                            run git clone -q https://github.com/openresty/echo-nginx-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/echo-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/echo-nginx-module"
                            fi
                        fi

                        # Fancy indexes module for the Nginx web server.
                        if "${NGX_HTTP_FANCYINDEX}"; then
                            echo "Adding ngx-http-fancyindex module..."

                            run git clone -q https://github.com/aperezdc/ngx-fancyindex.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx-fancyindex"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx-fancyindex"
                            fi
                        fi

                        # GeoIP module.
                        if "${NGX_HTTP_GEOIP}"; then
                            echo "Adding ngx-http-geoip module..."

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_geoip_module=dynamic"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_geoip_module"
                            fi
                        fi

                        # GeoIP2 module.
                        if "${NGX_HTTP_GEOIP2}"; then
                            echo "Adding ngx-http-geoip2 module..."

                            run git clone -q https://github.com/leev/ngx_http_geoip2_module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module"
                            fi

                            # install libmaxminddb
                            echo "GeoIP2 module requires MaxMind GeoIP2 library, install now..."

                            run cd "${BUILD_DIR}" && \

                            DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}

                            if [[ "${DISTRIB_NAME}" == "ubuntu" ]]; then
                                run add-apt-repository -y ppa:maxmind/ppa && \
                                run apt-get update -qq -y && \
                                run apt-get install -qq -y libmaxminddb0 libmaxminddb-dev mmdb-bin
                            else
                                if [ ! -d libmaxminddb ]; then
                                    run git clone -q --recursive https://github.com/maxmind/libmaxminddb.git && \
                                    run cd libmaxminddb || return 1
                                else
                                    run cd libmaxminddb && \
                                    run git pull -q
                                fi

                                run ./bootstrap && \
                                run ./configure && \
                                run make -j"${NB_PROC}" && \
                                run make install && \
                                run bash -c "echo /usr/local/lib  >> /etc/ld.so.conf.d/local.conf" && \
                                run ldconfig && \
                                run cd ../ || return 1
                            fi

                            echo "Downloading MaxMind GeoIP2-GeoLite2 database..."

                            run mkdir -p geoip-db && \
                            run cd geoip-db && \
                            run mkdir -p /opt/geoip

                            # Download MaxMind GeoLite2 database.
                            GEOLITE2_COUNTRY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"
                            if curl -sLI "${GEOLITE2_COUNTRY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
                                #run wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz && \
                                run wget -q "${GEOLITE2_COUNTRY_SRC}" -O GeoLite2-Country.tar.gz && \
                                run tar -xf GeoLite2-Country.tar.gz && \
                                run cd GeoLite2-Country_*/ && \
                                run mv GeoLite2-Country.mmdb /opt/geoip/ && \
                                run cd ../ || return 1
                            fi

                            GEOLITE2_CITY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"
                            if curl -sLI "${GEOLITE2_CITY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
                                #run wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz && \
                                run wget -q "${GEOLITE2_CITY_SRC}" -O GeoLite2-City.tar.gz && \
                                run tar -xf GeoLite2-City.tar.gz && \
                                run cd GeoLite2-City_*/ && \
                                run mv GeoLite2-City.mmdb /opt/geoip/
                            fi

                            run cd "${EXTRA_MODULE_DIR}" && \

                            if [[ -f /opt/geoip/GeoLite2-City.mmdb && -f /opt/geoip/GeoLite2-Country.mmdb ]]; then
                                success "MaxMind GeoIP2-GeoLite2 database successfully installed."
                            else
                                error "Failed installing MaxMind GeoIP2-GeoLite2 database."
                            fi
                        fi

                        # Headers more module.
                        if "${NGX_HTTP_HEADERS_MORE}"; then
                            echo "Adding ngx-http-headers-more-filter module..."

                            run git clone -q https://github.com/openresty/headers-more-nginx-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/headers-more-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/headers-more-nginx-module"
                            fi
                        fi

                        # HTTP Image Filter module.
                        if "${NGX_HTTP_IMAGE_FILTER}"; then
                            echo "Adding ngx-http-image-filter module..."

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_image_filter_module=dynamic"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_image_filter_module"
                            fi
                        fi

                        # Embed the power of Lua into Nginx HTTP Servers.
                        if "${NGX_HTTP_LUA}"; then
                            echo "Adding ngx-http-lua module..."

                            # Requires ngx-devel-kit enabled
                            NGX_HTTP_NDK=true

                            # Requires luajit lib
                            echo "Lua module requires LuaJIT 2.1 library, installing now..."

                            run cd "${BUILD_DIR}" || return 1

                            if [ ! -d luajit2 ]; then
                                run git clone -q https://github.com/openresty/luajit2.git && \
                                run cd luajit2 || return 1
                            else
                                run cd luajit2 && \
                                run git pull -q
                            fi

                            run make -j"${NB_PROC}" && \
                            run make install

                            run cd "${EXTRA_MODULE_DIR}" || return 1

                            echo "Configuring Lua Nginx Module..."

                            export LUAJIT_LIB=/usr/local/lib
                            export LUAJIT_INC=/usr/local/include/luajit-2.1
                            NGX_CONFIGURE_ARGS="--with-ld-opt=\"-Wl,-rpath,/usr/local/lib\""

                            run git clone -q https://github.com/openresty/lua-nginx-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/lua-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/lua-nginx-module"
                            fi
                        fi

                        # Openresty Memc - An extended version of the standard memcached module.
                        if "${NGX_HTTP_MEMCACHED}"; then
                            echo "Adding ngx-http-memcached module..."
                            run git clone -q https://github.com/openresty/memc-nginx-module.git
                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/memc-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/memc-nginx-module"
                            fi
                        fi

                        # NAXSI is an open-source, high performance, low rules maintenance WAF for Nginx.
                        if "${NGX_HTTP_NAXSI}"; then
                            echo "Adding ngx-http-naxsi (Web Application Firewall) module..."
                            run git clone -q https://github.com/nbs-system/naxsi.git
                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/naxsi/naxsi_src"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/naxsi/naxsi_src"
                            fi
                        fi

                        # NDK adds additional generic tools that module developers can use in their own modules.
                        if "${NGX_HTTP_NDK}"; then
                            echo "Adding ngx-http-ndk Nginx Devel Kit module..."
                            run git clone https://github.com/vision5/ngx_devel_kit.git
                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_devel_kit"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_devel_kit"
                            fi
                        fi

                        # NJS is a subset of the JavaScript language that allows extending nginx functionality.
                        # shellcheck disable=SC2153
                        if "${NGX_HTTP_JS}"; then
                            echo "Adding ngx-http-js module..."
                            run git clone https://github.com/nginx/njs.git
                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/njs/nginx"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/njs/nginx"
                            fi
                        fi

                        # Nginx mod HTTP Passenger.
                        if "${NGX_HTTP_PASSENGER}"; then
                            echo "Adding ngx-http-passenger module..."

                            if [[ -n $(command -v passenger-config) ]]; then
                                if "${NGINX_DYNAMIC_MODULE}"; then
                                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                        --add-dynamic-module=$(passenger-config --nginx-addon-dir)"
                                else
                                    NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                        --add-module=$(passenger-config --nginx-addon-dir)"
                                fi
                            else
                                error "Passenger module not found, skipped..."
                            fi
                        fi

                        # Openresty Redis 2.0 protocol.
                        if "${NGX_HTTP_REDIS2}"; then
                            echo "Adding ngx-http-redis2 module..."

                            run git clone -q https://github.com/openresty/redis2-nginx-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/redis2-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/redis2-nginx-module"
                            fi
                        fi

                        # A filter module which can do both regular expression and fixed string substitutions for nginx.
                        if "${NGX_HTTP_SUBS_FILTER}"; then
                            echo "Adding ngx-http-subs-filter module..."

                            run git clone -q https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_substitutions_filter_module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/ngx_http_substitutions_filter_module"
                            fi
                        fi

                        # Upstream Fair module enhances the standard round-robin load balancer provided with Nginx.
                        if "${NGX_HTTP_UPSTREAM_FAIR}"; then
                            echo "Adding ngx-http-nginx-upstream-fair module..."

                            #run git clone -q https://github.com/gnosek/nginx-upstream-fair.git
                            run git clone --branch="lemper" -q https://github.com/joglomedia/nginx-upstream-fair

                            echo "Patch nginx-upstream-fair module with tengine-patches..."
                            run git clone -q https://github.com/alibaba/tengine-patches.git

                            run cd nginx-upstream-fair && \
                            run patch -p1 < "${EXTRA_MODULE_DIR}/tengine-patches/nginx-upstream-fair/upstream-fair-upstream-check.patch"
                            run cd "${EXTRA_MODULE_DIR}" && \

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                # Dynamic module not supported yet (testing lemper branch)
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-upstream-fair"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/nginx-upstream-fair"
                            fi
                        fi

                        # Nginx virtual host traffic status module provides access to virtual host status information.
                        if "${NGX_HTTP_VTS}"; then
                            echo "Add ngxx-http-module-vts (VHost traffic status) module..."

                            run git clone -q https://github.com/vozlt/nginx-module-vts.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-module-vts"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/nginx-module-vts"
                            fi
                        fi

                        # HTTP XSLT module.
                        if "${NGX_HTTP_XSLT_FILTER}"; then
                            echo "Adding ngx-http-xslt-filter module..."

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_xslt_module=dynamic"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-http_xslt_module"
                            fi
                        fi

                        # Mail module.
                        if "${NGX_MAIL}"; then
                            echo "Adding ngx-mail module..."

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-mail=dynamic \
                                    --with-mail_ssl_module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-mail \
                                    --with-mail_ssl_module"
                            fi
                        fi

                        # Nchan pub/sub queuing server.
                        if "${NGX_NCHAN}"; then
                            echo "Adding ngx-nchan (Pub/Sub) module..."

                            run git clone -q https://github.com/slact/nchan.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/nchan"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/nchan"
                            fi
                        fi

                        # RTMP media streaming server.
                        if "${NGX_RTMP}"; then
                            echo "Adding ngx-rtmp (Media Streaming Server) module..."

                            run git clone -q https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/nginx-rtmp-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/nginx-rtmp-module"
                            fi
                        fi

                        # Stream module.
                        if "${NGX_STREAM}"; then
                            echo "Adding ngx-stream module..."

                            if "${NGINX_DYNAMIC_MODULE}"; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-stream=dynamic \
                                    --with-stream_geoip_module=dynamic \
                                    --with-stream_realip_module \
                                    --with-stream_ssl_module \
                                    --with-stream_ssl_preread_module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --with-stream \
                                    --with-stream_geoip_module \
                                    --with-stream_realip_module \
                                    --with-stream_ssl_module \
                                    --with-stream_ssl_preread_module"
                            fi
                        fi
                    fi

                    run cd "${CURRENT_DIR}" && \

                    # Build nginx from source installer.
                    echo -e "\nBuilding Nginx from source..."

                    #NGX_BUILD_URL="https://raw.githubusercontent.com/pagespeed/ngx_pagespeed/master/scripts/build_ngx_pagespeed.sh"
                    NGX_BUILD_URL="https://raw.githubusercontent.com/apache/incubator-pagespeed-ngx/master/scripts/build_ngx_pagespeed.sh"

                    if curl -sLI "${NGX_BUILD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sS -o "${BUILD_DIR}/build_nginx" "${NGX_BUILD_URL}" && \
                        run bash "${BUILD_DIR}/build_nginx" -v latest-stable -n "${NGINX_RELEASE_VERSION}" --dynamic-module \
                            -b "${BUILD_DIR}" -a "${NGX_CONFIGURE_ARGS}" -y
                    else
                        error "Nginx from source installer not found."
                    fi
                fi

                echo "Configuring Nginx extra modules..."

                # Create Nginx directories.
                if [ ! -d /etc/nginx/modules-available ]; then
                    run mkdir -p /etc/nginx/modules-available
                    run chmod 755 /etc/nginx/modules-available
                fi

                if [ ! -d /etc/nginx/modules-enabled ]; then
                    run mkdir -p /etc/nginx/modules-enabled
                    run chmod 755 /etc/nginx/modules-enabled
                fi

                # Custom Nginx dynamic modules configuration.

                if [[ -f /usr/lib/nginx/modules/ndk_http_module.so && \
                    ! -f /etc/nginx/modules-available/mod-ndk-http.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ndk_http_module.so\";' \
                        > /etc/nginx/modules-available/mod-ndk-http.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_auth_pam_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-auth-pam.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_auth_pam_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-auth-pam.conf"
                fi

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

                if [[ -f /usr/lib/nginx/modules/ngx_http_dav_ext_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-dav-ext.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_dav_ext_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-dav-ext.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_echo_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-echo.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_echo_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-echo.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_http_geoip2_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-geoip2.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_geoip2_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-geoip2.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_http_subs_filter_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-subs-filter.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_subs_filter_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-subs-filter.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_upstream_fair_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-upstream-fair.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_upstream_fair_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-upstream-fair.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_vhost_traffic_status_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-vhost-traffic-status.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_vhost_traffic_status_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-vhost-traffic-status.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_nchan_module.so && \
                    ! -f /etc/nginx/modules-available/mod-nchan.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_nchan_module.so\";' \
                        > /etc/nginx/modules-available/mod-nchan.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_pagespeed.so && \
                    ! -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_pagespeed.so\";' \
                        > /etc/nginx/modules-available/mod-pagespeed.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_rtmp_module.so && \
                    ! -f /etc/nginx/modules-available/mod-rtmp.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_rtmp_module.so\";' \
                        > /etc/nginx/modules-available/mod-rtmp.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_stream_geoip2_module.so && \
                    ! -f /etc/nginx/modules-available/mod-stream-geoip2.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_geoip2_module.so\";' \
                        > /etc/nginx/modules-available/mod-stream-geoip2.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_stream_geoip_module.so && \
                    ! -f /etc/nginx/modules-available/mod-stream-geoip.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_geoip_module.so\";' \
                        > /etc/nginx/modules-available/mod-stream-geoip.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && \
                    ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";' \
                        > /etc/nginx/modules-available/mod-stream.conf"
                fi

                # Enable Nginx Dynamic Module.
                if "${NGINX_DYNAMIC_MODULE}"; then
                    ENABLE_NGXDM=y
                else
                    echo ""
                    while [[ "${ENABLE_NGXDM}" != "y" && "${ENABLE_NGXDM}" != "n" ]]; do
                        read -rp "Enable Nginx dynamic modules? [y/n]: " -i y -e ENABLE_NGXDM
                    done
                fi

                # Enable Dynamic modules.
                if [[ "${ENABLE_NGXDM}" == Y* || "${ENABLE_NGXDM}" == y* ]]; then
                    if [[ "${NGX_HTTP_AUTH_PAM}" && \
                        -f /etc/nginx/modules-available/mod-http-auth-pam.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-auth-pam.conf \
                            /etc/nginx/modules-enabled/60-mod-http-auth-pam.conf
                    fi

                    if [[ "${NGX_HTTP_BROTLI}" && \
                        -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-brotli-filter.conf \
                            /etc/nginx/modules-enabled/20-mod-http-brotli-filter.conf
                    fi

                    if [[ "${NGX_HTTP_BROTLI}" && \
                        -f /etc/nginx/modules-available/mod-http-brotli-static.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-brotli-static.conf \
                            /etc/nginx/modules-enabled/20-mod-http-brotli-static.conf
                    fi

                    if [[ "${NGX_HTTP_CACHE_PURGE}" && \
                        -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-cache-purge.conf \
                            /etc/nginx/modules-enabled/50-mod-http-cache-purge.conf
                    fi

                    if [[ "${NGX_HTTP_DAV_EXT}" && \
                        -f /etc/nginx/modules-available/mod-http-dav-ext.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-dav-ext.conf \
                            /etc/nginx/modules-enabled/60-mod-http-dav-ext.conf
                    fi

                    if [[ "${NGX_HTTP_ECHO}" && \
                        -f /etc/nginx/modules-available/mod-http-echo.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-echo.conf \
                            /etc/nginx/modules-enabled/60-mod-http-echo.conf
                    fi

                    if [[ "${NGX_HTTP_FANCYINDEX}" && \
                        -f /etc/nginx/modules-available/mod-http-fancyindex.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-fancyindex.conf \
                            /etc/nginx/modules-enabled/40-mod-http-fancyindex.conf
                    fi

                    if [[ "${NGX_HTTP_GEOIP2}" && \
                        -f /etc/nginx/modules-available/mod-http-geoip2.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-geoip2.conf \
                            /etc/nginx/modules-enabled/50-mod-http-geoip2.conf
                    fi

                    if [[ "${NGX_HTTP_GEOIP}" && \
                        -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-geoip.conf \
                            /etc/nginx/modules-enabled/50-mod-http-geoip.conf
                    fi

                    if [[ "${NGX_HTTP_HEADERS_MORE}" && \
                        -f /etc/nginx/modules-available/mod-http-headers-more-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-headers-more-filter.conf \
                            /etc/nginx/modules-enabled/40-mod-http-headers-more-filter.conf
                    fi

                    if [[ "${NGX_HTTP_IMAGE_FILTER}" && \
                        -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-image-filter.conf \
                            /etc/nginx/modules-enabled/50-mod-http-image-filter.conf
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

                    if [[ "${NGX_HTTP_SUBS_FILTER}" && \
                        -f /etc/nginx/modules-available/mod-http-subs-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-subs-filter.conf \
                            /etc/nginx/modules-enabled/40-mod-http-subs-filter.conf
                    fi

                    if [[ "${NGX_HTTP_UPSTREAM_FAIR}" && \
                        -f /etc/nginx/modules-available/mod-http-upstream-fair.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-upstream-fair.conf \
                            /etc/nginx/modules-enabled/40-mod-http-upstream-fair.conf
                    fi

                    if [[ "${NGX_HTTP_VTS}" && \
                        -f /etc/nginx/modules-available/mod-http-vhost-traffic-status.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-vhost-traffic-status.conf \
                            /etc/nginx/modules-enabled/40-mod-http-vhost-traffic-status.conf
                    fi

                    if [[ "${NGX_HTTP_XSLT_FILTER}" && \
                        -f /etc/nginx/modules-available/mod-http-xslt-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-xslt-filter.conf \
                            /etc/nginx/modules-enabled/50-mod-http-xslt-filter.conf
                    fi

                    if [[ "${NGX_MAIL}" && \
                        -f /etc/nginx/modules-available/mod-mail.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-mail.conf \
                            /etc/nginx/modules-enabled/50-mod-mail.conf
                    fi

                    if [[ "${NGX_NCHAN}" && \
                        -f /etc/nginx/modules-available/mod-nchan.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-nchan.conf \
                            /etc/nginx/modules-enabled/50-mod-nchan.conf
                    fi

                    if [[ "${NGX_PAGESPEED}" && \
                        -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-pagespeed.conf \
                            /etc/nginx/modules-enabled/50-mod-pagespeed.conf
                    fi

                    if [[ "${NGX_STREAM}" && \
                        -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-stream.conf \
                            /etc/nginx/modules-enabled/50-mod-stream.conf

                        if [[ "${NGX_HTTP_GEOIP2}" && \
                            -f /etc/nginx/modules-available/mod-stream-geoip2.conf ]]; then
                            run ln -fs /etc/nginx/modules-available/mod-stream-geoip2.conf \
                                /etc/nginx/modules-enabled/60-mod-stream-geoip2.conf
                        fi

                        if [[ "${NGX_HTTP_GEOIP}" && \
                            -f /etc/nginx/modules-available/mod-stream-geoip.conf ]]; then
                            run ln -fs /etc/nginx/modules-available/mod-stream-geoip.conf \
                                /etc/nginx/modules-enabled/60-mod-stream-geoip.conf
                        fi
                    fi
                fi

                # Nginx init script.
                if [ ! -f /etc/init.d/nginx ]; then
                    run cp etc/init.d/nginx /etc/init.d/
                    run chmod ugo+x /etc/init.d/nginx
                fi

                # Nginx systemd script.
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

                # Masked (?).
                run systemctl unmask nginx.service
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. Nginx installation skipped."
            ;;
        esac

        echo "Creating Nginx configuration..."

        if [ ! -d /etc/nginx/sites-available ]; then
            run mkdir -p /etc/nginx/sites-available
        fi

        if [ ! -d /etc/nginx/sites-enabled ]; then
            run mkdir -p /etc/nginx/sites-enabled
        fi

        # Copy custom Nginx Config.
        if [ -f /etc/nginx/nginx.conf ]; then
            run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf~
        fi

        run cp -f etc/nginx/nginx.conf /etc/nginx/
        run cp -f etc/nginx/charset /etc/nginx/
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

        # Nginx cache directory.
        if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
            run mkdir -p /var/cache/nginx/fastcgi_cache
        fi
        if [ ! -d /var/cache/nginx/proxy_cache ]; then
            run mkdir -p /var/cache/nginx/proxy_cache
        fi

        # Fix ownership.
        run chown -hR www-data:www-data /var/cache/nginx

        # Adjust nginx to meet hardware resources.
        echo "Adjusting Nginx configuration..."

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

        # Enable more headers setting.
        if [[ "${NGX_HTTP_HEADERS_MORE}" && \
            -f /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf ]]; then
            run sed -i "s|#more_set_headers|more_set_headers|g" \
                /etc/nginx/nginx.conf
        fi

        # Enable PageSpeed config.
        if [[ "${NGX_PAGESPEED}" && \
            -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
            run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" \
                /etc/nginx/nginx.conf
        fi

        # Allow server IP to fastCGI cache purge rule.
        run sed -i "s/#allow\ SERVER_IP/allow\ ${SERVER_IP}/g" /etc/nginx/includes/rules_fastcgi_cache.conf

        # Generate Diffie-Hellman parameters.
        local DH_LENGTH=${KEY_HASH_LENGTH:-2048}
        if [ ! -f "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" ]; then
            echo "Enhancing HTTPS/SSL security with DH key..."

            [ ! -d /etc/nginx/ssl ] && mkdir -p /etc/nginx/ssl
            run openssl dhparam -dsaparam -out "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" "${DH_LENGTH}"
        fi

        # Final test.
        if "${DRYRUN}"; then
            info "Nginx HTTP server installed in dryrun mode."
        else
            # Make default server accessible from hostname or IP address.
            if [[ $(dig "${HOSTNAME}" +short) = "${SERVER_IP}" ]]; then
                run sed -i "s/localhost.localdomain/${HOSTNAME}/g" /etc/nginx/sites-available/default
            else
                run sed -i "s/localhost.localdomain/${SERVER_IP}/g" /etc/nginx/sites-available/default
            fi

            # Restart Nginx server
            echo "Starting Nginx HTTP server for ${HOSTNAME} (${SERVER_IP})..."

            if [[ $(pgrep -c nginx) -gt 0 ]]; then
                if nginx -t 2>/dev/null > /dev/null; then
                    run systemctl reload nginx
                    success "Nginx HTTP server restarted successfully."
                else
                    error "Nginx configuration test failed. Please correct the error below:"
                    run nginx -t
                fi
            elif [[ -n $(command -v nginx) ]]; then
                if nginx -t 2>/dev/null > /dev/null; then
                    run systemctl start nginx

                    if [[ $(pgrep -c nginx) -gt 0 ]]; then
                        success "Nginx HTTP server started successfully."
                    else
                        info "Something went wrong with Nginx installation."
                    fi
                else
                    error "Nginx configuration test failed. Please correct the error below:"
                    run nginx -t
                fi
            else
                error "Nginx configuration test failed. Please correct the error below:"
                run nginx -t
            fi
        fi
    else
        info "Nginx HTTP (web) server installation skipped."
    fi
}

echo "[Nginx HTTP (Web) Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available ]]; then
    info "Nginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
