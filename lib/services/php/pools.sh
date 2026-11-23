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
# Output PHP-FPM pool configuration
# To be outputted into new pool file in fpm/pool.d.
#
function create_fpm_pool_conf() {
    local POOLNAME="${1}"
    local PHPv="${2}"

    local RESOURCE_PROFILE MEMLIMIT_MB
    RESOURCE_PROFILE=$(detect_resource_profile)
    MEMLIMIT_MB=$(memory_to_mb "${PHP_MEMORY_LIMIT:-256M}")

    local POOL_MAX_CHILDREN POOL_START_SERVERS POOL_MIN_SPARE POOL_MAX_SPARE
    read -r POOL_MAX_CHILDREN POOL_START_SERVERS POOL_MIN_SPARE POOL_MAX_SPARE <<< \
        "$(calc_php_pool_sizing "${RESOURCE_PROFILE}" "${MEMLIMIT_MB}")"

    local COOKIE_SECURE=0
    [[ "${SESSION_COOKIE_SECURE:-false}" == true ]] && COOKIE_SECURE=1

    cat <<-EOL
[${POOLNAME}]
user = ${POOLNAME}
group = ${POOLNAME}

listen = /run/php/php${PHPv}-fpm.\$pool.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
;listen.allowed_clients = 127.1.0.1

; Custom PHP-FPM optimization, sized from SERVER_PROFILE and available RAM.
pm = dynamic
pm.max_children = ${POOL_MAX_CHILDREN}
pm.start_servers = ${POOL_START_SERVERS}
pm.min_spare_servers = ${POOL_MIN_SPARE}
pm.max_spare_servers = ${POOL_MAX_SPARE}
pm.process_idle_timeout = 30s
pm.max_requests = 500

pm.status_path = /php-fpm_status
ping.path = /php-fpm_ping

slowlog = /home/${POOLNAME}/logs/php/php${PHPv}-fpm_slow.log
request_slowlog_timeout = 10s
; Kill runaway workers even if max_execution_time is bypassed.
request_terminate_timeout = 300s

;chroot = /home/${POOLNAME}
chdir = /home/${POOLNAME}

; Do not leak the service environment into PHP.
clear_env = yes

;catch_workers_output = yes
;decorate_workers_output = no

security.limit_extensions = .php .php${PHPv//./}

; Custom PHP ini settings for LEMPer Stack.
php_admin_value[open_basedir] = /home/${POOLNAME}:/var/lib/php/lemper/${POOLNAME}
php_admin_value[disable_functions] = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,pcntl_unshare,exec,passthru,popen,proc_open,shell_exec,system
;php_admin_value[disable_classes] =
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /home/${POOLNAME}/logs/php/php${PHPv}-fpm_error.log
php_admin_flag[expose_php] = off
php_admin_value[sys_temp_dir] = /var/lib/php/lemper/${POOLNAME}/tmp
php_admin_value[upload_tmp_dir] = /var/lib/php/lemper/${POOLNAME}/tmp
;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f www@my.domain.com

; Configuration below can be overwritten from PHP call 'ini_set'.
php_flag[short_open_tag] = off
php_value[max_execution_time] = 300
php_value[max_input_time] = 60
php_value[memory_limit] = ${PHP_MEMORY_LIMIT:-256M}
php_value[post_max_size] = 50M
php_flag[file_uploads] = on
php_value[upload_max_filesize] = 50M
php_value[max_file_uploads] = 20
php_value[default_socket_timeout] = 60
php_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_admin_flag[display_errors] = off
php_admin_flag[display_startup_errors] = off
php_flag[cgi.fix_pathinfo] = off
php_value[date.timezone] = UTC
php_value[session.save_handler] = files
; Keep session files out of the document root: ini_set() must not relocate them.
php_admin_value[session.save_path] = /var/lib/php/lemper/${POOLNAME}/sessions
php_value[soap.wsdl_cache_dir] = /var/lib/php/lemper/${POOLNAME}/wsdlcache
php_value[opcache.file_cache] = /var/lib/php/lemper/${POOLNAME}/opcache
php_value[opcache.error_log] = /home/${POOLNAME}/logs/php/php${PHPv}-opcache_error.log

; Session hardening (not overridable from application code).
php_admin_value[session.use_strict_mode] = 1
php_admin_value[session.use_only_cookies] = 1
php_admin_value[session.cookie_httponly] = 1
php_admin_value[session.cookie_secure] = ${COOKIE_SECURE}
php_admin_value[session.cookie_samesite] = Lax
php_admin_value[session.sid_length] = 48
php_admin_value[session.sid_bits_per_character] = 5
php_admin_value[session.gc_probability] = 1
php_admin_value[session.gc_divisor] = 1000
EOL
}
