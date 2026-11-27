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



function str_trim() {
    local str="$*"

    # Remove leading whitespace characters.
    str="${str#"${str%%[![:space:]]*}"}"

    # Remove trailing whitespace characters.
    str="${str%"${str##*[![:space:]]}"}"

    echo -n "${str}"
}

##
# Convert string to uppercase.
# Ref: https://unix.stackexchange.com/a/51987
##
function str_to_upper() {
    local str="$*"

    printf '%s\n' "${str}" | awk '{ print toupper($0) }'
}

##
# Account sub commands
##
function cmd_account_help() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} account ${PROG_VERSION}
LEMPer Stack database account manager,
create, update, delete, and manage MySQL/MariaDB database account.

Usage: ${CMD_PARENT} ${CMD_NAME} account [--version] [--help]
       <command> [<options>]

Default options are read from the following files in the given order:
/etc/lemper/lemper.conf

These are common ${CMD_PARENT} ${CMD_NAME} account subcommands used in various situations:
  access    Grants privileges to the existing user.
  create    Creates a new user.
  delete    Deletes the existing user.
  passwd    Updates password for the existing user.
  rename    Renames the existing user.
  revoke    Revokes privileges from the existing user.
  users     Lists all existing users.

For help with each command run:
${CMD_PARENT} ${CMD_NAME} account <command> -h|--help
EOL

return 0
}

function cmd_account_version() {
    echo "${CMD_PARENT} ${CMD_NAME} account version ${PROG_VERSION}"
    return 0
}

# Grant access privileges.
function cmd_account_access() {
    if [[ -z "${DBUSER}" ]]; then
        fail "Please specify the account's username using --dbuser parameter."
    fi

    if [[ -z "${DBNAME}" ]]; then
        fail "Please specify the database name using --dbname parameter."
    fi

    if [[ -z "${DBPRIVILEGES}" ]]; then
        DBPRIVILEGES="ALL PRIVILEGES"
    fi

    if MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root -e "SHOW DATABASES;" | grep -Fxq -- "${DBNAME}"; then
        echo "Grants database '${DBNAME}' privileges to '${DBUSER}'@'${DBHOST}'"
        local grant_schema
        grant_schema=$(lemper_db_grant_schema "$DBNAME") || return 1
        MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" run "${MYSQLCLI}" -u root -e "GRANT ${DBPRIVILEGES} ON \`$grant_schema\`.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
    else
        fail "The specified database '${DBNAME}' does not exist."
    fi

    return 0
}

# Creates a new account.
function cmd_account_create() {
    if [ "${DBUSER}" != "root" ]; then
        DBUSER=${DBUSER:-"${LEMPER_USERNAME}_$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"}
        DBPASS=${DBPASS:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

        lemper_db_validate || return 1

        # Create database account.
        if MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -Fxq -- "${DBUSER}"; then
            fail "MySQL account ${DBUSER} is already exist. Please use another one!"
        else
            echo "Creating new MySQL account '${DBUSER}'@'${DBHOST}'..."

            # Pass the statement through stdin so the password never shows
            # up in the mysql process arguments.
            if [[ "${DRYRUN}" == true ]]; then
                info "Would create MySQL account '${DBUSER}'@'${DBHOST}'."
            elif ! printf '%s\n' "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; CREATE USER '${DBUSER}'@'${DBHOST}' IDENTIFIED BY $(lemper_db_password_sql "$DBPASS");" \
                | MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root; then
                fail "Unable to create MySQL account '${DBUSER}'@'${DBHOST}'."
            fi

            if MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -Fxq -- "${DBUSER}"; then
                success "MySQL account ${DBUSER} has been created."

                if [[ ${VERBOSE} == true ]]; then
                    echo -e "Below the account details:\nUsername: ${DBUSER}\nPassword: ********\nHost: ${DBHOST}"
                fi
            fi
        fi
    else
        fail "Root user is already exist. Please use another one!"
    fi

    return 0
}

# Deletes an existing account.
function cmd_account_delete() {
    if [ -z "${DBUSER}" ]; then
        fail "Please specify the account's username using --dbuser parameter."
    fi

    if [[ "${DBUSER}" = "root" || "${DBUSER}" = "lemper" ]]; then
        fail "You're not allowed to delete this user."
    else
        local SQL_QUERY="DROP USER '${DBUSER}'@'${DBHOST}';"

        if [[ "${DRYRUN}" != true ]]; then
            if MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root -e "${SQL_QUERY}"; then
                success "The database's account '${DBUSER}'@'${DBHOST}' has been deleted."
            else
                fail "Unable to delete database account '${DBUSER}'@'${DBHOST}'."
            fi
        else
            info "SQL query: \"${SQL_QUERY}\""
        fi
    fi

    return 0
}

# Update password.
function cmd_account_passwd() {
    DBPASS2=${DBPASS2:-"${DBPASS}"}

    if [ -z "${DBUSER}" ]; then
        fail "Please specify the account's username using --dbuser parameter."
    fi

    if [ -z "${DBPASS2}" ]; then
        error "Please specify the new password using --dbpass-file."
        echo "Example: account passwd --dbuser=user --dbpass-file=/root/new-db.pass"
        return 1
    fi

    local SQL_QUERY
    SQL_QUERY="SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; ALTER USER '${DBUSER}'@'${DBHOST}' IDENTIFIED BY $(lemper_db_password_sql "$DBPASS2");"

    if [[ "${DRYRUN}" != true ]]; then
        if printf '%s\n' "${SQL_QUERY}" | MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQLCLI}" -u root; then
            success "Password for account '${DBUSER}'@'${DBHOST}' has been updated."
        else
            fail "Unable to update password for '${DBUSER}'@'${DBHOST}'."
        fi
    else
        info "Would update the password for account '${DBUSER}'@'${DBHOST}'."
    fi

    return 0
}

# Rename an existing account.
function cmd_account_rename() {
    DBHOST2=${DBHOST2:-"${DBHOST}"}
    DBUSER2=${DBUSER2:-""}
    DBROOT_PASS=${DBROOTPASS:-"${MYSQL_ROOT_PASSWORD}"}

    if [ -z "${DBUSER}" ]; then
        fail "Please specify the account's username using --dbuser parameter."
    fi

    if [ -z "${DBUSER2}" ]; then
        error "Please specify the new username using --extra-args parameter (dbuser2)."
        echo "An example for passing extra arguments: --extra-args=\"dbuser2=newuser,dbhost2=127.0.0.1\""
        return 1
    fi

    local SQL_QUERY="RENAME USER '${DBUSER}'@'${DBHOST}' TO '${DBUSER2}'@'${DBHOST2}';"

    if [[ "${DRYRUN}" != true ]]; then
        if [[ "${DBUSER}" = "root" || "${DBUSER}" = "lemper" ]]; then
            fail "You are not allowed to rename this account."
        else
            if MYSQL_PWD="${DBROOT_PASS}" "${MYSQLCLI}" -u root -e "${SQL_QUERY}"; then
                success "Database account '${DBUSER}'@'${DBHOST}' has been renamed to '${DBUSER2}'@'${DBHOST2}'."
            else
                fail "Unable to rename database account '${DBUSER}'@'${DBHOST}'."
            fi
        fi
    else
        info "SQL query: \"${SQL_QUERY}\""
    fi

    return 0
}

# List all database users
function cmd_account_users() {
    DBUSER=${DBUSER:-"root"}
    DBPASS=${DBPASS:-""}
    [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

    echo "List all existing database users."

    MYSQL_PWD="${DBPASS}" run "${MYSQLCLI}" -u "${DBUSER}" -e "SELECT user,host FROM mysql.user;"

    return 0
}

# Aliases to create.
function cmd_account_add() {
    cmd_account_create "$@"
}

# Aliases to create.
function cmd_account_new() {
    cmd_account_create "$@"
}

# Aliases to users.
function cmd_account_list() {
    cmd_account_users "$@"
}

# Initialize account subcommand.
function init_cmd_account() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        local SUBCOMMAND && \
        SUBCOMMAND=$(str_trim "${1}")
        shift # Pass the remaining arguments to the next function.

        case "${SUBCOMMAND}" in
            help | -h | --help)
                cmd_account_help
            ;;
            version | -v | --version)
                cmd_account_version
            ;;
            *)
                if declare -F "cmd_account_${SUBCOMMAND}" &>/dev/null; then
                    "cmd_account_${SUBCOMMAND}" "$@"
                else
                    echo "${CMD_PARENT} ${CMD_NAME} account: unrecognized command '${SUBCOMMAND}'" >&2
                    echo "Run '${CMD_PARENT} ${CMD_NAME} account --help' for a list of known commands." >&2
                    return 1
                fi
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME} account: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} account --help' for more information."
        return 1
    fi
}

##
# Initialize account sub command.
##
function sub_cmd_account() {
    init_cmd_account "$@"
}

##
# Back up a database to a timestamped gzip dump.
##
function db_backup_database() {
    lemper_load_module services/mariadb/database || return 1
    lemper_with_lock lemper_db_dump gzip
}

function db_restore_database() {
    lemper_load_module services/mariadb/database || return 1
    lemper_with_lock lemper_db_restore
}

##
# Database Operations.
##
function db_operations() {
    local DBHOST="" DBPORT="" DBUSER="" DBPASS="" DBPASS_FILE="" DBNAME="" DBPREFIX=""
    local DBCOLLATION="" DBPRIVILEGES="" DBFILE="" DBQUERY="" DBSCHEDULE="" EXTRA_ARGS="" DBKEEP=""
    local DBUSER2="" DBHOST2="" DBPASS2="" DBROOTPASS="" USEROOT=false
    local DRYRUN="${DRYRUN:-false}" VERBOSE="${VERBOSE:-false}"
    lemper_parse_args 'a:H:P:u:p:n:b:C:g:f:q:x:DrhVv' 'action:,dbhost:,dbport:,dbuser:,dbpass:,dbpass-file:,dbname:,dbprefix:,dbcollation:,dbprivileges:,dbfile:,dbquery:,dbschedule:,keep:,extra-args:,dry-run,root,help,verbose,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    # Args counter
    local MAIN_ARGS=0
    local BYPASSED_ARGS=()

    # Parse flags
    while true
    do
        case "${1}" in
            -a | --action)
                shift
                local ACTION="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -b | --dbprefix)
                shift
                DBPREFIX="${1}"
                shift
            ;;
            -C | --dbcollation)
                shift
                DBCOLLATION="${1}"
                shift
            ;;
            -f | --dbfile)
                shift
                DBFILE="${1}"
                shift
            ;;
            -g | --dbprivileges)
                shift
                DBPRIVILEGES="${1}"
                shift
            ;;
            -H | --dbhost)
                shift
                DBHOST="${1}"
                shift
            ;;
            -n | --dbname)
                shift
                DBNAME="${1}"
                shift
            ;;
            -p | --dbpass)
                shift
                DBPASS="${1}"
                shift
            ;;
            --dbpass-file)
                shift
                DBPASS_FILE="${1}"
                shift
            ;;
            -P | --dbport)
                shift
                DBPORT="${1}"
                shift
            ;;
            -q | --dbquery)
                shift
                DBQUERY="${1}"
                shift
            ;;
            -u | --dbuser)
                shift
                DBUSER="${1}"
                shift
            ;;
            -x | --extra-args)
                shift
                EXTRA_ARGS="${1}"
                shift
            ;;
            --keep)
                DBKEEP="$2"; export DBKEEP; shift 2
            ;;
            --dbschedule)
                shift
                DBSCHEDULE="${1}"
                shift
            ;;

            -D | --dry-run)
                shift
                DRYRUN=true
            ;;
            -r | --root)
                shift
                USEROOT=true
            ;;
            -V | --verbose)
                shift
                VERBOSE=true
            ;;

            -h | --help)
                shift
                # Bypass args.
                BYPASSED_ARGS+=(--help)
            ;;
            -v | --version)
                shift
                # Bypass args.
                BYPASSED_ARGS+=(--version)
            ;;
            --)
                shift
                break
            ;;
            *)
                fail "unrecognized option '${1}'"
                return 1
            ;;
        esac
    done

    if [[ ${#BYPASSED_ARGS[@]} -gt 0 ]]; then
        if [[ "${BYPASSED_ARGS[0]}" == --help ]]; then cmd_help; else cmd_version; fi
        return 0
    fi

    if [[ "${ACTION:-}" =~ ^(backup|restore|backup-schedule)$ && $# -gt 0 ]]; then
        [[ -z "$DBNAME" ]] || { error "Choose either a site domain or --dbname."; return 1; }
        if [[ "$ACTION" == restore ]]; then
            [[ $# == 2 && -z "$DBFILE" ]] || { error "Usage: db restore <domain> <file>."; return 1; }
            DBFILE="$2"
        else
            [[ $# == 1 ]] || { error "Expected one database site domain."; return 1; }
        fi
        lemper_load_module services/site/database || return 1
        DBNAME=$(lemper_site_database_for_domain "$1") || return 1
        shift "$#"
    fi

    if [[ "${MAIN_ARGS}" -ge 1 ]]; then
        # Set default value.
        DBHOST=${DBHOST:-"localhost"}
        DBPORT=${DBPORT:-"3306"}
        DBUSER=${DBUSER:-""}
        DBPASS=${DBPASS:-""}
        DBPASS_FILE=${DBPASS_FILE:-""}
        DBNAME=${DBNAME:-""}
        DBPREFIX=${DBPREFIX:-""}
        DBCOLLATION=${DBCOLLATION:-"utf8_unicode_ci"}
        DBPRIVILEGES=${DBPRIVILEGES:-""}
        DBFILE=${DBFILE:-""}
        DBQUERY=${DBQUERY:-""}
        DBSCHEDULE=${DBSCHEDULE:-""}
        DRYRUN=${DRYRUN:-false}
        USEROOT=${USEROOT:-false}

        # Extra arguments remain data and cannot overwrite command paths or process state.
        local fields=() field key value
        if [[ -n "$EXTRA_ARGS" ]]; then
            IFS=, read -r -a fields <<< "$EXTRA_ARGS"
            for field in "${fields[@]}"; do
                [[ "$field" == *=* ]] || { error "Invalid extra database argument."; return 1; }
                key="${field%%=*}"; value="${field#*=}"
                key="${key#"${key%%[![:space:]]*}"}"
                case "${key^^}" in
                    DBUSER2|DBHOST2|DBPASS2|DBROOTPASS) printf -v "${key^^}" '%s' "$value" ;;
                    *) error "Unsupported extra database argument."; return 1 ;;
                esac
            done
        fi
        lemper_load_module services/mariadb/database || return 1
        lemper_db_validate || return 1
        if [[ -z "$DBPASS" && -n "$DBPASS_FILE" ]]; then
            local owner mode
            [[ -f "$DBPASS_FILE" && -r "$DBPASS_FILE" && ! -L "$DBPASS_FILE" ]] || {
                error "Cannot read database password file."; return 1;
            }
            read -r owner mode < <(stat -c '%u %a' -- "$DBPASS_FILE") || return 1
            if [[ "$owner" != "$EUID" ]] || (( (8#$mode & 0077) != 0 )); then
                error "Database password file must be owned by the caller and private (0600)."; return 1
            fi
            IFS= read -r DBPASS < "$DBPASS_FILE" || [[ -n "$DBPASS" ]] || return 1
        fi
        [[ -n "$DBPASS" ]] || DBPASS="${LEMPER_DB_PASSWORD:-}"
        lemper_db_validate || return 1

        # Ensure mariadb / mysql command is available before performing database operations.
        if [[ -n $(command -v mariadb) ]]; then
            MYSQLCLI=$(command -v mariadb)
        elif [[ -n $(command -v mysql) ]]; then
            MYSQLCLI=$(command -v mysql)
        else
            fail "MariaDB/MySQL is required to perform database operations, but it is not available in your current stack. Please install one of them first."
        fi

        # Database operations based on supplied action argument.
        case "${ACTION}" in
            # Database account operations.
            "account")
                sub_cmd_account "$@" "${BYPASSED_ARGS[@]}"
            ;;

            # Backup database with timestamped dump + optional scheduling.
            "backup")
                db_backup_database || return $?
                return 0
            ;;

            # Restore database from a SQL dump file.
            "restore")
                db_restore_database || return $?
                return 0
            ;;

            # Schedule database backup via cron.
            "prune")
                lemper_with_lock lemper_db_prune || return $?
                return 0
            ;;
            "backup-schedule")
                lemper_with_lock lemper_db_schedule || return $?
                return 0
            ;;

            # Create / add new database.
            "create" | "add")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}

                [[ -z "${DBPASS}" || ${USEROOT} == true ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                DBNAME=${DBNAME:-"${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"}

                lemper_db_validate || return 1

                # Create database name.
                echo "Creating new MySQL database '${DBNAME}' grants access to '${DBUSER}'@'${DBHOST}'..."

                until ! MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u root -e "SHOW DATABASES;" | grep -Fxq -- "${DBNAME}"; do
                    echo "Database '${DBNAME}' already exist, try another one..."
                    DBNAME="${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)"
                    echo "New auto-generated MySQL database '${DBNAME}'"
                done

                local SQL_QUERY grant_schema
                grant_schema=$(lemper_db_grant_schema "$DBNAME") || return 1
                SQL_QUERY="CREATE DATABASE ${DBNAME}; GRANT ALL PRIVILEGES ON \`$grant_schema\`.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
                MYSQL_PWD="${DBPASS}" run "${MYSQLCLI}" -u root -e "${SQL_QUERY}"

                if MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u root -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -Fxq -- "${DBNAME}"; then
                    success "MySQL database '${DBNAME}' has been created and granted to '${DBUSER}'@'${DBHOST}'."
                else
                    fail "Failed creating database '${DBNAME}'."
                fi

                return 0
            ;;

            # List all databases.
            "databases" | "list")
                DBUSER=${DBUSER:-"root"}
                local DATABASES

                if [[ -z "${DBPASS}" || "${USEROOT}" == true ]]; then
                    [[ -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"
                    DATABASES=$(MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u root -h "${DBHOST}" -P "${DBPORT}" -e "SELECT Db,Host FROM mysql.db WHERE User='${DBUSER}';")
                else
                    DATABASES=$(MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u "${DBUSER}" -h "${DBHOST}" -P "${DBPORT}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")
                fi

                if [[ -n "${DATABASES}" ]]; then
                    DATABASES=$(grep -vE "Host" <<< "${DATABASES}")
                    SAVEIFS=${IFS}  # Save current IFS
                    IFS=$'\n'
                    # shellcheck disable=SC2206
                    DBS=(${DATABASES})
                    IFS=${SAVEIFS} # Restore IFS

                    success "There are ${#DBS[@]} databases granted to '${DBUSER}'."
                    echo "+-------------------------------------+"
                    echo "|         'database'@'host'           |"
                    echo "+-------------------------------------+"

                    for ((i=0; i<${#DBS[@]}; i++)); do
                        # shellcheck disable=SC2206
                        ROW=(${DBS[${i}]})
                        echo "| '${ROW[0]}'@'${ROW[1]}'"
                    done

                    echo "+-------------------------------------+"
                else
                    info "There is no database granted to '${DBUSER}'."
                fi

                return 0
            ;;

            # Drope / delete database.
            "drop" | "delete")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the database name using the --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}

                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                if MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u root -e "SHOW DATABASES;" | grep -Fxq -- "${DBNAME}"; then
                    echo "Deleting database ${DBNAME}..."

                    MYSQL_PWD="${DBPASS}" run "${MYSQLCLI}" -u "${DBUSER}" -e "DROP DATABASE ${DBNAME};"

                    if ! MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u root -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -Fxq -- "${DBNAME}"; then
                        success "Database '${DBNAME}' has been dropped."
                    else
                        fail "Failed deropping database '${DBNAME}'."
                    fi
                else
                    fail "The specified database '${DBNAME}' does not exist."
                fi

                return 0
            ;;

            # Export / dump database to file.
            "export")
                lemper_with_lock lemper_db_dump plain || return $?
                return 0
            ;;

            # Import uses the same protected client and failure contract as restore.
            "import")
                lemper_with_lock lemper_db_restore || return $?
                return 0
            ;;

            # Perform SQL query.
            "query")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the database name using the --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}

                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                echo "Executing the SQL query against the database '${DBNAME}'..."

                local SQL_QUERY=${DBQUERY:-""}

                if [[ "${DRYRUN}" != true ]]; then
                    if MYSQL_PWD="${DBPASS}" "${MYSQLCLI}" -u "${DBUSER}" -D "${DBNAME}" -e "${SQL_QUERY}"; then
                        success "The SQL query was applied to '${DBNAME}' using the account '${DBUSER}'@'${DBHOST}'."
                    else
                        fail "Failed to execute the SQL query on '${DBNAME}' using the account '${DBUSER}'@'${DBHOST}'."
                    fi
                else
                    info "SQL query: \"${SQL_QUERY}\""
                fi

                return 0
            ;;

            *)
                echo "${CMD_PARENT} ${CMD_NAME}: '${ACTION}' is not valid sub command."
                echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
                return 1
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        return 1
    fi
}

function cmd_account() {
    db_operations "--action=account" "$@"
}

function cmd_create() {
    db_operations "--action=create" "$@"
}

function cmd_add() {
    db_operations "--action=add" "$@"
}

function cmd_databases() {
    db_operations "--action=databases" "$@"
}

function cmd_drop() {
    db_operations "--action=drop" "$@"
}

function cmd_delete() {
    db_operations "--action=delete" "$@"
}

function cmd_export() {
    db_operations "--action=export" "$@"
}

function cmd_import() {
    db_operations "--action=import" "$@"
}

function cmd_backup() {
    db_operations "--action=backup" "$@"
}

function cmd_prune() {
    db_operations "--action=prune" "$@"
}

function cmd_restore() {
    db_operations "--action=restore" "$@"
}

function cmd_backup_schedule() {
    db_operations "--action=backup-schedule" "$@"
}

function cmd_optimize() {
    echo "Optimizes the database."
    db_operations "--action=optimize" "$@"
}

function cmd_query() {
    db_operations "--action=query" "$@"
}

function cmd_repair() {
    echo "Repairs the database."
    db_operations "--action=repair" "$@"
}

function cmd_reset() {
    echo "Removes all tables from the database."
    db_operations "--action=reset" "$@"
}

function cmd_search() {
    echo "Finds a string in the database."
    db_operations "--action=search" "$@"
}

function cmd_size() {
    echo "Displays the database name and size."
    db_operations "--action=size" "$@"
}

function cmd_tables() {
    echo "Lists the database tables."
    db_operations "--action=tables" "$@"
}

function cmd_users() {
    echo "Lists users."
    db_operations "--action=users" "$@"
}

function cmd_user() {
    cmd_account "$@"
}

# Aliases of cmd database.
function cmd_show() {
    cmd_databases "$@"
}

function cmd_list() {
    cmd_databases "$@"
}

##
# Prints help.
##
function cmd_help() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer Stack database manager,
create, update, delete, and manage MySQL/MariaDB database on Debian/Ubuntu server.

Usage: ${CMD_PARENT} ${CMD_NAME} [--version] [--help]
       <command> [<options>]

Default options are read from the following files in the given order:
/etc/lemper/lemper.conf

These are common ${CMD_PARENT} ${CMD_NAME} subcommands used in various situations:
  account       Manage database account.
  create        Creates a new database.
  databases     Lists the databases.
  drop          Deletes the database.
  export        Exports a database to a private plain SQL file.
  backup [domain] Creates a timestamped backup; domain resolves recorded site ownership.
  restore [domain file] Restores a database from a backup file.
  prune         Prunes verified SQL dumps according to --keep.
  backup-schedule [domain] Schedules automatic database backups via cron.
  import        Imports a database from a file or from STDIN.
  list          An aliases of databases sub command.
  optimize      Optimizes the database.
  query         Executes a SQL query against the database.
  repair        Repairs the database.
  reset         Removes all tables from the database.
  search        Finds a string in the database.
  show          An aliases of databases subcommand.
  size          Displays the database name and size.
  tables        Lists all tables from the database.
  user          An aliases of account subcommand.


GLOBAL PARAMETERS

  --dbhost=<hostname>
      MySQL database host / server address, default is localhost.

  --dbport=<port_number>
      MySQL database host / server port, default is 3306.

  --dbuser=<username>
      MySQL database account username.

  --dbpass=<password>
      MySQL database account password.

  --dbpass-file=<path>
      Read a single-line password from a caller-owned private file (0600).
      For account passwd, this supplies the new password.
      Prefer this (or the LEMPER_DB_PASSWORD environment variable) over
      --dbpass, which is visible to other users in the process list.

  --dbname=<database_name>
      Selected database that will be used for operations.

  --dbfile=<path>
      Backup directory, export filename, or restore/import input file.
      Backup directories must be root-owned and not writable by other users.

  --keep=<count>
      SQL dumps to retain; enables rotation after backup or selects prune count.

  --dbschedule=<schedule>
      Five numeric cron fields for backup-schedule (default: 0 2 * * *).

  --dbprefix=<prefix>
      Database name prefix, such as prefix_.

  --dbcollation=<collation>
      A set of rules used to compare characters in a particular character set, default is utf8_unicode_ci.

  --dbprivileges=<privileges>
      Granted to a MySQL account determine which operations the account can perform.

  --dbfile=<path>
      Path to the SQL database file.

  --dbquery=<SQL_query>
      A set of SQL query.

  --dbschedule=<cron_schedule>
      Cron schedule for automated backups (default: "0 2 * * *").
      Used with backup-schedule subcommand.

  --extra-args=<arguments>
      Passes extra arguments to the command or subcommand operations.


Example:
  ${CMD_PARENT} ${CMD_NAME} backup example.com
  ${CMD_PARENT} ${CMD_NAME} restore example.com /var/backups/lemper/ARCHIVE.sql.gz
  ${CMD_PARENT} ${CMD_NAME} backup-schedule example.com --dbschedule='0 2 * * *'
  ${CMD_PARENT} ${CMD_NAME} account create --dbuser=user --dbpass-file=/root/app-db.pass

For help with each command run:
${CMD_PARENT} ${CMD_NAME} <command> -h|--help
EOL

return 0
}

function cmd_version() {
    echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
    return 0
}

##
# Main Database CLI Wrapper
##
function lemper_database_command() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        local SUBCMD="${1}"
        [[ "$SUBCMD" != backup-schedule ]] || SUBCMD=backup_schedule
        shift # Pass the remaining arguments to the next function.

        case ${SUBCMD} in
            help | -h | --help)
                cmd_help
            ;;
            version | -v | --version)
                cmd_version
            ;;
            *)
                if declare -F "cmd_${SUBCMD}" &>/dev/null; then
                    "cmd_${SUBCMD}" "$@"
                else
                    echo "${CMD_PARENT} ${CMD_NAME}: unrecognized command '${SUBCMD}'" >&2
                    echo "Run '${CMD_PARENT} ${CMD_NAME} --help' for a list of known commands." >&2
                    return 1
                fi
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        return 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
