#!/usr/bin/env bash

# Nginx Repository Management
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
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
                run curl -sSL -o "/etc/apt/trusted.gpg.d/ondrej-${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg" && \
                run touch "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb https://packages.sury.org/${NGINX_REPO}/ ${RELEASE_NAME} main' > /etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
        ;;
        ubuntu)
            # Nginx custom with ngx cache purge from Ondrej repo.
            run curl -sSL -o "/etc/apt/trusted.gpg.d/ondrej-${NGINX_REPO}.gpg" "https://packages.sury.org/${NGINX_REPO}/apt.gpg" && \
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C && \
            run add-apt-repository -y "ppa:ondrej/${NGINX_REPO}" && \
            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
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

    # MyGuard only has one repo for nginx
    local NGINX_REPO="nginx"

    DISTRIB_ARCH=$(get_distrib_arch)

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list" ]]; then
                run curl -sSL -o "/etc/apt/trusted.gpg.d/deb.myguard.nl.gpg" "https://deb.myguard.nl/pool/deb.myguard.nl.gpg" && \
                run touch "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH}] http://deb.myguard.nl ${RELEASE_NAME} main' > /etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Install extra module packages from repository
# Populates EXTRA_MODULE_PKGS array based on enabled modules
##
function get_repo_extra_module_packages() {
    local SELECTED_REPO="${1:-ondrej}"
    EXTRA_MODULE_PKGS=()

    echo "Determining extra module packages..."

    # Auth PAM
    if "${NGX_HTTP_AUTH_PAM:-false}"; then
        echo "Adding ngx-http-auth-pam module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-auth-pam")
    fi

    # Brotli compression
    if "${NGX_HTTP_BROTLI:-false}"; then
        echo "Adding ngx-http-brotli module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-brotli")
        else
            EXTRA_MODULE_PKGS+=("libnginx-mod-brotli")
        fi
    fi

    # Cache Purge
    if "${NGX_HTTP_CACHE_PURGE:-false}"; then
        echo "Adding ngx-http-cache-purge module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-cache-purge")
    fi

    # DAV Ext
    if "${NGX_HTTP_DAV_EXT:-false}"; then
        echo "Adding ngx-http-dav-ext module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-dav-ext")
    fi

    # Echo
    if "${NGX_HTTP_ECHO:-false}"; then
        echo "Adding ngx-http-echo module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-echo")
    fi

    # Fancy indexes
    if "${NGX_HTTP_FANCYINDEX:-false}"; then
        echo "Adding ngx-http-fancyindex module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-fancyindex")
    fi

    # GeoIP
    if "${NGX_HTTP_GEOIP:-false}"; then
        echo "Adding ngx-http-geoip module..."
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip" "libnginx-mod-stream-geoip")
    fi

    # GeoIP2
    if "${NGX_HTTP_GEOIP2:-false}"; then
        echo "Adding ngx-http-geoip2 module..."
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip2" "libnginx-mod-stream-geoip2")
    fi

    # Headers more
    if "${NGX_HTTP_HEADERS_MORE:-false}"; then
        echo "Adding ngx-http-headers-more-filter module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-headers-more-filter")
    fi

    # Image filter
    if "${NGX_HTTP_IMAGE_FILTER:-false}"; then
        echo "Adding ngx-http-image-filter module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-image-filter")
    fi

    # Lua
    if "${NGX_HTTP_LUA:-false}"; then
        echo "Adding ngx-http-lua module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("luarocks" "lua-cjson" "lua-resty" "lua-resty-core" "lua-resty-lrucache" "libnginx-mod-http-lua")
        else
            EXTRA_MODULE_PKGS+=("luajit" "luarocks" "lua-cjson" "lua-resty-core" "lua-resty-lrucache" "libnginx-mod-http-lua")
        fi
    fi

    # Memcached
    if "${NGX_HTTP_MEMCACHED:-false}"; then
        warning "ngx-http-memcached module is not supported in repo install."
    fi

    # NAXSI
    if "${NGX_HTTP_NAXSI:-false}"; then
        echo "Adding ngx-http-naxsi module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-naxsi")
        fi
    fi

    # NDK
    if "${NGX_HTTP_NDK:-false}"; then
        echo "Adding ngx-http-ndk module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-ndk")
    fi

    # NJS
    if "${NGX_HTTP_NJS:-false}"; then
        echo "Adding ngx-http-njs module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-njs")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-njs module. Skipped..."
        fi
    fi

    # Passenger
    if "${NGX_HTTP_PASSENGER:-false}"; then
        echo "Adding ngx-http-passenger module..."
        if [[ -n $(command -v passenger-config) ]]; then
            echo "Passenger found..."
        else
            error "Passenger not found. Skipped..."
        fi
    fi

    # Redis2
    if "${NGX_HTTP_REDIS2:-false}"; then
        echo "Adding ngx-http-redis2 module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-redis2")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-redis2 module. Skipped..."
        fi
    fi

    # Subs filter
    if "${NGX_HTTP_SUBS_FILTER:-false}"; then
        echo "Adding ngx-http-subs-filter module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-subs-filter")
    fi

    # Upstream fair
    if "${NGX_HTTP_UPSTREAM_FAIR:-false}"; then
        echo "Adding ngx-http-upstream-fair module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-upstream-fair")
    fi

    # VTS
    if "${NGX_HTTP_VTS:-false}"; then
        echo "Adding ngx-http-vts module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-vhost-traffic-status")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-vhost-traffic-status module. Skipped..."
        fi
    fi

    # XSLT
    if "${NGX_HTTP_XSLT_FILTER:-false}"; then
        echo "Adding ngx-http-xslt-filter module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-xslt-filter")
    fi

    # Mail
    if "${NGX_MAIL:-false}"; then
        echo "Adding ngx-mail module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-mail")
    fi

    # Nchan
    if "${NGX_NCHAN:-false}"; then
        echo "Adding ngx-nchan module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-nchan")
    fi

    # RTMP
    if "${NGX_RTMP:-false}"; then
        echo "Adding ngx-rtmp module..."
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-flv-live")
        else
            EXTRA_MODULE_PKGS+=("libnginx-mod-rtmp")
        fi
    fi

    # Stream
    if "${NGX_STREAM:-false}"; then
        echo "Adding ngx-stream module..."
        EXTRA_MODULE_PKGS+=("libnginx-mod-stream")
    fi
}

##
# Install Nginx from repository
##
function install_nginx_from_repo() {
    local SELECTED_REPO="${1:-ondrej}"

    echo "Installing Nginx from ${SELECTED_REPO} repository..."

    if [[ -n "${NGINX_PKGS[*]}" ]]; then
        if "${NGINX_EXTRA_MODULES:-false}"; then
            echo "Installing Nginx with extra modules..."
            get_repo_extra_module_packages "${SELECTED_REPO}"
        fi

        # Install Nginx and its modules
        run apt-get install -q -y "${NGINX_PKGS[@]}" "${EXTRA_MODULE_PKGS[@]}"
    fi
}
