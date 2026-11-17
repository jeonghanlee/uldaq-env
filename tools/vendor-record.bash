#!/bin/bash -p
# Writes and removes the per-wrapper vendor record of the autotools installation:
# <prefix>/cfg/<name>.buildid holds one "buildid=<path> <hex|none>" line per installed
# shared object, <prefix>/cfg/<name>.source holds the tag, commit, patch and upstream
# identity of the build. The installed file set is derived from a staged installation
# of the configured source, so files of other wrappers in the same prefix are never listed.
set -euo pipefail
export PATH=/usr/bin:/bin
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0
unset BASH_ENV ENV POSIXLY_CORRECT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

readonly -a REQUIRED_TOOLS=(find sort install mktemp readelf grep rmdir tail)
stage_dir=""

function usage {
    printf '%s\n' 'Usage: vendor-record.bash write MAKE TOP SOURCE NAME SRC_TAG PATCH' >&2
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

# Prints the tag= and commit= lines of the wrapper checkout. Any git fact that cannot be
# established reads unknown; only exit status 1 of git diff marks the tree as modified.
function source_facts {
    local top="$1" toplevel commit tag marker diff_status=0
    local -a git_cmd=(git -c "safe.directory=${top}" -C "$top")
    if [[ ! -x "$(command -v git 2>/dev/null)" ]]; then
        printf 'tag=unknown\ncommit=unknown\n'
        return 0
    fi
    toplevel=$("${git_cmd[@]}" rev-parse --show-toplevel 2>/dev/null) || toplevel=""
    if [[ -z "$toplevel" || "$(cd "$toplevel" && pwd -P)" != "$top" ]]; then
        printf 'tag=unknown\ncommit=unknown\n'
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
        printf 'tag=unknown\ncommit=unknown\n'
        return 0
    fi
    tag=$("${git_cmd[@]}" tag --points-at HEAD | sort -V | tail -n 1)
    printf 'tag=%s\ncommit=%s%s\n' "${tag:-untagged}" "$commit" "$marker"
}

# Replaces the destination with standard input through a temporary file in the same directory.
function write_atomic {
    local destination="$1" temporary
    temporary=$(mktemp "${destination%/*}/.${destination##*/}.XXXXXX")
    if ! cat >"$temporary"; then
        rm -f -- "$temporary"
        die "cannot write ${destination}"
    fi
    chmod 644 "$temporary"
    mv -f -- "$temporary" "$destination"
}

# Writes the two record files for the shared objects installed from the configured source.
function do_write {
    local make="$1" top="$2" src="$3" name="$4" src_tag="$5" patch="$6"
    local prefix cfg listing rel id patches upstream buildid_lines=""
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
        buildid_lines+="buildid=${rel} ${id}"$'\n'
    done

    if bash -p "$top/tools/apply_patch.bash" --fuzz=0 check "$src" "$patch" >/dev/null 2>&1; then
        patches="${patch##*/}"
    else
        patches=none
    fi
    upstream="${src_tag#tags/}"

    cfg="$prefix/cfg"
    install -d -m 755 "$cfg"
    printf '%s' "$buildid_lines" | write_atomic "$cfg/$name.buildid"
    {
        source_facts "$top"
        printf 'patches=%s\nupstream=%s\n' "$patches" "$upstream"
    } | write_atomic "$cfg/$name.source"
    printf 'Vendor record written: %s/%s.buildid and %s.source\n' "$cfg" "$name" "$name"
}

# Runs the source uninstall, then removes this wrapper's two record files and every
# directory of the installation that became empty; the prefix itself is never removed.
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
    rm -f -- "$prefix/cfg/$name.buildid" "$prefix/cfg/$name.source"
    # A directory that still holds files, or is already gone, is expected to stay.
    while IFS= read -r directory; do
        [[ -n "$directory" ]] || continue
        rmdir -- "$prefix/${directory#./}" 2>/dev/null || true
    done <<<"$directories"
    rmdir -- "$prefix/cfg" 2>/dev/null || true
    printf 'Vendor record removed: %s/cfg/%s.*\n' "$prefix" "$name"
}

function main {
    local action="${1:-}" top src
    case "$action" in
        write)
            [[ $# -eq 7 ]] || usage
            top=$(cd "$3" && pwd -P) || die "directory missing: $3"
            src=$(cd "$4" && pwd -P) || die "source directory missing: $4; run make init first"
            do_write "$2" "$top" "$src" "$5" "$6" "$7"
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
