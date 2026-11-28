#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer PHP Extension Package Selection                                  |
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

# Each generation is immutable after publication; one symlink switches all maps.
# Account metadata is root-only; only Dovecot may also read the derived passdb.
function lemper_mail_root() { printf '%s\n' "${LEMPER_MAIL_ROOT:-/etc/lemper-mail}"; }
function lemper_mail_home_root() { printf '%s\n' "${LEMPER_MAIL_HOME_ROOT:-/var/vmail}"; }

function lemper_mail_domain_valid() {
    local domain="$1"
    [[ "$domain" == "${domain,,}" && "$domain" != *. && "$(validate_fqdn "$domain")" == true ]]
}
function lemper_mail_address_valid() {
    local address="$1" name="${1%@*}" domain="${1#*@}"
    [[ ${#address} -le 254 && ${#name} -le 64 && "$address" == "$name@$domain" &&
       "$name" =~ ^[a-z0-9][a-z0-9._+-]*$ && "$name" != *..* && "$name" != *. ]] &&
        lemper_mail_domain_valid "$domain"
}
function lemper_mail_exists() {
    local file="$1" key="$2"
    awk -F '\t' -v key="$key" '$1 == key { found=1 } END { exit !found }' "$file"
}
function lemper_mail_ready() {
    local root
    root=$(lemper_mail_root)
    [[ -f "$root/managed" && -L "$root/current" && -f "$root/current/accounts" ]] || {
        error "Install the managed mailer first: lemperctl stack install mailer."
        return 1
    }
}
function lemper_mail_stage() {
    local root stage file
    root=$(lemper_mail_root)
    stage=$(mktemp -d "$root/generations/.stage.XXXXXXXX") || return 1
    for file in domains accounts aliases; do
        if [[ -f "$root/current/$file" ]]; then
            cp -p "$root/current/$file" "$stage/$file" || return 1
        else
            install -m 0600 /dev/null "$stage/$file" || return 1
        fi
    done
    printf '%s\n' "$stage"
}
function lemper_mail_key() {
    local domain="$1" root directory
    root=$(lemper_mail_root)
    [[ -f "$root/dkim-enabled" ]] || return 0
    directory="$root/keys/$domain"
    install -d -o opendkim -g opendkim -m 0750 "$directory" || return 1
    # Repeated installs and re-adding a domain must preserve its published key.
    if [[ ! -s "$directory/lemper.private" ]]; then
        opendkim-genkey -b 2048 -d "$domain" -D "$directory" -s lemper || return 1
    fi
    chown opendkim:opendkim "$directory/lemper.private" "$directory/lemper.txt" || return 1
    chmod 0600 "$directory/lemper.private" || return 1
    chmod 0644 "$directory/lemper.txt" || return 1
}
function lemper_mail_render() {
    local stage="$1" root domain address hash enabled target owner
    root=$(lemper_mail_root)
    install -m 0600 /dev/null "$stage/passwd" || return 1
    : > "$stage/mailboxes"
    : > "$stage/sender_login"
    : > "$stage/virtual_aliases"
    : > "$stage/key.table"
    : > "$stage/signing.table"
    while IFS=$'\t' read -r address hash enabled; do
        [[ -n "$address" ]] || continue
        lemper_mail_address_valid "$address" && lemper_mail_exists "$stage/domains" "${address#*@}" || return 1
        [[ "$hash" == "{SHA512-CRYPT}\$6\$"* && "$hash" != *:* && "$hash" != *[[:space:]]* ]] || return 1
        [[ "$enabled" == enabled || "$enabled" == disabled ]] || return 1
        printf '%s\t%s/%s/Maildir/\n' "$address" "${address#*@}" "${address%@*}" >> "$stage/mailboxes"
        if [[ "$enabled" == enabled ]]; then
            printf '%s:%s\n' "$address" "$hash" >> "$stage/passwd"
            printf '%s\t%s\n' "$address" "$address" >> "$stage/sender_login"
        fi
    done < "$stage/accounts"
    while IFS=$'\t' read -r address target; do
        [[ -n "$address" ]] || continue
        lemper_mail_address_valid "$address" && lemper_mail_address_valid "$target" || return 1
        lemper_mail_exists "$stage/domains" "${address#*@}" && lemper_mail_exists "$stage/accounts" "$target" || return 1
        ! lemper_mail_exists "$stage/accounts" "$address" || return 1
        printf '%s\t%s\n' "$address" "$target" >> "$stage/virtual_aliases"
        owner=$(awk -F '\t' -v key="$target" '$1 == key && $3 == "enabled" { print $1 }' "$stage/accounts")
        [[ -z "$owner" ]] || printf '%s\t%s\n' "$address" "$owner" >> "$stage/sender_login"
    done < "$stage/aliases"
    while IFS=$'\t' read -r domain _; do
        [[ -n "$domain" ]] || continue
        lemper_mail_domain_valid "$domain" || return 1
        if [[ -f "$root/dkim-enabled" ]]; then
            lemper_mail_key "$domain" || return 1
            printf 'lemper._domainkey.%s %s:lemper:%s/keys/%s/lemper.private\n' "$domain" "$domain" "$root" "$domain" >> "$stage/key.table"
            printf '*@%s lemper._domainkey.%s\n' "$domain" "$domain" >> "$stage/signing.table"
        fi
    done < "$stage/domains"
    chmod 0600 "$stage/accounts" || return 1
    chown root:dovecot "$stage/passwd" || return 1
    chmod 0640 "$stage/passwd" || return 1
    chmod 0644 "$stage/domains" "$stage/mailboxes" "$stage/sender_login" "$stage/aliases" "$stage/virtual_aliases" "$stage/key.table" "$stage/signing.table" || return 1
    local map
    for map in domains mailboxes sender_login virtual_aliases; do
        postmap "hash:$stage/$map" || return 1
        chmod 0644 "$stage/$map.db" || return 1
    done
    chmod 0755 "$stage"
}
function lemper_mail_select() {
    local root="$1" target="$2" selector
    selector=$(mktemp "$root/.current.XXXXXXXX") || return 1
    if ! ln -sfn "$target" "$selector" || ! mv -Tf "$selector" "$root/current"; then
        rm -f "$selector"
        return 1
    fi
}
function lemper_mail_author_configtest() {
    # rspamadm initializes its distro cache and host resolver before it reads -c.
    # Use the package identity for validation. The live worker has its own cache and network namespace.
    runuser -u _rspamd -- rspamadm configtest -qs -c "$1/submission-author.conf"
}
function lemper_mail_check() {
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would validate Postfix, Dovecot, submission author policy, and enabled DKIM configuration."
        return 0
    fi
    local root
    root=$(lemper_mail_root)
    postfix check && doveconf -n >/dev/null || return 1
    if [[ -f "$root/submission-author.conf" ]]; then
        lemper_mail_author_configtest "$root" || return 1
    fi
    [[ ! -f "$root/dkim-enabled" ]] || opendkim -n -x /etc/opendkim.conf
}
function lemper_mail_reload() {
    local root
    root=$(lemper_mail_root)
    if [[ -f "$root/submission-author.conf" ]]; then
        systemctl start lemper-mail-author || return 1
        [[ -S /var/spool/postfix/lemper-mail-author/filter.sock ]] || return 1
    fi
    # OpenDKIM cannot change its listening socket on SIGHUP after package startup.
    if [[ -f "$root/dkim-enabled" ]]; then systemctl restart opendkim || return 1; fi
    systemctl reload-or-restart dovecot && systemctl reload-or-restart postfix
}
function lemper_mail_publish() {
    local stage="$1" root previous="" rc=0
    root=$(lemper_mail_root)
    previous=$(readlink "$root/current") || previous=""
    if ! lemper_mail_render "$stage"; then rm -rf "$stage"; return 1; fi
    if ! lemper_mail_select "$root" "$stage"; then rm -rf "$stage"; return 1; fi
    if ! lemper_mail_check || ! lemper_mail_reload; then
        rc=1
        if [[ -n "$previous" ]]; then
            if ! lemper_mail_select "$root" "$previous" || ! lemper_mail_reload; then error "Mail rollback needs service recovery."; fi
        else
            rm -f "$root/current"
        fi
        error "Mail configuration failed; previous maps restored."
    fi
    # Retain the prior generation for recovery; no credentials are printed.
    return "$rc"
}
function lemper_mail_delete_row() {
    local file="$1" key="$2" temporary
    temporary=$(mktemp "${file}.XXXXXXXX") || return 1
    if ! awk -F '\t' -v key="$key" '$1 != key' "$file" > "$temporary" || ! mv -f "$temporary" "$file"; then
        rm -f "$temporary"
        return 1
    fi
}
