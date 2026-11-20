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


function core_begin_color() {
    color="${1}"
    echo -e -n "\e[${color}m"
}

function core_end_color() {
    echo -e -n "\e[0m"
}

function core_echo_color() {
    color="${1}"
    shift
    begin_color "${color}"
    echo "$@"
    end_color
}

function begin_color() {
    core_begin_color "$@"
}

function end_color() {
    core_end_color
}

function echo_color() {
    core_echo_color "$@"
}
