#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

##
# Download and extract Nginx source
##
function download_nginx_source() {
    local VERSION="${1:-${NGINX_RELEASE_VERSION}}" temporary
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        error "Invalid Nginx source version."
        return 1
    }
    local NGINX_URL="https://nginx.org/download/nginx-$VERSION.tar.gz"
    local NGINX_TARBALL="$NGINX_BUILD_DIR/nginx-$VERSION.tar.gz"
    NGINX_SRC_DIR="$NGINX_BUILD_DIR/nginx-$VERSION"
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would download Nginx $VERSION."
        return 0
    fi
    echo "Downloading Nginx $VERSION..."
    if [[ ! -f "$NGINX_TARBALL" ]] || ! tar -tzf "$NGINX_TARBALL" >/dev/null 2>&1; then
        temporary=$(mktemp "$NGINX_TARBALL.XXXXXXXX") || return 1
        if ! curl -fsSL --connect-timeout 10 --max-time 120 -o "$temporary" "$NGINX_URL"; then
            warning "nginx.org unavailable; using the official nginx/nginx release tag."
            if ! curl -fsSL --connect-timeout 10 --max-time 120 -o "$temporary" \
                "https://github.com/nginx/nginx/archive/refs/tags/release-$VERSION.tar.gz"; then
                rm -f "$temporary"
                return 1
            fi
        fi
        if ! tar -tzf "$temporary" >/dev/null 2>&1; then
            rm -f "$temporary"
            error "Invalid Nginx source archive."
            return 1
        fi
        mv "$temporary" "$NGINX_TARBALL" || return 1
    fi
    run mkdir -p "$NGINX_SRC_DIR"
    run tar -zxf "$NGINX_TARBALL" --strip-components=1 -C "$NGINX_SRC_DIR"
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

    local configure="./configure"
    [[ -f "$configure" ]] || configure="./auto/configure"
    [[ -f "$configure" ]] || {
        error "Nginx configure script missing."
        return 1
    }
    if [[ "${DRYRUN:-false}" == true ]]; then
        printf '[DRY-RUN] %s\n' "$configure"
    else
        "$configure" "${NGX_CONFIGURE_ARGS[@]}" || return 1
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
    run_spinner "Compiling Nginx" make -j"${NB_PROC}"

    echo "Installing Nginx..."
    run_spinner "Installing Nginx" make install

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
    if [[ -z "${NGINX_RELEASE_VERSION:-}" ]]; then
        NGINX_RELEASE_VERSION=$(determine_nginx_version) || return 1
    fi
    echo "Nginx version: ${NGINX_RELEASE_VERSION}"

    # Create build directory
    run mkdir -p "${NGINX_BUILD_DIR}" "${NGINX_EXTRA_MODULE_DIR}"
    run cd "${NGINX_BUILD_DIR}" || return 1

    # Get base configure arguments
    get_nginx_base_configure_args

    # Build custom SSL if required
    if [[ "${NGINX_WITH_CUSTOMSSL:-${NGINX_CUSTOMSSL:-false}}" == true ]]; then
        build_custom_ssl || return 1
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
    download_nginx_source "${NGINX_RELEASE_VERSION}" || return 1

    # Configure with all modules
    configure_nginx || return 1

    # Compile and install
    compile_nginx || return 1

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
