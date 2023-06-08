#!/usr/bin/env bash

# Nginx Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
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

##
# Add Ondrej's Nginx repository.
##
function add_nginx_repo_ondrej() {
    echo "Add Ondrej's Nginx repository..."

    # Nginx version.
    local NGINX_VERSION=${NGINX_VERSION:-"stable"}

    if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
        local NGINX_REPO="nginx-mainline"
    else
        local NGINX_REPO="nginx"
    fi

    case "${DISTRIB_NAME}" in
        debian)
            if [[ ! -f "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list" ]]; then
                run touch "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb https://packages.sury.org/${NGINX_REPO}/ ${RELEASE_NAME} main' > /etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
                run wget -qO "/etc/apt/trusted.gpg.d/${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKG="nginx-core"
        ;;
        ubuntu)
            # Nginx custom with ngx cache purge from Ondrej repo.
            run wget -qO "/etc/apt/trusted.gpg.d/${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg"
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C
            run add-apt-repository -y "ppa:ondrej/${NGINX_REPO}"
            run apt-get update -q -y
            NGINX_PKG="nginx-core"
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Add MyGuard's Nginx repository.
##
function add_nginx_repo_myguard() {
    echo "Add MyGuard's Nginx repository..."

    # Nginx version.
    NGINX_VERSION=${NGINX_VERSION:-"stable"}

    if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
        local NGINX_REPO="nginx"
    else
        local NGINX_REPO="nginx"
    fi

    DISTRIB_ARCH=$(get_distrib_arch)

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list" ]]; then
                run touch "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH}] http://deb.myguard.nl ${RELEASE_NAME} main' > /etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH}] http://deb.myguard.nl/openssl3 ${RELEASE_NAME} main' >> /etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
                run wget -qO "/etc/apt/trusted.gpg.d/deb.myguard.nl.gpg" "https://deb.myguard.nl/pool/deb.myguard.nl.gpg"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKG="nginx-core"
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Initialize Nginx installation.
##
function init_nginx_install() {
    local SELECTED_INSTALLER=${NGINX_INSTALLER:-"source"}
    local SELECTED_REPO="ondrej"

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ -z "${NGINX_INSTALLER}" || "${NGINX_INSTALLER}" == "none" ]]; then
            DO_INSTALL_NGINX="n"
        else
            DO_INSTALL_NGINX="y"
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

        # NgxPageSpeed module currently available from source install or MyGuard repo.
        if [[ "${NGX_PAGESPEED}" == true ]]; then
            info "NGX_PAGESPEED module requires Nginx to be installed from source or MyGuard repo."

            if [[ "${NGINX_INSTALLER}" == "repo" ]]; then
                # MyGuard repo only support mainline version.
                echo "Switch Nginx repo to the mainline/latest version."

                SELECTED_INSTALLER="repo"
                SELECTED_REPO="myguard"
            else
                SELECTED_INSTALLER="source"
            fi
        fi

        case "${SELECTED_INSTALLER}" in
            1|"repo")

                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                    add_nginx_repo_myguard
                else
                    add_nginx_repo_ondrej
                fi

                echo "Installing Nginx from ${SELECTED_REPO} repository..."

                #if hash apt-get 2>/dev/null; then
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

                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-brotli")
                                else
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-brotli")
                                fi
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
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip" "libnginx-mod-stream-geoip")
                            fi

                            # GeoIP2
                            if "${NGX_HTTP_GEOIP2}"; then
                                echo "Adding ngx-http-geoip2 module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip2" "libnginx-mod-stream-geoip2")
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

                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "lua-resty" "lua-resty-lrucache" "libnginx-mod-http-lua")
                                else
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "luajit" "libluajit" "libnginx-mod-http-lua")
                                fi
                            fi

                            # Nginx Memc - An extended version of the standard memcached module.
                            if "${NGX_HTTP_MEMCACHED}"; then
                                echo "Adding ngx-http-memcached module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-memcached")
                            fi

                            # NGX_HTTP_NAXSI is an open-source, high performance, low rules maintenance WAF for NGINX.
                            if "${NGX_HTTP_NAXSI}"; then
                                echo "Adding ngx-http-naxsi (Web Application Firewall) module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-naxsi")
                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-naxsi")
                                fi
                            fi

                            # NDK adds additional generic tools that module developers can use in their own modules.
                            if "${NGX_HTTP_NDK}"; then
                                echo "Adding ngx-http-ndk Nginx Devel Kit module..."
                                EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-ndk")
                            fi

                            # NJS is a subset of the JavaScript language that allows extending nginx functionality.
                            # shellcheck disable=SC2153
                            if "${NGX_HTTP_NJS}"; then
                                echo "Adding ngx-http-njs module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-njs")
                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-njs")
                                fi
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
                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-redis2")
                                fi
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
                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-http-vhost-traffic-status")
                                fi
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

                            # Nginx mod PageSpeed.
                            if "${NGX_PAGESPEED}"; then
                                echo "Adding ngx-pagespeed module..."
                                #EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-pagespeed")
                                if [[ "${SELECTED_REPO}" == "myguard" ]]; then
                                    EXTRA_MODULE_PKGS=("${EXTRA_MODULE_PKGS[@]}" "libnginx-mod-pagespeed")
                                fi
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
                        run apt-get install -q -y "${NGINX_PKG}" "${EXTRA_MODULE_PKGS[@]}"
                    fi
                #else
                #    fail "Unable to install Nginx, this GNU/Linux distribution is not supported."
                #fi
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
                    --with-debug \
                    --with-file-aio \
                    --with-http_addition_module \
                    --with-http_auth_request_module \
                    --with-http_dav_module \
                    --with-http_degradation_module \
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
                    NGINX_CUSTOMSSL_VERSION=${NGINX_CUSTOMSSL_VERSION:-"openssl-1.1.1l"}

                    echo "Build Nginx with custom SSL ${NGINX_CUSTOMSSL_VERSION^}..."

                    # OpenSSL
                    if grep -iq openssl <<<"${NGINX_CUSTOMSSL_VERSION}"; then
                        OPENSSL_SOURCE_URL="https://www.openssl.org/source/${NGINX_CUSTOMSSL_VERSION}.tar.gz"
                        #OPENSSL_SOURCE_URL="https://github.com/openssl/openssl/archive/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                        if curl -sLI "${OPENSSL_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
                            run wget -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${OPENSSL_SOURCE_URL}" && \
                            run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                            [[ -d "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" ]] && \
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
                        LIBRESSL_SOURCE_URL="https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                        if curl -sLI "${LIBRESSL_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
                            run wget -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${LIBRESSL_SOURCE_URL}" && \
                            run tar -zxf "${NGINX_CUSTOMSSL_VERSION}.tar.gz"

                            [[ -d "${BUILD_DIR}/${NGINX_CUSTOMSSL_VERSION}" ]] && \
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
                            GOLANG_VER="1.17.8"

                            DISTRIB_ARCH=$(get_distrib_arch)

                            case "${DISTRIB_NAME}" in
                                debian)
                                    GOLANG_DOWNLOAD_URL="https://go.dev/dl/go${GOLANG_VER}.linux-${DISTRIB_ARCH}.tar.gz"

                                    if curl -sLI "${GOLANG_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                                        run wget -O golang.tar.gz "${GOLANG_DOWNLOAD_URL}" && \
                                        run tar -C /usr/local -zxf golang.tar.gz && \
                                        run bash -c "echo -e '\nexport PATH=\"\$PATH:/usr/local/go/bin\"' >> ~/.profile" && \
                                        run source ~/.profile
                                    else
                                        info "Unable to determine Golang source page."
                                    fi
                                ;;
                                ubuntu)
                                    run add-apt-repository -y ppa:longsleep/golang-backports && \
                                    run apt-get update -q -y && \
                                    run apt-get install -q -y golang-go
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
                        [[ -z ${BORINGSSL_VERSION} || ${BORINGSSL_VERSION} == "latest" ]] && BORINGSSL_VERSION="master"
                        BORINGSSL_SOURCE_URL="https://boringssl.googlesource.com/boringssl/+archive/refs/heads/${BORINGSSL_VERSION}.tar.gz"

                        if curl -sLI "${BORINGSSL_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
                            run wget -O "${NGINX_CUSTOMSSL_VERSION}.tar.gz" "${BORINGSSL_SOURCE_URL}" && \
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
                            run cp build/crypto/libcrypto.a build/ssl/libssl.a .openssl/lib && \

                            # Back to extra module dir.
                            run cd "${EXTRA_MODULE_DIR}" || return 1

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
                    NGINX_PCRE_VERSION=${NGINX_PCRE_VERSION:-"8.45"}
                    PCRE_SOURCE_URL="https://onboardcloud.dl.sourceforge.net/project/pcre/pcre/${NGINX_PCRE_VERSION}/pcre-${NGINX_PCRE_VERSION}.tar.gz"

                    echo "Build Nginx with PCRE JIT ${NGINX_PCRE_VERSION}..."

                    if curl -sLI "${PCRE_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run wget -O "${NGINX_PCRE_VERSION}.tar.gz" "${PCRE_SOURCE_URL}" && \
                        run tar -zxf "${NGINX_PCRE_VERSION}.tar.gz"

                        if [ -d "${BUILD_DIR}/${NGINX_PCRE_VERSION}" ]; then
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} --with-pcre=${BUILD_DIR}/${NGINX_PCRE_VERSION} --with-pcre-jit"
                        fi
                    else
                        error "Unable to determine PCRE JIT ${NGINX_PCRE_VERSION} source."
                    fi
                fi

                if "${NGINX_EXTRA_MODULES}"; then
                    echo "Build Nginx with extra modules..."

                    local EXTRA_MODULE_DIR="${BUILD_DIR}/nginx_modules"

                    if [[ -d "${EXTRA_MODULE_DIR}" && "${FORCE_REMOVE}" == true ]]; then
                        run rm -rf "${EXTRA_MODULE_DIR}"
                    fi

                    run mkdir -p "${EXTRA_MODULE_DIR}" && \
                    run cd "${EXTRA_MODULE_DIR}" || return 1

                    # Auth PAM module.
                    if "${NGX_HTTP_AUTH_PAM}"; then
                        echo "Adding ngx-http-auth-pam module..."

                        run git clone --branch="master" --single-branch https://github.com/sto/ngx_http_auth_pam_module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module"
                        else
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-module=${EXTRA_MODULE_DIR}/ngx_http_auth_pam_module"
                        fi

                        # Requires libpam-dev
                        echo "Building Auth PAM module requires libpam-dev package, install now..."

                        run apt-get install -q -y libpam-dev
                    fi

                    # Brotli compression module.
                    if "${NGX_HTTP_BROTLI}"; then
                        echo "Adding ngx-http-brotli module..."

                        run git clone https://github.com/google/ngx_brotli.git && \
                        run cd ngx_brotli && \
                        run git checkout master -q && \
                        run git submodule update --init -q && \
                        run cd ../ || return 1

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/nginx-modules/ngx_cache_purge.git
                        #run git clone https://github.com/joglomedia/ngx_cache_purge.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/arut/nginx-dav-ext-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/openresty/echo-nginx-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/aperezdc/ngx-fancyindex.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/leev/ngx_http_geoip2_module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module"
                        else
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-module=${EXTRA_MODULE_DIR}/ngx_http_geoip2_module"
                        fi

                        # install libmaxminddb
                        echo "GeoIP2 module requires MaxMind GeoIP2 library, install now..."

                        run cd "${BUILD_DIR}" || return 1

                        DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}

                        if [[ "${DISTRIB_NAME}" == "ubuntu" ]]; then
                            run add-apt-repository -y ppa:maxmind/ppa && \
                            run apt-get update -q -y && \
                            run apt-get install -q -y libmaxminddb0 libmaxminddb-dev mmdb-bin
                        else
                            if [ ! -d libmaxminddb ]; then
                                run git clone --recursive https://github.com/maxmind/libmaxminddb.git && \
                                run cd libmaxminddb || return 1
                            else
                                run cd libmaxminddb && \
                                run git pull
                            fi

                            run ./bootstrap && \
                            run ./configure && \
                            run make -j"${NB_PROC}" && \
                            run make install && \
                            run bash -c "echo /usr/local/lib >> /etc/ld.so.conf.d/local.conf" && \
                            run ldconfig && \
                            run cd ../ || return 1
                        fi

                        echo "Downloading MaxMind GeoIP2-GeoLite2 database..."

                        if [ -d geoip-db ]; then
                            run rm -rf geoip-db
                        fi

                        run mkdir -p geoip-db && \
                        run cd geoip-db && \
                        run mkdir -p /opt/geoip

                        # Download MaxMind GeoLite2 database.
                        if [[ ! -f GeoLite2-City.tar.gz ]]; then
                            GEOLITE2_COUNTRY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"

                            if curl -sLI "${GEOLITE2_COUNTRY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
                                run wget "${GEOLITE2_COUNTRY_SRC}" -O GeoLite2-Country.tar.gz && \
                                run tar -xf GeoLite2-Country.tar.gz && \
                                run cd GeoLite2-Country_*/ && \
                                run mv GeoLite2-Country.mmdb /opt/geoip/ && \
                                run cd ../ || return 1
                            fi
                        fi

                        if [[ ! -f GeoLite2-City.tar.gz ]]; then
                            GEOLITE2_CITY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"

                            if curl -sLI "${GEOLITE2_CITY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
                                run wget "${GEOLITE2_CITY_SRC}" -O GeoLite2-City.tar.gz && \
                                run tar -xf GeoLite2-City.tar.gz && \
                                run cd GeoLite2-City_*/ && \
                                run mv GeoLite2-City.mmdb /opt/geoip/
                            fi
                        fi

                        run cd "${EXTRA_MODULE_DIR}" || return 1

                        if [[ -f /opt/geoip/GeoLite2-City.mmdb && -f /opt/geoip/GeoLite2-Country.mmdb ]]; then
                            success "MaxMind GeoIP2-GeoLite2 database successfully installed."
                        else
                            error "Failed installing MaxMind GeoIP2-GeoLite2 database."
                        fi
                    fi

                    # Headers more module.
                    if "${NGX_HTTP_HEADERS_MORE}"; then
                        echo "Adding ngx-http-headers-more-filter module..."

                        run git clone --branch="master" --single-branch https://github.com/openresty/headers-more-nginx-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        LUA_JIT_VERSION=${LUA_JIT_VERSION:-"v2.1-20211210"}
                        LUA_RESTY_CORE_VERSION=${LUA_RESTY_CORE_VERSION:-"v0.1.22"}
                        LUA_RESTY_LRUCACHE_VERSION=${LUA_RESTY_LRUCACHE_VERSION:-"v0.11"}

                        # Requires ngx-devel-kit enabled
                        NGX_HTTP_NDK=true

                        # Requires luajit library
                        echo "Lua module requires LuaJIT 2.1 library, installing now..."

                        run cd "${BUILD_DIR}" || return 1

                        if [ ! -d luajit2 ]; then
                            run git clone https://github.com/openresty/luajit2.git && \
                            run cd luajit2 || return 1
                        else
                            run cd luajit2 && \
                            run git fetch -q --all --tags
                        fi

                        run git checkout "tags/${LUA_JIT_VERSION}" && \
                        run make -j"${NB_PROC}" && \
                        run make install

                        # Requires lua core library
                        echo "Lua module requires Lua Resty Core library, installing now..."

                        if [ ! -d lua-resty-core ]; then
                            run git clone https://github.com/openresty/lua-resty-core.git && \
                            run cd lua-resty-core || return 1
                        else
                            run cd lua-resty-core && \
                            run git fetch -q --all --tags
                        fi

                        run git checkout "tags/${LUA_RESTY_CORE_VERSION}" && \
                        run make install && \
                        run cd ../ || return 1

                        # Requires lua lru cache
                        echo "Lua module requires Lua-land LRU Cache library, installing now..."

                        if [ ! -d lua-resty-lrucache ]; then
                            run git clone https://github.com/openresty/lua-resty-lrucache.git && \
                            run cd lua-resty-lrucache || return 1
                        else
                            run cd lua-resty-lrucache && \
                            run git fetch -q --all --tags
                        fi

                        run git checkout "tags/${LUA_RESTY_LRUCACHE_VERSION}" && \
                        run make install && \
                        run cd "${EXTRA_MODULE_DIR}" || return 1

                        echo "Configuring Lua Nginx Module..."

                        export LUAJIT_LIB=/usr/local/lib
                        export LUAJIT_INC=/usr/local/include/luajit-2.1
                        NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} --with-ld-opt=\"-Wl,-rpath,/usr/local/lib\""

                        run git clone --branch="${LUA_NGINX_MODULE_VERSION}" --single-branch \
                        https://github.com/openresty/lua-nginx-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/openresty/memc-nginx-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/nbs-system/naxsi.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/vision5/ngx_devel_kit.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-dynamic-module=${EXTRA_MODULE_DIR}/ngx_devel_kit"
                        else
                            NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                --add-module=${EXTRA_MODULE_DIR}/ngx_devel_kit"
                        fi
                    fi

                    # NJS is a subset of the JavaScript language that allows extending nginx functionality.
                    # shellcheck disable=SC2153
                    if "${NGX_HTTP_NJS}"; then
                        echo "Adding ngx-http-js module..."

                        run git clone --branch="master" --single-branch https://github.com/nginx/njs.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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
                            if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/openresty/redis2-nginx-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        #run git clone https://github.com/gnosek/nginx-upstream-fair.git
                        run git clone --branch="lemper" https://github.com/joglomedia/nginx-upstream-fair

                        echo "Patch nginx-upstream-fair module with tengine-patches..."
                        run git clone --branch="master" --single-branch https://github.com/alibaba/tengine-patches.git

                        run cd nginx-upstream-fair && \
                        run bash -c "patch -p1 < '${EXTRA_MODULE_DIR}/tengine-patches/nginx-upstream-fair/upstream-fair-upstream-check.patch'"
                        run cd "${EXTRA_MODULE_DIR}" || return 1

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/vozlt/nginx-module-vts.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/slact/nchan.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        run git clone --branch="master" --single-branch https://github.com/arut/nginx-rtmp-module.git

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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

                        if "${NGX_HTTP_LUA}"; then
                            echo "Adding ngx-stream-lua module..."

                            run git clone --branch="master" --single-branch https://github.com/openresty/stream-lua-nginx-module.git

                            if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-dynamic-module=${EXTRA_MODULE_DIR}/stream-lua-nginx-module"
                            else
                                NGX_CONFIGURE_ARGS="${NGX_CONFIGURE_ARGS} \
                                    --add-module=${EXTRA_MODULE_DIR}/stream-lua-nginx-module"
                            fi
                        fi
                    fi
                fi

                run cd "${CURRENT_DIR}" || return 1

                # Build nginx from source installer.
                echo -e "\nBuilding Nginx from source..."

                NGX_BUILD_URL="https://raw.githubusercontent.com/apache/incubator-pagespeed-ngx/master/scripts/build_ngx_pagespeed.sh"

                if [[ -f "${BUILD_DIR}/build_nginx.sh" ]]; then
                    echo "Using cached build_nginx script..."
                else
                    if [[ -f "${PWD}/scripts/build_nginx.sh" ]]; then
                        echo "Copying custom build_nginx script..."
                        run cp "${PWD}/scripts/build_nginx.sh" "${BUILD_DIR}/build_nginx.sh"
                    else
                        echo "Downloading build_nginx script..."

                        if curl -sLI "${NGX_BUILD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                            run curl -sS -o "${BUILD_DIR}/build_nginx.sh" "${NGX_BUILD_URL}"
                        else
                            fail "Nginx from source installer not found."
                        fi
                    fi
                fi

                NGX_PAGESPEED_VERSION=${NGX_PAGESPEED_VERSION:-"latest-stable"}
                NGX_BUILD_EXTRA_ARGS=()

                # Workaround for NPS issue https://github.com/apache/incubator-pagespeed-ngx/issues/1752
                if ! version_older_than "${NGINX_RELEASE_VERSION}" "1.22.99"; then
                    NGX_PAGESPEED_VERSION="latest-stable"
                    # --psol-from-source
                    NGX_BUILD_EXTRA_ARGS+=("-s" "-t Release")
                fi

                # Workaround for Building on newer glibc (eg. Ubuntu 21.10 and above)
                # issue https://github.com/apache/incubator-pagespeed-ngx/issues/1743
                if [[ "${RELEASE_NAME}" == "jammy" ]]; then
                    export PSOL_BINARY_URL && \
                        PSOL_BINARY_URL="https://www.tiredofit.nl/psol-jammy.tar.gz"
                fi

                [[ "${NGINX_DYNAMIC_MODULE}" == true ]] && NGX_BUILD_EXTRA_ARGS+=("--dynamic-module")
                [[ "${DRYRUN}" == true ]] && NGX_BUILD_EXTRA_ARGS+=("--dryrun")

                # Build Nginx from source.
                run bash "${BUILD_DIR}/build_nginx.sh" -y "${NGX_BUILD_EXTRA_ARGS[@]}" -b "${BUILD_DIR}" \
                    --ngx-pagespeed-version="${NGX_PAGESPEED_VERSION}" --nginx-version="${NGINX_RELEASE_VERSION}" \
                    --additional-nginx-configure-arguments="${NGX_CONFIGURE_ARGS}"

                echo "Configuring Nginx extra modules..."

                # Create Nginx modules directory.

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
                    ! -f /etc/nginx/modules-available/mod-http-ndk.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ndk_http_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-ndk.conf"
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
                    ! -f /etc/nginx/modules-available/mod-http-brotli.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_brotli_static_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-brotli.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_http_js_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-njs.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_js_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-njs.conf"
                fi

                if [[ -f /usr/lib/nginx/modules/ngx_http_lua_module.so && \
                    ! -f /etc/nginx/modules-available/mod-http-lua.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_http_lua_module.so\";' \
                        > /etc/nginx/modules-available/mod-http-lua.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && \
                    ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";' \
                        > /etc/nginx/modules-available/mod-stream.conf"
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

                if [[ -f /usr/lib/nginx/modules/ngx_stream_js_module.so && \
                    ! -f /etc/nginx/modules-available/mod-stream-js.conf ]]; then
                    run bash -c "echo 'load_module \"/usr/lib/nginx/modules/ngx_stream_js_module.so\";' \
                        > /etc/nginx/modules-available/mod-stream-js.conf"
                fi

                # Enable Nginx Dynamic Module.
                if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
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
                            /etc/nginx/modules-enabled/50-mod-http-auth-pam.conf
                    fi

                    if [[ "${NGX_HTTP_BROTLI}" && \
                        -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-brotli-filter.conf \
                            /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf
                    fi

                    if [[ "${NGX_HTTP_BROTLI}" && \
                        -f /etc/nginx/modules-available/mod-http-brotli.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-brotli.conf \
                            /etc/nginx/modules-enabled/50-mod-http-brotli.conf
                    fi

                    if [[ "${NGX_HTTP_CACHE_PURGE}" && \
                        -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-cache-purge.conf \
                            /etc/nginx/modules-enabled/40-mod-http-cache-purge.conf
                    fi

                    if [[ "${NGX_HTTP_DAV_EXT}" && \
                        -f /etc/nginx/modules-available/mod-http-dav-ext.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-dav-ext.conf \
                            /etc/nginx/modules-enabled/50-mod-http-dav-ext.conf
                    fi

                    if [[ "${NGX_HTTP_ECHO}" && \
                        -f /etc/nginx/modules-available/mod-http-echo.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-echo.conf \
                            /etc/nginx/modules-enabled/50-mod-http-echo.conf
                    fi

                    if [[ "${NGX_HTTP_FANCYINDEX}" && \
                        -f /etc/nginx/modules-available/mod-http-fancyindex.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-fancyindex.conf \
                            /etc/nginx/modules-enabled/50-mod-http-fancyindex.conf
                    fi

                    if [[ "${NGX_HTTP_GEOIP2}" && \
                        -f /etc/nginx/modules-available/mod-http-geoip2.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-geoip2.conf \
                            /etc/nginx/modules-enabled/30-mod-http-geoip2.conf
                    fi

                    if [[ "${NGX_HTTP_GEOIP}" && \
                        -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-geoip.conf \
                            /etc/nginx/modules-enabled/30-mod-http-geoip.conf
                    fi

                    if [[ "${NGX_HTTP_HEADERS_MORE}" && \
                        -f /etc/nginx/modules-available/mod-http-headers-more-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-headers-more-filter.conf \
                            /etc/nginx/modules-enabled/40-mod-http-headers-more-filter.conf
                    fi

                    if [[ "${NGX_HTTP_IMAGE_FILTER}" && \
                        -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-image-filter.conf \
                            /etc/nginx/modules-enabled/40-mod-http-image-filter.conf
                    fi

                    if [[ "${NGX_HTTP_NJS}" && \
                        -f /etc/nginx/modules-available/mod-http-njs.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-njs.conf \
                            /etc/nginx/modules-enabled/30-mod-http-njs.conf
                    fi

                    if [[ "${NGX_HTTP_LUA}" && \
                        -f /etc/nginx/modules-available/mod-http-lua.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-lua.conf \
                            /etc/nginx/modules-enabled/30-mod-http-lua.conf
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

                    if [[ "${NGX_HTTP_NDK}" && \
                        -f /etc/nginx/modules-available/mod-http-ndk.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-http-ndk.conf \
                            /etc/nginx/modules-enabled/20-mod-http-ndk.conf
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
                            /etc/nginx/modules-enabled/40-mod-http-xslt-filter.conf
                    fi

                    if [[ "${NGX_MAIL}" && \
                        -f /etc/nginx/modules-available/mod-mail.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-mail.conf \
                            /etc/nginx/modules-enabled/60-mod-mail.conf
                    fi

                    if [[ "${NGX_NCHAN}" && \
                        -f /etc/nginx/modules-available/mod-nchan.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-nchan.conf \
                            /etc/nginx/modules-enabled/60-mod-nchan.conf
                    fi

                    if [[ "${NGX_PAGESPEED}" && \
                        -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                        run ln -fs /etc/nginx/modules-available/mod-pagespeed.conf \
                            /etc/nginx/modules-enabled/60-mod-pagespeed.conf
                    fi

                    local MOD_STREAM_ENABLED=false

                    if [[ "${NGX_STREAM}" && \
                        -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                        # Enable mod-stream if it's not already enabled.
                        run ln -fs /etc/nginx/modules-available/mod-stream.conf \
                            /etc/nginx/modules-enabled/20-mod-stream.conf

                        if [[ "${NGX_HTTP_GEOIP2}" && \
                            -f /etc/nginx/modules-available/mod-stream-geoip2.conf ]]; then
                            run ln -fs /etc/nginx/modules-available/mod-stream-geoip2.conf \
                                /etc/nginx/modules-enabled/50-mod-stream-geoip2.conf
                        fi

                        if [[ "${NGX_HTTP_GEOIP}" && \
                            -f /etc/nginx/modules-available/mod-stream-geoip.conf ]]; then
                            run ln -fs /etc/nginx/modules-available/mod-stream-geoip.conf \
                                /etc/nginx/modules-enabled/50-mod-stream-geoip.conf
                        fi

                        if [[ "${NGX_HTTP_NJS}" && \
                            -f /etc/nginx/modules-available/mod-stream-js.conf ]]; then
                            run ln -fs /etc/nginx/modules-available/mod-stream-js.conf \
                                /etc/nginx/modules-enabled/50-mod-stream-js.conf.conf
                        fi

                        MOD_STREAM_ENABLED=true
                    fi
                fi
            ;;
            *)
                # Skip installation.
                fail "Installer method not supported. Nginx installation failed."
            ;;
        esac

        echo "Creating Nginx configuration..."

        # Copy custom Nginx config.
        [ -f /etc/nginx/nginx.conf ] && run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf~
        run cp -f etc/nginx/nginx.conf /etc/nginx/
        run cp -f etc/nginx/charset /etc/nginx/
        run cp -f etc/nginx/{fastcgi_cache,fastcgi_https_map,fastcgi_params,mod_pagespeed,proxy_cache,proxy_params} \
            /etc/nginx/
        run cp -f etc/nginx/{http_cloudflare_ips,http_proxy_ips,upstream} /etc/nginx/
        run cp -fr etc/nginx/{conf.d,includes,vhost} /etc/nginx/

        # Copy custom index & error pages.
        [ ! -d /usr/share/nginx/html ] && run mkdir -p /usr/share/nginx/html/
        run cp -fr share/nginx/html/error-pages /usr/share/nginx/html/
        run cp -f share/nginx/html/index.html /usr/share/nginx/html/

        # Let's Encrypt acme challenge directory.
        [ ! -d /usr/share/nginx/html/.well-known ] && run mkdir -p /usr/share/nginx/html/.well-known/acme-challenge/

        # Create Nginx cache directory.
        [ ! -d /var/cache/nginx/fastcgi_cache ] && run mkdir -p /var/cache/nginx/fastcgi_cache
        [ ! -d /var/cache/nginx/proxy_cache ] && run mkdir -p /var/cache/nginx/proxy_cache

        # Create Nginx http vhost directory.
        [ ! -d /etc/nginx/sites-available ] && run mkdir -p /etc/nginx/sites-available
        [ ! -d /etc/nginx/sites-enabled ] && run mkdir -p /etc/nginx/sites-enabled

        # TODO: Add stream support.

        if [[ "${MOD_STREAM_ENABLED}" == true ]]; then
            # Create Nginx stream vhost directory.
            [ ! -d /etc/nginx/streams-available ] && run mkdir -p /etc/nginx/streams-available
            [ ! -d /etc/nginx/streams-enabled ] && run mkdir -p /etc/nginx/streams-enabled

            # Copy custom stream vhost.
            cat >> /etc/nginx/nginx.conf <<EOL

stream {
    # Load stream vhost configs.
    include /etc/nginx/streams-enabled/*;
}
EOL
        fi

        # Nginx rate limit config.
        if [[ "${NGINX_RATE_LIMITING}" == true ]]; then
            run sed -i "s|#limit_|limit_|g" /etc/nginx/nginx.conf
            run sed -i "s|rate=10r\/s|rate=${NGINX_RATE_LIMIT_REQUESTS}r\/s|g" /etc/nginx/nginx.conf
        fi

        # Custom tmp, PHP opcache & sessions dir.
        run mkdir -p /usr/share/nginx/html/.lemper/tmp
        run mkdir -p /usr/share/nginx/html/.lemper/php/sessions
        run mkdir -p /usr/share/nginx/html/.lemper/php/opcache
        run mkdir -p /usr/share/nginx/html/.lemper/php/wsdlcache

        # Fix ownership.
        [ -d /usr/share/nginx/html ] && run chown -hR www-data:www-data /usr/share/nginx/html
        [ -d /var/cache/nginx ] && run chown -hR www-data:www-data /var/cache/nginx

        # Nginx Logrotate.
        #run cp -f etc/logrotate.d/nginx /etc/logrotate.d/ && \
        #run chmod 0644 /etc/logrotate.d/nginx
        add_nginx_logrotate

        # Adjust nginx to meet hardware resources.
        echo "Customize Nginx configuration..."

        local CPU_CORES && \
        CPU_CORES=$(grep -c processor /proc/cpuinfo)

        # Adjust worker processes.
        if [[ "${CPU_CORES}" -gt 1 ]]; then
            run sed -i "s/worker_processes\ auto/worker_processes\ ${CPU_CORES}/g" /etc/nginx/nginx.conf
        fi

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
        if [[ "${NGX_HTTP_HEADERS_MORE}" == true && \
            -f /etc/nginx/modules-enabled/40-mod-http-headers-more-filter.conf ]]; then
            run sed -i "s|#more_set_headers|more_set_headers|g" \
                /etc/nginx/nginx.conf
        fi

        # Enable Lua package path.
        if [[ "${NGX_HTTP_LUA}" == true && \
            -f /etc/nginx/modules-enabled/30-mod-http-lua.conf ]]; then
            run sed -i "s|#lua_package_path|lua_package_path|g" \
                /etc/nginx/nginx.conf
        fi

        # Enable PageSpeed config.
        if [[ "${NGX_PAGESPEED}" == true && \
            -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
            run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" \
                /etc/nginx/nginx.conf
        fi

        # Allow server IP to fastCGI cache purge rule.
        run sed -i "s/#allow\ SERVER_IP/allow\ ${SERVER_IP}/g" /etc/nginx/includes/rules_fastcgi_cache.conf

        # Generate Diffie-Hellman parameters.
        local DH_LENGTH=${KEY_HASH_LENGTH:-2048}
        if [[ ! -f "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" ]]; then
            echo "Enhancing HTTPS/SSL security with DH key..."

            [ ! -d /etc/nginx/ssl ] && mkdir -p /etc/nginx/ssl
            run openssl dhparam -out "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" "${DH_LENGTH}"
        fi

        # Generate default hostname SSL cert.
        generate_hostname_cert

        # Nginx init script.
        if [ ! -f /etc/init.d/nginx ]; then
            run cp etc/init.d/nginx /etc/init.d/
            run chmod ugo+x /etc/init.d/nginx
        fi

        # Nginx systemd script.
        [ ! -f /lib/systemd/system/nginx.service ] && \
        run cp etc/systemd/nginx.service /lib/systemd/system/

        [ ! -f /etc/systemd/system/multi-user.target.wants/nginx.service ] && \
        run ln -s /lib/systemd/system/nginx.service \
            /etc/systemd/system/multi-user.target.wants/nginx.service

        # Try reloading daemon.
        run systemctl daemon-reload

        # Masked (?).
        run systemctl unmask nginx.service

        # Enable in start up.
        run systemctl enable nginx.service

        # Final test.
        if [[ "${DRYRUN}" != true ]]; then
            # Copy custom default vhost.
            [ -f /etc/nginx/sites-available/default ] && \
            run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default~

            if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" ]]; then
                run cp -f etc/nginx/sites-available/default-ssl /etc/nginx/sites-available/default
                run sed -i "s|HOSTNAME_CERT_PATH|${HOSTNAME_CERT_PATH}|g" "/etc/nginx/sites-available/default"
            else
                run cp -f etc/nginx/sites-available/default /etc/nginx/sites-available/default
            fi

            # Enable default vhost (mandatory).
            [ -f /etc/nginx/sites-enabled/default ] && run unlink /etc/nginx/sites-enabled/default
            [ -f /etc/nginx/sites-enabled/00-default ] && run unlink /etc/nginx/sites-enabled/00-default
            run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/00-default

            # Make default server accessible from hostname or IP address.
            if [[ $(dig "${HOSTNAME}" +short) == "${SERVER_IP}" ]]; then
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
        else
            info "Nginx HTTP server installed in dry run mode."
        fi
    else
        info "Nginx HTTP (web) server installation skipped."
    fi
}

function generate_hostname_cert() {
    # Generate a new certificate for the hostname domain.
    if [[ "${ENVIRONMENT}" == prod* && $(dig "${HOSTNAME}" +short) == "${SERVER_IP}" ]]; then
        # Stop webserver first.
        run systemctl stop nginx.service

        if [[ ! -e "/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem" ]]; then
            run certbot certonly --standalone --agree-tos --preferred-challenges http \
                --webroot-path=/usr/share/nginx/html -d "${HOSTNAME}"
        fi

        HOSTNAME_CERT_PATH="/etc/letsencrypt/live/${HOSTNAME}"

        # Re-start webserver.
        run systemctl start nginx.service
    else
        # Self-signed certificate for local development environment.
        run sed -i "s|^CN\ =\ .*|CN\ =\ ${HOSTNAME}|g" /etc/lemper/ssl/ca.conf && \
        run sed -i "s|^CN\ =\ .*|CN\ =\ ${HOSTNAME}|g" /etc/lemper/ssl/csr.conf && \
        run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${HOSTNAME}|g" /etc/lemper/ssl/csr.conf && \
        run sed -i "s|^DNS\.2\ =\ .*|DNS\.2\ =\ www\.${HOSTNAME}|g" /etc/lemper/ssl/csr.conf && \
        run sed -r -i "s|^IP.1\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.1\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
        run sed -r -i "s|^IP.2\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.2\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
        run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${HOSTNAME}|g" /etc/lemper/ssl/cert.conf

        # Create Certificate Authority (CA).
        run openssl req -x509 -sha256 -days 365000 -nodes -newkey "rsa:${KEY_HASH_LENGTH}" \
            -keyout /etc/lemper/ssl/lemperCA.key -out /etc/lemper/ssl/lemperCA.crt \
            -config /etc/lemper/ssl/ca.conf && \

        # Create Server Private Key.
        run openssl genrsa -out "/etc/lemper/ssl/${HOSTNAME}/privkey.pem" "${KEY_HASH_LENGTH}" && \

        # Generate Certificate Signing Request (CSR) using Server Private Key.
        run openssl req -new -key "/etc/lemper/ssl/${HOSTNAME}/privkey.pem" \
            -out "/etc/lemper/ssl/${HOSTNAME}/csr.pem" -config /etc/lemper/ssl/csr.conf

        # Generate SSL certificate With self signed CA.
        run openssl x509 -req -sha256 -days 365000 -CAcreateserial \
            -CA /etc/lemper/ssl/lemperCA.crt -CAkey /etc/lemper/ssl/lemperCA.key \
            -in "/etc/lemper/ssl/${HOSTNAME}/csr.pem" -out "/etc/lemper/ssl/${HOSTNAME}/cert.pem" \
            -extfile /etc/lemper/ssl/cert.conf

        # Create chain file.
        run cat "/etc/lemper/ssl/${HOSTNAME}/cert.pem" /etc/lemper/ssl/lemperCA.crt > \
            "/etc/lemper/ssl/${HOSTNAME}/fullchain.pem"
        #run ln -s "/etc/lemper/ssl/${HOSTNAME}/cert.pem" "/etc/lemper/ssl/${HOSTNAME}/fullchain.pem"

        if [ -f "/etc/lemper/ssl/${HOSTNAME}/cert.pem" ]; then
            HOSTNAME_CERT_PATH="/etc/lemper/ssl/${HOSTNAME}"
            success "Self-signed SSL certificate has been successfully generated."
        else
            fail "An error occurred when generating self-signed SSL certificate."
        fi
    fi
}

function add_nginx_logrotate() {
    run touch "/etc/logrotate.d/nginx"
    cat >> "/etc/logrotate.d/nginx" <<EOL
/var/log/nginx/*.log /home/*/logs/nginx/*_log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then
            run-parts /etc/logrotate.d/httpd-prerotate;
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOL

    run chmod 0644 "/etc/logrotate.d/nginx"
}

echo "[Nginx HTTP (Web) Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available && "${FORCE_INSTALL}" != true ]]; then
    info "Nginx web server already exists, installation skipped."
else
    init_nginx_install "$@"
fi
