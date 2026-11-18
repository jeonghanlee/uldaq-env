#!/bin/bash -p
# Writes and removes the vendor record of the autotools installation. The record is the
# file <prefix>/cfg/<name>/build-record (key=value lines: format, name, version, tag,
# source, upstream, patch, arch, then artifact=<path> <sha256> directly followed by
# buildid=<path> <hex|none> for each installed shared object, paths relative to the
# prefix) and its digest file build-record.sha256. The installed file set is derived
# from a staged installation of the configured source, so files of other wrappers in
# the same prefix are never listed.
set -euo pipefail
export PATH=/usr/bin:/bin
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0
unset BASH_ENV ENV POSIXLY_CORRECT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

readonly -a REQUIRED_TOOLS=(find sort mktemp readelf grep rmdir tail sha256sum uname)
stage_dir=""

function usage {
    printf '%s\n' 'Usage: vendor-record.bash write MAKE TOP SOURCE NAME VERSION SRC_TAG PATCH' >&2
    printf '%s\n' '       vendor-record.bash remove MAKE TOP SOURCE NAME' >&2
    exit 2
}

function die {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Removes the disposable staging directory on every exit path.
function cleanup {
    if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
        rm -rf -- "$stage_dir"
    fi
}
trap cleanup EXIT

function require_tools {
    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if [[ ! -x "$(command -v "$tool" 2>/dev/null)" ]]; then
            die "required command not found: ${tool} (readelf belongs to the binutils package)"
        fi
    done
}

# Prints the installation prefix recorded in the configured source Makefile.
function configured_prefix {
    local src="$1" line
    if [[ ! -f "$src/Makefile" ]]; then
        die "source is not configured: ${src}/Makefile is missing; run make conf"
    fi
    line=$(grep -m1 '^prefix = ' "$src/Makefile") || die "prefix not found in ${src}/Makefile"
    printf '%s\n' "${line#prefix = }"
}

# Installs the files of the real installation into <stage_dir>/tree without touching the prefix.
function stage_install {
    local make="$1" src="$2"
    stage_dir=$(mktemp -d)
    mkdir "$stage_dir/tree"
    if ! { "$make" -C "$src" install-exec DESTDIR="$stage_dir/tree" &&
           "$make" -C "$src/src" install-includeHEADERS DESTDIR="$stage_dir/tree"; } \
           >"$stage_dir/stage.log" 2>&1; then
        tail -n 20 "$stage_dir/stage.log" >&2
        die "staged installation failed"
    fi
}

# Prints the GNU build-id of an installed file as lower-case hex, or none.
function build_id {
    local file="$1" notes
    notes=$(readelf -n "$file") || die "readelf failed: ${file}"
    if [[ "$notes" =~ Build\ ID:\ ([0-9a-f]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' none
    fi
}

# Prints the tag= and source= lines of the wrapper checkout (the tag and the commit of the
# wrapper repository). Any git fact that cannot be established reads unknown; only exit
# status 1 of git diff marks the tree as modified.
function source_facts {
    local top="$1" toplevel commit tag marker diff_status=0
    local -a git_cmd=(git -c "safe.directory=${top}" -C "$top")
    if [[ ! -x "$(command -v git 2>/dev/null)" ]]; then
        printf 'tag=unknown\nsource=unknown\n'
        return 0
    fi
    toplevel=$("${git_cmd[@]}" rev-parse --show-toplevel 2>/dev/null) || toplevel=""
    if [[ -z "$toplevel" || "$(cd "$toplevel" && pwd -P)" != "$top" ]]; then
        printf 'tag=unknown\nsource=unknown\n'
        return 0
    fi
    commit=$("${git_cmd[@]}" rev-parse HEAD 2>/dev/null) || commit=""
    "${git_cmd[@]}" diff --quiet HEAD >/dev/null 2>&1 || diff_status=$?
    case "$diff_status" in
        0) marker="" ;;
        1) marker="+dirty" ;;
        *) commit="" ;;
    esac
    if [[ -z "$commit" ]]; then
        printf 'tag=unknown\nsource=unknown\n'
        return 0
    fi
    tag=$("${git_cmd[@]}" tag --points-at HEAD | sort -V | tail -n 1)
    printf 'tag=%s\nsource=%s%s\n' "${tag:-untagged}" "$commit" "$marker"
}

# Replaces the destination with standard input through a temporary file in the same
# directory; the file mode is the one the umask gives, with no explicit chmod.
function write_atomic {
    local destination="$1" temporary="${1%/*}/.${1##*/}.tmp.$$"
    if ! cat >"$temporary"; then
        rm -f -- "$temporary"
        die "cannot write ${destination}"
    fi
    mv -f -- "$temporary" "$destination"
}

# Writes build-record and its digest file for the shared objects installed from the
# configured source; the digest file is written after the record.
function do_write {
    local make="$1" top="$2" src="$3" name="$4" version="$5" src_tag="$6" patch="$7"
    local prefix dir listing rel id sum patch_status patch_line upstream arch artifact_lines=""
    local -a rels=()

    if [[ "$(uname -s)" != Linux ]]; then
        printf 'notice: vendor record skipped: GNU build-id records apply to Linux only\n'
        return 0
    fi
    require_tools
    prefix=$(configured_prefix "$src")
    stage_install "$make" "$src"
    listing=$(cd "$stage_dir/tree$prefix" && find . -type f -name '*.so*' | sort) \
        || die "staged prefix is missing: ${prefix}"
    if [[ -n "$listing" ]]; then
        mapfile -t rels <<<"$listing"
    fi
    for rel in "${rels[@]}"; do
        rel="${rel#./}"
        if [[ ! -f "$prefix/$rel" ]]; then
            die "installed file missing: ${prefix}/${rel}"
        fi
        id=$(build_id "$prefix/$rel")
        read -r sum _ < <(sha256sum -- "$prefix/$rel")
        artifact_lines+="artifact=${rel} ${sum}"$'\n'"buildid=${rel} ${id}"$'\n'
    done

    # The check status tells the cause: 0 applied, 1 not applied, any other status (input
    # error, unclassifiable state) cannot be decided.
    patch_status=0
    bash -p "$top/tools/apply_patch.bash" --fuzz=0 check "$src" "$patch" >/dev/null 2>&1 || patch_status=$?
    case "$patch_status" in
        0) patch_line="patch=${patch##*/}" ;;
        1) patch_line="" ;;
        *) patch_line="patch=unknown" ;;
    esac
    upstream="${src_tag#tags/}"
    arch="linux-$(uname -m)"

    dir="$prefix/cfg/$name"
    mkdir -p "$dir"
    {
        printf 'format=1\nname=%s\nversion=%s\n' "$name" "$version"
        source_facts "$top"
        printf 'upstream=%s\n' "$upstream"
        if [[ -n "$patch_line" ]]; then
            printf '%s\n' "$patch_line"
        fi
        printf 'arch=%s\n' "$arch"
        printf '%s' "$artifact_lines"
    } | write_atomic "$dir/build-record"
    read -r sum _ < <(sha256sum -- "$dir/build-record")
    printf '%s\n' "$sum" | write_atomic "$dir/build-record.sha256"
    printf 'Vendor record written: %s/build-record and build-record.sha256\n' "$dir"
}

# Runs the source uninstall, then removes this wrapper's record files and directory, the
# cfg directory when it is empty, and every directory of the installation that became
# empty; the prefix itself is never removed.
function do_remove {
    local make="$1" top="$2" src="$3" name="$4"
    local prefix directories directory

    if [[ ! -f "$src/Makefile" ]]; then
        printf 'notice: %s is not configured; nothing was removed\n' "$src"
        return 0
    fi
    if [[ "$(uname -s)" != Linux ]]; then
        "$make" -C "$src" uninstall || die "source uninstall failed"
        return 0
    fi
    require_tools
    prefix=$(configured_prefix "$src")
    stage_install "$make" "$src"
    directories=$(cd "$stage_dir/tree$prefix" && find . -mindepth 1 -type d | sort -r) \
        || die "staged prefix is missing: ${prefix}"

    "$make" -C "$src" uninstall || die "source uninstall failed"
    rm -f -- "$prefix/cfg/$name/build-record" "$prefix/cfg/$name/build-record.sha256"
    # A directory that still holds files, or is already gone, is expected to stay.
    rmdir -- "$prefix/cfg/$name" 2>/dev/null || true
    while IFS= read -r directory; do
        [[ -n "$directory" ]] || continue
        rmdir -- "$prefix/${directory#./}" 2>/dev/null || true
    done <<<"$directories"
    rmdir -- "$prefix/cfg" 2>/dev/null || true
    printf 'Vendor record removed: %s/cfg/%s\n' "$prefix" "$name"
}

function main {
    local action="${1:-}" top src
    case "$action" in
        write)
            [[ $# -eq 8 ]] || usage
            top=$(cd "$3" && pwd -P) || die "directory missing: $3"
            src=$(cd "$4" && pwd -P) || die "source directory missing: $4; run make init first"
            do_write "$2" "$top" "$src" "$5" "$6" "$7" "$8"
            ;;
        remove)
            [[ $# -eq 5 ]] || usage
            top=$(cd "$3" && pwd -P) || die "directory missing: $3"
            if [[ -d "$4" ]]; then
                src=$(cd "$4" && pwd -P)
            else
                src="$4"
            fi
            do_remove "$2" "$top" "$src" "$5"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
