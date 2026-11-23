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

function lemper_mail_path_valid() { [[ "$1" =~ ^/[a-zA-Z0-9_./-]+$ && "$1" != *..* ]]; }
function lemper_mail_certificate_valid() {
    local directory="$1" hostname="$2" certificate_key private_key
    [[ -s "$directory/fullchain.pem" && -s "$directory/privkey.pem" ]] || return 1
    openssl x509 -in "$directory/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1 &&
        openssl x509 -in "$directory/fullchain.pem" -noout -checkhost "$hostname" >/dev/null 2>&1 || return 1
    certificate_key=$(openssl x509 -in "$directory/fullchain.pem" -pubkey -noout) || return 1
    private_key=$(openssl pkey -passin pass: -in "$directory/privkey.pem" -pubout) || return 1
    [[ "$certificate_key" == "$private_key" ]]
}
function lemper_mail_postfix_configure() {
    local hostname="$1" certificate="$2" root="$3" setting
    # Loopback-only trusted networks; receiving port 25 never advertises authentication.
    local settings=(
        "myhostname=$hostname" "myorigin=$hostname" 'mydestination=localhost,localhost.localdomain'
        'inet_interfaces=all' 'inet_protocols=all' 'mynetworks=127.0.0.0/8 [::1]/128'
        'smtpd_relay_restrictions=permit_mynetworks,reject_unauth_destination'
        'smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unlisted_recipient'
        'smtpd_sasl_auth_enable=no' 'smtpd_sasl_type=dovecot' 'smtpd_sasl_path=private/auth'
        'smtpd_sasl_security_options=noanonymous' 'smtpd_tls_auth_only=yes'
        "smtpd_tls_cert_file=$certificate/fullchain.pem" "smtpd_tls_key_file=$certificate/privkey.pem"
        'smtpd_tls_security_level=may' 'smtp_tls_security_level=may' 'smtpd_tls_loglevel=1'
        'smtpd_tls_mandatory_protocols=>=TLSv1.2' 'smtpd_tls_protocols=>=TLSv1.2'
        'virtual_alias_domains=' "virtual_mailbox_domains=proxy:hash:$root/current/domains"
        "virtual_mailbox_maps=proxy:hash:$root/current/mailboxes"
        "virtual_alias_maps=proxy:hash:$root/current/virtual_aliases"
        "smtpd_sender_login_maps=proxy:hash:$root/current/sender_login"
        'virtual_transport=lmtp:unix:private/dovecot-lmtp' 'smtpd_reject_unlisted_recipient=yes'
        'recipient_delimiter='
    )
    for setting in "${settings[@]}"; do postconf -e "$setting" || return 1; done
    postconf -M 'submission/inet=submission inet n - y - - smtpd' || return 1
    local overrides=(
        'smtpd_tls_security_level=encrypt' 'smtpd_sasl_auth_enable=yes'
        'smtpd_relay_restrictions=permit_sasl_authenticated,reject'
        'smtpd_recipient_restrictions=permit_sasl_authenticated,reject'
        'smtpd_sender_restrictions=reject_authenticated_sender_login_mismatch'
        'milter_macro_daemon_name=ORIGINATING'
    )
    for setting in "${overrides[@]}"; do postconf -P "submission/inet/$setting" || return 1; done
    if [[ -f "$root/dkim-enabled" ]]; then
        postconf -e 'smtpd_milters=inet:127.0.0.1:8891' "non_smtpd_milters=\$smtpd_milters" \
            'milter_protocol=6' 'milter_default_action=tempfail' 'policyd-spf_time_limit=3600' || return 1
        postconf -M 'policyd-spf/unix=policyd-spf unix - n n - 0 spawn user=policyd-spf argv=/usr/bin/policyd-spf' || return 1
        postconf -e 'smtpd_recipient_restrictions=permit_mynetworks,reject_unauth_destination,reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unlisted_recipient,check_policy_service unix:private/policyd-spf' || return 1
    fi
}
function lemper_mail_template() {
    local template="$1" destination="$2" certificate="$3" hostname="$4" domain="$5" root="$6" home="$7" uid="$8"
    # Inputs are validated before entering a sed replacement expression.
    sed -e "s|@CERT@|$certificate|g" -e "s|@HOSTNAME@|$hostname|g" -e "s|@DOMAIN@|$domain|g" \
        -e "s|@ROOT@|$root|g" -e "s|@HOME@|$home|g" -e "s|@UID@|$uid|g" "$template" > "$destination"
}
function lemper_mail_dovecot_template() {
    case "${1:-}" in
        2.3.*) printf 'dovecot.conf\n' ;;
        2.4.*) printf 'dovecot-2.4.conf\n' ;;
        *) error "Unsupported Dovecot configuration version; use maintained 2.3 or 2.4 packages."; return 1 ;;
    esac
}
function lemper_mail_install() {
    local hostname="${MAILER_HOSTNAME:-${SERVER_HOSTNAME:-}}" domain="${SENDER_DOMAIN:-${SERVER_HOSTNAME:-}}"
    local certificate="${MAILER_CERT_PATH:-${HOSTNAME_CERT_PATH:-}}" root home backup stage uid existing=false dovecot_template
    root=$(lemper_mail_root); home=$(lemper_mail_home_root)
    if ! lemper_mail_domain_valid "$hostname" || ! lemper_mail_domain_valid "$domain"; then
        error "Set MAILER_HOSTNAME/SERVER_HOSTNAME and SENDER_DOMAIN to valid lowercase domains."; return 1
    fi
    lemper_mail_path_valid "$root" && lemper_mail_path_valid "$home" || return 1
    [[ -z "$certificate" ]] || lemper_mail_path_valid "$certificate" || { error "Invalid certificate path."; return 1; }
    if [[ -n "$certificate" ]]; then
        lemper_mail_certificate_valid "$certificate" "$hostname" || { error "Mail certificate is missing, expired, mismatched, or invalid for the mail hostname."; return 1; }
    elif [[ "${ENVIRONMENT:-production}" == prod* ]]; then
        certificate="/etc/letsencrypt/live/$hostname"
        lemper_mail_certificate_valid "$certificate" "$hostname" || {
            error "Provision a certificate for $hostname first and set MAILER_CERT_PATH."; return 1;
        }
    else
        certificate="$root/tls"
    fi
    if [[ ! -f "$root/managed" && ! -f "$root/installing" ]] && { command -v postfix >/dev/null || command -v dovecot >/dev/null; }; then
        existing=true
        [[ "${FORCE_INSTALL:-false}" == true ]] || {
            error "Existing mail installation is unmanaged. Back up/migrate its mail and use FORCE_INSTALL=true only for an approved takeover."; return 1;
        }
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would install Postfix, Dovecot IMAP/LMTP, virtual mailboxes, and TLS for $hostname ($domain)."
        return 0
    fi
    local owned_packages=() package
    local packages=(postfix mailutils dovecot-core dovecot-imapd dovecot-lmtpd openssl)
    [[ "${INSTALL_SPFDKIM:-true}" != true ]] || packages+=(postfix-policyd-spf-python opendkim opendkim-tools)
    for package in "${packages[@]}"; do
        if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" != 'install ok installed' ]]; then owned_packages+=("$package"); fi
    done
    install -d -m 0755 "$root" "$root/generations" || return 1
    # Identify our interrupted installation before APT starts any services.
    # This permits a retry without treating our partial packages as an unmanaged takeover.
    install -m 0600 /dev/null "$root/installing" || return 1
    if [[ ${#owned_packages[@]} -gt 0 ]]; then
        local ownership
        ownership=$(mktemp "$root/.packages.XXXXXXXX") || return 1
        if [[ -f "$root/owned-packages" ]]; then cat "$root/owned-packages" > "$ownership" || return 1; fi
        printf '%s\n' "${owned_packages[@]}" >> "$ownership" || return 1
        sort -u "$ownership" -o "$ownership" || return 1
        mv -f "$ownership" "$root/owned-packages" || return 1
    fi
    lemper_exec env DEBIAN_FRONTEND=noninteractive apt-get install -q -y "${packages[@]}" || return 1
    dovecot_template=$(lemper_mail_dovecot_template "$(dovecot --version)") || return 1
    backup=$(mktemp -d "$root/backup.XXXXXXXX") || return 1
    chmod 0700 "$backup" || return 1
    cp -p /etc/postfix/main.cf /etc/postfix/master.cf /etc/dovecot/dovecot.conf "$backup/" || return 1
    [[ ! -f /etc/opendkim.conf ]] || cp -p /etc/opendkim.conf "$backup/" || return 1
    if [[ ! -s "$certificate/fullchain.pem" && "$certificate" == "$root/tls" ]]; then
        install -d -m 0700 "$certificate" || return 1
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=$hostname" \
            -addext "subjectAltName=DNS:$hostname" -keyout "$certificate/privkey.pem" -out "$certificate/fullchain.pem" >/dev/null 2>&1 || return 1
        chmod 0600 "$certificate/privkey.pem" || return 1
        warning "Development mail certificate is self-signed; install a trusted certificate before production."
    fi
    if ! getent passwd vmail >/dev/null; then
        lemper_exec useradd --system --user-group --home-dir "$home" --shell /usr/sbin/nologin vmail || return 1
    else
        local existing_home existing_shell
        IFS=: read -r _ _ uid _ _ existing_home existing_shell < <(getent passwd vmail)
        [[ "$existing_home" == "$home" && "$existing_shell" == /usr/sbin/nologin ]] || {
            error "Existing vmail account does not match the managed mail storage."; return 1;
        }
    fi
    uid=$(id -u vmail) || return 1
    install -d -o vmail -g vmail -m 0750 "$home" || return 1
    if [[ "${INSTALL_SPFDKIM:-true}" == true ]]; then
        touch "$root/dkim-enabled" || return 1
        install -d -o opendkim -g opendkim -m 0750 "$root/keys" || return 1
    fi
    # Preserve a working enabled DKIM installation on reconciliation.
    stage=$(lemper_mail_stage) || return 1
    lemper_mail_exists "$stage/domains" "$domain" || printf '%s\tOK\n' "$domain" >> "$stage/domains"
    if ! lemper_mail_render "$stage"; then rm -rf "$stage"; return 1; fi
    local previous="" rc=0
    previous=$(readlink "$root/current") || previous=""
    lemper_mail_select "$root" "$stage" || return 1
    if ! lemper_mail_template "$BASE_DIR/etc/mail/$dovecot_template" /etc/dovecot/dovecot.conf "$certificate" "$hostname" "$domain" "$root" "$home" "$uid" ||
        ! lemper_mail_postfix_configure "$hostname" "$certificate" "$root"; then rc=1; fi
    if [[ "$rc" -eq 0 && -f "$root/dkim-enabled" ]]; then
        lemper_mail_template "$BASE_DIR/etc/mail/opendkim.conf" /etc/opendkim.conf "$certificate" "$hostname" "$domain" "$root" "$home" "$uid" || rc=1
    fi
    if [[ "$rc" -eq 0 ]]; then lemper_mail_check && lemper_mail_reload || rc=1; fi
    if [[ "$rc" -ne 0 ]]; then
        cp -p "$backup/main.cf" /etc/postfix/main.cf
        cp -p "$backup/master.cf" /etc/postfix/master.cf
        cp -p "$backup/dovecot.conf" /etc/dovecot/dovecot.conf
        [[ ! -f "$backup/opendkim.conf" ]] || cp -p "$backup/opendkim.conf" /etc/opendkim.conf
        if [[ -n "$previous" ]]; then lemper_mail_select "$root" "$previous"; else rm -f "$root/current"; fi
        lemper_mail_reload || error "Restored mail configuration needs service recovery."
        error "Mail installation failed; configuration backup restored ($backup)."
        return 1
    fi
    systemctl enable postfix dovecot || return 1
    [[ ! -f "$root/dkim-enabled" ]] || systemctl enable opendkim || return 1
    printf '%s\n' "$hostname" > "$root/hostname"
    touch "$root/managed" || return 1
    rm -f "$root/installing" || return 1
    [[ "$existing" != true ]] || warning "Old local accounts/aliases are backed up; migrate them explicitly to virtual mailboxes."
    success "Mailer configured. Add mailboxes and postmaster aliases with lemperctl mail."
}

function lemper_mail_update() {
    local package packages=()
    lemper_mail_ready || return 1
    if [[ "${DRYRUN:-false}" != true ]]; then lemper_mail_check || return 1; fi
    for package in postfix mailutils dovecot-core dovecot-imapd dovecot-lmtpd opendkim opendkim-tools postfix-policyd-spf-python; do
        if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == 'install ok installed' ]]; then packages+=("$package"); fi
    done
    [[ ${#packages[@]} -gt 0 ]] || { error "No installed mail packages to update."; return 1; }
    lemper_exec apt-get update -q || return 1
    lemper_exec env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -q -y "${packages[@]}" || return 1
    [[ "${DRYRUN:-false}" == true ]] || { lemper_mail_check && lemper_mail_reload; }
}

function lemper_mail_remove() {
    local root package packages=()
    root=$(lemper_mail_root)
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would remove owned mail packages; retain mailboxes, keys, and account maps."; return 0; fi
    [[ -f "$root/owned-packages" ]] || { info "No owned mail packages; preserving existing installation."; return 0; }
    while IFS= read -r package; do
        case "$package" in postfix|mailutils|dovecot-core|dovecot-imapd|dovecot-lmtpd|postfix-policyd-spf-python|opendkim|opendkim-tools) packages+=("$package") ;; esac
    done < "$root/owned-packages"
    [[ ${#packages[@]} -gt 0 ]] || return 0
    # apt remove retains configuration; mailbox data and signing keys are always retained.
    lemper_exec env DEBIAN_FRONTEND=noninteractive apt-get remove -q -y "${packages[@]}" || return 1
    rm -f "$root/owned-packages" || return 1
    info "Mail data/configuration retained in $(lemper_mail_home_root) and $root."
}
