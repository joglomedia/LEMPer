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

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list" ]]; then
                echo "Adding PostgreSQL repository..."

                run bash -c "curl -fsSL https://www.postgresql.org/media/keys/${POSTGRES_REPO_KEY}.asc | gpg --dearmor --yes -o /usr/share/keyrings/postgres-${RELEASE_NAME}.gpg" && \
                run touch "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [signed-by=/usr/share/keyrings/postgres-${RELEASE_NAME}.gpg] http://apt.postgresql.org/pub/repos/apt ${RELEASE_NAME}-pgdg main' > /etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list" && \
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

    export POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-"postgres"}
    export POSTGRES_DB_USER=${POSTGRES_DB_USER:-"${LEMPER_USERNAME}"}
    export POSTGRES_DB_PASS=${POSTGRES_DB_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

    local POSTGRES_VERSION=${POSTGRES_VERSION:-"15"}
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

        # Install Postgres
        if [[ "${POSTGRES_VERSION}" == "latest" || "${POSTGRES_VERSION}" == "stable" ]]; then
            POSTGRES_PKGS+=("postgresql" "postgresql-client" "postgresql-client-common" "postgresql-common")
        else
            POSTGRES_PKGS+=("postgresql-${POSTGRES_VERSION}" "postgresql-client-${POSTGRES_VERSION}" \
                "postgresql-client-common" "postgresql-common")
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
            if [[ -f "/lib/systemd/system/postgresql@${POSTGRES_VERSION}-main.service" ]]; then
                # Trying to reload daemon.
                run systemctl daemon-reload

                # Enable PostgreSQL on startup.
                run systemctl enable "postgresql@${POSTGRES_VERSION}-main.service"

                # Restart PostgreSQL service daemon.
                #run systemctl restart "postgresql@${POSTGRES_VERSION}-main.service"
            fi

            if [[ $(pgrep -c postgres) -gt 0 || -n $(command -v psql) ]]; then
                success "PostgreSQL server installed successfully."

                # Create default PostgreSQL role and database test.
                # Skip from GitHub Action due to unknown database connection issue.
                if [[ -n $(command -v psql) && "${SERVER_HOSTNAME}" != "gh-ci.lemper.cloud" ]]; then
                    echo "Creating PostgreSQL user '${POSTGRES_DB_USER}' and database '${POSTGRES_TEST_DB}'."

                    run sudo -i -u "${POSTGRES_SUPERUSER}" -- psql -v ON_ERROR_STOP=1 <<-PGSQL
                        CREATE ROLE ${POSTGRES_DB_USER} LOGIN PASSWORD '${POSTGRES_DB_PASS}';
                        CREATE DATABASE ${POSTGRES_TEST_DB};
                        GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_TEST_DB} TO ${POSTGRES_DB_USER};
PGSQL
                fi

                # Restart Postgres
                run systemctl restart "postgresql@${POSTGRES_VERSION}-main.service"
                sleep 3

                if [[ $(pgrep -c postgres) -gt 0 ]]; then
                    success "PostgreSQL server configured successfully."
                else
                    # Server died? try to start it.
                    run systemctl start "postgresql@${POSTGRES_VERSION}-main.service"

                    if [[ $(pgrep -c postgres) -gt 0 ]]; then
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
