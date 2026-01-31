#!/usr/bin/env bash

# Nginx Dynamic Module Configuration
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Create module configuration files for all dynamic modules
##
function create_module_conf_files() {
    echo "Creating Nginx dynamic module configuration files..."

    # Create module directories if they don't exist
    run mkdir -p "${NGINX_MODULES_AVAILABLE}" "${NGINX_MODULES_ENABLED}"
    run chmod 755 "${NGINX_MODULES_AVAILABLE}" "${NGINX_MODULES_ENABLED}"

    # NDK module
    add_module_conf "http-ndk" "ndk_http_module.so"

    # Auth PAM module
    add_module_conf "http-auth-pam" "ngx_http_auth_pam_module.so"

    # Brotli module (filter + static)
    add_module_conf "http-brotli" "ngx_http_brotli_filter_module.so"
    append_module_conf "http-brotli" "ngx_http_brotli_static_module.so"

    # Cache Purge module
    add_module_conf "http-cache-purge" "ngx_http_cache_purge_module.so"

    # DAV Ext module
    add_module_conf "http-dav-ext" "ngx_http_dav_ext_module.so"

    # Echo module
    add_module_conf "http-echo" "ngx_http_echo_module.so"

    # Fancy Index module
    add_module_conf "http-fancyindex" "ngx_http_fancyindex_module.so"

    # GeoIP module
    add_module_conf "http-geoip" "ngx_http_geoip_module.so"

    # GeoIP2 module
    add_module_conf "http-geoip2" "ngx_http_geoip2_module.so"

    # Headers More module
    add_module_conf "http-headers-more-filter" "ngx_http_headers_more_filter_module.so"

    # Image Filter module
    add_module_conf "http-image-filter" "ngx_http_image_filter_module.so"

    # NJS module
    add_module_conf "http-njs" "ngx_http_js_module.so"

    # Lua module
    add_module_conf "http-lua" "ngx_http_lua_module.so"

    # Memcached module
    add_module_conf "http-memc" "ngx_http_memc_module.so"

    # NAXSI module
    add_module_conf "http-naxsi" "ngx_http_naxsi_module.so"

    # Passenger module
    add_module_conf "http-passenger" "ngx_http_passenger_module.so"

    # Redis2 module
    add_module_conf "http-redis2" "ngx_http_redis2_module.so"

    # Subs Filter module
    add_module_conf "http-subs-filter" "ngx_http_subs_filter_module.so"

    # Upstream Fair module
    add_module_conf "http-upstream-fair" "ngx_http_upstream_fair_module.so"

    # VTS module
    add_module_conf "http-vhost-traffic-status" "ngx_http_vhost_traffic_status_module.so"

    # XSLT Filter module
    add_module_conf "http-xslt-filter" "ngx_http_xslt_filter_module.so"

    # Mail module
    add_module_conf "mail" "ngx_mail_module.so"

    # Nchan module
    add_module_conf "nchan" "ngx_nchan_module.so"

    # RTMP (HTTP-FLV) module
    add_module_conf "rtmp" "ngx_http_flv_live_module.so"

    # Stream module
    add_module_conf "stream" "ngx_stream_module.so"
    add_module_conf "stream-geoip" "ngx_stream_geoip_module.so"
    add_module_conf "stream-geoip2" "ngx_stream_geoip2_module.so"
    add_module_conf "stream-js" "ngx_stream_js_module.so"

    echo "Dynamic module configuration files created."
}

##
# Enable dynamic modules based on configuration
##
function enable_dynamic_modules() {
    echo "Enabling Nginx dynamic modules..."

    # Check if dynamic modules should be enabled
    local ENABLE_NGXDM="${NGINX_DYNAMIC_MODULE:-true}"

    if [[ "${ENABLE_NGXDM}" != true ]]; then
        while [[ "${ENABLE_NGXDM}" != "y" && "${ENABLE_NGXDM}" != "n" ]]; do
            read -rp "Enable Nginx dynamic modules? [y/n]: " -i y -e ENABLE_NGXDM
        done
        [[ "${ENABLE_NGXDM}" != y* && "${ENABLE_NGXDM}" != Y* ]] && return 0
    fi

    # Enable modules based on their configuration flags
    # Priority: 15 = core, 40 = lua/njs, 50 = most modules, 60 = mail/stream/plugins
    
    # Core modules (priority 15)
    "${NGX_HTTP_NDK:-false}" && enable_module "http-ndk" 15
    "${NGX_STREAM:-false}" && enable_module "stream" 15

    # NJS/Lua (priority 40 - must load before dependent modules)
    "${NGX_HTTP_NJS:-false}" && enable_module "http-njs" 40
    "${NGX_HTTP_LUA:-false}" && enable_module "http-lua" 40

    # Standard modules (priority 50)
    "${NGX_HTTP_AUTH_PAM:-false}" && enable_module "http-auth-pam" 50
    "${NGX_HTTP_BROTLI:-false}" && enable_module "http-brotli" 50
    "${NGX_HTTP_CACHE_PURGE:-false}" && enable_module "http-cache-purge" 50
    "${NGX_HTTP_DAV_EXT:-false}" && enable_module "http-dav-ext" 50
    "${NGX_HTTP_ECHO:-false}" && enable_module "http-echo" 50
    "${NGX_HTTP_FANCYINDEX:-false}" && enable_module "http-fancyindex" 50
    "${NGX_HTTP_GEOIP:-false}" && enable_module "http-geoip" 50
    "${NGX_HTTP_GEOIP2:-false}" && enable_module "http-geoip2" 50
    "${NGX_HTTP_HEADERS_MORE:-false}" && enable_module "http-headers-more-filter" 50
    "${NGX_HTTP_IMAGE_FILTER:-false}" && enable_module "http-image-filter" 50
    "${NGX_HTTP_MEMCACHED:-false}" && enable_module "http-memc" 50
    "${NGX_HTTP_NAXSI:-false}" && enable_module "http-naxsi" 50
    "${NGX_HTTP_PASSENGER:-false}" && enable_module "http-passenger" 50
    "${NGX_HTTP_REDIS2:-false}" && enable_module "http-redis2" 50
    "${NGX_HTTP_SUBS_FILTER:-false}" && enable_module "http-subs-filter" 50
    "${NGX_HTTP_UPSTREAM_FAIR:-false}" && enable_module "http-upstream-fair" 50
    "${NGX_HTTP_VTS:-false}" && enable_module "http-vhost-traffic-status" 50
    "${NGX_HTTP_XSLT_FILTER:-false}" && enable_module "http-xslt-filter" 50

    # Stream submodules (priority 50, require stream)
    if "${NGX_STREAM:-false}"; then
        "${NGX_HTTP_GEOIP:-false}" && enable_module "stream-geoip" 50
        "${NGX_HTTP_GEOIP2:-false}" && enable_module "stream-geoip2" 50
        "${NGX_HTTP_NJS:-false}" && enable_module "stream-js" 50
    fi

    # Plugin modules (priority 60)
    "${NGX_MAIL:-false}" && enable_module "mail" 60
    "${NGX_NCHAN:-false}" && enable_module "nchan" 60

    echo "Dynamic modules enabled."
}
