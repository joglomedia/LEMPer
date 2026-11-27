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
# Add MongoDB repository.
##
function add_mongodb_repo() {
    lemper_load_module services/apt/catalog || return 1
    lemper_apt_prepare_repository mongodb || return 1
    lemper_exec apt-get update -q -y
}

function lemper_mongodb_security_unit() {
    local file="$1" phase="$2" staged
    local command='/usr/bin/mongod --config /etc/mongod.conf --bind_ip 127.0.0.1 --port 27017 --nounixsocket --auth'
    # Shell expansions belong to the service process, after namespace setup.
    # shellcheck disable=SC2016
    local namespace_guard='host=$(/usr/bin/readlink /proc/1/ns/net); current=$(/usr/bin/readlink /proc/self/ns/net);'
    # shellcheck disable=SC2016
    namespace_guard+=' if [[ -z "$host" || -z "$current" || "$host" == "$current" ]]; then'
    namespace_guard+=' echo "MongoDB bootstrap requires an isolated network namespace." >&2; exit 1; fi;'
    lemper_directory_trusted "${file%/*}" || return 1
    lemper_exec install -d -m 0755 "${file%/*}" || return 1
    staged=$(mktemp "$file.XXXXXXXX") || return 1
    if ! {
        printf '%s\n' '# Managed by LEMPer' '[Service]' 'ExecStart='
        if [[ "$phase" == bootstrap ]]; then
            # Some systemd builds proceed when PrivateNetwork cannot be applied.
            # Verify isolation in the process that will become mongod.
            printf "ExecStart=:!/bin/bash -ec '%s exec /usr/bin/setpriv --reuid mongodb --regid mongodb --init-groups %s'\n" \
                "$namespace_guard" "$command"
            printf '%s\n' 'PrivateNetwork=true'
        else
            printf 'ExecStart=%s --setParameter enableLocalhostAuthBypass=0\n' "$command"
            printf '%s\n' 'PrivateNetwork=false'
        fi
        printf '%s\n' 'PrivateTmp=true'
    } > "$staged" || ! chmod 0644 "$staged" || ! lemper_exec mv -Tf -- "$staged" "$file"; then
        rm -f -- "$staged"
        return 1
    fi
    lemper_exec systemctl daemon-reload
}

# Feed a noninteractive shell through stdin. Credentials never enter its arguments.
function lemper_mongodb_admin_check() {
    local phase="$1" user="$2" password="$3" pid="${4:-}" user_json password_json net host_net
    local -a client=(env -u MONGODB_ADMIN_PASSWORD -u MONGODB_ADMIN_PASS mongosh
        --quiet --norc --host 127.0.0.1 --port 27017 admin --file /dev/stdin)
    if [[ "$phase" == bootstrap ]]; then
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
        net=$(readlink "/proc/$pid/ns/net") && host_net=$(readlink /proc/self/ns/net) || return 1
        [[ "$net" != "$host_net" ]] || return 1
        client=(nsenter --target "$pid" --net -- "${client[@]}")
    fi
    user_json=$(printf '%s' "$user" | jq -Rs .) || return 1
    password_json=$(printf '%s' "$password" | jq -Rs .) || return 1
    {
        printf 'const user = %s;\nconst password = %s;\n' "$user_json" "$password_json"
        cat <<'JS'
function verifyAdmin() {
    try {
        db.auth(user, password);
        return db.adminCommand({serverStatus: 1}).ok === 1;
    } catch (error) {
        return false;
    }
}
JS
        if [[ "$phase" == bootstrap ]]; then
            cat <<'JS'
if (!verifyAdmin()) {
    try {
        db.createUser({user, pwd: password, roles: [{role: "root", db: "admin"}]});
    } catch (error) {
        quit(1);
    }
}
JS
        else
            cat <<'JS'
try {
    if (db.adminCommand({serverStatus: 1}).code !== 13) quit(1);
} catch (error) {
    if (error.code !== 13) quit(1);
}
JS
        fi
        printf '%s\n' 'quit(verifyAdmin() ? 0 : 1);'
    } | timeout 5 "${client[@]}" >/dev/null 2>&1
}

function lemper_mongodb_save_profile() (
    local mongo_user="$1" mongo_password="$2" profile=/etc/lemper/lemper.conf
    local stage prepared="" key value
    init_config && lemper_load_module core/config-update || return 1
    [[ -f "$profile" && ! -L "$profile" ]] || return 1
    stage=$(mktemp "$profile.mongo.XXXXXXXX") || return 1
    trap '[[ -z "$stage" ]] || secure_shred "$stage"; [[ -z "$prepared" ]] || secure_shred "$prepared"' EXIT
    cp -- "$profile" "$stage" || return 1
    for key in MONGODB_HOST MONGODB_PORT MONGODB_ADMIN_USER MONGODB_ADMIN_PASS MONGODB_ADMIN_PASSWORD; do
        case "$key" in
            MONGODB_HOST) value=127.0.0.1 ;;
            MONGODB_PORT) value=27017 ;;
            MONGODB_ADMIN_USER) value="$mongo_user" ;;
            MONGODB_ADMIN_PASS) value="$mongo_password" ;;
            MONGODB_ADMIN_PASSWORD) value="" ;;
        esac
        prepared=$(core_config_prepare_value "$stage" "$key" "$value") || return 1
        [[ -z "$prepared" ]] || lemper_exec mv -Tf -- "$prepared" "$stage" || return 1
        prepared=""
    done
    lemper_exec mv -Tf -- "$stage" "$profile" || return 1
    stage=""
)

function lemper_mongodb_managed_install() {
    local state="$1" dropin="$2"
    local mongo_user mongo_password staged phase=bootstrap pid attempt
    local -a packages=(mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-tools
        mongodb-org-mongos mongodb-database-tools mongodb-database-tools-extra mongodb-mongosh)

    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would install MongoDB and enroll its administrator in a private network namespace."
        return 0
    fi
    lemper_directory_trusted "$state" || return 1
    if [[ -f "$state/configured" && ! -L "$state/configured" ]]; then
        phase=normal
        mongo_user="${MONGODB_ADMIN_USER:-lemperdb}"
        mongo_password="${MONGODB_ADMIN_PASS:-${MONGODB_ADMIN_PASSWORD:-}}"
    elif [[ -f "$state/pending" && ! -L "$state/pending" && "$(stat -c '%u:%a' "$state/pending")" == 0:600 ]]; then
        {
            IFS= read -r mongo_user && IFS= read -r mongo_password
        } < "$state/pending" || return 1
    else
        if command -v mongod >/dev/null || [[ -e /etc/mongod.conf || -L /etc/mongod.conf ]] ||
            [[ -d /var/lib/mongodb && -n "$(find /var/lib/mongodb -mindepth 1 -print -quit)" ]] ||
            systemctl cat mongod.service >/dev/null 2>&1; then
            warning "Preserving existing MongoDB service and data. Review its authorization policy separately."
            return 0
        fi
        mongo_user="${MONGODB_ADMIN_USER:-lemperdb}"
        mongo_password="${MONGODB_ADMIN_PASSWORD:-${MONGODB_ADMIN_PASS:-$(openssl rand -hex 32)}}"
    fi
    if [[ ! "$mongo_user" =~ ^[A-Za-z0-9_.-]{1,64}$ || ! "$mongo_password" =~ ^[A-Za-z0-9_.+-]{16,256}$ ]]; then
        error "MongoDB requires a valid administrator name and a password of at least 16 supported characters."
        return 1
    fi
    lemper_exec install -d -m0700 "$state" || return 1
    if [[ "$phase" == bootstrap && ! -f "$state/pending" ]]; then
        staged=$(mktemp "$state/.pending.XXXXXXXX") || return 1
        if ! printf '%s\n%s\n' "$mongo_user" "$mongo_password" > "$staged" ||
            ! lemper_exec mv -Tf -- "$staged" "$state/pending"; then
            rm -f -- "$staged"
            return 1
        fi
    fi

    # Package maintainer scripts may start the daemon immediately.
    lemper_mongodb_security_unit "$dropin" "$phase" || return 1
    if ! command -v mongod >/dev/null || ! command -v mongosh >/dev/null; then
        add_mongodb_repo && lemper_exec apt-get install -q -y "${packages[@]}" || return 1
    fi
    lemper_exec systemctl restart mongod.service || return 1
    if [[ "$phase" == bootstrap ]]; then
        for attempt in {1..10}; do
            pid=$(systemctl show --property=MainPID --value mongod.service) || return 1
            if lemper_mongodb_admin_check bootstrap "$mongo_user" "$mongo_password" "$pid"; then break; fi
            [[ "$attempt" != 10 ]] || { error "MongoDB isolated enrollment failed; retry the managed installation."; return 1; }
            sleep 1
        done
        lemper_mongodb_save_profile "$mongo_user" "$mongo_password" || return 1
        lemper_mongodb_security_unit "$dropin" normal || return 1
        lemper_exec systemctl restart mongod.service || return 1
    fi
    for attempt in {1..10}; do
        if lemper_mongodb_admin_check normal "$mongo_user" "$mongo_password"; then break; fi
        if [[ "$attempt" == 10 ]]; then
            lemper_exec systemctl stop mongod.service
            error "MongoDB authorization could not be verified. The managed service was stopped."
            return 1
        fi
        sleep 1
    done
    lemper_exec systemctl enable mongod.service || return 1
    if [[ "$phase" == bootstrap ]]; then
        lemper_exec install -m0600 /dev/null "$state/configured" || return 1
    fi
    lemper_exec rm -f -- "$state/pending" || return 1
    success "MongoDB administrator authenticated and anonymous administration was denied."
}

##
# Initialize MongoDB Installation.
##
function init_mongodb_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MONGODB}" == true ]]; then
            DO_INSTALL_MONGODB="y"
        else
            DO_INSTALL_MONGODB="n"
        fi
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to install MongoDB server? [y/n]: " -i y -e DO_INSTALL_MONGODB
        done
    fi

    if [[ ${DO_INSTALL_MONGODB} == y* || ${DO_INSTALL_MONGODB} == Y* ]]; then
        lemper_mongodb_managed_install /var/lib/lemper/mongodb \
            /etc/systemd/system/mongod.service.d/90-lemper-security.conf
    else
        info "MongoDB server installation skipped."
    fi
}

function lemper_mongodb_install_entry() {
    case "${RELEASE_NAME}" in
        bookworm)
            MONGODB_VERSION="7.0"
            ;;
        jammy)
            if version_older_than "${MONGODB_VERSION}" "6.0"; then
                MONGODB_VERSION="6.0"
            fi
            ;;
        *)
            MONGODB_VERSION=${MONGODB_VERSION:-"6.0"}
            ;;
    esac
    echo "[MongoDB ${MONGODB_VERSION} Server Installation]"
    if command -v mongod >/dev/null && [[ "${FORCE_INSTALL:-false}" != true && ! -f /var/lib/lemper/mongodb/pending ]]; then
        info "MongoDB server already exists, installation skipped."
    else
        init_mongodb_install "$@"
    fi
}
