#!/bin/bash
# Builds one scratch copy of the repository per row of a mutation table (tests/mutations.tsv).
# A row replaces one literal text in one file; the old text must occur exactly once and the
# copy must differ afterwards, otherwise the run stops. Each copy is written to
# OUT/<id>/src with OUT/<id>/mutation.txt holding the row and the SHA-256 of the file before
# and after. A row whose file column is - produces the unchanged copy.
set -euo pipefail

function usage {
    printf '%s\n' 'Usage: build-mutants.bash TABLE OUT [REPOSITORY]' >&2
    exit 2
}

function die {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

function digest {
    local hash
    read -r hash _ < <(sha256sum -- "$1")
    printf '%s\n' "$hash"
}

function count_occurrences {
    local text="$1" needle="$2" count=0
    while [[ "$text" == *"$needle"* ]]; do
        count=$((count + 1))
        text="${text#*"$needle"}"
    done
    printf '%s\n' "$count"
}

function main {
    local table="${1:-}" out="${2:-}" repository="${3:-.}"
    local id file old new mode intended_new intended_old
    local destination text before after count mutated
    [[ -n "$table" && -n "$out" ]] || usage
    repository=$(cd "$repository" && pwd -P)
    mkdir -p "$out"
    out=$(cd "$out" && pwd -P)

    while IFS=$'\t' read -r id file old new mode intended_new intended_old; do
        [[ -n "$id" && "$id" != \#* ]] || continue
        destination="$out/$id"
        mkdir "$destination" "$destination/src"
        (cd "$repository" && tar --exclude=./.git --exclude=./work --exclude='./*-src' -cf - .) \
            | tar -xf - -C "$destination/src"
        before="-"
        after="-"
        if [[ "$file" != "-" ]]; then
            [[ -f "$destination/src/$file" ]] || die "${id}: file missing: ${file}"
            before=$(digest "$destination/src/$file")
            IFS= read -r -d '' text < "$destination/src/$file" || true
            count=$(count_occurrences "$text" "$old")
            [[ "$count" -eq 1 ]] || die "${id}: old text occurs ${count} times in ${file}, expected once"
            mutated="${text%%"$old"*}${new}${text#*"$old"}"
            printf '%s' "$mutated" > "$destination/src/$file"
            after=$(digest "$destination/src/$file")
            [[ "$before" != "$after" ]] || die "${id}: copy is unchanged after the mutation"
        fi
        printf 'id=%s\nfile=%s\nsha256_before=%s\nsha256_after=%s\nmode=%s\nexpected_new=%s\nexpected_old=%s\n' \
            "$id" "$file" "$before" "$after" "$mode" "$intended_new" "$intended_old" > "$destination/mutation.txt"
        printf 'built %s (%s)\n' "$id" "$file"
    done < "$table"
}

main "$@"
