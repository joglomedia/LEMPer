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


function lemper_runtime_help() {
    cat <<- EOL
${PROG_NAME} ${PROG_VERSION}
Command line management tool for LEMPer Stack (Linux, Nginx, MySQL/MariaDB, PHP).

Usage: ${PROG_NAME} [command] [subcommand] [options]
EOL

    echo
    echo "LEMP Stack Management:"
    help_entry stack "Install, remove, update, and control one service."
    help_subentry "config php --default-runtime" "Choose the CLI and new-site PHP default."
    help_entry create "Create a new virtual host (add a domain)."
    help_entry add "Alias of 'create'."
    help_entry site "Virtual host management."
    help_subentry "app add|update|remove|list" "Manage Laravel mounts under an existing domain."
    help_subentry "list [options]" "List all vhosts (table or JSON)."
    help_subentry "show <domain> [options]" "Show detailed vhost config."
    help_subentry "enable <domain>" "Enable a vhost."
    help_subentry "disable <domain>" "Disable a vhost."
    help_entry manage "Manage existing virtual hosts (mod/ssl/rewrite)."
    help_entry mod "Alias of 'manage'."

    echo
    echo "Database Management:"
    help_entry db "MySQL/MariaDB database manager."
    help_subentry "create [options]" "Create a new database."
    help_subentry "drop <name>" "Delete a database."
    help_subentry "export [options]" "Export a database to SQL."
    help_subentry "backup [options]" "Create a timestamped backup (.sql.gz)."
    help_subentry "restore [options]" "Restore from a backup file."
    help_subentry "prune --dbname NAME --keep COUNT" "Rotate verified SQL dumps for one database."
    help_subentry "backup-schedule [options]" "Schedule automated backups via cron."
    help_subentry "account <subcommand>" "Manage database user accounts."

    echo
    echo "System Administration:"
    help_entry data "Encrypted application/mail backups, retention and staged restore."
    help_entry monitor "Authenticated local health monitoring, alerts and logs."
    help_entry firewall "Scoped native nftables policy, migration and SSH recovery."
    help_entry hosting "Hosting plans with enforced disk/inode quotas and recovery."
    help_entry config "Validate configuration with config check."
    help_entry mail "Manage mail domains, mailbox accounts, aliases, and DNS records."
    help_entry account "Create a system user account."
    help_entry adduser "Interactively add a system user."
    help_entry tui "Launch interactive TUI dashboard."
    help_entry backup "Back up and restore LEMPer-managed configuration."
    help_subentry "create [options]" "Archive system configuration."
    help_subentry "list [options]" "List configuration archives."
    help_subentry "show <archive|latest>" "Show manifest details."
    help_subentry "verify <archive|latest>" "Check archive integrity."
    help_subentry "restore [options]" "Restore an archive (snapshots first)."
    help_subentry "prune [options]" "Delete old archives."
    help_entry selfssl "Generate self-signed SSL certificates."
    help_entry fixpermission "Fix file/directory permissions for web root."
    help_entry bench "Run server benchmark checks."
    help_entry modsec "ModSecurity WAF status, reporting, and auto-tuning."
    help_subentry status "Show engine and CRS status."
    help_subentry report "Summarize triggered rules."
    help_subentry "tune [options]" "Adjust paranoia/thresholds."
    help_entry update "Patch PHP2Shell and keep the stack current."
    help_subentry check "Audit PHP/nginx/MariaDB state."
    help_subentry php "Patch PHP; migrate EOL vhosts with --migrate-to=VERSION."
    help_subentry nginx "Upgrade package-managed nginx from MyGuard."
    help_subentry mariadb "Upgrade MariaDB packages."
    help_subentry lemper "Reinstall CLI, plugins, and web admin tools."
    help_subentry all "Run every update step."

    cat <<- EOL

Options:
  --version, -v   Show version and exit.
  --help, -h      Show this help message.
  --config-password-stdin  Read one configuration passphrase from standard input.
                  Falls back to LEMPER_PASSWORD or /etc/lemper/.config_key.

For detailed help on a specific command:
  ${PROG_NAME} <command> --help
  ${PROG_NAME} <command> <subcommand> --help
EOL

    return 0
}

function help_entry() { printf "  %-16s%s\n" "$1" "$2"; }
function help_subentry() { printf "    %-28s  %s\n" "$1" "$2"; }
