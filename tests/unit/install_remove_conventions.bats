#!/usr/bin/env bats
##
# Convention and regression tests for the install and remove scripts.
#
# Headers, checkout-root loading, help-before-root, and the CrowdSec
# installer/remover fixes are checked structurally. Those scripts need
# root, apt, and systemd, which a unit run cannot provide.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
}

# Non-empty shell scripts that carry the canonical banner.
installer_files() {
    local f
    for f in \
        "${REAL_BASE_DIR}/install.sh" \
        "${REAL_BASE_DIR}/remove.sh" \
        "${REAL_BASE_DIR}/lemper.sh" \
        "${REAL_BASE_DIR}/update.sh" \
        "${REAL_BASE_DIR}/scripts/utils.sh" \
        "${REAL_BASE_DIR}/lib/core/lemper-stacks.sh" \
        "${REAL_BASE_DIR}"/scripts/install_*.sh \
        "${REAL_BASE_DIR}"/scripts/remove_*.sh \
        "${REAL_BASE_DIR}"/scripts/server_*.sh \
        "${REAL_BASE_DIR}"/scripts/nginx/*.sh
    do
        [[ -s "${f}" ]] || continue
        printf '%s\n' "${f}"
    done
}

@test "install and remove scripts carry the 2014-2026 copyright banner" {
    local f
    while IFS= read -r f; do
        run grep -q 'Copyright (c) 2014-2026 MasEDI.Net' "${f}"
        [ "${status}" -eq 0 ]

        run grep -q 'GNU General Public License' "${f}"
        [ "${status}" -eq 0 ]

        run grep -q 'Authors: Edi Septriyanto' "${f}"
        [ "${status}" -eq 0 ]

        run grep -q '2014-2024' "${f}"
        [ "${status}" -ne 0 ]
    done < <(installer_files)
}

@test "install and remove header boxes are 77 columns wide" {
    local f
    while IFS= read -r f; do
        run awk 'NR <= 40 && /^# [|+]/ && length($0) != 77 { print FILENAME ":" NR ":" length($0); bad=1 } END { exit bad }' "${f}"
        [ "${status}" -eq 0 ]
    done < <(installer_files)
}

@test "component scripts load helpers from the checkout root" {
    local f
    for f in "${REAL_BASE_DIR}"/scripts/install_*.sh "${REAL_BASE_DIR}"/scripts/remove_*.sh; do
        [[ -s "${f}" ]] || continue
        run grep -q 'dirname "${BASH_SOURCE\[0\]}" )/.."' "${f}"
        [ "${status}" -eq 0 ]
        run grep -q 'scripts/utils.sh' "${f}"
        [ "${status}" -eq 0 ]
        # The old layout sourced utils.sh from the scripts directory itself.
        run grep -F -q '${BASE_DIR}/utils.sh' "${f}"
        [ "${status}" -ne 0 ]
    done
}

@test "entry points help without root and run from the checkout root" {
    local script
    for script in install.sh remove.sh lemper.sh; do
        run "${REAL_BASE_DIR}/${script}" --help
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"Usage:"* ]]

        if [[ "${script}" == "lemper.sh" ]]; then
            run grep -F -q 'cd "${LEMPER_ROOT}"' "${REAL_BASE_DIR}/${script}"
        else
            run grep -F -q 'cd "${BASE_DIR}"' "${REAL_BASE_DIR}/${script}"
        fi
        [ "${status}" -eq 0 ]
    done
}

@test "CrowdSec installer uses the release tarball and current hub items" {
    local installer="${REAL_BASE_DIR}/scripts/install_crowdsec.sh"

    grep -q 'crowdsec-release.tgz' "${installer}"
    grep -q 'wizard.sh --bininstall --force' "${installer}"
    grep -q 'crowdsecurity/linux' "${installer}"
    grep -q 'crowdsecurity/sshd' "${installer}"
    grep -q 'crowdsecurity/nginx' "${installer}"
    grep -q 'crowdsecurity/whitelist-good-actors' "${installer}"
    grep -q 'crowdsecurity/base-http-scenarios' "${installer}"
    grep -q 'crowdsecurity/wordpress' "${installer}"
    grep -q 'crowdsec-firewall-bouncer-iptables' "${installer}"
    grep -q 'crowdsec-nginx-bouncer' "${installer}"

    # Retired names abort `cscli hub install` and `apt-get install`.
    # whitelist-good-actors must stay; the old item was exactly "whitelist".
    run grep -E -q 'ssh-buster|wordpress-phpunit|hub install crowdsecurity/whitelist($|[^a-z-])' "${installer}"
    [ "${status}" -ne 0 ]
    run grep -E -q 'crowdsec-bouncer-nginx|crowdsec-bouncer[[:space:]]' "${installer}"
    [ "${status}" -ne 0 ]
    run grep -F -q 'script.deb.sh | bash' "${installer}"
    [ "${status}" -ne 0 ]
    run grep -F -q 'linux_amd64.tar.gz' "${installer}"
    [ "${status}" -ne 0 ]
}

@test "CrowdSec removal does not abort on a stopped unit" {
    local remover="${REAL_BASE_DIR}/scripts/remove_crowdsec.sh"

    grep -q 'systemctl cat crowdsec.service' "${remover}"
    grep -q 'pkill -x crowdsec' "${remover}"
    grep -q '/usr/bin/crowdsec' "${remover}"
    grep -q '/usr/local/lib/crowdsec' "${remover}"

    # `run` exits on failure, so the real stop cannot be `run ... || true`.
    # Dry-run still prints the command through `run`.
    grep -q 'systemctl stop crowdsec >/dev/null 2>&1 || true' "${remover}"
    run grep -F -q 'run systemctl stop crowdsec 2>/dev/null || true' "${remover}"
    [ "${status}" -ne 0 ]
    run grep -F -q 'pkill -f crowdsec' "${remover}"
    [ "${status}" -ne 0 ]

    # autoremove only follows a purge, so an already-absent package does not
    # drag unrelated automatic dependencies off the system.
    run awk '
        /apt-get purge/ { purge=NR }
        /apt-get autoremove/ { auto=NR }
        END { exit !(purge > 0 && auto > purge) }
    ' "${remover}"
    [ "${status}" -eq 0 ]
}
