#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Nginx Repository Installer                                              |
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Add the Nginx repository. The Ondřej nginx archive is no longer published.
##
function add_nginx_repo_ondrej() {
    warning "The Ondřej nginx repository is no longer published. Using the MyGuard nginx repository."
    add_nginx_repo_myguard
}

##
# Add MyGuard's nginx-only repository.
# Keyring path and source line match https://deb.myguard.nl/how-to-use/
##
function add_nginx_repo_myguard() {
    local NGINX_REPO="nginx"
    local codename="${RELEASE_NAME:-}"
    local arch="${DISTRIB_ARCH:-}"
    local key list pin line fp

    echo "Add MyGuard's Nginx repository..."

    case "${DISTRIB_NAME}" in
        debian | ubuntu) ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
            ;;
    esac

    if [[ -z "${codename}" || "${codename}" == "unsupported" ]]; then
        fail "Unable to add the MyGuard nginx repository; the distribution codename is unknown."
    fi

    case "${codename}" in
        focal | jammy | noble | resolute | bullseye | bookworm | trixie) ;;
        *)
            fail "MyGuard nginx packages are not published for ${codename}."
            ;;
    esac

    if [[ -z "${arch}" ]]; then
        arch=$(get_distrib_arch 2>/dev/null || dpkg --print-architecture)
    fi

    key="/etc/apt/keyrings/deb.myguard.nl.gpg"
    list="/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${codename}.list"
    pin="/etc/apt/preferences.d/myguard-${NGINX_REPO}-${codename}.pref"
    line="deb [arch=${arch} signed-by=${key}] https://deb.myguard.nl/apt/nginx/${codename} ${codename} main"

    run install -d -m 0755 /etc/apt/keyrings
    if [[ ! -s "${key}" ]]; then
        run curl -fsSL --retry 3 --retry-delay 2 -o "${key}" "https://deb.myguard.nl/deb.myguard.nl.gpg"
        run chmod 0644 "${key}"
    fi

    if [[ "${DRYRUN:-false}" != true && -s "${key}" ]] && command -v gpg >/dev/null 2>&1; then
        fp=$(gpg --batch --with-colons --show-keys "${key}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}' || true)
        if [[ -z "${fp}" ]]; then
            fp=$(gpg --batch --with-colons --import-options show-only --import "${key}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}' || true)
        fi
        if [[ "${fp}" != "D18B8E5ADF7D55CE2A00D58167F9C3D8456D7F62" ]]; then
            fail "MyGuard signing key fingerprint does not match."
        fi
    fi

    if [[ ! -f "${list}" ]] || ! grep -qF "https://deb.myguard.nl/apt/nginx/${codename}" "${list}"; then
        run bash -c 'printf "%s\n" "$1" > "$2"' _ "${line}" "${list}"
    else
        info "MyGuard nginx repository already exists."
    fi

    run tee "${pin}" >/dev/null <<'EOF'
Package: nginx nginx-common nginx-core nginx-full nginx-extras nginx-light nginx-minimal libnginx-mod-* libssl-nginx libssl-nginx-dev libz-ng2
Pin: origin "deb.myguard.nl"
Pin-Priority: 501
EOF

    run apt-get update -q -y
    NGINX_PKGS=("nginx" "nginx-common")
}

##
# Build extra module packages list from repository
# Populates EXTRA_MODULE_PKGS array based on enabled modules
# Note: All debug messages go to stderr to avoid polluting package list
##
function get_repo_extra_module_packages() {
    local SELECTED_REPO="${1:-myguard}"
    EXTRA_MODULE_PKGS=()

    echo "Determining extra module packages..." >&2

    # Auth PAM
    if "${NGX_HTTP_AUTH_PAM:-false}"; then
        echo "  Adding: libnginx-mod-http-auth-pam" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-auth-pam")
    fi

    # Brotli compression
    if "${NGX_HTTP_BROTLI:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-brotli" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-brotli")
        else
            echo "  Adding: libnginx-mod-brotli" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-brotli")
        fi
    fi

    # Cache Purge
    if "${NGX_HTTP_CACHE_PURGE:-false}"; then
        echo "  Adding: libnginx-mod-http-cache-purge" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-cache-purge")
    fi

    # DAV Ext
    if "${NGX_HTTP_DAV_EXT:-false}"; then
        echo "  Adding: libnginx-mod-http-dav-ext" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-dav-ext")
    fi

    # Echo
    if "${NGX_HTTP_ECHO:-false}"; then
        echo "  Adding: libnginx-mod-http-echo" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-echo")
    fi

    # Fancy indexes
    if "${NGX_HTTP_FANCYINDEX:-false}"; then
        echo "  Adding: libnginx-mod-http-fancyindex" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-fancyindex")
    fi

    # GeoIP. The module depends on libmaxminddb0. Headers are omitted here:
    # Ubuntu's libmaxminddb-dev requires the distro library exactly, and the
    # MyGuard nginx archive publishes a newer libmaxminddb0.
    if "${NGX_HTTP_GEOIP:-false}"; then
        echo "  Adding: libnginx-mod-http-geoip" >&2
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libnginx-mod-http-geoip" "libnginx-mod-stream-geoip")
    fi

    # GeoIP2
    if "${NGX_HTTP_GEOIP2:-false}"; then
        echo "  Adding: libnginx-mod-http-geoip2" >&2
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libnginx-mod-http-geoip2" "libnginx-mod-stream-geoip2")
    fi

    # Headers more
    if "${NGX_HTTP_HEADERS_MORE:-false}"; then
        echo "  Adding: libnginx-mod-http-headers-more-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-headers-more-filter")
    fi

    # Image filter
    if "${NGX_HTTP_IMAGE_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-image-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-image-filter")
    fi

    # Lua
    if "${NGX_HTTP_LUA:-false}"; then
        echo "  Adding: libnginx-mod-http-lua" >&2
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
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-naxsi" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-naxsi")
        fi
    fi

    # NDK
    if "${NGX_HTTP_NDK:-false}"; then
        echo "  Adding: libnginx-mod-http-ndk" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-ndk")
    fi

    # NJS
    if "${NGX_HTTP_NJS:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-njs" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-njs")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-njs module. Skipped..."
        fi
    fi

    # Passenger
    if "${NGX_HTTP_PASSENGER:-false}"; then
        if [[ -n $(command -v passenger-config) ]]; then
            echo "  Passenger found..." >&2
        else
            error "Passenger not found. Skipped..."
        fi
    fi

    # Redis2
    if "${NGX_HTTP_REDIS2:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-redis2" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-redis2")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-redis2 module. Skipped..."
        fi
    fi

    # Subs filter
    if "${NGX_HTTP_SUBS_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-subs-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-subs-filter")
    fi

    # Upstream fair
    if "${NGX_HTTP_UPSTREAM_FAIR:-false}"; then
        echo "  Adding: libnginx-mod-http-upstream-fair" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-upstream-fair")
    fi

    # VTS
    if "${NGX_HTTP_VTS:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-vhost-traffic-status" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-vhost-traffic-status")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-vhost-traffic-status module. Skipped..."
        fi
    fi

    # XSLT
    if "${NGX_HTTP_XSLT_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-xslt-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-xslt-filter")
    fi

    # Mail
    if "${NGX_MAIL:-false}"; then
        echo "  Adding: libnginx-mod-mail" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-mail")
    fi

    # Nchan
    if "${NGX_NCHAN:-false}"; then
        echo "  Adding: libnginx-mod-nchan" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-nchan")
    fi

    # RTMP
    if "${NGX_RTMP:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-flv-live" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-flv-live")
        else
            echo "  Adding: libnginx-mod-rtmp" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-rtmp")
        fi
    fi

    # Stream
    if "${NGX_STREAM:-false}"; then
        echo "  Adding: libnginx-mod-stream" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-stream")
    fi

    echo "Total extra modules: ${#EXTRA_MODULE_PKGS[@]}" >&2
}

##
# Install Nginx from repository
##
function install_nginx_from_repo() {
    local SELECTED_REPO="${1:-myguard}"

    echo "Installing Nginx from ${SELECTED_REPO} repository..."

    if [[ -n "${NGINX_PKGS[*]}" ]]; then
        # Build extra module packages list if enabled
        if "${NGINX_EXTRA_MODULES:-false}"; then
            echo "Checking for extra modules..."
            get_repo_extra_module_packages "${SELECTED_REPO}"
        fi

        # Install Nginx packages
        if [[ ${#EXTRA_MODULE_PKGS[@]} -gt 0 ]]; then
            echo "Installing Nginx with ${#EXTRA_MODULE_PKGS[@]} extra module packages..."
            run apt-get install -q -y "${NGINX_PKGS[@]}" "${EXTRA_MODULE_PKGS[@]}"
        else
            echo "Installing Nginx (no extra modules)..."
            run apt-get install -q -y "${NGINX_PKGS[@]}"
        fi
    fi

    success "Nginx installed from repository successfully!"
}
