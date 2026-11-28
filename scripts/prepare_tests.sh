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

# Run only in a designated disposable Linux environment or CI runner.
set -euo pipefail
[[ "$EUID" == 0 && "$(uname -s)" == Linux ]] || {
    echo 'Test setup requires root in a disposable Debian/Ubuntu environment.' >&2
    exit 1
}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
test_lint_packages=(bashate)
if ! apt-cache show bashate >/dev/null 2>&1; then
    # Resolute no longer packages the upstream Python-based lint tool.
    test_lint_packages=(python3-venv)
fi
apt-get install -q -y bash bats bc bind9-utils ca-certificates curl git gnupg iproute2 jq mariadb-client nginx \
    openssh-server "${test_lint_packages[@]}" libxml2-utils quota rsync shfmt socat sudo unzip zip xz-utils
if [[ "${test_lint_packages[0]}" != bashate ]]; then
    python3 -m venv /opt/lemper-test-tools/bashate
    /opt/lemper-test-tools/bashate/bin/pip install --disable-pip-version-check bashate
    ln -sfn /opt/lemper-test-tools/bashate/bin/bashate /usr/local/bin/bashate
fi
mkdir -p /run/sshd
ssh-keygen -A
if ! shellcheck --version 2>/dev/null | grep -qx 'version: 0.11.0'; then
    case "$(uname -m)" in x86_64) arch=x86_64 ;; aarch64 | arm64) arch=aarch64 ;; *)
        echo 'Unsupported ShellCheck architecture.' >&2
        exit 1
        ;;
    esac
    tools_work=$(mktemp -d)
    trap 'rm -rf -- "$tools_work"' EXIT
    curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.$arch.tar.xz" \
        -o "$tools_work/shellcheck.tar.xz"
    tar -xf "$tools_work/shellcheck.tar.xz" -C "$tools_work"
    install -m0755 "$tools_work/shellcheck-v0.11.0/shellcheck" /usr/local/bin/shellcheck
fi
shellcheck --version | grep -qx 'version: 0.11.0'
