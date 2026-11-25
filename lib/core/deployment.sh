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



# Shared export path for release bootstrap, full install and tooling refresh.
# Only static source code is versioned; configuration and state stay under /etc.
function lemper_cli_activate() {
    local release="$1" prefix="${2:-}" name target module current temporary
    prefix="${prefix%/}"
    current="$prefix/opt/lemper/current"
    [[ -d "$release" && -f "$release/lib/core/registry.sh" && -f "$release/bin/lemper-cli.sh" ]] || return 1
    [[ ! -e "$current" || -L "$current" ]] || { error "Release selector must be a symlink."; return 1; }
    while IFS=: read -r name target; do
        [[ -f "$release/lib/$name.sh" ]] || { error "Missing command module: $name"; return 1; }
    done < <(lemper_command_plugins)
    install -d -m 0755 "$prefix/opt/lemper" "$prefix/usr/local/bin" "$prefix/usr/bin" || return 1
    install -d -m 0700 "$prefix/etc/lemper" "$prefix/etc/lemper/core" "$prefix/etc/lemper/cli-plugins" || return 1
    # Code copied from a user-owned checkout must not remain user-writable.
    if [[ "$(id -u)" -eq 0 ]]; then chown -hR root:root "$release" || return 1; fi
    find "$release" -type d -exec chmod 0755 {} + || return 1
    find "$release" -type f -exec chmod go-w {} + || return 1
    find "$release/lib" -type f -name '*.sh' -exec chmod 0644 {} + || return 1
    # Source code is public; secrets are never copied into this tree.
    chmod 0755 "$release/bin/lemper-cli.sh" || return 1
    for module in "$release"/lib/core/*.sh; do
        ln -sfn "$current/lib/core/${module##*/}" "$prefix/etc/lemper/core/${module##*/}" || return 1
    done
    for module in runtime services compat; do
        [[ -d "$release/lib/$module" ]] || continue
        if [[ -d "$prefix/etc/lemper/$module" && ! -L "$prefix/etc/lemper/$module" ]]; then
            error "Refusing to replace existing library directory: $module"
            return 1
        fi
        ln -sfn "$current/lib/$module" "$prefix/etc/lemper/$module" || return 1
    done
    while IFS=: read -r name target; do
        chmod 0755 "$release/lib/$name.sh" || return 1
        ln -sfn "$current/lib/$name.sh" "$prefix/etc/lemper/cli-plugins/$target" || return 1
    done < <(lemper_command_plugins)
    while IFS=: read -r name target; do
        ln -sfn "$prefix/etc/lemper/cli-plugins/$target" "$prefix/etc/lemper/cli-plugins/$name" || return 1
    done < <(lemper_command_aliases)
    ln -sfn "$current/bin/lemper-cli.sh" "$prefix/usr/local/bin/lemperctl" || return 1
    ln -sfn "$prefix/usr/local/bin/lemperctl" "$prefix/usr/local/bin/lemper-cli" || return 1
    ln -sfn "$prefix/usr/local/bin/lemperctl" "$prefix/usr/bin/lemper-cli" || return 1
    temporary=$(mktemp "$prefix/opt/lemper/.current.XXXXXXXX") || return 1
    ln -sfn "$release" "$temporary" || return 1
    if ! mv -Tf "$temporary" "$current"; then rm -f "$temporary"; return 1; fi
}

function lemper_cli_snapshot() {
    local source="$1" prefix="${2:-}" staged module destination
    [[ "${DRYRUN:-false}" != true ]] || { info "Would install CLI snapshot from $source."; return 0; }
    prefix="${prefix%/}"
    install -d -m 0755 "$prefix/opt/lemper" || return 1
    staged=$(mktemp -d "$prefix/opt/lemper/.stage.XXXXXXXX") || return 1
    for module in bin lib scripts etc share; do
        [[ -d "$source/$module" ]] || continue
        if ! cp -a "$source/$module" "$staged/"; then rm -rf "$staged"; return 1; fi
    done
    for module in .env.dist install.sh remove.sh lemper.sh update.sh; do
        [[ -f "$source/$module" ]] || continue
        if ! cp -p "$source/$module" "$staged/"; then rm -rf "$staged"; return 1; fi
    done
    destination="$prefix/opt/lemper/local-${staged##*.stage.}"
    mv "$staged" "$destination" || return 1
    if ! lemper_cli_activate "$destination" "$prefix"; then
        # Keep the staged release for diagnosis; never remove the selected release.
        error "CLI activation failed; staged code retained at $destination."
        return 1
    fi
}
