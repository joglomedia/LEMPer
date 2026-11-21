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



# Root-only timed recovery must work before CLI/configuration bootstrap completes.
[[ $(id -u) == 0 && -f /etc/lemper/firewall/pending ]] || exit 1
[[ ! -L /etc/lemper/firewall/recovery-driver.sh ]] || exit 1
[[ $(stat -c '%u %a' /etc/lemper/firewall/recovery-driver.sh) == '0 600' ]] || exit 1
export DRYRUN=false
error() { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }
lemper_exec() { "$@"; }
# This is an installed root-owned code copy, never user configuration.
# shellcheck source=/dev/null
. /etc/lemper/firewall/recovery-driver.sh || exit 1
lemper_nft_rollback
