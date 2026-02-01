#!/usr/bin/env bash

# Nginx Extra Modules Installation
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Install Auth PAM module
##
function install_ngx_auth_pam() {
    echo "Adding ngx-http-auth-pam module..."

    clone_or_update_repo "https://github.com/sto/ngx_http_auth_pam_module.git" "ngx_http_auth_pam_module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_http_auth_pam_module"

    # Requires libpam-dev
    echo "Auth PAM module requires libpam-dev package..."
    run apt-get install -q -y libpam-dev
}

##
# Install Brotli compression module
##
function install_ngx_brotli() {
    echo "Adding ngx-http-brotli module..."

    if [[ -d "${NGINX_EXTRA_MODULE_DIR}/ngx_brotli" ]]; then
        run cd "${NGINX_EXTRA_MODULE_DIR}/ngx_brotli" && \
        run git pull && \
        run git checkout master -q && \
        run git submodule update --init -q && \
        run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1
    else
        run git clone https://github.com/google/ngx_brotli.git "${NGINX_EXTRA_MODULE_DIR}/ngx_brotli" && \
        run cd "${NGINX_EXTRA_MODULE_DIR}/ngx_brotli" && \
        run git checkout master -q && \
        run git submodule update --init -q && \
        run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1
    fi

    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_brotli"
}

##
# Install Cache Purge module
##
function install_ngx_cache_purge() {
    echo "Adding ngx-http-cache-purge module..."

    clone_or_update_repo "https://github.com/nginx-modules/ngx_cache_purge.git" "ngx_cache_purge" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_cache_purge"
}

##
# Install DAV Ext module
##
function install_ngx_dav_ext() {
    echo "Adding ngx-http-dav-ext module..."

    clone_or_update_repo "https://github.com/arut/nginx-dav-ext-module.git" "nginx-dav-ext-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/nginx-dav-ext-module"
}

##
# Install Echo module
##
function install_ngx_echo() {
    echo "Adding ngx-http-echo module..."

    clone_or_update_repo "https://github.com/openresty/echo-nginx-module.git" "echo-nginx-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/echo-nginx-module"
}

##
# Install Fancy Index module
##
function install_ngx_fancyindex() {
    echo "Adding ngx-http-fancyindex module..."

    clone_or_update_repo "https://github.com/aperezdc/ngx-fancyindex.git" "ngx-fancyindex" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx-fancyindex"
}

##
# Install GeoIP module (built-in)
##
function install_ngx_geoip() {
    echo "Adding ngx-http-geoip module..."

    if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-http_geoip_module=dynamic")
    else
        NGX_CONFIGURE_ARGS+=("--with-http_geoip_module")
    fi
}

##
# Install GeoIP2 module with MaxMind database
##
function install_ngx_geoip2() {
    echo "Adding ngx-http-geoip2 module..."

    clone_or_update_repo "https://github.com/leev/ngx_http_geoip2_module.git" "ngx_http_geoip2_module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_http_geoip2_module"

    # Install libmaxminddb
    install_maxmind_library

    # Download GeoLite2 databases
    download_geolite2_databases
}

##
# Install MaxMind GeoIP2 library
##
function install_maxmind_library() {
    echo "Installing MaxMind GeoIP2 library..."

    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    run cd "${NGINX_BUILD_DIR}" || return 1

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}

    if [[ "${DISTRIB_NAME}" == "ubuntu" ]]; then
        if dpkg-query -l | awk '/libmaxminddb0/ { print $2 }' | grep -qwE "^libmaxminddb0"; then
            echo "MaxMind GeoIP2 library is already installed."
        else
            run add-apt-repository -y ppa:maxmind/ppa && \
            run apt-get update -q -y && \
            run apt-get install -q -y libmaxminddb0 libmaxminddb-dev mmdb-bin
        fi
    else
        if [[ ! -d libmaxminddb ]]; then
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
        run cd "${NGINX_BUILD_DIR}" || return 1
    fi
}

##
# Download MaxMind GeoLite2 databases
##
function download_geolite2_databases() {
    echo "Downloading MaxMind GeoIP2-GeoLite2 database..."

    run cd "${NGINX_BUILD_DIR}" || return 1

    if [[ -d geoip-db ]]; then
        run rm -rf geoip-db
    fi

    run mkdir -p geoip-db && \
    run cd geoip-db && \
    run mkdir -p /opt/geoip

    # Download Country database
    if [[ ! -f GeoLite2-Country.tar.gz && -n "${GEOLITE2_LICENSE_KEY}" ]]; then
        local GEOLITE2_COUNTRY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"

        if curl -sLI "${GEOLITE2_COUNTRY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
            run curl -sSL -o GeoLite2-Country.tar.gz "${GEOLITE2_COUNTRY_SRC}" && \
            run tar -xf GeoLite2-Country.tar.gz && \
            run cd GeoLite2-Country_*/ && \
            run mv GeoLite2-Country.mmdb /opt/geoip/ && \
            run cd "${NGINX_BUILD_DIR}/geoip-db" || return 1
        else
            error "Unable to download MaxMind GeoLite2 Country database..."
        fi
    fi

    # Download City database
    if [[ ! -f GeoLite2-City.tar.gz && -n "${GEOLITE2_LICENSE_KEY}" ]]; then
        local GEOLITE2_CITY_SRC="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${GEOLITE2_LICENSE_KEY}&suffix=tar.gz"

        if curl -sLI "${GEOLITE2_CITY_SRC}" | grep -q "HTTP/[.12]* [2].."; then
            run curl -sSL -o GeoLite2-City.tar.gz "${GEOLITE2_CITY_SRC}" && \
            run tar -xf GeoLite2-City.tar.gz && \
            run cd GeoLite2-City_*/ && \
            run mv GeoLite2-City.mmdb /opt/geoip/ && \
            run cd "${NGINX_BUILD_DIR}/geoip-db" || return 1
        else
            error "Unable to download MaxMind GeoLite2 City database..."
        fi
    fi

    run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1

    if [[ -f /opt/geoip/GeoLite2-City.mmdb && -f /opt/geoip/GeoLite2-Country.mmdb ]]; then
        success "MaxMind GeoIP2-GeoLite2 database successfully installed."
    else
        warning "GeoLite2 databases not fully installed. Check your license key."
    fi
}

##
# Install Headers More module
##
function install_ngx_headers_more() {
    echo "Adding ngx-http-headers-more-filter module..."

    clone_or_update_repo "https://github.com/openresty/headers-more-nginx-module.git" "headers-more-nginx-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/headers-more-nginx-module"
}

##
# Install Image Filter module (built-in)
##
function install_ngx_image_filter() {
    echo "Adding ngx-http-image-filter module..."

    if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-http_image_filter_module=dynamic")
    else
        NGX_CONFIGURE_ARGS+=("--with-http_image_filter_module")
    fi
}

##
# Install Lua module with LuaJIT
##
function install_ngx_lua() {
    echo "Adding ngx-http-lua module..."

    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    local LUA_JIT_VERSION=${LUA_JIT_VERSION:-"v2.1-20211210"}
    local LUA_RESTY_CORE_VERSION=${LUA_RESTY_CORE_VERSION:-"v0.1.22"}
    local LUA_RESTY_LRUCACHE_VERSION=${LUA_RESTY_LRUCACHE_VERSION:-"v0.11"}
    local LUA_NGINX_MODULE_VERSION=${LUA_NGINX_MODULE_VERSION:-"v0.10.26"}

    # Lua requires NDK
    NGX_HTTP_NDK=true

    run cd "${NGINX_BUILD_DIR}" || return 1

    # Install LuaJIT
    echo "Installing LuaJIT 2.1..."
    if [[ -d luajit2 ]]; then
        run cd luajit2 && run git pull
    else
        run git clone --branch="${LUA_JIT_VERSION}" --single-branch https://github.com/openresty/luajit2.git && \
        run cd luajit2 || return 1
    fi

    run make -j"${NB_PROC}" && \
    run make install && \
    run cd "${NGINX_BUILD_DIR}" || return 1

    # Install Lua Resty Core
    echo "Installing Lua Resty Core..."
    if [[ -d lua-resty-core ]]; then
        run cd lua-resty-core && run git pull
    else
        run git clone --branch="${LUA_RESTY_CORE_VERSION}" --single-branch https://github.com/openresty/lua-resty-core.git && \
        run cd lua-resty-core || return 1
    fi

    run make install && \
    run cd "${NGINX_BUILD_DIR}" || return 1

    # Install Lua Resty LRUCache
    echo "Installing Lua Resty LRUCache..."
    if [[ -d lua-resty-lrucache ]]; then
        run cd lua-resty-lrucache && run git pull
    else
        run git clone --branch="${LUA_RESTY_LRUCACHE_VERSION}" --single-branch https://github.com/openresty/lua-resty-lrucache.git && \
        run cd lua-resty-lrucache || return 1
    fi

    run make install && \
    run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1

    # Configure Lua paths
    echo "Configuring Lua Nginx Module..."
    export LUAJIT_LIB="/usr/local/lib"
    export LUAJIT_INC="/usr/local/include/luajit-2.1"
    NGX_CONFIGURE_ARGS+=("--with-ld-opt=\"-Wl,-rpath,/usr/local/lib\"")

    # Clone Lua Nginx module
    clone_or_update_repo "https://github.com/openresty/lua-nginx-module.git" "lua-nginx-module" "${LUA_NGINX_MODULE_VERSION}"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/lua-nginx-module"
}

##
# Install Memcached module
##
function install_ngx_memcached() {
    echo "Adding ngx-http-memcached module..."

    clone_or_update_repo "https://github.com/openresty/memc-nginx-module.git" "memc-nginx-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/memc-nginx-module"
}

##
# Install NAXSI WAF module
##
function install_ngx_naxsi() {
    echo "Adding ngx-http-naxsi (WAF) module..."

    clone_or_update_repo "https://github.com/wargio/naxsi.git" "naxsi" "main"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/naxsi/naxsi_src"
}

##
# Install NDK (Nginx Development Kit) module
##
function install_ngx_ndk() {
    echo "Adding ngx-http-ndk module..."

    clone_or_update_repo "https://github.com/vision5/ngx_devel_kit.git" "ngx_devel_kit" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_devel_kit"
}

##
# Install NJS module
##
function install_ngx_njs() {
    echo "Adding ngx-http-njs module..."

    clone_or_update_repo "https://github.com/nginx/njs.git" "njs" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/njs/nginx"
}

##
# Install Passenger module
##
function install_ngx_passenger() {
    echo "Adding ngx-http-passenger module..."

    if [[ -n $(command -v passenger-config) ]]; then
        add_ngx_module_arg "$(passenger-config --nginx-addon-dir)"
    else
        error "Passenger module not found, skipped..."
    fi
}

##
# Install Redis2 module
##
function install_ngx_redis2() {
    echo "Adding ngx-http-redis2 module..."

    clone_or_update_repo "https://github.com/openresty/redis2-nginx-module.git" "redis2-nginx-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/redis2-nginx-module"
}

##
# Install Subs Filter module
##
function install_ngx_subs_filter() {
    echo "Adding ngx-http-subs-filter module..."

    clone_or_update_repo "https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git" "ngx_http_substitutions_filter_module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/ngx_http_substitutions_filter_module"
}

##
# Install Upstream Fair module
##
function install_ngx_upstream_fair() {
    echo "Adding ngx-http-upstream-fair module..."

    if [[ -d "${NGINX_EXTRA_MODULE_DIR}/nginx-upstream-fair" ]]; then
        run cd "${NGINX_EXTRA_MODULE_DIR}/nginx-upstream-fair" && \
        run git pull && \
        run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1
    else
        run git clone --branch="lemper" --single-branch https://github.com/joglomedia/nginx-upstream-fair.git "${NGINX_EXTRA_MODULE_DIR}/nginx-upstream-fair"

        echo "Patching nginx-upstream-fair module..."
        clone_or_update_repo "https://github.com/alibaba-archive/tengine-patches.git" "tengine-patches" "master"

        run cd "${NGINX_EXTRA_MODULE_DIR}/nginx-upstream-fair" && \
        run bash -c "patch -p1 < '${NGINX_EXTRA_MODULE_DIR}/tengine-patches/nginx-upstream-fair/upstream-fair-upstream-check.patch'" && \
        run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1
    fi

    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/nginx-upstream-fair"
}

##
# Install VTS (Virtual Host Traffic Status) module
##
function install_ngx_vts() {
    echo "Adding ngx-http-vts module..."

    clone_or_update_repo "https://github.com/vozlt/nginx-module-vts.git" "nginx-module-vts" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/nginx-module-vts"
}

##
# Install XSLT Filter module (built-in)
##
function install_ngx_xslt_filter() {
    echo "Adding ngx-http-xslt-filter module..."

    if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-http_xslt_module=dynamic")
    else
        NGX_CONFIGURE_ARGS+=("--with-http_xslt_module")
    fi
}

##
# Install Mail module (built-in)
##
function install_ngx_mail() {
    echo "Adding ngx-mail module..."

    if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-mail=dynamic" "--with-mail_ssl_module")
    else
        NGX_CONFIGURE_ARGS+=("--with-mail" "--with-mail_ssl_module")
    fi
}

##
# Install Nchan pub/sub module
##
function install_ngx_nchan() {
    echo "Adding ngx-nchan module..."

    clone_or_update_repo "https://github.com/slact/nchan.git" "nchan" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/nchan"
}

##
# Install RTMP (HTTP-FLV) module
##
function install_ngx_rtmp() {
    echo "Adding ngx-rtmp module..."

    clone_or_update_repo "https://github.com/winshining/nginx-http-flv-module.git" "nginx-http-flv-module" "master"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/nginx-http-flv-module"
}

##
# Install Stream module (built-in) with optional Lua support
##
function install_ngx_stream() {
    echo "Adding ngx-stream module..."

    if [[ "${NGINX_DYNAMIC_MODULE}" == true ]]; then
        NGX_CONFIGURE_ARGS+=(
            "--with-stream=dynamic"
            "--with-stream_geoip_module=dynamic"
            "--with-stream_realip_module"
            "--with-stream_ssl_module"
            "--with-stream_ssl_preread_module"
        )
    else
        NGX_CONFIGURE_ARGS+=(
            "--with-stream"
            "--with-stream_geoip_module"
            "--with-stream_realip_module"
            "--with-stream_ssl_module"
            "--with-stream_ssl_preread_module"
        )
    fi

    # Add Stream Lua module if Lua is enabled
    if "${NGX_HTTP_LUA:-false}"; then
        install_ngx_stream_lua
    fi
}

##
# Install Stream Lua module
##
function install_ngx_stream_lua() {
    echo "Adding stream-lua-nginx-module..."

    local LUA_NGINX_STREAM_MODULE_VERSION=${LUA_NGINX_STREAM_MODULE_VERSION:-"master"}

    clone_or_update_repo "https://github.com/openresty/stream-lua-nginx-module.git" "stream-lua-nginx-module" "${LUA_NGINX_STREAM_MODULE_VERSION}"
    add_ngx_module_arg "${NGINX_EXTRA_MODULE_DIR}/stream-lua-nginx-module"
}

##
# Install all enabled extra modules for source build
##
function install_all_extra_modules() {
    echo "Installing enabled extra modules for source build..."

    run mkdir -p "${NGINX_EXTRA_MODULE_DIR}" && \
    run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1

    # Install modules based on configuration flags
    "${NGX_HTTP_AUTH_PAM:-false}" && install_ngx_auth_pam
    "${NGX_HTTP_BROTLI:-false}" && install_ngx_brotli
    "${NGX_HTTP_CACHE_PURGE:-false}" && install_ngx_cache_purge
    "${NGX_HTTP_DAV_EXT:-false}" && install_ngx_dav_ext
    "${NGX_HTTP_ECHO:-false}" && install_ngx_echo
    "${NGX_HTTP_FANCYINDEX:-false}" && install_ngx_fancyindex
    "${NGX_HTTP_GEOIP:-false}" && install_ngx_geoip
    "${NGX_HTTP_GEOIP2:-false}" && install_ngx_geoip2
    "${NGX_HTTP_HEADERS_MORE:-false}" && install_ngx_headers_more
    "${NGX_HTTP_IMAGE_FILTER:-false}" && install_ngx_image_filter
    "${NGX_HTTP_LUA:-false}" && install_ngx_lua
    "${NGX_HTTP_MEMCACHED:-false}" && install_ngx_memcached
    "${NGX_HTTP_NAXSI:-false}" && install_ngx_naxsi
    "${NGX_HTTP_NDK:-false}" && install_ngx_ndk
    "${NGX_HTTP_NJS:-false}" && install_ngx_njs
    "${NGX_HTTP_PASSENGER:-false}" && install_ngx_passenger
    "${NGX_HTTP_REDIS2:-false}" && install_ngx_redis2
    "${NGX_HTTP_SUBS_FILTER:-false}" && install_ngx_subs_filter
    "${NGX_HTTP_UPSTREAM_FAIR:-false}" && install_ngx_upstream_fair
    "${NGX_HTTP_VTS:-false}" && install_ngx_vts
    "${NGX_HTTP_XSLT_FILTER:-false}" && install_ngx_xslt_filter
    "${NGX_MAIL:-false}" && install_ngx_mail
    "${NGX_NCHAN:-false}" && install_ngx_nchan
    "${NGX_RTMP:-false}" && install_ngx_rtmp
    "${NGX_STREAM:-false}" && install_ngx_stream
}
