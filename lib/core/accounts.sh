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



# Restricted administrator policy; hosting users receive no sudo rule.
function write_account_sudoers() {
    local username="${1}" directory="${2:-/etc/sudoers.d}" temporary version action
    is_valid_username "${username}" && [[ "${username}" != root ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || { info "Would restrict sudo for ${username}."; return 0; }
    command -v visudo >/dev/null 2>&1 || { error "visudo is required to validate account privileges."; return 1; }
    install -d -m 0750 "${directory}" || return 1
    temporary=$(mktemp "${directory}/.lemper-sudo.XXXXXX") || return 1
    {
        printf '# LEMPer-managed restricted administrator: %s\n' "${username}"
        for action in reload restart; do
            printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl %s nginx\n' "${username}" "${action}"
            for version in 8.2 8.3 8.4 8.5; do
                printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl %s php%s-fpm\n' "${username}" "${action}" "${version}"
            done
        done
        printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl restart mariadb, /usr/bin/systemctl restart mysql, /usr/bin/systemctl restart redis-server, /usr/bin/systemctl restart valkey-server\n' "${username}"
        printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl --no-pager status nginx\n' "${username}"
    } > "${temporary}"
    chmod 0440 "${temporary}" || { rm -f "${temporary}"; return 1; }
    if ! visudo -cf "${temporary}" >/dev/null 2>&1; then
        rm -f "${temporary}"
        error "Generated account privileges failed validation."
        return 1
    fi
    mv -f "${temporary}" "${directory}/90-${username}"
}

# Only a rule carrying our exact owner marker is eligible for automatic revocation.
function remove_managed_account_sudo() {
    local username="$1" directory="${2:-/etc/sudoers.d}" rule
    is_valid_username "$username" && [[ "$username" != root ]] || return 1
    rule="$directory/90-$username"
    [[ -f "$rule" && ! -L "$rule" ]] || return 0
    local marker
    IFS= read -r marker < "$rule" || return 1
    [[ "$marker" == "# LEMPer-managed restricted administrator: $username" ]] || return 0
    lemper_exec rm -- "$rule"
}

# Change only the dedicated Nginx administrator verifier. Enrollment reads a password from stdin.
function lemper_account_admin_auth() (
    local action="$1" username="$2" directory="${3:-/etc/nginx}" db temporary secret entry mode LC_ALL=C
    [[ "$EUID" == 0 && ( "$action" == enroll || "$action" == revoke ) ]] || return 1
    is_valid_username "$username" && [[ "$username" != root ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || return 0
    db="$directory/lemper-admin.htpasswd"
    if [[ "$action" == revoke && ! -e "$db" && ! -L "$db" ]]; then
        return 0
    fi
    lemper_directory_trusted "$directory" || { error "Unsafe web administration credential directory."; return 1; }
    if [[ ! -d "$directory" ]]; then
        mkdir -m 0755 -- "$directory" || return 1
        lemper_directory_trusted "$directory" || return 1
    fi
    if [[ -e "$db" || -L "$db" ]]; then
        [[ -f "$db" && ! -L "$db" ]] || return 1
        mode=$(stat -c '%u:%a:%h' -- "$db") || return 1
        [[ "$mode" == 0:600:1 || "$mode" == 0:640:1 ]] || {
            error "The web administration verifier must be a private, root-owned file."
            return 1
        }
    fi

    temporary=$(mktemp "$directory/.lemper-admin.XXXXXXXX") || return 1
    trap 'rm -f -- "$temporary"' EXIT
    if [[ -f "$db" ]]; then
        awk -F: -v username="$username" '$1 != username' "$db" >"$temporary" || return 1
    fi
    if [[ "$action" == enroll ]]; then
        set +x
        export -n secret
        IFS= read -r secret && [[ -n "$secret" && "$secret" != *$'\r'* ]] || return 1
        unset LEMPER_PASSWORD
        if [[ ${#secret} -le 72 ]] && command -v htpasswd >/dev/null; then
            entry=$(printf '%s\n' "$secret" | htpasswd -nBi "$username") || return 1
        else
            entry=$(printf '%s\n' "$secret" | openssl passwd -6 -stdin) || return 1
            entry="$username:$entry"
        fi
        [[ "$entry" == "$username:"?* && "$entry" != *$'\n'* && "$entry" != *$'\r'* ]] || return 1
        printf '%s\n' "$entry" >>"$temporary" || return 1
    fi
    chown root:www-data -- "$temporary" && chmod 0640 -- "$temporary" && mv -Tf -- "$temporary" "$db"
)

# Explicit migration only. The caller must establish LEMPer ownership first.
function restrict_account_sudo() {
    local username="${1}" root="${2:-}" uid directory legacy staged backups rc=0
    is_valid_username "${username}" && [[ "${username}" != root ]] || return 1
    uid=$(id -u "${username}") || return 1
    [[ "${uid}" -ge 1000 ]] || { error "Refusing to migrate a system account."; return 1; }
    if [[ "${username}" != "${LEMPER_USERNAME:-lemper}" && ! -f "${root}/etc/lemper/accounts/${username}.conf" ]]; then
        error "This account is not recorded as managed by LEMPer."
        return 1
    fi
    [[ "${DRYRUN:-false}" != true ]] || { info "Would migrate privileges for ${username}."; return 0; }
    directory="${root}/etc/sudoers.d"
    legacy="${directory}/90-lemper-users"
    backups="${root}/etc/lemper/accounts"
    install -d -m 0750 "${directory}" || return 1
    staged=$(mktemp -d "${directory}/.lemper-migration.XXXXXX") || return 1
    # Validate both proposed files before changing any effective privilege.
    if ! write_account_sudoers "${username}" "${staged}"; then rm -rf "${staged}"; return 1; fi
    if [[ -f "${legacy}" ]]; then
        awk -v user="${username}" '$1 != user && $1 != "%" user' "${legacy}" > "${staged}/legacy"
        chmod 0440 "${staged}/legacy"
        if ! visudo -cf "${staged}/legacy" >/dev/null 2>&1; then
            rm -rf "${staged}"
            error "Legacy sudoers migration failed validation."
            return 1
        fi
    fi
    install -d -m 0700 "${backups}" || { rm -rf "${staged}"; return 1; }
    [[ ! -f "${legacy}" ]] || cp -p "${legacy}" "${staged}/legacy.bak" || { rm -rf "${staged}"; return 1; }
    [[ ! -f "${directory}/90-${username}" ]] || cp -p "${directory}/90-${username}" "${staged}/rule.bak" || { rm -rf "${staged}"; return 1; }
    [[ ! -f "${staged}/legacy.bak" ]] || cp -p "${staged}/legacy.bak" "${backups}/${username}.sudoers.bak" || { rm -rf "${staged}"; return 1; }
    [[ ! -f "${staged}/rule.bak" ]] || cp -p "${staged}/rule.bak" "${backups}/${username}.restricted.bak" || { rm -rf "${staged}"; return 1; }
    mv -f "${staged}/90-${username}" "${directory}/90-${username}" || rc=1
    if [[ "${rc}" == 0 && -f "${staged}/legacy" ]]; then mv -f "${staged}/legacy" "${legacy}" || rc=1; fi
    if [[ "${rc}" == 0 ]] && id -nG "${username}" | tr ' ' '\n' | grep -qx sudo; then
        gpasswd -d "${username}" sudo || rc=1
    fi
    if [[ "${rc}" != 0 ]]; then
        if [[ -f "${staged}/rule.bak" ]]; then cp -p "${staged}/rule.bak" "${directory}/90-${username}"; else rm -f "${directory}/90-${username}"; fi
        [[ ! -f "${staged}/legacy.bak" ]] || cp -p "${staged}/legacy.bak" "${legacy}"
        error "Account migration failed; previous sudoers restored."
    fi
    rm -rf "${staged}"
    return "${rc}"
}
