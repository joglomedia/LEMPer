#!/usr/bin/env bats

load env_helper

setup() {
    unit_setup
}

@test "MongoDB bootstrap isolates the package-started service until admin enrollment" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mongodb/install || exit 1
        DRYRUN=false
        MONGODB_ADMIN_USER=fixtureuser
        MONGODB_ADMIN_PASSWORD=fixture-password-for-install
        dropin="$TEST_TMPDIR/mongod.service.d/90-lemper-security.conf"
        state="$TEST_TMPDIR/mongodb"
        systemctl() {
            case "$1" in
                cat) return 1 ;;
                show) printf "%s\n" 123 ;;
                restart) printf "%s\n" restart ;;
                enable|daemon-reload) return 0 ;;
                *) return 1 ;;
            esac
        }
        add_mongodb_repo() { :; }
        apt-get() {
            grep -Fxq PrivateNetwork=true "$dropin" || return 1
            grep -Fq -- "--nounixsocket --auth" "$dropin" || return 1
            grep -Fq "MongoDB bootstrap requires an isolated network namespace." "$dropin" || return 1
            grep -Fq -- "setpriv --reuid mongodb --regid mongodb --init-groups" "$dropin" || return 1
            [[ "$(stat -c %a "$state/pending")" == 600 ]] || return 1
            mongod() { :; }
            mongosh() { :; }
            printf "%s\n" packages
        }
        lemper_mongodb_admin_check() {
            if [[ "$1" == bootstrap ]]; then
                [[ "$4" == 123 && "$2" == fixtureuser && "$3" == fixture-password-for-install ]] || return 1
                grep -Fxq PrivateNetwork=true "$dropin" || return 1
                printf "%s\n" enrolled
            else
                grep -Fxq PrivateNetwork=false "$dropin" || return 1
                grep -Fq -- "--auth --setParameter enableLocalhostAuthBypass=0" "$dropin" || return 1
                printf "%s\n" authenticated
            fi
        }
        lemper_mongodb_save_profile() { printf "%s\n" persisted; }
        lemper_mongodb_managed_install "$state" "$dropin" || exit 1
        [[ -f "$state/configured" && ! -e "$state/pending" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *$'packages\nrestart\nenrolled\npersisted\nrestart\nauthenticated'* ]]
}

@test "MongoDB retry retains a credential when enrollment cannot finish" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mongodb/install || exit 1
        DRYRUN=false
        MONGODB_ADMIN_USER=fixtureuser
        MONGODB_ADMIN_PASSWORD=fixture-first-password
        dropin="$TEST_TMPDIR/mongod.service.d/90-lemper-security.conf"
        state="$TEST_TMPDIR/mongodb"
        systemctl() {
            case "$1" in
                cat) return 1 ;;
                show) printf "%s\n" 123 ;;
                *) return 0 ;;
            esac
        }
        add_mongodb_repo() { :; }
        apt-get() { mongod() { :; }; mongosh() { :; }; }
        sleep() { :; }
        lemper_mongodb_admin_check() { return 1; }
        ! lemper_mongodb_managed_install "$state" "$dropin" || exit 1
        [[ -f "$state/pending" && ! -e "$state/configured" ]] || exit 1
        grep -Fxq PrivateNetwork=true "$dropin" || exit 1
        MONGODB_ADMIN_PASSWORD=fixture-other-password
        lemper_mongodb_admin_check() { [[ "$3" == fixture-first-password ]]; }
        lemper_mongodb_save_profile() { [[ "$2" == fixture-first-password ]]; }
        lemper_mongodb_managed_install "$state" "$dropin" || exit 1
        [[ -f "$state/configured" && ! -e "$state/pending" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"isolated enrollment failed"* ]]
}

@test "cache config writes a private final mode and keeps one managed block across retries" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/redis/install || exit 1
        DRYRUN=false
        chgrp() { :; }
        config="$TEST_TMPDIR/redis.conf"
        printf "%s\n" "bind 127.0.0.1" "daemonize yes" > "$config"
        lemper_cache_configure redis "$config" 256 fixture-first-password || exit 1
        lemper_cache_configure redis "$config" 2048 fixture-next-password || exit 1
        [[ "$(stat -c %a "$config")" == 640 ]] || exit 1
        [[ "$(grep -c "^requirepass " "$config")" == 1 ]] || exit 1
        grep -Fxq "requirepass fixture-next-password" "$config" || exit 1
        grep -Fxq "maxmemory 2048mb" "$config" || exit 1
        grep -Fxq "bind 127.0.0.1" "$config" || exit 1
        lemper_cache_configure redis "$config" 256 || exit 1
        grep -Fxq "requirepass fixture-next-password" "$config"
    '
    [ "$status" -eq 0 ]
}

@test "cache access verification requires denial of anonymous requests and stdin authentication" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/redis/install || exit 1
        timeout() {
            case "${*: -1}" in
                PING) printf "%s\n" "NOAUTH Authentication required." ;;
                AUTH) [[ "$*" != *fixture-password-for-install* && "$(cat)" == fixture-password-for-install ]] || return 1
                    printf "%s\n" OK ;;
                *) return 1 ;;
            esac
        }
        lemper_cache_check_access redis fixture-password-for-install || exit 1
        timeout() { printf "%s\n" PONG; }
        ! lemper_cache_check_access redis fixture-password-for-install || exit 1
        lemper_cache_check_access redis
    '
    [ "$status" -eq 0 ]
}
