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

# Never fall back to php-EXT metapackages: they can select a different runtime.
function lemper_php_extension_package() {
    local version="$1" extension="$2" package
    [[ "$version" =~ ^[5-8]\.[0-9]$ && "$extension" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
    case "$extension" in
        tokenizer) extension=common ;;
        xsl) extension=xml ;;
    esac
    package="php$version-$extension"
    apt-cache show "$package" >/dev/null 2>&1 || return 1
    printf '%s\n' "$package"
}
