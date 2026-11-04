#!/bin/bash -p
# Apply, reverse, or check the required patch without accepting partial hunks.
set -euo pipefail
export PATH=/usr/bin:/bin
unset BASH_ENV ENV POSIXLY_CORRECT PATCH_GET VERSION_CONTROL SIMPLE_BACKUP_SUFFIX

if [[ $# -ne 3 ]]; then
    printf '%s\n' 'Usage: patch-source.bash apply|revert|check SOURCE PATCH' >&2
    exit 2
fi

readonly action="$1" source_dir="$2" patch_file="$3"
if [[ ! -d "$source_dir" ]]; then
    printf 'error: source directory missing: %s; run make init first\n' "$source_dir" >&2
    exit 1
fi
if [[ ! -s "$patch_file" ]]; then
    printf 'error: required patch missing or empty: %s\n' "$patch_file" >&2
    exit 1
fi
if ! command -v patch >/dev/null; then
    printf '%s\n' 'error: patch is required; install the patch package' >&2
    exit 1
fi

declare -ar patch_args=(-d "$source_dir" -p0 --batch --force --fuzz=0 --no-backup-if-mismatch)

function original_source {
    patch "${patch_args[@]}" --dry-run < "$patch_file" >/dev/null 2>&1
}

function patched_source {
    patch "${patch_args[@]}" --reverse --dry-run < "$patch_file" >/dev/null 2>&1
}

case "$action" in
    apply)
        if patched_source; then
            printf 'Required patch already applied: %s\n' "$patch_file"
        elif original_source; then
            patch "${patch_args[@]}" < "$patch_file"
            patched_source
        else
            printf 'error: required patch is incompatible with source: %s\n' "$patch_file" >&2
            exit 1
        fi
        ;;
    revert)
        if patched_source; then
            patch "${patch_args[@]}" --reverse < "$patch_file"
            original_source
        elif original_source; then
            printf 'Required patch already reverted: %s\n' "$patch_file"
        else
            printf 'error: required patch is incompatible with source: %s\n' "$patch_file" >&2
            exit 1
        fi
        ;;
    check)
        if ! patched_source; then
            printf 'error: required patch not applied or incompatible: %s; run make patch.apply\n' "$patch_file" >&2
            exit 1
        fi
        printf 'Required patch verified: %s\n' "$patch_file"
        ;;
    *)
        printf 'error: unknown patch operation: %s\n' "$action" >&2
        exit 2
        ;;
esac
