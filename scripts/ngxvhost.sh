#!/usr/bin/env bash

#  +------------------------------------------------------------------------+
#  | NgxVhost - Simple Nginx vHost Configs File Generator                   |
#  +------------------------------------------------------------------------+
#  | Copyright (c) 2014-2019 NgxTools (https://ngxtools.eslabs.id)          |
#  +------------------------------------------------------------------------+
#  | This source file is subject to the New BSD License that is bundled     |
#  | with this package in the file docs/LICENSE.txt.                        |
#  |                                                                        |
#  | If you did not receive a copy of the license and are unable to         |
#  | obtain it through the world-wide-web, please send an email             |
#  | to license@eslabs.id so we can send you a copy immediately.            |
#  +------------------------------------------------------------------------+
#  | Authors: Edi Septriyanto <eslabs.id@gmail.com>                         |
#  |          Fideloper <https://gist.github.com/fideloper/9063376>         |
#  +------------------------------------------------------------------------+

# VERSION Control
VERSION='1.6.0'
LAST_UPDATE='29/12/2018'

INSTALL_DIR=$(pwd)

# May need to run this as sudo!
# I have it in /usr/local/bin and run command 'ngxvhost' from anywhere, using sudo.
if [ $(id -u) -ne 0 ]; then
    echo "You must be root: \"sudo ngxvhost\""
    exit 1  #error
fi

# Check prerequisite packages
if [[ ! -f $(which unzip) || ! -f $(which git) || ! -f $(which rsync) ]]; then
    echo "Ngxvhost requires rsync, unzip and git, please install it first"
    echo "help: sudo apt-get install rsync unzip git"
    exit 1
fi

#
# Show Usage, Output to STDERR
#
function show_usage {
cat <<- _EOF_
ngxvhost $VERSION
Creates Nginx virtual host (vHost) configuration file.

Requirements:
  * Nginx setup uses /etc/nginx/sites-available and /etc/nginx/sites-enabled
  * PHP FPM setup uses /etc/php/{version_number}/fpm/

Usage: ngxvhost [options]...

Options:
  -u, --username <virtual-host username>
      Use username added from adduser/useradd. Do not use root user.

  -s, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed.
      i.e. example.com or sub.example.com

  -d, --docroot <document root>
      Document root is absolut path to the website root directory.
      i.e. /home/username/Webs/example.test

  -t, --framework <website framework>
      Type of web framework and cms, i.e. default.
      Currently supported framework and cms: default (vanilla php), codeigniter, laravel, phalcon, wordpress, wordpress-ms.

      Another framework and cms will be added soon.

  -c, --clone-skeleton <framework default skeleton>
      Clone default skeleton for selected framework.

  -h, --help
      Print this message and exit.

Example:
ngxvhost -u username -s example.com -t default -d /home/username/Webs/example.dev

Found bugs or suggestions?
Send your pull request to https://github.com/joglomedia/LEMPer.git.

_EOF_
}

#
# Decorator
#
RED=31
GREEN=32
YELLOW=33

function begin_color() {
    color="$1"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="$1"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    local error_message="$@"
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
INITIAL_ENV=$(printenv | sort)
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run"
        echo " $@"
        env_differences=$(comm -13 <(echo "$INITIAL_ENV") <(printenv | sort))

        if [ -n "$env_differences" ]; then
            echo "  with the following additional environment variables:"
            echo "$env_differences" | sed 's/^/    /'
        fi
    else
        if ! "$@"; then
            error "Failure running '$@', exiting."
            exit 1
        fi
    fi
}

#
# Output Default virtual host (vHost) skeleton, fill with user input
# To be outputted into new file
# Work for default and WordPress site
#
function create_vhost_default() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name $SERVERNAME www.${SERVERNAME} *.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${DOCROOT}';
    root \$root_path;
    index index.php index.html index.htm;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to php fpm.
    location ~ \.php$ {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;

        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/conf.vhost/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Laravel virtual host skeleton, fill with user input
# To be outputted into new file
#
function create_vhost_laravel() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name $SERVERNAME www.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${DOCROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to php fpm.
    location ~ \.php$ {
        fastcgi_index index.php;

        fastcgi_split_path_info    ^(.+\.php)(/.+)$;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Overwrite FastCGI Params here.
        #fastcgi_param PATH_INFO        \$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
        #fastcgi_param SCRIPT_NAME        \$fastcgi_script_name;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/conf.vhost/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Phalcon virtual host skeleton, fill with user input
# To be outputted into new file
#
function create_vhost_phalcon() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name $SERVERNAME www.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${DOCROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## pass the PHP scripts to php5-fpm
    location ~ \.php {
        fastcgi_index index.php;

        fastcgi_split_path_info    ^(.+\.php)(/.+)$;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Overwrite FastCGI Params here.
        fastcgi_param PATH_INFO            \$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME        \$fastcgi_script_name;

        # Phalcon PHP custom params.
        fastcgi_param APPLICATION_ENV    development;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/conf.vhost/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Wordpress Multisite vHost header
#
function prepare_vhost_wpms() {
cat <<- _EOF_
# Wordpress Multisite Mapping for Nginx (Requires Nginx Helper plugin).
map \$http_host \$blogid {
    default     0;
    include     ${DOCROOT}/wp-content/uploads/nginx-helper/map.conf;
}

_EOF_
}

#
# Output index.html skeleton for default index page
# To be outputted into new index.html file in document root
#
function create_index_file() {
cat <<- _EOF_
<!DOCTYPE html>
<html>
  <head>
    <title>It Works!</title>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="robots" content="index, follow" />
    <meta name="description" content="This is a default index page for Nginx server generated with ngxvhost tool from https://eslabs.id" />
  </head>
  <body>
    <h1>It Works!</h1>
    <div class="content">
        <p>If you are site owner or administrator of this website, please upload your page or update this index page.</p>
        <p style="font-size:90%;">Generated using <em>ngxvhost</em> tool from <a href="https://ngxtools.eslabs.id/">Nginx vHost Tool</a>, simple <a href="http://nginx.org/" rel="nofollow">Nginx</a> web server management tool.</p>
    </div>
  </body>
</html>
_EOF_
}

function create_fpm_pool_conf() {

cat <<- _EOF_
[$USERNAME]
user = $USERNAME
group = $USERNAME

listen = /run/php/php${PHP_VERSION}-fpm.\$pool.sock
listen.owner = $USERNAME
listen.group = $USERNAME
listen.mode = 0666
;listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 5
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s;
pm.max_requests = 500

slowlog = /var/log/php${PHP_VERSION}-fpm_slow.\$pool.log
request_slowlog_timeout = 1

chdir = /

security.limit_extensions = .php .php3 .php4 .php5 .php7 .php${PHP_VERSION//./}

;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_flag[display_errors] = on
php_admin_value[error_log] = /var/log/php${PHP_VERSION}-fpm.\$pool.log
php_admin_flag[log_errors] = on
;php_admin_value[memory_limit] = 32M
_EOF_
}

function install_wordpress() {
    # Check WordPress install directory
    if [ ! -d "${DOCROOT}/wp-admin" ]; then
        #echo -n "Should we copy WordPress skeleton into document root? [Y/n]: "
        #read instal

        # Clone new WordPress files
        #if [[ "${instal}" == "Y" || "${instal}" == "y" || "${instal}" == "yes" ]]; then
        if [ "$CLONE_SKELETON" ]; then
            status "Copying WordPress skeleton files..."

            run wget --no-check-certificate "https://wordpress.org/latest.zip"
            run unzip "latest.zip"
            run rsync -r "wordpress" \
                          "${DOCROOT}"
            run rm -f "latest.zip"
            run rm -fr "wordpress"
            #git clone https://github.com/WordPress/WordPress.git $DOCROOT/
        else
            # create default index file
            status "Creating default WordPress index file..."

            create_index_file > ${DOCROOT}/index.html
            run chown $USERNAME:$USERNAME "${DOCROOT}/index.html"
        fi
    else
        warning "WordPress installation file already exists..."
    fi

    # Pre-install nginx helper plugin
    if [[ -d "${DOCROOT}/wp-content/plugins" && ! -d "${DOCROOT}/wp-content/plugins/nginx-helper" ]]; then
        status "Copying Nginx Helper plugin into WordPress install..."
        warning "Please activate the plugin after WordPress installation."

        run wget --no-check-certificate "https://downloads.wordpress.org/plugin/nginx-helper.zip"
        run unzip "nginx-helper.zip"
        run mv "nginx-helper" \
               "${DOCROOT}/wp-content/plugins/"
        run rm -f "nginx-helper.zip"
        #git clone https://github.com/rtCamp/nginx-helper.git $DOCROOT/wp-content/plugins/nginx-helper
    fi
}

#
# Main
#
function ngxvhost() {
    getopt --test
    if [ "$?" != 4 ]; then
        # Even Centos 5 and Ubuntu 10 LTS have new-style getopt, so I don't expect
        # this to be hit in practice on systems that are actually able to run
        # Nginx web server.
        fail "Your version of getopt is too old.  Exiting with no changes made."
    fi

    opts=$(getopt -o u:s:d:t:p:fch \
      --longoptions username:,domain-name:,docroot:,framework:,php-version: \
      --longoptions enable-fastcgi-cache,clone-skeleton,help \
      -n "$(basename "$0")" -- "$@")

    # Sanity check
    if [ $# -lt 8  ]; then
        show_usage
        exit 0
    fi

    eval set -- "$opts"

    # Default value
    FRAMEWORK="default"
    PHP_VERSION="7.0"
    #TODO
    ENABLE_FASTCGI_CACHE=false
    #ENABLE_HTTPS=false
    CLONE_SKELETON=false
    DRYRUN=false

    # Parse flags
    while true; do
        case $1 in
            -u | --username) shift
                USERNAME="$1"
                shift
            ;;
            -s | --domain-name) shift
                SERVERNAME="$1"
                shift
            ;;
            -d | --docroot) shift
                DOCROOT="${1%%+(/)}"
                shift
            ;;
            -t | --framework) shift
                FRAMEWORK="$1"
                shift
            ;;
            -p | --php-version) shift
                PHP_VERSION="$1"
                shift
            ;;
            -f | --enable-fastcgi-cache) shift
                ENABLE_FASTCGI_CACHE=true
            ;;
            -c | --clone-skeleton) shift
                CLONE_SKELETON=true
            ;;
            -h | --help) shift
                show_usage
                exit 0
            ;;
            --) shift
                break
            ;;
            *)
                echo "Invalid argument: $1"
                show_usage
                exit 1
            ;;
        esac
    done

    # Additional Check - are user already exist?
    if [[ -z $(getent passwd $USERNAME) ]]; then
        fail "Error: The user ${USERNAME} does not exist, please add new user first! Aborting...
Help: adduser username, try ngxvhost -h for more helps"
    fi

    # Check PHP fpm version is exists?
    if [ -n $(which php-fpm${PHP_VERSION}) ]; then
        status "Setting up PFP-FPM pool configuration..."

        # Additional check - is FPM user's pool already exist
        if [ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]; then
            warning "The PHP${PHP_VERSION} FPM pool configuration for user ${USERNAME} doesn't exist."
            status "Creating new pool [${USERNAME}] configuration..."

            create_fpm_pool_conf > /etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf
            run touch "/var/log/php${PHP_VERSION}-fpm_slow.${USERNAME}.log"

            # Restart PHP FPM
            status "Restart php${PHP_VERSION}-fpm configuration..."
            run systemctl restart "php${PHP_VERSION}-fpm.service"
        fi
    else
        fail "Error: There is no PHP${PHP_VERSION} version installed, please install it first! Aborting..."
    fi

    # Additional Check - ensure that Nginx's configuration meets the requirement
    if [ ! -d "/etc/nginx/sites-available" ]; then
        fail "It seems that your Nginx installation doesn't meet ngxvhost requirements. Aborting..."
    fi

    # Vhost file
    vhost_file="/etc/nginx/sites-available/${SERVERNAME}.conf"

    # Check if vhost not exists.
    if [ ! -f "${vhost_file}" ]; then
        status "Adding domain ${SERVERNAME} to virtual host..."

        # Creates document root
        if [ ! -d $DOCROOT ]; then
            status "Creating document root, ${DOCROOT}..."

            run mkdir -p "${DOCROOT}"
            run chown -R $USERNAME:$USERNAME "${DOCROOT}"
            run chmod 755 "${DOCROOT}"
        fi

        echo "Selecting ${FRAMEWORK} framewrok..."

        # Ugly hacks for custom framework-specific configs + Skeleton auto installer.
        case $FRAMEWORK in
            laravel)
                status "Setting up Laravel framework virtual host..."

                # Install Laravel framework skeleton
                if [ ! -f "${DOCROOT}/server.php" ]; then
                    #echo -n "Should we install Laravel skeleton into document root? [Y/n]: "
                    #read INSTALL_LV

                    # Clone new Laravel files
                    #if [[ "${INSTALL_LV}" == "Y" || "${INSTALL_LV}" == "y" || "${INSTALL_LV}" == "yes" ]]; then
                    if [ "$CLONE_SKELETON" ]; then
                        status "Copying Laravel skeleton files..."
                        run git clone "https://github.com/laravel/laravel.git" \
                                      "${DOCROOT}"
                    else
                        # Create default index file
                        status "Creating default Laravel index files..."
                        create_index_file > ${DOCROOT}/index.html
                        run chown $USERNAME:$USERNAME "${DOCROOT}/index.html"
                    fi
                fi

                # Create vhost
                status "Creating virtual host file, ${vhost_file}..."
                create_vhost_laravel > ${vhost_file}
            ;;

            phalcon)
                status "Setting up Phalcon framework virtual host..."
                # TODO: Auto install Phalcon PHP framework skeleton

                # Create vhost
                status "Creating virtual host file, ${vhost_file}..."
                create_vhost_phalcon > ${vhost_file}
            ;;

            wordpress)
                status "Setting up WordPress virtual host..."

                # Install WordPress
                install_wordpress

                # Create vhost
                status "Creating virtual host file, ${vhost_file}..."
                create_vhost_default > ${vhost_file}
            ;;

            wordpress-ms)
                status "Setting up WordPress Multi-site virtual host..."

                # Install WordPress
                install_wordpress

                # Pre-populate blog id mapping, used by Nginx vhost conf
                run mkdir "${DOCROOT}/wp-content/uploads/"
                run mkdir "${DOCROOT}/wp-content/uploads/nginx-helper/"
                run touch "${DOCROOT}/wp-content/uploads/nginx-helper/map.conf"

                status "Creating virtual host file, ${vhost_file}..."

                # Prepare vhost specific rule for WordPress Multisite
                prepare_vhost_wpms > ${vhost_file}

                # Create vhost
                create_vhost_default >> ${vhost_file}
            ;;

            codeigniter|mautic|*)
                # Create default index file
                create_index_file > ${DOCROOT}/index.html
                run chown $USERNAME:$USERNAME "${DOCROOT}/index.html"

                # Create default vhost
                status "Creating virtual host file, ${vhost_file}..."
                create_vhost_default > ${vhost_file}
            ;;
        esac

        # Fix document root ownership
        run chown -R $USERNAME:$USERNAME "${DOCROOT}"

        # Fix document root permission
        if [ "$(ls -A ${DOCROOT})" ]; then
            run find "${DOCROOT}" -type d -print0 | xargs -0 chmod 755
            run find "${DOCROOT}" -type f -print0 | xargs -0 chmod 644
        fi

        # Enable site
        #cd "/etc/nginx/sites-enabled"
        run ln -s "/etc/nginx/sites-available/${SERVERNAME}.conf" \
                    "/etc/nginx/sites-enabled/${SERVERNAME}.conf"

        # Reload Nginx
        status "Reloading Nginx configuration..."
        #service nginx reload -s
        run systemctl reload "nginx.service"

        if [ "${FRAMEWORK}" = "wordpress-ms" ]; then
            warning "Note: You're installing Wordpress Multisite."
            warning "You should activate Nginx Helper plugin to work properly."
        fi
    else
        fail "vHost config file for ${SERVERNAME} already exists. Aborting..."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
ngxvhost "$@"
