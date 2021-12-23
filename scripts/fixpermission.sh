#!/usr/bin/env bash

# Fix file permission
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 17/07/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# directory
[ "${1}" = "" ] && return 0

find "${1}" -type d -print0 | xargs -0 chmod 755
find "${1}" -type f -print0 | xargs -0 chmod 644
