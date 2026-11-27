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
    local release="$1" prefix="${2:-}" name target module current temporary unsafe directory
    prefix="${prefix%/}"
    current="$prefix/opt/lemper/current"
    [[ -d "$release" && -f "$release/lib/core/registry.sh" && -f "$release/bin/lemper-cli.sh" ]] || return 1
    [[ "${release%/*}" == "$prefix/opt/lemper" ]] && lemper_directory_trusted "$release" || return 1
    for directory in "$prefix/usr/local/bin" "$prefix/usr/bin" "$prefix/etc/lemper/core" "$prefix/etc/lemper/cli-plugins"; do
        lemper_directory_trusted "$directory" || { error "Unsafe installation directory: $directory"; return 1; }
    done
    # The compatibility loader is the only link shipped in a release.
    [[ ! -L "$release" ]] || return 1
    unsafe=$(find "$release" \( \( -type f -links +1 \) -o \( ! -type d ! -type f \
        ! \( -type l -path "$release/scripts/lemper_stacks.sh" -lname '../lib/core/lemper-stacks.sh' \) \) \) -printf x -quit) || return 1
    [[ -z "$unsafe" ]] || { error "Refusing linked or special files in CLI release."; return 1; }
    if [[ -e "$current" || -L "$current" ]]; then
        [[ -L "$current" && "$(stat -c %u -- "$current")" == "$EUID" ]] || {
            error "Release selector must be a symlink owned by the installer."
            return 1
        }
    fi
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
    lemper_release_tree_trusted "$release" || return 1
    for module in "$release"/lib/core/*.sh; do
        ln -sfnT "$current/lib/core/${module##*/}" "$prefix/etc/lemper/core/${module##*/}" || return 1
    done
    for module in runtime services compat; do
        [[ -d "$release/lib/$module" ]] || continue
        if [[ -d "$prefix/etc/lemper/$module" && ! -L "$prefix/etc/lemper/$module" ]]; then
            error "Refusing to replace existing library directory: $module"
            return 1
        fi
        ln -sfnT "$current/lib/$module" "$prefix/etc/lemper/$module" || return 1
    done
    while IFS=: read -r name target; do
        chmod 0755 "$release/lib/$name.sh" || return 1
        ln -sfnT "$current/lib/$name.sh" "$prefix/etc/lemper/cli-plugins/$target" || return 1
    done < <(lemper_command_plugins)
    while IFS=: read -r name target; do
        ln -sfnT "$prefix/etc/lemper/cli-plugins/$target" "$prefix/etc/lemper/cli-plugins/$name" || return 1
    done < <(lemper_command_aliases)
    ln -sfnT "$current/bin/lemper-cli.sh" "$prefix/usr/local/bin/lemperctl" || return 1
    ln -sfnT "$prefix/usr/local/bin/lemperctl" "$prefix/usr/local/bin/lemper-cli" || return 1
    ln -sfnT "$prefix/usr/local/bin/lemperctl" "$prefix/usr/bin/lemper-cli" || return 1
    temporary=$(mktemp "$prefix/opt/lemper/.current.XXXXXXXX") || return 1
    ln -sfnT "$release" "$temporary" || return 1
    if ! mv -Tf "$temporary" "$current"; then rm -f "$temporary"; return 1; fi
}

function lemper_cli_snapshot() {
    local source="$1" prefix="${2:-}" staged module destination
    [[ "${DRYRUN:-false}" != true ]] || { info "Would install CLI snapshot from $source."; return 0; }
    prefix="${prefix%/}"
    lemper_directory_trusted "$prefix/opt/lemper" || { error "Unsafe CLI release directory."; return 1; }
    install -d -m 0755 "$prefix/opt/lemper" || return 1
    lemper_directory_trusted "$prefix/opt/lemper" || return 1
    staged=$(mktemp -d "$prefix/opt/lemper/.stage.XXXXXXXX") || return 1
    for module in bin lib scripts etc share sbin; do
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
