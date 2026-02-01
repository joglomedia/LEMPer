#!/usr/bin/env bash

# PostgreSQL server installer
# Min. Requirement  : GNU/Linux Ubuntu 20.04
# Last Build        : 02/01/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.6

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
# Add PostgreSQL Repository.
# Uses official PGDG repository setup method.
# Ref: https://wiki.postgresql.org/wiki/Apt
##
function add_postgres_repo() {
    local POSTGRES_REPO_KEY_URL="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
    local POSTGRES_REPO_KEY_PATH="/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc"
    local POSTGRES_REPO_FILE="/etc/apt/sources.list.d/pgdg.list"

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "${POSTGRES_REPO_FILE}" ]]; then
                echo "Adding PostgreSQL PGDG repository..."

                # Create directory for the key.
                run install -d /usr/share/postgresql-common/pgdg

                # Download and install the repository signing key.
                run curl -fsSL -o "${POSTGRES_REPO_KEY_PATH}" "${POSTGRES_REPO_KEY_URL}"

                # Add the repository to sources list.
                run bash -c "echo 'deb [signed-by=${POSTGRES_REPO_KEY_PATH}] https://apt.postgresql.org/pub/repos/apt ${RELEASE_NAME}-pgdg main' > ${POSTGRES_REPO_FILE}"

                # Update package lists.
                run apt-get update -q -y
            else
                info "PostgreSQL PGDG repository already exists."
            fi
        ;;
        *)
            error "Unable to add PostgreSQL repo, unsupported release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

##
# PostgreSQL service control helper.
# Tries multiple methods to start/stop/restart PostgreSQL:
# 1. systemctl (for systems with systemd running)
# 2. pg_ctlcluster (Debian/Ubuntu wrapper - works in containers)
# 3. service (legacy SysV init fallback)
##
function postgres_ctl() {
    local action="${1}"  # start, stop, restart, reload, status, enable, disable, daemon-reload
    local version="${2:-${POSTGRES_VERSION:-17}}"
    local cluster="${3:-main}"

    # Handle systemd-specific actions (only work with systemctl)
    case "${action}" in
        daemon-reload)
            if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
                systemctl daemon-reload 2>/dev/null && return 0
            fi
            return 0  # Non-fatal if systemd not available
        ;;
        enable|disable)
            if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
                systemctl "${action}" "postgresql@${version}-${cluster}.service" 2>/dev/null && return 0
            fi
            return 0  # Non-fatal if systemd not available
        ;;
    esac

    # Try systemctl first (for systems with systemd running)
    if command -v systemctl &>/dev/null; then
        # Check if systemd is actually running (not just installed)
        if systemctl is-system-running &>/dev/null 2>&1; then
            if systemctl "${action}" "postgresql@${version}-${cluster}.service" 2>/dev/null; then
                return 0
            fi
        fi
    fi

    # Fallback to pg_ctlcluster (Debian/Ubuntu - works in containers!)
    if command -v pg_ctlcluster &>/dev/null; then
        if sudo -u postgres pg_ctlcluster "${version}" "${cluster}" "${action}" 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback to service command (legacy SysV init)
    if command -v service &>/dev/null; then
        if service postgresql "${action}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

##
# Install Postgres.
##
function init_postgres_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_POSTGRES}" == true ]]; then
            local DO_INSTALL_POSTGRES="y"
        else
            local DO_INSTALL_POSTGRES="n"
        fi
    else
        while [[ "${DO_INSTALL_POSTGRES}" != y* && "${DO_INSTALL_POSTGRES}" != n* ]]; do
            read -rp "Do you want to install PostgreSQL server? [y/n]: " -i y -e DO_INSTALL_POSTGRES
        done
    fi

    export POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-"postgres"}
    export POSTGRES_DB_USER=${POSTGRES_DB_USER:-"${LEMPER_USERNAME}"}
    export POSTGRES_DB_PASS=${POSTGRES_DB_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9!@#%^&*' | fold -w 32 | head -n 1)}

    local POSTGRES_VERSION=${POSTGRES_VERSION:-"17"}
    local POSTGRES_PORT=${POSTGRES_PORT:-"5432"}
    local POSTGRES_TEST_DB="${POSTGRES_DB_USER}db"
    #local PGDATA=${POSTGRES_PGDATA:-"/var/lib/postgresql/data"}
    local POSTGRES_PKGS=()

    # Do PostgreSQL server installation here...
    if [[ ${DO_INSTALL_POSTGRES} == y* || ${DO_INSTALL_POSTGRES} == Y* ]]; then
        # Add repository.
        add_postgres_repo

        echo "Installing PostgreSQL server..."

        # Default PostgreSQL user
        #if [[ -z $(getent passwd "${POSTGRES_SUPERUSER}") ]]; then
        #    run groupadd -r "${POSTGRES_SUPERUSER}" --gid=999 && \
        #    run useradd -r -g "${POSTGRES_SUPERUSER}" --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash "${POSTGRES_SUPERUSER}" && \
        #    run mkdir -p /var/lib/postgresql && \
        #    run chown -hR "${POSTGRES_SUPERUSER}":"${POSTGRES_SUPERUSER}" /var/lib/postgresql
        #fi

        # Install Postgres packages.
        if [[ "${POSTGRES_VERSION}" == "latest" || "${POSTGRES_VERSION}" == "stable" ]]; then
            POSTGRES_PKGS+=("postgresql" "postgresql-client" "postgresql-contrib" \
                "postgresql-client-common" "postgresql-common")
        else
            POSTGRES_PKGS+=("postgresql-${POSTGRES_VERSION}" "postgresql-client-${POSTGRES_VERSION}" \
                "postgresql-contrib-${POSTGRES_VERSION}" "postgresql-client-common" "postgresql-common")
        fi

        run apt-get install -q -y "${POSTGRES_PKGS[@]}"

        #run mkdir -p /var/run/postgresql && \
        #run chown -R "${POSTGRES_SUPERUSER}":"${POSTGRES_SUPERUSER}" /var/run/postgresql && \
        #run chmod 2777 /var/run/postgresql
        #run mkdir -p "${PGDATA}" && \
        #run chown -R "${POSTGRES_SUPERUSER}":"${POSTGRES_SUPERUSER}" "${PGDATA}" && \
        #run chmod 777 "${PGDATA}"

        # Configure PostgreSQL installation.
        if [[ "${DRYRUN}" == true ]]; then
            info "PostgreSQL server installed in dry run mode."
        else
            if [[ -f "/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf" ]]; then
                sed -i "s/port\ =\ [0-9]*/port\ =\ ${POSTGRES_PORT}/g" "/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf"
            fi

            # Start PostgreSQL service if cluster is available.
            if [[ -d "/etc/postgresql/${POSTGRES_VERSION}/main" ]]; then
                # Reload systemd daemon and enable service on startup.
                postgres_ctl daemon-reload "${POSTGRES_VERSION}" main
                postgres_ctl enable "${POSTGRES_VERSION}" main

                # Start PostgreSQL service using helper (tries systemctl, pg_ctlcluster, service).
                if ! postgres_ctl start "${POSTGRES_VERSION}" main; then
                    info "Could not start PostgreSQL service (may be in container/CI environment)."
                fi
                sleep 2
            fi

            if pg_isready -q 2>/dev/null || [[ $(pgrep -c postgres) -gt 0 ]] || [[ -n $(command -v psql) ]]; then
                success "PostgreSQL server installed successfully."

                # Create default PostgreSQL role and database test.
                # Skip from GitHub Action due to unknown database connection issue.
                if [[ -n $(command -v psql) && "${SERVER_HOSTNAME}" != "gh-ci.lemper.cloud" ]]; then
                    echo "Creating PostgreSQL user '${POSTGRES_DB_USER}' and database '${POSTGRES_TEST_DB}'."

                    # Restart PostgreSQL service using helper.
                    if ! postgres_ctl restart "${POSTGRES_VERSION}" main; then
                        info "Could not restart PostgreSQL service."
                    fi
                    sleep 3

                    run sudo -i -u "${POSTGRES_SUPERUSER}" -- psql -v ON_ERROR_STOP=1 <<-PGSQL
                        CREATE USER ${POSTGRES_DB_USER} WITH PASSWORD '${POSTGRES_DB_PASS}';
                        CREATE DATABASE ${POSTGRES_TEST_DB} WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0 OWNER=${POSTGRES_DB_USER};
                        GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_TEST_DB} TO ${POSTGRES_DB_USER};
                        ALTER USER ${POSTGRES_DB_USER} CREATEDB;
PGSQL
                fi

                if pg_isready -q 2>/dev/null || [[ $(pgrep -c postgres) -gt 0 ]]; then
                    success "PostgreSQL server configured successfully."
                else
                    # Server died? try to start it using helper.
                    if ! postgres_ctl start "${POSTGRES_VERSION}" main; then
                        info "Could not start PostgreSQL service."
                    fi

                    if pg_isready -q 2>/dev/null || [[ $(pgrep -c postgres) -gt 0 ]]; then
                        success "PostgreSQL server configured successfully."
                    else
                        info "Something went wrong with PostgreSQL server configuration."
                    fi
                fi

                # Save config.
                save_config -e "POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER}\nPSQL_DB_USER=${POSTGRES_DB_USER}\nPSQL_DB_PASS=${POSTGRES_DB_PASS}\nPSQL_DB_TEST=${POSTGRES_TEST_DB}"

                # Save log.
                save_log -e "Postgres server credentials.\nPostgres default user: ${POSTGRES_SUPERUSER}, Postgres DB Username: ${POSTGRES_DB_USER}, Postgres DB Password: ${POSTGRES_DB_PASS}, Postgres DB Test: ${POSTGRES_TEST_DB}\nSave this credential and use it to authenticate your PostgreSQL test database connection."
            else
                info "Something went wrong with PostgreSQL server installation."
            fi
        fi
    else
        info "PostgreSQL installation skipped."
    fi
}

echo "[PostgreSQL Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v psql) && "${FORCE_INSTALL}" != true ]]; then
    info "PostgreSQL server already exists, installation skipped."
else
    init_postgres_install "$@"
fi
