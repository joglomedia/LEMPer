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



LEMPER_CORE_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
# shellcheck source=lib/core/security.sh
. "${LEMPER_CORE_SOURCE_DIR}/security.sh" || return 1
# shellcheck source=lib/core/accounts.sh
. "${LEMPER_CORE_SOURCE_DIR}/accounts.sh" || return 1
# shellcheck source=lib/core/acme.sh
. "${LEMPER_CORE_SOURCE_DIR}/acme.sh" || return 1
# shellcheck source=lib/core/args.sh
. "${LEMPER_CORE_SOURCE_DIR}/args.sh" || return 1

# shellcheck source=lib/core/config.sh
. "${LEMPER_CORE_SOURCE_DIR}/config.sh" || return 1

# shellcheck source=lib/core/colors.sh
. "${LEMPER_CORE_SOURCE_DIR}/colors.sh" || return 1

# shellcheck source=lib/core/logging.sh
. "${LEMPER_CORE_SOURCE_DIR}/logging.sh" || return 1

# shellcheck source=lib/core/distro.sh
. "${LEMPER_CORE_SOURCE_DIR}/distro.sh" || return 1

# shellcheck source=lib/core/network.sh
. "${LEMPER_CORE_SOURCE_DIR}/network.sh" || return 1

# shellcheck source=lib/core/validation.sh
. "${LEMPER_CORE_SOURCE_DIR}/validation.sh" || return 1

# shellcheck source=lib/core/resources.sh
. "${LEMPER_CORE_SOURCE_DIR}/resources.sh" || return 1

# shellcheck source=lib/core/schema.sh
. "${LEMPER_CORE_SOURCE_DIR}/schema.sh" || return 1

# shellcheck source=lib/core/ssh.sh
. "${LEMPER_CORE_SOURCE_DIR}/ssh.sh" || return 1

# shellcheck source=lib/core/cli.sh
. "${LEMPER_CORE_SOURCE_DIR}/cli.sh" || return 1

# shellcheck source=lib/core/registry.sh
. "${LEMPER_CORE_SOURCE_DIR}/registry.sh" || return 1
# shellcheck source=lib/core/execution.sh
. "${LEMPER_CORE_SOURCE_DIR}/execution.sh" || return 1
