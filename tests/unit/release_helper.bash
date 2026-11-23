# Bash fixtures for release/provider and hostile-archive tests.
function release_fixture() {
    local repo="$1" tag="$2" name="$3" digest="${4:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    jq -n --arg tag "$tag" --arg name "$name" --arg digest "$digest" \
        --arg url "https://github.com/$repo/releases/download/$tag/$name" \
        '{tag_name:$tag,draft:false,prerelease:false,assets:[{name:"unwanted-update.zip"},{name:$name,digest:("sha256:"+$digest),browser_download_url:$url}]}' >"$TEST_TMPDIR/metadata"
}
function metadata_exec() {
    run bash -c '. "$REAL_BASE_DIR/lib/services/site/release_metadata.sh"; lemper_site_release_metadata "$@"' _ "$@"
}
function archive_exec() {
    run bash -c '. "$REAL_BASE_DIR/lib/services/site/release_archive.sh"; lemper_site_release_unpack "$@"' _ "$@"
}
function zip_u16() {
    local value="$1" byte
    for byte in "$((value & 255))" "$(((value >> 8) & 255))"; do
        printf -v byte '\\%03o' "$byte"
        printf '%b' "$byte"
    done
}
function zip_u32() {
    zip_u16 "$(($1 & 65535))"
    zip_u16 "$((($1 >> 16) & 65535))"
}
# Empty stored ZIP entries have CRC 0; build headers directly to preserve hostile
# names that ordinary zip tools normalize/refuse (including duplicate entries).
function hostile_zip() {
    local archive="$1" name offset=0 start length count=0 central
    shift
    central="$TEST_TMPDIR/central"
    : >"$central"
    : >"$archive"
    for name in "$@"; do
        length="${#name}"
        {
            printf 'PK\003\004'
            zip_u16 20
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u32 0
            zip_u32 0
            zip_u32 0
            zip_u16 "$length"
            zip_u16 0
            printf '%s' "$name"
        } >>"$archive"
        {
            printf 'PK\001\002'
            zip_u16 20
            zip_u16 20
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u32 0
            zip_u32 0
            zip_u32 0
            zip_u16 "$length"
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u16 0
            zip_u32 0
            zip_u32 "$offset"
            printf '%s' "$name"
        } >>"$central"
        offset=$((offset + 30 + length)) count=$((count + 1))
    done
    start="$offset"
    cat "$central" >>"$archive"
    {
        printf 'PK\005\006'
        zip_u16 0
        zip_u16 0
        zip_u16 "$count"
        zip_u16 "$count"
        zip_u32 "$(wc -c <"$central")"
        zip_u32 "$start"
        zip_u16 0
    } >>"$archive"
}
