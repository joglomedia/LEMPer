#!/usr/bin/env bats
load env_helper
setup() { unit_setup; export LEMPER_HOSTING_ROOT="$TEST_TMPDIR/hosting"; }

hosting_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    lemper_load_module services/hosting/quota
    lemper_load_module services/hosting/plans
    error() { echo "$*" >&2; }
    info() { :; }
    DRYRUN=false
    HOSTING_QUOTA_MOUNT=/home
    lemper_quota_mount() { echo 11111111-1111-1111-1111-111111111111; }
    lemper_hosting_user() { echo 1001; }
    lemper_quota_read() { cat "$TEST_TMPDIR/quota"; }
    setquota() { printf "20 4 %s %s %s %s\n" "$3" "$4" "$5" "$6" > "$TEST_TMPDIR/quota"; }
    printf "20 4 100 200 10 20\n" > "$TEST_TMPDIR/quota"
'
@test "hosting sizes validate binary units and reject malformed/inverted/unlimited limits" {
    run bash -c "$hosting_child"'
        [[ $(lemper_hosting_size 2G) == 2097152 ]] || exit 1
        ! lemper_hosting_size "1G;touch unsafe" || exit 1
        ! lemper_hosting_size -1 || exit 1
        ! lemper_hosting_limits 200 100 10 20 || exit 1
        ! lemper_hosting_limits 0 0 0 0 || exit 1
        ! lemper_hosting_limits 01 200 10 20
    '
    [ "$status" -eq 0 ]
}
@test "hosting assignment upgrade repeat and detach preserve original quotas and data" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        lemper_hosting_plan_put large 256 512 60 80 || exit 1
        lemper_hosting_assign alice small || exit 1
        lemper_hosting_assign alice small || exit 1
        lemper_hosting_assign alice large || exit 1
        lemper_hosting_detach alice || exit 1
        [[ $(cat "$TEST_TMPDIR/quota") == "20 4 100 200 10 20" ]] || exit 1
        [[ ! -e "$LEMPER_HOSTING_ROOT/assignments/alice.conf" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting active plans are immutable and cannot be deleted" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        lemper_hosting_assign alice small || exit 1
        ! lemper_hosting_plan_put small 128 512 30 40 || exit 1
        ! lemper_hosting_plan_delete small || exit 1
        [[ $(lemper_hosting_plan_read small) == "128 256 30 40" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting downgrade below live usage makes no quota change" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put tiny 1 10 1 2 || exit 1
        ! lemper_hosting_assign alice tiny || exit 1
        [[ $(cat "$TEST_TMPDIR/quota") == "20 4 100 200 10 20" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting dry-run neither creates plans nor changes live quotas" {
    run bash -c "$hosting_child"'
        DRYRUN=true lemper_hosting_plan_put tiny 1 100 1 10 || exit 1
        [[ ! -e "$LEMPER_HOSTING_ROOT" ]] || exit 1
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        DRYRUN=true lemper_hosting_assign alice small || exit 1
        [[ ! -e "$LEMPER_HOSTING_ROOT/assignments/alice.conf" ]] || exit 1
        [[ $(cat "$TEST_TMPDIR/quota") == "20 4 100 200 10 20" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting failed quota application restores prior limits and metadata" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        setquota() {
            [[ "$4" != 256 ]] || return 1
            printf "20 4 %s %s %s %s\n" "$3" "$4" "$5" "$6" > "$TEST_TMPDIR/quota"
        }
        ! lemper_hosting_assign alice small || exit 1
        [[ ! -e "$LEMPER_HOSTING_ROOT/assignments/alice.conf" ]] || exit 1
        [[ $(cat "$TEST_TMPDIR/quota") == "20 4 100 200 10 20" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting failed rollback retains pending recovery and blocks plan deletion" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        setquota() { return 1; }
        ! lemper_hosting_assign alice small || exit 1
        lemper_hosting_state_read alice || exit 1
        [[ ${LEMPER_HOSTING_STATE[17]} == pending ]] || exit 1
        ! lemper_hosting_plan_delete small || exit 1
        setquota() { printf "20 4 %s %s %s %s\n" "$3" "$4" "$5" "$6" > "$TEST_TMPDIR/quota"; }
        lemper_hosting_detach alice true || exit 1
        [[ ! -e "$LEMPER_HOSTING_ROOT/assignments/alice.conf" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting UID drift and externally changed limits cannot be overwritten" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        lemper_hosting_assign alice small || exit 1
        lemper_hosting_user() { echo 1002; }
        ! lemper_hosting_detach alice || exit 1
        lemper_hosting_user() { echo 1001; }
        echo "20 4 128 999 30 40" > "$TEST_TMPDIR/quota"
        ! lemper_hosting_assign alice small || exit 1
        ! lemper_hosting_detach alice
    '
    [ "$status" -eq 0 ]
}
@test "hosting symlink state and executable/malformed plans are rejected without evaluation" {
    run bash -c "$hosting_child"'
        mkdir -p "$TEST_TMPDIR/target"
        ln -s "$TEST_TMPDIR/target" "$LEMPER_HOSTING_ROOT"
        ! lemper_hosting_plan_put small 128 256 30 40 || exit 1
        rm "$LEMPER_HOSTING_ROOT"
        mkdir -p "$LEMPER_HOSTING_ROOT/plans"
        printf "$(printf '\''$'\'')(touch %s/pwned)\n" "$TEST_TMPDIR" > "$LEMPER_HOSTING_ROOT/plans/small.conf"
        ! lemper_hosting_plan_read small || exit 1
        [[ ! -e "$TEST_TMPDIR/pwned" ]]
    '
    [ "$status" -eq 0 ]
}
@test "quota capability checks reject overlay and inactive ext4 without mutations" {
    run bash -c "$hosting_child"'
        lemper_load_module services/hosting/quota
        realpath() { echo /home; }
        findmnt() { echo "/home overlay -"; }
        ! lemper_quota_mount /home || exit 1
        findmnt() { echo "/home ext4 11111111-1111-1111-1111-111111111111"; }
        quotaon() { echo "user quota on /home is off"; }
        ! lemper_quota_mount /home
    '
    [ "$status" -eq 0 ]
}
@test "quota numeric CSV parser extracts limits and rejects unknown formats" {
    run bash -c "$hosting_child"'
        lemper_load_module services/hosting/quota
        repquota() {
            echo "User,BlockStatus,FileStatus,BlockUsed,BlockSoftLimit,BlockHardLimit,BlockGrace,FileUsed,FileSoftLimit,FileHardLimit,FileGrace"
            echo "#1001,ok,ok,20,100,200,0,4,10,20,0"
        }
        [[ $(lemper_quota_read 1001 /home) == "20 4 100 200 10 20" ]] || exit 1
        [[ $(lemper_quota_read 1002 /home) == "0 0 0 0 0 0" ]] || exit 1
        repquota() { echo unknown; }
        ! lemper_quota_read 1001 /home
    '
    [ "$status" -eq 0 ]
}
@test "hosting commands require explicit teardown and help never reads host state" {
    run bash -c "$hosting_child"'
        lemper_load_module runtime/hosting/commands
        lemper_hosting_command detach alice && exit 1
        lemper_quota_mount() { echo UNEXPECTED; return 1; }
        lemper_hosting_command --help
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED* ]]
}
@test "hosting refuses unowned accounts system UIDs and homes on another filesystem" {
    run bash -c "$hosting_child"'
        lemper_load_module services/hosting/plans
        export LEMPER_HOSTING_ACCOUNT_ROOT="$TEST_TMPDIR/accounts"
        ! lemper_hosting_user alice /home || exit 1
        mkdir -p "$LEMPER_HOSTING_ACCOUNT_ROOT"
        touch "$LEMPER_HOSTING_ACCOUNT_ROOT/alice.conf"
        id() { echo 33; }
        ! lemper_hosting_user alice /home || exit 1
        id() { echo 1001; }
        getent() { echo "alice:x:1001:1001::/home/alice:/bin/bash"; }
        realpath() { echo /home/alice; }
        findmnt() { echo /; }
        ! lemper_hosting_user alice /home || exit 1
        findmnt() { echo /home; }
        [[ $(lemper_hosting_user alice /home) == 1001 ]]
    '
    [ "$status" -eq 0 ]
}
@test "quota commands that report success without applying limits fail verification" {
    run bash -c "$hosting_child"'
        setquota() { :; }
        ! lemper_quota_set 1001 /home 200 300 20 30
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"verification failed"* ]]
}
@test "quota capability accepts enabled quotaon status 1 but rejects a noncanonical target" {
    run bash -c "$hosting_child"'
        lemper_load_module services/hosting/quota
        realpath() { echo /home; }
        findmnt() { echo "/home ext4 11111111-1111-1111-1111-111111111111"; }
        quotaon() { echo "user quota on /home (/dev/test) is on"; return 1; }
        [[ $(lemper_quota_mount /home) == 11111111-1111-1111-1111-111111111111 ]] || exit 1
        ! lemper_quota_mount /home/link
    '
    [ "$status" -eq 0 ]
}
@test "account quota preflight fails before account creation on an unsupported filesystem" {
    run bash -c "$hosting_child"'
        lemper_load_module runtime/account/commands
        lemper_quota_mount() { return 1; }
        create_account() { echo UNEXPECTED-CREATION; }
        ! lemper_account_with_plan alice missing
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED-CREATION* ]]
}
@test "pending transaction after successful application recovers the original baseline" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        lemper_hosting_assign alice small || exit 1
        sed -i "s/ active$/ pending/" "$LEMPER_HOSTING_ROOT/assignments/alice.conf"
        lemper_hosting_detach alice true || exit 1
        [[ $(cat "$TEST_TMPDIR/quota") == "20 4 100 200 10 20" ]]
    '
    [ "$status" -eq 0 ]
}
@test "hosting strict configuration accepts public options and forbids state-path overrides" {
    run bash -c "$hosting_child"'
        validate_config_value HOSTING_QUOTA_MOUNT /home strict || exit 1
        validate_config_value HOSTING_QUOTA_MOUNT / strict || exit 1
        ! validate_config_value HOSTING_QUOTA_MOUNT "/home;rm" strict || exit 1
        ! validate_config_value LEMPER_HOSTING_ROOT /tmp/attacker || exit 1
        ! validate_config_value INSTALL_QUOTA yes strict || exit 1
        validate_config_file "$REAL_BASE_DIR/.env.dist" strict
    '
    [ "$status" -eq 0 ]
}
@test "active assignments block quota and full-stack removal even in dry-run or force mode" {
    run bash -c "$hosting_child"'
        lemper_hosting_plan_put small 128 256 30 40 || exit 1
        lemper_hosting_assign alice small || exit 1
        lemper_load_module services/optional
        ! DRYRUN=true lemper_optional_lifecycle remove quota || exit 1
        . "$REAL_BASE_DIR/lib/runtime/stack/recipe.sh"
        lemper_recipe_components() { echo UNEXPECTED-REMOVAL; }
        ! DRYRUN=true FORCE_REMOVE=true lemper_remove
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *UNEXPECTED-REMOVAL* ]]
}
