#!/bin/bash
# Exercises the shipped Make targets against the real ULDAQ source and toolchain.
# Every case copies the real build files into a fresh directory and runs the actual make
# targets; the checks read the installed files, the vendor record files and the exit codes.
# Evidence files in the workspace: source.tsv, commands.tsv, checks.tsv, result.txt, logs/.
set -euo pipefail

readonly UPSTREAM_COMMIT="f87594f7db478adb736a7868859133c45b6ec6b7"
readonly UPSTREAM_TAG="v1.2.2"
readonly UPSTREAM_VERSION="1.2.2"
readonly PATCH_NAME="1.2.2-tcp-receive.p0.patch"
readonly CORRECTION="err = (received == 0) ? ERR_DEV_NOT_CONNECTED : ERR_DEAD_DEV;"
readonly SOURCE_FILE="src/net/NetDaqDevice.cpp"
readonly RECORD_NAME="uldaq"
readonly COMMAND_TIMEOUT=900
readonly CHECK_PATTERN=$'\t\t\t// EOF or a short header cannot represent a complete response.\n\t\t\t'

repository=""
workspace=""
source_repository=""
jobs=2
mode="build"
protected_prefix=""
config_target="conf"

logs_dir=""
seed=""
total_checks=0
command_count=0
complete=0
error_text=""
declare -a failed_names=()
declare -A snapshot=()

# Case and prefix of the most recently created case.
case_dir=""
case_prefix=""
# Exit status and log path of the most recent command.
run_code=0
run_log=""

function usage {
    printf '%s\n' 'Usage: test_build.bash --workspace DIR [--repository DIR] [--source-repository DIR]' >&2
    printf '%s\n' '       [--jobs N] [--mode build|user|protected] [--protected-prefix DIR] [--config-target T]' >&2
    exit 2
}

function digest {
    local hash
    read -r hash _ < <(sha256sum -- "$1")
    printf '%s\n' "$hash"
}

# Reads a whole file into the named variable, keeping every newline.
function slurp {
    local -n target="$1"
    IFS= read -r -d '' target < "$2" || true
}

function one_line {
    local text="$1"
    text="${text//$'\t'/ }"
    text="${text//$'\n'/ }"
    printf '%s' "${text:0:300}"
}

function utc_now {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Records one assertion: check NAME EVIDENCE COMMAND...; the command passes with exit status 0.
function check {
    local name="$1" evidence="$2" verdict="PASS"
    shift 2
    if ! "$@"; then
        verdict="FAIL"
    fi
    total_checks=$((total_checks + 1))
    printf '%s\t%s\t%s\t%s\n' "$total_checks" "$verdict" "$name" "$(one_line "$evidence")" >> "$workspace/checks.tsv"
    printf '[%s] %s\n' "$verdict" "$name"
    if [[ "$verdict" == "FAIL" ]]; then
        failed_names+=("$name")
        exit 1
    fi
}

function equal {
    [[ "$1" == "$2" ]]
}

function not_equal {
    [[ "$1" != "$2" ]]
}

function contains {
    [[ "$1" == *"$2"* ]]
}

function is_empty {
    [[ -z "$1" ]]
}

function file_nonempty {
    [[ -s "$1" ]]
}

function path_absent {
    [[ ! -e "$1" ]]
}

function same_bytes {
    cmp -s -- "$1" "$2"
}

function not_writable {
    [[ ! -w "$1" ]]
}

# Runs a command in CWD with a clean environment and records it: run CWD EXPECTED COMMAND...
# EXPECTED is an exit status that is checked, or - when the caller judges the status itself.
function run {
    local cwd="$1" expected="$2" started before after
    shift 2
    command_count=$((command_count + 1))
    run_log="$logs_dir/$(printf '%03d' "$command_count")-${cwd##*/}.log"
    started=$(utc_now)
    before=$(date +%s%N)
    run_code=0
    ( cd "$cwd" && exec env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="${HOME:?}" LANG=C LC_ALL=C \
        timeout "$COMMAND_TIMEOUT" "$@" ) > "$run_log" 2>&1 || run_code=$?
    after=$(date +%s%N)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$command_count" "$started" "$(( (after - before) / 1000000 ))ms" \
        "$run_code" "$cwd" "$run_log" "$*" >> "$workspace/commands.tsv"
    if [[ "$expected" != "-" ]]; then
        check "${cwd##*/}: ${*:1:3}" "exit_code=${run_code} log=${run_log}" equal "$run_code" "$expected"
    fi
}

function run_output {
    local output
    IFS= read -r -d '' output < "$run_log" || true
    printf '%s' "$output"
}

# Runs make for a case: make_case CASE PREFIX EXPECTED TARGET...
function make_case {
    local cwd="$1" prefix="$2" expected="$3"
    local -a command=(make "-j${jobs}")
    shift 3
    command+=("$@" "INSTALL_LOCATION=${prefix}")
    if [[ -n "$seed" ]]; then
        command+=("SRC_GITURL=${seed}")
    fi
    run "$cwd" "$expected" "${command[@]}"
}

function write_snapshot {
    local member
    : > "$workspace/source.tsv"
    while IFS= read -r member; do
        snapshot["$member"]=$(digest "$repository/$member")
        printf '%s\t%s\n' "${snapshot[$member]}" "$member" >> "$workspace/source.tsv"
    done < <(cd "$repository" && { printf '%s\n' Makefile; find configure tools patch tests -type f ! -name '*.local'; } | LC_ALL=C sort)
}

# Copies the real build inputs into a fresh case directory and verifies their hashes.
function new_case {
    local name="$1" member exact=0
    case_dir="$workspace/$name"
    mkdir "$case_dir"
    cp -p "$repository/Makefile" "$case_dir/Makefile"
    for member in configure tools patch; do
        cp -rp "$repository/$member" "$case_dir/$member"
        find "$case_dir/$member" -name '*.local' -delete
    done
    for member in "${!snapshot[@]}"; do
        [[ "$member" == tests/* ]] && continue
        [[ "$(digest "$case_dir/$member")" == "${snapshot[$member]}" ]] || exact=1
    done
    check "${name}: exact build inputs" "members=${#snapshot[@]}" equal "$exact" 0
    case_prefix="$case_dir/prefix/nested/install"
}

function initialized_case {
    local name="$1" commit
    new_case "$name"
    make_case "$case_dir" "$case_prefix" 0 init
    run "$case_dir/uldaq-src" 0 git rev-parse HEAD
    commit=$(run_output)
    commit="${commit//$'\n'/}"
    check "${name}: upstream commit" "$commit" equal "$commit" "$UPSTREAM_COMMIT"
    if [[ -z "$seed" ]]; then
        seed="$case_dir/uldaq-src"
    fi
}

function build_id_of {
    local notes
    notes=$(LC_ALL=C readelf -n "$1")
    if [[ "$notes" =~ Build\ ID:\ ([0-9a-f]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' none
    fi
}

# Verifies the file set, the exact bytes of build-record and the content of its digest file
# against the independently derived expectation.
# The optional fifth argument is the expected patch line: the default is the line naming the
# required patch file, an empty string means the record has no patch line.
# check_record CASE PREFIX TAG SOURCE [PATCH_LINE]: TAG and SOURCE are the expected tag and source values.
function check_record {
    local name="$1" prefix="$2" tag="$3" source_value="$4" patch_line="patch=${PATCH_NAME}"
    local library="lib/libuldaq.so.1.2.2"
    local cfg="$prefix/cfg" dir="$prefix/cfg/${RECORD_NAME}" expected_dir="$workspace/${name}-expected"
    local listing id sum recorded

    if [[ $# -ge 5 ]]; then
        patch_line="$5"
    fi
    mkdir -p "$expected_dir"
    id=$(build_id_of "$prefix/$library")
    sum=$(digest "$prefix/$library")
    recorded=$(digest "$dir/build-record")
    {
        printf 'format=1\nname=%s\nversion=%s\n' "$RECORD_NAME" "$UPSTREAM_VERSION"
        printf 'tag=%s\nsource=%s\nupstream=%s\n' "$tag" "$source_value" "$UPSTREAM_TAG"
        if [[ -n "$patch_line" ]]; then
            printf '%s\n' "$patch_line"
        fi
        printf 'arch=linux-%s\n' "$(uname -m)"
        printf 'artifact=%s %s\nbuildid=%s %s\n' "$library" "$sum" "$library" "$id"
    } > "$expected_dir/build-record"
    printf '%s\n' "$recorded" > "$expected_dir/build-record.sha256"
    listing=$(cd "$cfg" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')
    check "${name}: record file set" "$listing" equal "$listing" \
        "./${RECORD_NAME} ./${RECORD_NAME}/build-record ./${RECORD_NAME}/build-record.sha256 "
    check "${name}: record build-record bytes" "tag=${tag} source=${source_value} ${patch_line}" \
        same_bytes "$dir/build-record" "$expected_dir/build-record"
    check "${name}: record digest bytes" "$recorded" \
        same_bytes "$dir/build-record.sha256" "$expected_dir/build-record.sha256"
}

# Checks the installed artifacts, the optional ownership, and the vendor record of a non-git copy.
function installed {
    local case_path="$1" prefix="$2" owner="${3:-}"
    local name="${case_path##*/}" header="$prefix/include/uldaq.h" library="$prefix/lib/libuldaq.so"
    local source_text wrong

    check "${name}: installed artifacts" "header and library" test -f "$header" -a -f "$library"
    check "${name}: installed header" "$header" same_bytes "$header" "$case_path/uldaq-src/src/uldaq.h"
    slurp source_text "$case_path/uldaq-src/$SOURCE_FILE"
    check "${name}: compiled source correction" "$SOURCE_FILE" contains "$source_text" "$CORRECTION"
    run "$case_path" 0 ldd "$library"
    if [[ -n "$owner" ]]; then
        wrong=$(find "$prefix" ! -uid "$owner" | tr '\n' ' ')
        check "${name}: installed ownership" "$wrong" is_empty "$wrong"
    fi
    printf 'header_sha256=%s\nlibrary_sha256=%s\nlibrary=%s\nprefix=%s\nowner=%s\n' \
        "$(digest "$header")" "$(digest "$library")" "$(readlink -f "$library")" "$prefix" "$owner" \
        > "$workspace/${name}-installation.txt"
    check_record "$name" "$prefix" unknown unknown
}

function patch_cycle {
    local source original patched stripped

    initialized_case "patch-cycle"
    source="$case_dir/uldaq-src/$SOURCE_FILE"
    cp -p "$source" "$workspace/patch-cycle-original.cpp"
    slurp original "$source"

    make_case "$case_dir" "$case_prefix" - build
    check "unpatched direct build rejected" "exit_code=${run_code}" test "$run_code" -ne 0
    check "unpatched direct build diagnostic" "$run_log" contains "$(run_output)" "patch.check] Error 1"

    make_case "$case_dir" "$case_prefix" 0 patch.apply
    slurp patched "$source"
    stripped="${patched/"${CHECK_PATTERN}${CORRECTION}"$'\n'/}"
    check "exact TCP correction" "patched differs from original" not_equal "$patched" "$original"
    check "exact TCP correction removal" "only the correction block differs" equal "$stripped" "$original"
    cp -p "$source" "$workspace/patch-cycle-patched.cpp"

    make_case "$case_dir" "$case_prefix" 0 patch.apply
    check "idempotent apply" "$source" same_bytes "$source" "$workspace/patch-cycle-patched.cpp"
    make_case "$case_dir" "$case_prefix" 0 patch.revert
    check "byte-exact revert" "$source" same_bytes "$source" "$workspace/patch-cycle-original.cpp"
    run "$case_dir/uldaq-src" 0 git diff --exit-code

    make_case "$case_dir" "$case_prefix" - install
    check "unpatched installation rejected" "exit_code=${run_code}" test "$run_code" -ne 0
    check "unpatched installation diagnostic" "$run_log" contains "$(run_output)" "patch.check] Error 1"

    make_case "$case_dir" "$case_prefix" 0 patch.apply
    check "byte-exact reapply" "$source" same_bytes "$source" "$workspace/patch-cycle-patched.cpp"
}

function invalid_patches {
    local target fault name patch source objects text expected status verb
    for target in build all github install; do
        for fault in missing empty incompatible; do
            name="${target}-${fault}"
            if [[ "$target" == "github" ]]; then
                new_case "$name"
            else
                initialized_case "$name"
            fi
            patch="$case_dir/patch/$PATCH_NAME"
            case "$fault" in
                missing) mv -- "$patch" "${patch%.patch}.disabled" ;;
                empty) : > "$patch" ;;
                incompatible)
                    slurp text "$patch"
                    printf '%s' "${text//NetDaqDevice.cpp/AbsentDevice.cpp}" > "$patch"
                    ;;
            esac
            # The tool exit status shows in the make error line: 2 input error, 3 unclassifiable state;
            # build and install stop in patch.check, all and github stop in patch.apply (through conf).
            case "$fault" in
                missing|empty) status=2 ;;
                *) status=3 ;;
            esac
            verb=check
            [[ "$target" == all || "$target" == github ]] && verb=apply
            expected="patch.${verb}] Error ${status}"
            make_case "$case_dir" "$case_prefix" - "$target"
            check "${name}: required patch rejected" "exit_code=${run_code}" test "$run_code" -ne 0
            check "${name}: required patch diagnostic" "$run_log" contains "$(run_output)" "$expected"
            source="$case_dir/uldaq-src"
            objects=""
            if [[ -d "$source" ]]; then
                objects=$(find "$source" -name '*.o' | head -n 1)
            fi
            check "${name}: no configuration or compilation" "$objects" test ! -e "$source/config.status" -a -z "$objects"
            check "${name}: no installation" "$case_prefix" path_absent "$case_prefix"
        done
    done
}

function builds {
    local target prepatched name
    local -a plan=("direct:0" "direct:1" "all:0" "all:1" "github:0")
    local entry
    for entry in "${plan[@]}"; do
        target="${entry%%:*}"
        prepatched="${entry##*:}"
        name="${target}-original"
        [[ "$prepatched" == 1 ]] && name="${target}-patched"
        if [[ "$target" == "github" ]]; then
            new_case "$name"
        else
            initialized_case "$name"
        fi
        if [[ "$prepatched" == 1 ]]; then
            make_case "$case_dir" "$case_prefix" 0 patch.apply
        fi
        if [[ "$target" == "direct" ]]; then
            make_case "$case_dir" "$case_prefix" 0 "$config_target"
            make_case "$case_dir" "$case_prefix" 0 build
            make_case "$case_dir" "$case_prefix" 0 install
        else
            make_case "$case_dir" "$case_prefix" 0 "$target"
        fi
        installed "$case_dir" "$case_prefix" "$(id -u)"
    done
}

# Builds in a real git checkout and verifies the source record for an untagged commit, for the
# highest of several tags on HEAD, and for a modified tracked file; then calls the record writer
# directly for the patch states that the install gate never lets through make install (patch not
# applied, patch state unclassifiable); then verifies that the uninstall removes only this
# wrapper's files and is repeatable.
function vendor_record {
    local name="record-git" head listing text
    local -a git_run=(git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false)

    new_case "$name"
    run "$case_dir" 0 "${git_run[@]}" init -q
    run "$case_dir" 0 "${git_run[@]}" add -A
    run "$case_dir" 0 "${git_run[@]}" commit -q -m base
    run "$case_dir" 0 "${git_run[@]}" rev-parse HEAD
    head=$(run_output)
    head="${head//$'\n'/}"
    make_case "$case_dir" "$case_prefix" 0 init
    make_case "$case_dir" "$case_prefix" 0 all
    check_record "${name}-untagged" "$case_prefix" untagged "$head"

    run "$case_dir" 0 "${git_run[@]}" tag 1.2.2
    run "$case_dir" 0 "${git_run[@]}" tag 1.2.2-2
    run "$case_dir" 0 "${git_run[@]}" tag 1.2.2-10
    make_case "$case_dir" "$case_prefix" 0 install
    check_record "${name}-tagged" "$case_prefix" 1.2.2-10 "$head"

    printf '%s\n' '# modified' >> "$case_dir/configure/CONFIG_SITE"
    make_case "$case_dir" "$case_prefix" 0 install
    check_record "${name}-dirty" "$case_prefix" 1.2.2-10 "${head}+dirty"

    make_case "$case_dir" "$case_prefix" 0 patch.revert
    run "$case_dir" 0 bash -p tools/vendor-record.bash write make "$case_dir" uldaq-src "$RECORD_NAME" \
        "$UPSTREAM_VERSION" "tags/${UPSTREAM_TAG}" "$case_dir/patch/$PATCH_NAME"
    check_record "${name}-unapplied" "$case_prefix" 1.2.2-10 "${head}+dirty" ""

    slurp text "$case_dir/patch/$PATCH_NAME"
    printf '%s' "${text//NetDaqDevice.cpp/AbsentDevice.cpp}" > "$case_dir/patch/$PATCH_NAME"
    run "$case_dir" 0 bash -p tools/vendor-record.bash write make "$case_dir" uldaq-src "$RECORD_NAME" \
        "$UPSTREAM_VERSION" "tags/${UPSTREAM_TAG}" "$case_dir/patch/$PATCH_NAME"
    check_record "${name}-unknown" "$case_prefix" 1.2.2-10 "${head}+dirty" "patch=unknown"

    : > "$case_prefix/lib/libother.so.1"
    mkdir "$case_prefix/cfg/other"
    : > "$case_prefix/cfg/other/build-record"
    make_case "$case_dir" "$case_prefix" 0 uninstall
    listing=$(cd "$case_prefix" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')
    check "${name}: uninstall keeps only other files" "$listing" \
        equal "$listing" "./cfg ./cfg/other ./cfg/other/build-record ./lib ./lib/libother.so.1 "
    make_case "$case_dir" "$case_prefix" 0 uninstall
    listing=$(cd "$case_prefix" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')
    check "${name}: second uninstall removes nothing" "$listing" \
        equal "$listing" "./cfg ./cfg/other ./cfg/other/build-record ./lib ./lib/libother.so.1 "
}

function permissions {
    local prefix owner name wrong
    check "permission suite uses ordinary user" "uid=$(id -u)" not_equal "$(id -u)" 0
    new_case "${mode}-github"
    prefix="$case_prefix"
    if [[ "$mode" == "protected" ]]; then
        prefix="$protected_prefix"
        check "protected prefix specified" "$prefix" test -n "$prefix"
        check "protected parent not writable" "${prefix%/*}" not_writable "${prefix%/*}"
    fi
    make_case "$case_dir" "$prefix" 0 github
    owner="$(id -u)"
    [[ "$mode" == "protected" ]] && owner=0
    installed "$case_dir" "$prefix" "$owner"
    wrong=$(find "$case_dir/uldaq-src" ! -uid "$(id -u)" | tr '\n' ' ')
    check "source remains user-owned" "$wrong" is_empty "$wrong"
    if [[ "$mode" == "user" ]]; then
        make_case "$case_dir" "$prefix" 0 install
        installed "$case_dir" "$prefix" "$(id -u)"
    fi
}

# Writes result.txt from the recorded checks and sets the exit status: 0 Passed, 1 Failed, 2 Incomplete.
function finish {
    local status=$? verdict names
    trap - EXIT
    if [[ -z "$workspace" || ! -d "$workspace" ]]; then
        exit "$status"
    fi
    if [[ "${#failed_names[@]}" -gt 0 ]]; then
        verdict="Failed"
        status=1
    elif [[ "$complete" == 1 ]]; then
        verdict="Passed"
        status=0
    else
        verdict="Incomplete"
        status=2
        error_text="${error_text:-run stopped before completion (exit status unrelated to a check)}"
    fi
    names="${failed_names[*]:-}"
    printf 'complete=%s\nverdict=%s\nerror=%s\ntotal=%s\nfailed=%s\nmode=%s\n' \
        "$complete" "$verdict" "$error_text" "$total_checks" "$names" "$mode" > "$workspace/result.txt"
    printf '%s: %s checks; evidence %s\n' "$verdict" "$total_checks" "$workspace"
    exit "$status"
}

function parse_args {
    repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repository) repository="$2"; shift ;;
            --workspace) workspace="$2"; shift ;;
            --source-repository) source_repository="$2"; shift ;;
            --jobs) jobs="$2"; shift ;;
            --mode) mode="$2"; shift ;;
            --protected-prefix) protected_prefix="$2"; shift ;;
            --config-target) config_target="$2"; shift ;;
            *) usage ;;
        esac
        shift
    done
    [[ -n "$workspace" ]] || usage
    case "$mode" in
        build|user|protected) ;;
        *) usage ;;
    esac
}

function main {
    parse_args "$@"
    repository=$(cd "$repository" && pwd -P)
    mkdir -p "$(dirname "$workspace")"
    mkdir "$workspace"
    workspace=$(cd "$workspace" && pwd -P)
    logs_dir="$workspace/logs"
    mkdir "$logs_dir"
    : > "$workspace/commands.tsv"
    : > "$workspace/checks.tsv"
    seed="$source_repository"
    trap finish EXIT
    write_snapshot
    if [[ "$mode" == "build" ]]; then
        patch_cycle
        invalid_patches
        builds
        vendor_record
    else
        permissions
    fi
    complete=1
}

main "$@"
