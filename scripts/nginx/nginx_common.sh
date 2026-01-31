#!/usr/bin/env bash

# Nginx Common Variables and Utilities
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Common paths and directories
##
NGINX_CONF_DIR="/etc/nginx"
NGINX_MODULES_AVAILABLE="${NGINX_CONF_DIR}/modules-available"
NGINX_MODULES_ENABLED="${NGINX_CONF_DIR}/modules-enabled"
NGINX_SITES_AVAILABLE="${NGINX_CONF_DIR}/sites-available"
NGINX_SITES_ENABLED="${NGINX_CONF_DIR}/sites-enabled"
NGINX_LIB_MODULES="/usr/lib/nginx/modules"
NGINX_SHARE_DIR="/usr/share/nginx"
NGINX_CACHE_DIR="/var/cache/nginx"

##
# Default build directory
##
NGINX_BUILD_DIR="${BUILD_DIR:-/tmp/lemper}"
NGINX_EXTRA_MODULE_DIR="${NGINX_BUILD_DIR}/nginx_modules"

##
# Get number of CPU cores for parallel compilation
##
function get_cpu_cores() {
    getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}

##
# Add a dynamic module configuration
# Usage: add_module_conf "module_name" "module_so_file"
##
function add_module_conf() {
    local MODULE_NAME="$1"
    local MODULE_SO="$2"
    local CONF_FILE="${NGINX_MODULES_AVAILABLE}/mod-${MODULE_NAME}.conf"

    if [[ -f "${NGINX_LIB_MODULES}/${MODULE_SO}" && ! -f "${CONF_FILE}" ]]; then
        run bash -c "echo 'load_module \"${NGINX_LIB_MODULES}/${MODULE_SO}\";' > ${CONF_FILE}"
        return 0
    fi
    return 1
}

##
# Append to a dynamic module configuration
# Usage: append_module_conf "module_name" "module_so_file"
##
function append_module_conf() {
    local MODULE_NAME="$1"
    local MODULE_SO="$2"
    local CONF_FILE="${NGINX_MODULES_AVAILABLE}/mod-${MODULE_NAME}.conf"

    if [[ -f "${NGINX_LIB_MODULES}/${MODULE_SO}" && -f "${CONF_FILE}" ]]; then
        run bash -c "echo 'load_module \"${NGINX_LIB_MODULES}/${MODULE_SO}\";' >> ${CONF_FILE}"
        return 0
    fi
    return 1
}

##
# Enable a dynamic module
# Usage: enable_module "module_name" "priority"
##
function enable_module() {
    local MODULE_NAME="$1"
    local PRIORITY="${2:-50}"
    local CONF_FILE="${NGINX_MODULES_AVAILABLE}/mod-${MODULE_NAME}.conf"
    local ENABLED_LINK="${NGINX_MODULES_ENABLED}/${PRIORITY}-mod-${MODULE_NAME}.conf"

    if [[ -f "${CONF_FILE}" ]]; then
        run ln -fs "${CONF_FILE}" "${ENABLED_LINK}"
        return 0
    fi
    return 1
}

##
# Add configure argument for dynamic or static module
# Usage: add_ngx_module_arg "module_path" [dynamic=true]
##
function add_ngx_module_arg() {
    local MODULE_PATH="$1"
    local IS_DYNAMIC="${2:-${NGINX_DYNAMIC_MODULE:-true}}"

    if [[ "${IS_DYNAMIC}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--add-dynamic-module=${MODULE_PATH}")
    else
        NGX_CONFIGURE_ARGS+=("--add-module=${MODULE_PATH}")
    fi
}

##
# Clone or update a git repository for a module
# Usage: clone_or_update_repo "repo_url" "local_dir" "branch"
##
function clone_or_update_repo() {
    local REPO_URL="$1"
    local LOCAL_DIR="$2"
    local BRANCH="${3:-master}"
    local TARGET_DIR="${NGINX_EXTRA_MODULE_DIR}/${LOCAL_DIR}"

    if [[ -d "${TARGET_DIR}" ]]; then
        run cd "${TARGET_DIR}" && \
        run git pull && \
        run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1
    else
        run git clone --branch="${BRANCH}" --single-branch "${REPO_URL}" "${TARGET_DIR}"
    fi
}
