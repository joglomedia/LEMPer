#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child programs preserve literal fixture expansions.
load env_helper
setup() { unit_setup; }

@test "every runtime and service module imports without configuration, mutations, options or traps" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        poison() { printf "SOURCE_MUTATION\n"; return 99; }
        run() { poison; }
        lemper_exec() { poison; }
        curl() { poison; }
        wget() { poison; }
        apt-get() { poison; }
        systemctl() { poison; }
        requires_root() { poison; }
        preflight_system_check() { poison; }
        before_environment=$(export -p)
        before_options=$(set +o)
        before_traps=$(trap -p)
        before_directory=$PWD
        profile=$(sha256sum "$TEST_TMPDIR/.env")
        while IFS= read -r module; do
            . "$module" || exit 1
        done < <(find "$REAL_BASE_DIR/lib/runtime" "$REAL_BASE_DIR/lib/services" -name "*.sh" | sort)
        [[ "$(export -p)" == "$before_environment" ]] || exit 1
        [[ "$(set +o)" == "$before_options" && "$(trap -p)" == "$before_traps" && "$PWD" == "$before_directory" ]] || exit 1
        [[ "$(sha256sum "$TEST_TMPDIR/.env")" == "$profile" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *SOURCE_MUTATION* ]]
}

@test "component adapters and the registry resolve the same module and callable entry" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        count=0
        for script in "$REAL_BASE_DIR"/scripts/install_*.sh "$REAL_BASE_DIR"/scripts/remove_*.sh; do
            grep -q '\''_entry "\$@"'\'' "$script" || continue
            base=${script##*/}
            action=${base%%_*}
            component=${base#*_}; component=${component%.sh}
            [[ "$component" != certbotle ]] || component=certbot
            read -r module handler < <(lemper_component_driver "$action" "$component") || exit 1
            [[ -n "$module" && -n "$handler" ]] || exit 1
            grep -Fq "lemper_load_module $module " "$script" || exit 1
            lemper_load_module "$module" || exit 1
            declare -F "$handler" >/dev/null || exit 1
            count=$((count + 1))
        done
        ((count > 0)) || exit 1
        [[ "$(lemper_component_driver install valkey)" == "$(lemper_component_driver install redis)" ]] || exit 1
        ! lemper_component_driver "install;bad" php
    '
    [ "$status" -eq 0 ]
}

@test "component orchestration preserves arguments and returns driver failures" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/components/lifecycle
        lemper_component_driver() { printf "services/php/install fixture_entry\n"; }
        lemper_load_module() { printf "MODULE <%s>\n" "$1"; }
        fixture_entry() { printf "ARG <%s>\n" "$@"; return 23; }
        lemper_component_apply install php "space value" "literal;value"
    '
    [ "$status" -eq 23 ]
    [[ "$output" == *'MODULE <services/php/install>'* ]]
    [[ "$output" == *'ARG <space value>'* && "$output" == *'ARG <literal;value>'* ]]
}

@test "update help and invalid dispatch return without changing the calling shell" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        PROG_NAME=lemperctl LEMPER_UPDATE_LIB_ONLY=true
        requires_root() { :; }
        . "$REAL_BASE_DIR/lib/lemper-update.sh"
        before_options=$(set +o)
        before_traps=$(trap -p)
        init_lemper_update help >/dev/null || exit 1
        if init_lemper_update unknown >/dev/null 2>&1; then exit 1; fi
        [[ "$(set +o)" == "$before_options" && "$(trap -p)" == "$before_traps" ]] || exit 1
        printf "SURVIVED\n"
    '
    [ "$status" -eq 0 ]
    [ "$output" = SURVIVED ]
}

@test "component help and version bypass private profiles, root checks and locks" {
    run bash -c '
        for script in "$REAL_BASE_DIR"/scripts/install_*.sh "$REAL_BASE_DIR"/scripts/remove_*.sh; do
            grep -q '\''_entry "\$@"'\'' "$script" || continue
            LEMPER_ENV_FILE=/missing/private/profile bash "$script" --help >/dev/null || exit 1
            LEMPER_ENV_FILE=/missing/private/profile bash "$script" --version >/dev/null || exit 1
        done
    '
    [ "$status" -eq 0 ]
}
