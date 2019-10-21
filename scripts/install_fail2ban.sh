#!/usr/bin/env bash

# fail2ban Installer

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_fail2ban_install() {
    echo "Installing fail2ban"
    run apt-get -qq install -y fail2ban

    echo "Install sendmail (for email alerts)"
    run apt-get -qq install -y sendmail

    # Write fail2ban config files (example)
    sshd_port=2269

# heredocs don't seem to format nicely
cat << EOF > /etc/fail2ban/jail.local
backend = systemd

[sshd]
enabled = true
port = $sshd_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 6
EOF

}

echo "[fail2ban Package Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v fail2ban-server) ]]; then
    warning "fail2ban already exists. Installation skipped..."
else
    init_fail2ban_install
fi
