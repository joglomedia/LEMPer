#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Encrypted Configuration (at-rest encryption)               |
# +-------------------------------------------------------------------------+
# | Provides AES-256-CBC encryption/decryption for /etc/lemper/lemper.conf. |
# | Backward compatible: plaintext configuration files load as-is.          |
# |                                                                         |
# | Invoked as: library - sourced by LEMPer scripts.                        |
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
# Compatibility library; the core provider defines functions only.
if [[ "$(type -t lemper_load_module)" != function ]]; then
    LEMPER_ENCRYPT_LIBRARY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
    # shellcheck source=/dev/null
    . "$LEMPER_ENCRYPT_LIBRARY/core/loader.sh" || return 1
fi
lemper_load_module core/encryption || return 1

# Library module: safe to source. Direct execution and CLI dispatch only
# print a notice; configuration encryption is handled by lemper-cli itself.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lemper-encrypt is a library module; source it from a LEMPer script."
    exit 0
elif [[ "$(type -t requires_root)" == "function" && -z "${LEMPER_ENCRYPT_LIB_ONLY:-}" ]]; then
    echo "lemper-encrypt is a library module; there is no 'lemper-cli encrypt' command."
    echo "Configuration encryption is handled automatically by lemper-cli."
fi
