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
PROG_NAME=$(basename "$0")
PROG_VER="2.x.x"
CMD_PARENT="lemper-cli"
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
# Prints help.
##
function cmd_help() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VER}
Command line database management tool for LEMPer stack.

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

    exit 0
}

function cmd_version() {
    echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VER}"
    exit 0
}

function cmd_account() {
    db_ops "--action=account" "$@"
}

function cmd_create() {
    db_ops "--action=create" "$@"
}

function cmd_add() {
    db_ops "--action=add" "$@"
}

function cmd_databases() {
    db_ops "--action=databases" "$@"
}

function cmd_list() {
    db_ops "--action=list" "$@"
}

function cmd_drop() {
    db_ops "--action=drop" "$@"
}

function cmd_delete() {
    db_ops "--action=delete" "$@"
}

function cmd_export() {
    db_ops "--action=export" "$@"
}

function cmd_import() {
    db_ops "--action=import" "$@"
}

function cmd_optimize() {
    echo "Optimizes the database."
    db_ops "--action=optimize" "$@"
}

function cmd_query() {
    db_ops "--action=query" "$@"
}

function cmd_repair() {
    echo "Repairs the database."
    db_ops "--action=repair" "$@"
}

function cmd_reset() {
    echo "Removes all tables from the database."
    db_ops "--action=reset" "$@"
}

function cmd_search() {
    echo "Finds a string in the database."
    db_ops "--action=search" "$@"
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

function cmd_size() {
    echo "Displays the database name and size."
    db_ops "--action=size" "$@"
}

function cmd_tables() {
    echo "Lists the database tables."
    db_ops "--action=tables" "$@"
}

function cmd_users() {
    echo "Lists users."
    db_ops "--action=users" "$@"
}

##
# Initialize account subcommand.
## 
function sub_cmd_account() {
    # account subcommands
    function cmd_account_help() {
        cat <<- EOL
${PROG_NAME} ${PROG_VER}
Command line database management tool for LEMPer stack.

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

        exit 0
    }

    function cmd_account_version() {
        echo "${CMD_PARENT} ${CMD_NAME} account version ${PROG_VER}"
        exit 0
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

        #if [ -d "/var/lib/mysql/${DBNAME}" ]; then
        if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
            echo "Grants database '${DBNAME}' privileges to '${DBUSER}'@'${DBHOST}'"
            run "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ${DBPRIVILEGES} ON ${DBNAME}.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
        else
            error "Specified database '${DBNAME}' does not exist."
            exit 1
        fi
    }

    # Creates a new account.
    function cmd_account_create() {
        if [ "${DBUSER}" != "root" ]; then
            DBUSER=${DBUSER:-"${LEMPER_USERNAME}_$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"}
            DBPASS=${DBPASS:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

            # Create database account.
            if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
                error "MySQL account ${DBUSER} is already exist. Please use another one!"
                exit 1
            else
                echo "Creating new MySQL account '${DBUSER}'@'${DBHOST}' using password ${DBPASS}..."

                run "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${DBUSER}'@'${DBHOST}' IDENTIFIED BY '${DBPASS}';"

                if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
                    success "MySQL account ${DBUSER} has been created."
                    [[ ${VERBOSE} == true ]] && echo -e "Below the account details:\nUsername: ${DBUSER}\nPassword: ${DBPASS}\nHost: ${DBHOST}"
                fi

                exit 0
            fi
        else
            error "Root user is already exist. Please use another one!"
            exit 1
        fi
    }

    # Deletes an existing account.
    function cmd_account_delete() {
        if [ -z "${DBUSER}" ]; then
            fail "Please specify the account's username using --dbuser parameter."
        fi

        if [[ "${DBUSER}" = "root" || "${DBUSER}" = "lemper" ]]; then
            error "You're not allowed to delete this user."
            exit 1
        else
            local SQL_QUERY="DROP USER '${DBUSER}'@'${DBHOST}';"

            if ! "${DRYRUN}"; then
                if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "${SQL_QUERY}"; then
                    success "The database's account '${DBUSER}'@'${DBHOST}' has been deleted."
                else
                    error "Unable to delete database account '${DBUSER}'@'${DBHOST}'."
                    exit 1
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
            echo "An example for passing extra arguments: --extra-args=\"dbuser2=newuser,dbhost2=127.0.0.1\""
            exit 1
        fi

        local SQL_QUERY="UPDATE mysql.user SET Password=PASSWORD('${DBPASS2}') WHERE USER='${DBUSER}' AND Host='${DBHOST}';"

        if ! "${DRYRUN}"; then
            if "${MYSQLCLI}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "${SQL_QUERY}"; then
                success "Password for account '${DBUSER}'@'${DBHOST}' has been updated to '${DBPASS2}'."
            else
                error "Unable to update password for '${DBUSER}'@'${DBHOST}'."
                exit 1
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

        if ! "${DRYRUN}"; then
            if [[ "${DBUSER}" = "root" || "${DBUSER}" = "lemper" ]]; then
                error "You are not allowed to rename this account."
                exit 1
            else
                if "${MYSQLCLI}" -u root -p"${DBROOT_PASS}" -e "${SQL_QUERY}"; then
                    success "Database account '${DBUSER}'@'${DBHOST}' has been renamed to '${DBUSER2}'@'${DBHOST2}'."
                else
                    error "Unable to rename database account '${DBUSER}'@'${DBHOST}'."
                    exit 1
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

    init_cmd_account "$@"
}

##
# Main Database Operations.
##
function db_ops() {
    OPTS=$(getopt -o a:H:P:u:p:n:b:C:g:f:q:x:DrhVv \
      -l action:,dbhost:,dbport:,dbuser:,dbpass:,dbname:,dbprefix:,dbcollation:,dbprivileges:,dbfile:,dbquery:,extra-args: \
      -l dry-run,root,help,verbose,version \
      -n "${CMD_PARENT} ${CMD_NAME}" -- "$@")

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
                DBHOST=${1}
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
                DBPORT=${1}
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

    if [ ${MAIN_ARGS} -ge 1 ]; then
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
            for FIELD in "${FIELDS[@]}"; do
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
            fail "MariaDB / MySQL is required to perform database operations, but not available on your stack. Please install it first!"
        fi

        # Database operations based on supplied action argument.
        case "${ACTION}" in
            "account")
                sub_cmd_account "$@" "${BYPASSED_ARGS}"
            ;;

            "create" | "add")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ -z "${DBPASS}" || ${USEROOT} == true ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                DBNAME=${DBNAME:-"${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"}

                # Create database name.
                echo "Creating new MySQL database '${DBNAME}' grants access to '${DBUSER}'@'${DBHOST}'..."

                until ! "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; do
                    echo "Database ${DBNAME} already exist, try another one..."
                    DBNAME="${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)"
                    echo "New auto-generated MySQL database '${DBNAME}'"
                done

                local SQL_QUERY="CREATE DATABASE ${DBNAME}; GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
                run "${MYSQLCLI}" -u root -p"${DBPASS}" -e "${SQL_QUERY}"

                if "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                    success "MySQL database '${DBNAME}' has been created."
                    exit 0
                else
                    error "Failed creating database '${DBNAME}'."
                    exit 1
                fi
            ;;

            "databases" | "list")
                DBUSER=${DBUSER:-"root"}
                local DATABASES

                if [[ -z "${DBPASS}" || ${USEROOT} == true ]]; then
                    [[ -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"
                    DATABASES=$(mysql -u root -p"${DBPASS}" -h "${DBHOST}" -P "${DBPORT}" -e "SELECT Db,Host FROM mysql.db WHERE User='${DBUSER}' AND Grant_priv='Y';")
                else
                    DATABASES=$(mysql -u "${DBUSER}" -p"${DBPASS}" -h "${DBHOST}" -P "${DBPORT}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")
                fi

                if [[ -n "${DATABASES}" ]]; then
                    DATABASES=$(grep -vE "Host" <<< "${DATABASES}")
                    SAVEIFS=${IFS}  # Save current IFS
                    IFS=$'\n'
                    # shellcheck disable=SC2206
                    DBS=(${DATABASES})
                    IFS=${SAVEIFS} # Restore IFS

                    echo "There are ${#DBS[@]} databases granted to '${DBUSER}'."
                    echo "+------------------------------+"
                    echo "|  'database'@'host'"
                    echo "+------------------------------+"

                    #for DB in "${DBS[@]}"; do
                    #    echo "|  ${DB}"
                    #done
                    for ((i=0; i<${#DBS[@]}; i++)); do
                        # shellcheck disable=SC2206
                        ROW=(${DBS[${i}]})
                        echo "| '${ROW[0]}'@'${ROW[1]}'"
                    done

                    echo "+------------------------------+"
                else
                    echo "No database found."
                fi
            ;;

            "drop" | "delete")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                #if [ -d "/var/lib/mysql/${DBNAME}" ]; then
                if "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                    echo "Deleting database ${DBNAME}..."

                    run "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "DROP DATABASE ${DBNAME};"

                    if ! "${MYSQLCLI}" -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                        success "Database '${DBNAME}' has been dropped."
                    else
                        error "Failed deleting database '${DBNAME}'."
                        exit 1
                    fi
                else
                    error "Specified database '${DBNAME}' does not exist."
                    exit 1
                fi
            ;;

            "export")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                DBFILE=${DBFILE:-"${DBNAME}_$(date '+%d-%m-%Y_%T').sql"}

                # Export database tables.
                echo "Exporting database ${DBNAME}'s tables..."

                if [[ -n $(command -v mysqldump) ]]; then
                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run mysqldump -u "${DBUSER}" -p"${DBPASS}" --databases "${DBNAME}" > "${DBFILE}"
                        [ -f "${DBFILE}" ] && success "database ${DBNAME} exported to ${DBFILE}."
                    else
                        error "Specified database '${DBNAME}' does not exist."
                        exit 1
                    fi
                else
                    fail "Mysqldump is required to export database, but not available on your stack. Please install it first!"
                fi
            ;;

            "import")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                # Import database tables.
                if [[ -n "${DBFILE}" && -e "${DBFILE}" ]]; then
                    echo "Importing '${DBNAME}' database's tables..."

                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" "${DBNAME}" < "${DBFILE}"
                        echo "Database file '${DBFILE}' imported to '${DBNAME}'."
                    else
                        error "Specified database '${DBNAME}' does not exist."
                        exit 1
                    fi
                else
                    fail "Please specifiy the database file (.sql) to import using --dbfile parameter."
                fi
            ;;

            "query")
                if [[ -z "${DBNAME}" ]]; then
                    fail "Please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASSWORD}"

                echo "Executes a SQL query against the database."

                local SQL_QUERY=${DBQUERY:-""}

                if ! "${DRYRUN}"; then
                    if "${MYSQLCLI}" -u "${DBUSER}" -p"${DBPASS}" -D "${DBNAME}" -e "${SQL_QUERY}"; then
                        success "SQL query applied to ${DBNAME} as '${DBUSER}'@'${DBHOST}'."
                    else
                        error "Unable to execute SQL query on ${DBNAME} as '${DBUSER}'@'${DBHOST}'."
                        exit 1
                    fi
                else
                    info "SQL query: \"${SQL_QUERY}\""
                fi
            ;;

            *)
                fail "Something went wrong."
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi
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
