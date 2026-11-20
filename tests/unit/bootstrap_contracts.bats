#!/usr/bin/env bats
setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TEST_TMPDIR}"
    export RELEASE_VERSION=4.0.0
    export STAGE="${TEST_TMPDIR}/stage/LEMPer-${RELEASE_VERSION}"
    export ARCHIVE="${TEST_TMPDIR}/release.tar.gz"
    export PREFIX="${TEST_TMPDIR}/installed"
    mkdir -p "${STAGE}"
    cp -R "${REAL_BASE_DIR}/bin" "${REAL_BASE_DIR}/lib" "${REAL_BASE_DIR}/scripts" "${STAGE}/"
    cp "${REAL_BASE_DIR}/.env.dist" "${STAGE}/.env.dist"
    cp "$REAL_BASE_DIR/install.sh" "$STAGE/install.sh"
}
make_archive() {
    tar -czf "${ARCHIVE}" -C "${TEST_TMPDIR}/stage" "LEMPer-${RELEASE_VERSION}"
    export RELEASE_SHA
    RELEASE_SHA=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
}
bootstrap_run() {
    run bash "${REAL_BASE_DIR}/get-lemper" --version "${RELEASE_VERSION}" --archive "${ARCHIVE}" --sha256 "${RELEASE_SHA}" --prefix "${PREFIX}"
}
@test "bootstrap installs versioned CLI and aliases without running stack installers" {
    printf 'echo SHOULD_NOT_RUN > "%s/installer-ran"\n' "${TEST_TMPDIR}" > "${STAGE}/scripts/install_nginx.sh"
    make_archive
    bootstrap_run
    [ "${status}" -eq 0 ]
    [ -L "${PREFIX}/usr/local/bin/lemper-cli" ]
    [ -L "${PREFIX}/usr/local/bin/lemperctl" ]
    [ -f "${PREFIX}/etc/lemper/core/loader.sh" ]
    [ -x "${PREFIX}/etc/lemper/cli-plugins/lemper-stack" ]
    [ ! -f "${TEST_TMPDIR}/installer-ran" ]
    [ "$(stat -c %a "${PREFIX}/etc/lemper/lemper.conf")" = 600 ]
}
@test "bootstrap preserves existing config and repeats only identical releases" {
    mkdir -p "${PREFIX}/etc/lemper"
    printf 'EXISTING=keep-me\n' > "${PREFIX}/etc/lemper/lemper.conf"
    make_archive
    bootstrap_run
    [ "${status}" -eq 0 ]
    bootstrap_run
    [ "${status}" -eq 0 ]
    [ "$(cat "${PREFIX}/etc/lemper/lemper.conf")" = "EXISTING=keep-me" ]
}
@test "bootstrap rejects an incorrect checksum before creating installation paths" {
    make_archive
    RELEASE_SHA=$(printf '0%.0s' {1..64})
    bootstrap_run
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"checksum mismatch"* ]]
    [ ! -e "${PREFIX}" ]
}

@test "bootstrap CLI dry run validates the release without creating a prefix" {
    make_archive
    run bash "$REAL_BASE_DIR/get-lemper" --version "$RELEASE_VERSION" --archive "$ARCHIVE" \
        --sha256 "$RELEASE_SHA" --prefix "$PREFIX" --dry-run
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX" ]
}

@test "bootstrap full-stack dry run accepts a configured profile without activating CLI code" {
    printf 'SSH_PASSWORDLESS=false\nDRYRUN=true\n' > "$TEST_TMPDIR/profile"
    make_archive
    run bash "$REAL_BASE_DIR/get-lemper" --version "$RELEASE_VERSION" --archive "$ARCHIVE" \
        --sha256 "$RELEASE_SHA" --install --config "$TEST_TMPDIR/profile" --minimal --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"no system changes"* && "$output" == *"mariadb"* ]]
    [ ! -e /opt/lemper/4.0.0 ]
}

@test "bootstrap rejects full-stack prefix overrides and a mislabeled release" {
    make_archive
    run bash "$REAL_BASE_DIR/get-lemper" --version "$RELEASE_VERSION" --archive "$ARCHIVE" \
        --sha256 "$RELEASE_SHA" --prefix "$PREFIX" --install --config "$STAGE/.env.dist"
    [ "$status" -ne 0 ]
    [ ! -e "$PREFIX" ]
    sed -i 's/PROG_VERSION="4.0.0"/PROG_VERSION="3.6.0"/' "$STAGE/bin/lemper-cli.sh"
    make_archive
    bootstrap_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Release version does not match"* ]]
    [ ! -e "$PREFIX" ]
}
@test "bootstrap rejects archive symlinks and traversal before extraction" {
    ln -s /etc "${STAGE}/unsafe-link"
    make_archive
    bootstrap_run
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"links and special files"* ]]
    [ ! -e "${PREFIX}" ]
    rm "${STAGE}/unsafe-link"
    tar -czf "${ARCHIVE}" --transform='s,^,../,' -C "${TEST_TMPDIR}/stage" "LEMPer-${RELEASE_VERSION}"
    RELEASE_SHA=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
    bootstrap_run
    [ "${status}" -ne 0 ]
    [ ! -e "${PREFIX}" ]
}

@test "bootstrap accepts ordinary systemd template filenames in complete releases" {
    mkdir -p "$STAGE/etc/systemd"
    printf '[Unit]\nDescription=Fixture\n' > "$STAGE/etc/systemd/memcached@.service"
    make_archive
    bootstrap_run
    [ "$status" -eq 0 ]
    [ -f "$PREFIX/opt/lemper/$RELEASE_VERSION/etc/systemd/memcached@.service" ]
}
@test "release builder produces repeatable checksummed archives and refuses mismatched versions" {
    local root="${TEST_TMPDIR}/repo"
    mkdir -p "${root}/scripts" "${root}/bin"
    cp "${REAL_BASE_DIR}/scripts/build_release.sh" "${root}/scripts/"
    cp "${REAL_BASE_DIR}/get-lemper" "${root}/get-lemper"
    printf 'PROG_VERSION="4.0.0"\n' > "${root}/bin/lemper-cli.sh"
    printf '## [4.0.0]\n' > "${root}/CHANGELOG.md"
    git init -q "${root}"
    git -C "${root}" add .
    git -C "${root}" -c user.name=Fixture -c user.email=fixture@example.test -c core.hooksPath=/dev/null commit -qm fixture
    run bash "${root}/scripts/build_release.sh" 4.0.0 "${TEST_TMPDIR}/out1"
    [ "${status}" -eq 0 ]
    run bash "${root}/scripts/build_release.sh" 4.0.0 "${TEST_TMPDIR}/out2"
    [ "${status}" -eq 0 ]
    cmp "${TEST_TMPDIR}/out1/lemper-v4.0.0.tar.gz" "${TEST_TMPDIR}/out2/lemper-v4.0.0.tar.gz"
    run bash -c 'cd "$1" && sha256sum -c get-lemper.sha256' _ "$TEST_TMPDIR/out1"
    [ "$status" -eq 0 ]
    run bash "${root}/scripts/build_release.sh" 3.6.0 "${TEST_TMPDIR}/out3"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"does not match"* ]]
}

@test "CLI snapshots exclude checkout credentials and switch one code tree without changing old releases" {
    printf 'PRIVATE_SECRET=synthetic\n' > "$STAGE/.env"
    run bash -c '
        . "$1/lib/core/registry.sh"
        . "$1/lib/core/deployment.sh"
        error() { echo "$*" >&2; }
        info() { :; }
        DRYRUN=false
        lemper_cli_snapshot "$2" "$3" || exit 1
        previous=$(readlink "$3/opt/lemper/current")
        digest=$(sha256sum "$previous/bin/lemper-cli.sh")
        [ ! -e "$previous/.env" ] || exit 1
        [ -L "$3/etc/lemper/core/loader.sh" ] || exit 1
        [ -L "$3/etc/lemper/runtime" ] || exit 1
        printf "\n# new fixture revision\n" >> "$2/bin/lemper-cli.sh"
        lemper_cli_snapshot "$2" "$3" || exit 1
        [ "$(readlink "$3/opt/lemper/current")" != "$previous" ] || exit 1
        [ "$(sha256sum "$previous/bin/lemper-cli.sh")" = "$digest" ] || exit 1
        [ "$(stat -c %a "$3/opt/lemper/current/lib/core/registry.sh")" = 644 ]
    ' _ "$REAL_BASE_DIR" "$STAGE" "$PREFIX"
    [ "$status" -eq 0 ]
    [ "$(cat "$STAGE/.env")" = PRIVATE_SECRET=synthetic ]
}
@test "incomplete release activation preserves the selected code tree" {
    make_archive
    bootstrap_run
    [ "$status" -eq 0 ]
    local previous
    previous=$(readlink "$PREFIX/opt/lemper/current")
    rm "$STAGE/lib/lemper-stack.sh"
    run bash -c '
        . "$1/lib/core/registry.sh"
        . "$1/lib/core/deployment.sh"
        error() { echo "$*" >&2; }
        lemper_cli_activate "$2" "$3"
    ' _ "$REAL_BASE_DIR" "$STAGE" "$PREFIX"
    [ "$status" -ne 0 ]
    [ "$(readlink "$PREFIX/opt/lemper/current")" = "$previous" ]
}

@test "historical installed plugin paths still resolve the selected runtime modules" {
    make_archive
    bootstrap_run
    [ "$status" -eq 0 ]
    run bash -c '
        requires_root() { :; }
        PROG_NAME=lemperctl
        PROG_VERSION=test
        . "$1/etc/lemper/cli-plugins/lemper-site" create example.com --type=wordpress --runtime=php@8.5 --dry-run
    ' _ "$PREFIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create example.com"* ]]
}
