#!/usr/bin/env bash

# PostgreSQL server installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 08/04/2023
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
##
function add_postgres_repo() {
    local POSTGRES_VERSION=${POSTGRES_VERSION:-"15"}
    local POSTGRES_REPO_KEY=${POSTGRES_REPO_KEY:-"ACCC4CF8"}

    case ${DISTRIB_NAME} in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list" ]]; then
                echo "Adding PostgreSQL repository key..."

                run bash -c "wget --quiet -O - https://www.postgresql.org/media/keys/${POSTGRES_REPO_KEY}.asc | apt-key add -"

                echo "Adding PostgreSQL repository..."

                run touch "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list"
                run bash -c "echo 'deb http://apt.postgresql.org/pub/repos/apt ${RELEASE_NAME}-pgdg main' > /etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list"
                run apt-get update -q -y
            else
                info "PostgreSQL ${POSTGRES_VERSION} repository already exists."
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

    #export POSTGRES_USER=${POSTGRES_USER:-"postgres"}
    export POSTGRES_USER="postgres"
    export PSQL_USER=${LEMPER_USERNAME:-"lemper"}
    export PSQL_PASS=${LEMPER_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

    local POSTGRES_VERSION=${POSTGRES_VERSION:-"15"}
    local POSTGRES_TEST_DB="${PSQL_USER}db"
    #local PGDATA=${POSTGRES_PGDATA:-"/var/lib/postgresql/data"}
    local POSTGRES_PKGS=()

    # Do PostgreSQL server installation here...
    if [[ ${DO_INSTALL_POSTGRES} == y* || ${DO_INSTALL_POSTGRES} == Y* ]]; then
        # Add repository.
        add_postgres_repo

        echo "Installing PostgreSQL server..."

        # Default PostgreSQL user
        #if [[ -z $(getent passwd "${POSTGRES_USER}") ]]; then
        #    run groupadd -r "${POSTGRES_USER}" --gid=999 && \
        #    run useradd -r -g "${POSTGRES_USER}" --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash "${POSTGRES_USER}" && \
        #    run mkdir -p /var/lib/postgresql && \
        #    run chown -hR "${POSTGRES_USER}":"${POSTGRES_USER}" /var/lib/postgresql
        #fi

        # Install Postgres
        if [[ "${POSTGRES_VERSION}" == "latest" || "${POSTGRES_VERSION}" == "stable" ]]; then
            POSTGRES_PKGS+=("postgresql" "postgresql-client" "postgresql-client-common" "postgresql-common")
        else
            POSTGRES_PKGS+=("postgresql-${POSTGRES_VERSION}" "postgresql-client-${POSTGRES_VERSION}" \
                "postgresql-client-common" "postgresql-common")
        fi

        run apt-get install -q -y "${POSTGRES_PKGS[@]}"

        #run mkdir -p /var/run/postgresql && \
        #run chown -R "${POSTGRES_USER}":"${POSTGRES_USER}" /var/run/postgresql && \
        #run chmod 2777 /var/run/postgresql
        #run mkdir -p "${PGDATA}" && \
        #run chown -R "${POSTGRES_USER}":"${POSTGRES_USER}" "${PGDATA}" && \
        #run chmod 777 "${PGDATA}"

        # Configure PostgreSQL installation.
        if [[ "${DRYRUN}" == true ]]; then
            info "PostgreSQL server installed in dry run mode."
        else
            if [[ -f "/lib/systemd/system/postgresql@${POSTGRES_VERSION}-main.service" ]]; then
                # Trying to reload daemon.
                run systemctl daemon-reload

                # Enable PostgreSQL on startup.
                run systemctl enable "postgresql@${POSTGRES_VERSION}-main.service"

                # Restart PostgreSQL service daemon.
                #run systemctl start "postgresql@${POSTGRES_VERSION}-main.service"
            fi

            if [[ $(pgrep -c postgres) -gt 0 || -n $(command -v psql) ]]; then
                success "PostgreSQL server installed successfully."

                if [[ -n $(command -v psql) ]]; then
                    echo "Creating PostgreSQL user '${POSTGRES_USER}' and database '${POSTGRES_TEST_DB}'."

                    # Create test role and database.
                    run sudo -i -u "${POSTGRES_USER}" -- psql -v ON_ERROR_STOP=1 <<-PGSQL
                        CREATE ROLE ${PSQL_USER} LOGIN PASSWORD '${PSQL_PASS}';
                        CREATE DATABASE ${POSTGRES_TEST_DB};
                        GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_TEST_DB} TO ${PSQL_USER};
PGSQL
                fi

                # Restart Postgres
                run systemctl restart "postgresql@${POSTGRES_VERSION}-main.service"

                if [[ $(pgrep -c postgres) -gt 0 ]]; then
                    success "PostgreSQL server configured successfully."
                elif [[ -n $(command -v postgres) ]]; then
                    # Server died? try to start it.
                    run systemctl start "postgresql@${POSTGRES_VERSION}-main.service"

                    if [[ $(pgrep -c postgres) -gt 0 ]]; then
                        success "PostgreSQL server configured successfully."
                    else
                        info "Something went wrong with PostgreSQL server installation."
                    fi
                fi
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
if [[ -n $(command -v postgres) && "${FORCE_INSTALL}" != true ]]; then
    info "PostgreSQL server already exists, installation skipped."
else
    init_postgres_install "$@"
fi
