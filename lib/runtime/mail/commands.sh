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

function lemper_mail_help() {
    cat <<HELP
Usage: ${CMD_PARENT:-lemperctl} mail <command> [options]
  domain add|delete DOMAIN             Add/remove a hosted domain (empty before removal).
  domain list                         List hosted domains.
  account add|edit|delete ADDRESS      Create, change password/status, or remove a mailbox.
  account list [DOMAIN]               List addresses and enabled/disabled status.
  alias add|edit ADDRESS TARGET        Route an address to a managed mailbox (cross-domain allowed).
  alias delete ADDRESS                Delete an alias.
  alias list [DOMAIN]                 List address mappings.
  dns DOMAIN                          Show MX/SPF/DKIM/DMARC guidance.
  check|status                        Validate configuration or show service status.
Options:
  --password-file FILE                One password line; root-owned file, mode 0600.
                                      Otherwise add/edit prompts securely (minimum 12 characters).
  --enable|--disable                  Edit mailbox login status; incoming mail is retained.
  --purge --yes                       Delete an account's stored mail permanently.
  --yes                              Confirm account/domain/alias deletion.
  --dry-run                          Validate and preview without reading passwords or changing files.
  --help, --version                   Show help/version.
Addresses use lowercase ASCII local parts. Aliases target a mailbox, not another alias.
Use lemperctl stack <install|remove|start|stop|restart|status> mailer for services.
HELP
}
function lemper_mail_password_hash() {
    local file="$1" password confirmation hash
    local lines=()
    if [[ -n "$file" ]]; then
        [[ -f "$file" && ! -L "$file" && "$(stat -c %u "$file")" == 0 && "$(stat -c %a "$file")" == 600 ]] || {
            error "Password file must be root-owned, regular, and mode 0600."; return 1;
        }
        mapfile -t lines < "$file" || return 1
        [[ ${#lines[@]} -eq 1 ]] || { error "Password file must contain one line."; return 1; }
        password="${lines[0]}"
    else
        [[ -t 0 ]] || { error "Use --password-file for noninteractive account changes."; return 1; }
        read -rsp 'Mailbox password: ' password || return 1
        printf '\n' >&2
        read -rsp 'Confirm password: ' confirmation || return 1
        printf '\n' >&2
        [[ "$password" == "$confirmation" ]] || { error "Passwords differ."; return 1; }
    fi
    [[ ${#password} -ge 12 && ${#password} -le 1024 && "$password" != *$'\r'* ]] || {
        error "Use a password of 12–1024 characters."; return 1;
    }
    # The password travels through stdin, never argv or dry-run rendering.
    hash=$(printf '%s\n%s\n' "$password" "$password" | doveadm pw -s SHA512-CRYPT 2>/dev/null) || return 1
    [[ "$hash" == "{SHA512-CRYPT}\$6\$"* ]] || return 1
    printf '%s\n' "$hash"
}
function lemper_mail_change() {
    local kind="$1" action="$2" address="$3" target="$4" password_file="$5" login="$6" purge="$7" yes="$8"
    local root current stage hash="" enabled=enabled home
    root=$(lemper_mail_root); current="$root/current"
    lemper_mail_ready || return 1
    case "$kind" in
        domain)
            lemper_mail_domain_valid "$address" || { error "Invalid lowercase domain."; return 1; }
            if [[ "$action" == add ]]; then
                ! lemper_mail_exists "$current/domains" "$address" || { error "Domain already exists."; return 1; }
            else
                lemper_mail_exists "$current/domains" "$address" || { error "Domain not found."; return 1; }
                if awk -F '\t' -v domain="$address" 'split($1,p,"@") && p[2] == domain { found=1 } END { exit !found }' "$current/accounts" "$current/aliases"; then
                    error "Remove the domain's accounts and aliases first."; return 1
                fi
            fi ;;
        account|alias)
            lemper_mail_address_valid "$address" || { error "Invalid lowercase mail address."; return 1; }
            lemper_mail_exists "$current/domains" "${address#*@}" || { error "Add the domain first."; return 1; }
            local table=accounts other=aliases
            [[ "$kind" == account ]] || { table=aliases; other=accounts; }
            if [[ "$action" == add ]]; then
                if lemper_mail_exists "$current/$table" "$address" || lemper_mail_exists "$current/$other" "$address"; then
                    error "Address already exists."; return 1
                fi
            else
                lemper_mail_exists "$current/$table" "$address" || { error "Address not found."; return 1; }
            fi
            if [[ "$kind" == alias && "$action" != delete ]]; then
                if ! lemper_mail_address_valid "$target" || ! lemper_mail_exists "$current/accounts" "$target"; then
                    error "Alias target must be a managed mailbox."; return 1
                fi
            fi
            if [[ "$kind" == account && "$action" == delete ]] &&
                awk -F '\t' -v address="$address" '$2 == address { found=1 } END { exit !found }' "$current/aliases"; then
                error "Remove or edit aliases targeting this account first."; return 1
            fi ;;
    esac
    home="$(lemper_mail_home_root)/${address#*@}/${address%@*}"
    if [[ "$purge" == true ]]; then
        [[ "$yes" == true ]] || { error "Permanent mailbox purge requires --yes."; return 1; }
        [[ ! -L "$(lemper_mail_home_root)" && ! -L "$(lemper_mail_home_root)/${address#*@}" && ! -L "$home" ]] || {
            error "Refusing to purge a symlinked mail directory."; return 1;
        }
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would $action mail $kind $address."; return 0; fi
    if [[ "$action" == delete && "$yes" != true ]]; then
        local answer
        read -rp "Delete mail $kind $address? [y/N]: " answer || return 1
        [[ "$answer" == y || "$answer" == Y ]] || return 1
    fi
    if [[ "$kind" == account && "$action" != delete ]]; then
        if [[ "$action" == edit ]]; then
            IFS=$'\t' read -r _ hash enabled < <(awk -F '\t' -v key="$address" '$1 == key' "$current/accounts")
        fi
        if [[ "$action" == add || -n "$password_file" || -z "$login" ]]; then
            hash=$(lemper_mail_password_hash "$password_file") || return 1
        fi
        [[ -z "$login" ]] || enabled="$login"
    fi
    stage=$(lemper_mail_stage) || return 1
    local file
    case "$kind" in domain) file=domains ;; account) file=accounts ;; alias) file=aliases ;; esac
    lemper_mail_delete_row "$stage/$file" "$address" || { rm -rf "$stage"; return 1; }
    if [[ "$action" != delete ]]; then
        case "$kind" in
            domain) printf '%s\tOK\n' "$address" >> "$stage/domains" ;;
            account) printf '%s\t%s\t%s\n' "$address" "$hash" "$enabled" >> "$stage/accounts" ;;
            alias) printf '%s\t%s\n' "$address" "$target" >> "$stage/aliases" ;;
        esac || { rm -rf "$stage"; return 1; }
    fi
    lemper_mail_publish "$stage" || return 1
    if [[ "$kind" == account && "$action" != add ]]; then
        doveadm auth cache flush "$address" >/dev/null || return 1
        # Disconnect existing sessions when login is disabled or an account deleted.
        local kick_rc=0
        doveadm kick "$address" >/dev/null || kick_rc=$?
        # doveadm uses EX_NOUSER (68) when no active sessions match.
        [[ "$kick_rc" == 0 || "$kick_rc" == 68 ]] || { error "Unable to disconnect mailbox sessions."; return 1; }
    fi
    [[ "$purge" != true || ! -d "$home" ]] || lemper_exec rm -rf -- "$home" || return 1
    success "Mail $kind $address: $action completed."
}
function lemper_mail_dns() {
    local domain="$1" root hostname
    root=$(lemper_mail_root)
    if ! lemper_mail_domain_valid "$domain" || ! lemper_mail_exists "$root/current/domains" "$domain"; then
        error "Hosted domain not found."; return 1
    fi
    IFS= read -r hostname < "$root/hostname"
    printf '%s. MX 10 %s.\n%s. TXT "v=spf1 mx -all"\n' "$domain" "$hostname" "$domain"
    printf '_dmarc.%s. TXT "v=DMARC1; p=none"\n' "$domain"
    [[ ! -f "$root/keys/$domain/lemper.txt" ]] || cat "$root/keys/$domain/lemper.txt"
    info "Point the mail hostname A/AAAA records at this server and ask the provider to set matching PTR."
    info "SPF assumes only this MX sends mail. Tighten DMARC after checking reports and alignment."
}
function init_lemper_mail() {
    local kind="${1:-help}" action="" address="" target="" argument password_file="" login="" purge=false yes=false
    local DRYRUN="${DRYRUN:-false}" positional=()
    case "$kind" in
        help|--help|-h) lemper_mail_help; return 0 ;;
        version|--version|-v) echo "${CMD_PARENT:-lemperctl} mail version ${PROG_VERSION:-}"; return 0 ;;
    esac
    shift
    case "$kind" in
        domain|account|alias) action="${1:-}"; [[ $# -eq 0 ]] || shift ;;
        dns|check|status) action="$kind" ;;
        *) error "Unknown mail command."; return 1 ;;
    esac
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            --help|-h) lemper_mail_help; return 0 ;;
            --dry-run) DRYRUN=true ;;
            --yes) yes=true ;;
            --purge) purge=true ;;
            --enable|--disable)
                [[ -z "$login" ]] || { error "Conflicting login options."; return 1; }
                if [[ "$argument" == --enable ]]; then login=enabled; else login=disabled; fi ;;
            --password-file)
                [[ $# -gt 0 && -z "$password_file" ]] || { error "Specify one password file."; return 1; }
                password_file="$1"; shift ;;
            --*) error "Unknown mail option."; return 1 ;;
            *) positional+=("$argument") ;;
        esac
    done
    address="${positional[0]:-}"; target="${positional[1]:-}"
    if [[ -n "$password_file" || -n "$login" ]]; then
        [[ "$kind" == account && ( "$action" == add || "$action" == edit ) ]] || { error "Login options require account add/edit."; return 1; }
    fi
    [[ "$purge" != true || ( "$kind" == account && "$action" == delete ) ]] || { error "Purge requires account delete."; return 1; }
    local expected=1
    case "$kind:$action" in
        domain:list|account:list|alias:list|check:check|status:status) expected=0 ;;
        alias:add|alias:edit) expected=2 ;;
        domain:add|domain:delete|account:add|account:edit|account:delete|alias:delete|dns:dns) ;;
        *) error "Unknown mail operation."; return 1 ;;
    esac
    if [[ "$action" == list && "$kind" != domain ]]; then
        [[ ${#positional[@]} -le 1 ]] || return 1
    else
        [[ ${#positional[@]} -eq "$expected" ]] || { error "Incorrect number of mail arguments."; return 1; }
    fi
    lemper_load_module services/mail/store || return 1
    lemper_mail_ready || return 1
    case "$action" in
        list)
            [[ -z "$address" ]] || lemper_mail_domain_valid "$address" || return 1
            local table="$kind" root
            root=$(lemper_mail_root)
            case "$kind" in domain) table=domains ;; account) table=accounts ;; alias) table=aliases ;; esac
            if [[ "$kind" == account ]]; then
                awk -F '\t' -v domain="$address" 'domain == "" || substr($1,index($1,"@")+1) == domain { print $1 "\t" $3 }' "$root/current/$table"
            else
                awk -F '\t' -v domain="$address" 'domain == "" || substr($1,index($1,"@")+1) == domain { print }' "$root/current/$table"
            fi ;;
        dns) lemper_mail_dns "$address" ;;
        check) lemper_mail_check ;;
        status)
            systemctl status --no-pager postfix dovecot || return 1
            [[ ! -f "$(lemper_mail_root)/dkim-enabled" ]] || systemctl status --no-pager opendkim ;;
        *) lemper_with_lock lemper_mail_change "$kind" "$action" "$address" "$target" "$password_file" "$login" "$purge" "$yes" ;;
    esac
}
