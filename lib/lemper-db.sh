#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - MySQL / MariDB Database Manager                            |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
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

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="db"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Main Functions
##

##
# Trim whitespace.
# Ref: https://stackoverflow.com/a/3352015/12077262
##
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
}

function cmd_account_version() {
    echo "${CMD_PARENT} ${CMD_NAME} account version ${PROG_VERSION}"
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

    if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
        echo "Grants database '${DBNAME}' privileges to '${DBUSER}'@'${DBHOST}'"
        run "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ${DBPRIVILEGES} ON ${DBNAME}.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
        exit 0
    else
        fail "The specified database '${DBNAME}' does not exist."
    fi
}

# Creates a new account.
function cmd_account_create() {
    if [ "${DBUSER}" != "root" ]; then
        DBUSER=${DBUSER:-"${LEMPER_USERNAME}_$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"}
        DBPASS=${DBPASS:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

        # Create database account.
        if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
            fail "MySQL account ${DBUSER} is already exist. Please use another one!"
        else
            echo "Creating new MySQL account '${DBUSER}'@'${DBHOST}' using password ${DBPASS}..."

            run "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${DBUSER}'@'${DBHOST}' IDENTIFIED BY '${DBPASS}';"

            if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
                success "MySQL account ${DBUSER} has been created."
                [[ ${VERBOSE} == true ]] && echo -e "Below the account details:\nUsername: ${DBUSER}\nPassword: ${DBPASS}\nHost: ${DBHOST}"
            fi
        fi
    else
        fail "Root user is already exist. Please use another one!"
    fi
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
            if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "${SQL_QUERY}"; then
                success "The database's account '${DBUSER}'@'${DBHOST}' has been deleted."
            else
                fail "Unable to delete database account '${DBUSER}'@'${DBHOST}'."
            fi
        else
            info "SQL query: \"${SQL_QUERY}\""
        fi
    fi
}

# Update password.
function cmd_account_passwd() {
    DBPASS2=${DBPASS2:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

    if [ -z "${DBUSER}" ]; then
        fail "Please specify the account's username using --dbuser parameter."
    fi

    if [ -z "${DBPASS2}" ]; then
        error "Please specify the new password using --extra-args parameter (dbpass2)."
        echo "An example for passing extra arguments: --extra-args=\"dbpass2=newpass\""
        exit 1
    fi

    local SQL_QUERY="UPDATE mysql.user SET Password=PASSWORD('${DBPASS2}') WHERE USER='${DBUSER}' AND Host='${DBHOST}';"

    if [[ "${DRYRUN}" != true ]]; then
        if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "${SQL_QUERY}"; then
            success "Password for account '${DBUSER}'@'${DBHOST}' has been updated to '${DBPASS2}'."
        else
            fail "Unable to update password for '${DBUSER}'@'${DBHOST}'."
        fi
    else
        info "SQL query: \"${SQL_QUERY}\""
    fi
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
        exit 1
    fi

    local SQL_QUERY="RENAME USER '${DBUSER}'@'${DBHOST}' TO '${DBUSER2}'@'${DBHOST2}';"

    if [[ "${DRYRUN}" != true ]]; then
        if [[ "${DBUSER}" = "root" || "${DBUSER}" = "lemper" ]]; then
            fail "You are not allowed to rename this account."
        else
            if "${MYSQLCLI}" -u root -p"${DBROOT_PASS}" -e "${SQL_QUERY}"; then
                success "Database account '${DBUSER}'@'${DBHOST}' has been renamed to '${DBUSER2}'@'${DBHOST2}'."
            else
                fail "Unable to rename database account '${DBUSER}'@'${DBHOST}'."
            fi
        fi
    else
        info "SQL query: \"${SQL_QUERY}\""
    fi
}

# List all database users
function cmd_account_users() {
    DBUSER=${DBUSER:-"root"}
    DBPASS=${DBPASS:-""}
    [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"
                
    echo "List all existing database users."

    run "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "SELECT user,host FROM mysql.user;"
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
                exit 0
            ;;
            version | -v | --version)
                cmd_account_version
                exit 0
            ;;
            *)
                if declare -F "cmd_account_${SUBCOMMAND}" &>/dev/null; then
                    "cmd_account_${SUBCOMMAND}" "$@"
                else
                    echo "${CMD_PARENT} ${CMD_NAME} account: unrecognized command '${SUBCOMMAND}'" >&2
                    echo "Run '${CMD_PARENT} ${CMD_NAME} account --help' for a list of known commands." >&2
                    exit 1
                fi
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME} account: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} account --help' for more information."
        exit 1
    fi
}

##
# Initialize account sub command.
## 
function sub_cmd_account() {
    init_cmd_account "$@"
}

##
# Database Operations.
##
function db_operations() {
    OPTS=$(getopt -o a:H:P:u:p:n:b:C:g:f:q:x:DrhVv \
      -l action:,dbhost:,dbport:,dbuser:,dbpass:,dbname:,dbprefix:,dbcollation:,dbprivileges:,dbfile:,dbquery:,extra-args: \
      -l dry-run,root,help,verbose,version \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    # Args counter
    local MAIN_ARGS=0
    local BYPASSED_ARGS=""

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
                BYPASSED_ARGS="${BYPASSED_ARGS} --help"
            ;;
            -v | --version) 
                shift
                # Bypass args.
                BYPASSED_ARGS="${BYPASSED_ARGS} --version"
            ;;
            --) 
                shift
                break
            ;;
            *)
                fail "unrecognized option '${1}'"
                exit 1
            ;;
        esac
    done

    if [[ "${MAIN_ARGS}" -ge 1 ]]; then
        # Set default value.
        DBHOST=${DBHOST:-"localhost"}
        DBPORT=${DBPORT:-"3306"}
        DBUSER=${DBUSER:-""}
        DBPASS=${DBPASS:-""}
        DBNAME=${DBNAME:-""}
        DBPREFIX=${DBPREFIX:-""}
        DBCOLLATION=${DBCOLLATION:-"utf8_unicode_ci"}
        DBPRIVILEGES=${DBPRIVILEGES:-""}
        DBFILE=${DBFILE:-""}
        DBQUERY=${DBQUERY:-""}
        DRYRUN=${DRYRUN:-false}
        USEROOT=${USEROOT:-false}

        # Parse and export extra arguments.
        EXTRA_ARGS=${EXTRA_ARGS:-""}
        if [ -n "${EXTRA_ARGS}" ]; then
            SAVEIFS=${IFS}  # Save current IFS
            IFS=', ' read -r -a FIELDS <<< "${EXTRA_ARGS}"
            IFS=${SAVEIFS}    # Restore IFS

            for FIELD in "${FIELDS[@]}"; 
            do
                #export "${FIELD}"
                SAVEIFS=${IFS}  # Save current IFS
                IFS='= ' read -r -a ARG_PARTS <<< "${FIELD}"
                IFS=${SAVEIFS}    # Restore IFS
                #ARG=$(str_to_upper "${ARG_PARTS[0]}")
                ARG=${ARG_PARTS[0]}
                VAL=${ARG_PARTS[1]}
                export "${ARG^^}=${VAL}"
            done
        fi

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
                sub_cmd_account "$@" "${BYPASSED_ARGS}"
            ;;

            # Create / add new database.
            "create" | "add")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}

                [[ -z "${DBPASS}" || ${USEROOT} == true ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                DBNAME=${DBNAME:-"${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"}

                # Create database name.
                echo "Creating new MySQL database '${DBNAME}' grants access to '${DBUSER}'@'${DBHOST}'..."

                until ! "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; do
                    echo "Database '${DBNAME}' already exist, try another one..."
                    DBNAME="${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)"
                    echo "New auto-generated MySQL database '${DBNAME}'"
                done

                local SQL_QUERY="CREATE DATABASE ${DBNAME}; GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
                run "${MYSQLCLI}" -u root -p"${DBPASS}" -e "${SQL_QUERY}"

                if "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                    success "MySQL database '${DBNAME}' has been created."
                    exit 0
                else
                    fail "Failed creating database '${DBNAME}'."
                fi
            ;;

            # List all databases.
            "databases" | "list")
                DBUSER=${DBUSER:-"root"}
                local DATABASES

                if [[ -z "${DBPASS}" || "${USEROOT}" == true ]]; then
                    [[ -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"
                    DATABASES=$("${MYSQLCLI}" -u root -p"${DBPASS}" -h "${DBHOST}" -P "${DBPORT}" -e "SELECT Db,Host FROM mysql.db WHERE User='${DBUSER}';")
                else
                    DATABASES=$("${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -h "${DBHOST}" -P "${DBPORT}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")
                fi

                if [[ -n "${DATABASES}" ]]; then
                    DATABASES=$(grep -vE "Host" <<< "${DATABASES}")
                    SAVEIFS=${IFS}  # Save current IFS
                    IFS=$'\n'
                    # shellcheck disable=SC2206
                    DBS=(${DATABASES})
                    IFS=${SAVEIFS} # Restore IFS

                    echo "There are ${#DBS[@]} databases granted to '${DBUSER}'."
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
                    echo "No database found."
                fi
            ;;

            # Drope / delete database.
            "drop" | "delete")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the database name using the --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}

                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                if "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                    echo "Deleting database ${DBNAME}..."

                    run "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "DROP DATABASE ${DBNAME};"

                    if ! "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                        success "Database '${DBNAME}' has been dropped."
                    else
                        fail "Failed deleting database '${DBNAME}'."
                    fi
                else
                    fail "The specified database '${DBNAME}' does not exist."
                fi
            ;;

            # Export / dump database to file.
            "export")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the database name using the --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}

                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                DBFILE=${DBFILE:-"${DBNAME}_$(date '+%d-%m-%Y_%T').sql"}

                # Export database tables.
                echo "Exporting database ${DBNAME}'s tables..."

                if [[ -n $(command -v mysqldump) ]]; then
                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run mysqldump -u "${DBUSER}" -p"${DBPASS}" --databases "${DBNAME}" > "${DBFILE}"

                        if [[ -f "${DBFILE}" ]]; then
                            success "Database '${DBNAME}' has been successfully exported to '${DBFILE}'."
                        else
                            fail "Failed to export the database '${DBNAME}'."
                        fi
                    else
                        fail "The specified database '${DBNAME}' does not exist."
                    fi
                else
                    fial "Mysqldump is required to export database, but it is not available in your current stack. Please install it first."
                fi
            ;;

            # Import database from file.
            "import")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the database name using the --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}

                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                # Import database tables.
                if [[ -n "${DBFILE}" && -e "${DBFILE}" ]]; then
                    echo "Importing database ${DBNAME}'s tables..."

                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" "${DBNAME}" < "${DBFILE}"
                        echo "Database file '${DBFILE}' has been successfully imported to '${DBNAME}'."
                    else
                        fail "The specified database '${DBNAME}' does not exist."
                    fi
                else
                    fail "Please specifiy the database file (.sql) to import using --dbfile parameter."
                fi
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
                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -D "${DBNAME}" -e "${SQL_QUERY}"; then
                        success "The SQL query was applied to '${DBNAME}' using the account '${DBUSER}'@'${DBHOST}'."
                    else
                        fail "Failed to execute the SQL query on '${DBNAME}' using the account '${DBUSER}'@'${DBHOST}'."
                    fi
                else
                    info "SQL query: \"${SQL_QUERY}\""
                fi
            ;;

            *)
                echo "${CMD_PARENT} ${CMD_NAME}: '${ACTION}' is not valid sub command."
                echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
                exit 1
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
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
  export        Exports a database to a file or to STDOUT.
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

  --dbname=<database_name>
      Selected database that will be used for operations.

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

  --extra-args=<arguments>
      Passes extra arguments to the command or subcommand operations.


Example:
  ${CMD_PARENT} ${CMD_NAME} account create --dbuser=user --dbpass=secret

For help with each command run:
${CMD_PARENT} ${CMD_NAME} <command> -h|--help
EOL
}

function cmd_version() {
    echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
}

##
# Main Database CLI Wrapper
##
function init_lemper_db() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        local SUBCMD="${1}"
        shift # Pass the remaining arguments to the next function.

        case ${SUBCMD} in
            help | -h | --help)
                cmd_help
                exit 0
            ;;
            version | -v | --version)
                cmd_version
                exit 0
            ;;
            *)
                if declare -F "cmd_${SUBCMD}" &>/dev/null; then
                    "cmd_${SUBCMD}" "$@"
                else
                    echo "${CMD_PARENT} ${CMD_NAME}: unrecognized command '${SUBCMD}'" >&2
                    echo "Run '${CMD_PARENT} ${CMD_NAME} --help' for a list of known commands." >&2
                    exit 1
                fi
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_db "$@"
