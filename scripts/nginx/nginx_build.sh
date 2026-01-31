#!/usr/bin/env bash

# Nginx Source Build Module
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Download and extract Nginx source
##
function download_nginx_source() {
    local VERSION="${1:-${NGINX_RELEASE_VERSION}}"
    local NGINX_URL="https://nginx.org/download/nginx-${VERSION}.tar.gz"
    local NGINX_TARBALL="${NGINX_BUILD_DIR}/nginx-${VERSION}.tar.gz"

    echo "Downloading Nginx ${VERSION}..."

    if [[ -f "${NGINX_TARBALL}" ]]; then
        echo "Using cached Nginx tarball..."
    else
        if ! curl -sLI "${NGINX_URL}" | grep -q "HTTP/[.12]* [2].."; then
            fail "Unable to download Nginx ${VERSION}. Check if version exists at nginx.org"
        fi
        run curl -sSL -o "${NGINX_TARBALL}" "${NGINX_URL}"
    fi

    echo "Extracting Nginx..."
    run tar -zxf "${NGINX_TARBALL}" -C "${NGINX_BUILD_DIR}"

    NGINX_SRC_DIR="${NGINX_BUILD_DIR}/nginx-${VERSION}"
}

##
# Configure Nginx with all modules
##
function configure_nginx() {
    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    if [[ ! -d "${NGINX_SRC_DIR}" ]]; then
        fail "Nginx source directory not found: ${NGINX_SRC_DIR}"
    fi

    run cd "${NGINX_SRC_DIR}" || return 1

    echo "Configuring Nginx with modules..."

    # Build configure command from NGX_CONFIGURE_ARGS array
    local CONFIGURE_CMD="./configure"
    
    for arg in "${NGX_CONFIGURE_ARGS[@]}"; do
        CONFIGURE_CMD="${CONFIGURE_CMD} ${arg}"
    done

    echo "Running: ${CONFIGURE_CMD}"
    
    if [[ "${DRYRUN:-false}" == true ]]; then
        echo "[DRY-RUN] ${CONFIGURE_CMD}"
    else
        eval "${CONFIGURE_CMD}"
    fi
}

##
# Compile and install Nginx
##
function compile_nginx() {
    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    if [[ ! -d "${NGINX_SRC_DIR}" ]]; then
        fail "Nginx source directory not found: ${NGINX_SRC_DIR}"
    fi

    run cd "${NGINX_SRC_DIR}" || return 1

    echo "Compiling Nginx (using ${NB_PROC} cores)..."
    run make -j"${NB_PROC}"

    echo "Installing Nginx..."
    run make install

    # Create nginx symlink if not exists
    if [[ ! -f /usr/sbin/nginx && -f /etc/nginx/sbin/nginx ]]; then
        run ln -sf /etc/nginx/sbin/nginx /usr/sbin/nginx
    fi

    success "Nginx compiled and installed successfully!"
}

##
# Build Nginx from source with all configured modules
# This is the main entry point for source builds
##
function build_nginx_from_source() {
    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    echo "Building Nginx from source..."

    # Get nginx version
    NGINX_RELEASE_VERSION="${NGINX_RELEASE_VERSION:-$(determine_nginx_version)}"
    echo "Nginx version: ${NGINX_RELEASE_VERSION}"

    # Create build directory
    run mkdir -p "${NGINX_BUILD_DIR}" "${NGINX_EXTRA_MODULE_DIR}"
    run cd "${NGINX_BUILD_DIR}" || return 1

    # Get base configure arguments
    get_nginx_base_configure_args

    # Build custom SSL if required
    if [[ "${NGINX_CUSTOMSSL:-false}" == true && -n "${NGINX_CUSTOMSSL_VERSION:-}" ]]; then
        build_custom_ssl
    fi

    # Build PCRE if required
    if [[ -n "${NGINX_PCRE_VERSION:-}" ]]; then
        build_pcre "${NGINX_PCRE_VERSION}"
    fi

    # Install and configure extra modules if enabled
    if [[ "${NGINX_EXTRA_MODULES:-false}" == true ]]; then
        install_all_extra_modules
    fi

    # Download nginx source
    download_nginx_source "${NGINX_RELEASE_VERSION}"

    # Configure with all modules
    configure_nginx

    # Compile and install
    compile_nginx

    # Configure dynamic modules
    echo "Configuring Nginx dynamic modules..."
    create_module_conf_files
    enable_dynamic_modules

    # Return to original directory
    run cd "${CURRENT_DIR:-$(pwd)}" || return 1
}

##
# Get base configure arguments for nginx build
##
function get_nginx_base_configure_args() {
    NGX_CONFIGURE_ARGS=(
        "--prefix=/etc/nginx"
        "--sbin-path=/usr/sbin/nginx"
        "--modules-path=/usr/lib/nginx/modules"
        "--conf-path=/etc/nginx/nginx.conf"
        "--error-log-path=/var/log/nginx/error.log"
        "--http-log-path=/var/log/nginx/access.log"
        "--pid-path=/var/run/nginx.pid"
        "--lock-path=/var/run/nginx.lock"
        "--http-client-body-temp-path=/var/cache/nginx/client_temp"
        "--http-proxy-temp-path=/var/cache/nginx/proxy_temp"
        "--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp"
        "--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp"
        "--http-scgi-temp-path=/var/cache/nginx/scgi_temp"
        "--user=www-data"
        "--group=www-data"
        "--with-compat"
        "--with-file-aio"
        "--with-threads"
        "--with-http_addition_module"
        "--with-http_auth_request_module"
        "--with-http_flv_module"
        "--with-http_gunzip_module"
        "--with-http_gzip_static_module"
        "--with-http_mp4_module"
        "--with-http_random_index_module"
        "--with-http_realip_module"
        "--with-http_secure_link_module"
        "--with-http_slice_module"
        "--with-http_ssl_module"
        "--with-http_stub_status_module"
        "--with-http_sub_module"
        "--with-http_dav_module"
        "--with-http_v2_module"
        "--with-pcre"
        "--with-pcre-jit"
    )

    # Add stream module if enabled
    if [[ "${NGX_STREAM:-false}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-stream" "--with-stream_ssl_module" "--with-stream_realip_module")
    fi

    # Add mail module if enabled
    if [[ "${NGX_MAIL:-false}" == true ]]; then
        NGX_CONFIGURE_ARGS+=("--with-mail" "--with-mail_ssl_module")
    fi
}

##
# Install Nginx from repository
##
function install_nginx_from_repo() {
    local REPO_SOURCE="${1:-ondrej}"

    echo "Installing Nginx from ${REPO_SOURCE} repository..."

    # Get extra module packages for this repo
    local EXTRA_PKGS
    EXTRA_PKGS=$(get_repo_extra_module_packages "${REPO_SOURCE}")

    # Install nginx and modules
    if [[ -n "${EXTRA_PKGS}" ]]; then
        # shellcheck disable=SC2086
        run apt-get install -q -y "${NGINX_PKGS[@]}" ${EXTRA_PKGS}
    else
        run apt-get install -q -y "${NGINX_PKGS[@]}"
    fi

    success "Nginx installed from repository successfully!"
}
