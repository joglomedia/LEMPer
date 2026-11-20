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
