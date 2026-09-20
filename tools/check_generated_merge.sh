#!/bin/bash
# gate: cheap
# Tests GIT'S BEHAVIOUR, not the compiler (inc-m1wb): independent edits must
# conflict with the shipped guard and merge cleanly with both edits without it.
# No game build or seeded session is needed. All git operations use scratch repos.
. "$(dirname "$0")/check_lib.sh"

command -v git >/dev/null 2>&1 || _check_die 2 "git is unavailable"

# One parent owns every temporary file; its path is assigned in this shell.
scratch=""
trap 'if [ -n "$scratch" ]; then rm -rf "$scratch"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
scratch=$(mktemp -d "${TMPDIR:-/tmp}/generated-merge.XXXXXX") ||
    _check_die 2 "cannot create scratch directory"

# Inherited repository paths, config, attributes and hooks must not affect us.
for variable in ${!GIT_@}; do unset "$variable"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_ATTR_NOSYSTEM=1 LC_ALL=C
mkdir -p "$scratch/template" "$scratch/hooks" || _check_die 2 "cannot set up scratch directories"

setup() {
    "$@" || _check_die 2 "fixture setup failed: $*"
}

fails=0
for mode in guarded unguarded; do
    repo="$scratch/$mode"
    setup git init -q --template="$scratch/template" "$repo"
    setup git -C "$repo" symbolic-ref HEAD refs/heads/base
    setup git -C "$repo" config user.name "generated merge check"
    setup git -C "$repo" config user.email "check@example.invalid"
    setup git -C "$repo" config commit.gpgsign false
    setup git -C "$repo" config core.hooksPath "$scratch/hooks"
    setup git -C "$repo" config core.attributesFile /dev/null
    setup mkdir -p "$repo/lib"
    if [ "$mode" = guarded ] && [ -f "$CHECK_ROOT/.gitattributes" ]; then
        setup cp -f "$CHECK_ROOT/.gitattributes" "$repo/.gitattributes"
    fi
    # Distinct lines separate the edits beyond Git's merge context.
    for ((line=1; line<=30; line++)); do echo "base line $line"; done > "$repo/lib/dispatch.h"
    setup git -C "$repo" add .
    setup git -C "$repo" commit -qm base
    setup git -C "$repo" checkout -qb ours
    setup sed 's/^base line 2$/ours change/' "$repo/lib/dispatch.h" > "$scratch/ours"
    setup cp -f "$scratch/ours" "$repo/lib/dispatch.h"
    setup git -C "$repo" commit -qam ours
    setup git -C "$repo" checkout -qb theirs base
    setup sed 's/^base line 29$/theirs change/' "$repo/lib/dispatch.h" > "$scratch/theirs"
    setup cp -f "$scratch/theirs" "$repo/lib/dispatch.h"
    setup git -C "$repo" commit -qam theirs
    setup git -C "$repo" checkout -q ours

    git -C "$repo" merge --no-commit --no-ff theirs > "$scratch/merge.log" 2>&1
    rc=$?
    unmerged=$(git -C "$repo" ls-files -u -- lib/dispatch.h) ||
        _check_die 2 "cannot inspect scratch index"
    if [ "$mode" = guarded ]; then
        if [ "$rc" -eq 1 ] && [ -n "$unmerged" ] &&
           grep -q 'CONFLICT.*lib/dispatch.h' "$scratch/merge.log" &&
           cmp -s "$scratch/ours" "$repo/lib/dispatch.h"; then
            echo "PASS: with guard: conflict reported; current branch copy retained"
        else
            echo "FAIL: with guard: expected conflict and current branch copy (merge exit $rc)"
            fails=$((fails + 1))
        fi
    else
        setup sed 's/^base line 29$/theirs change/' "$scratch/ours" > "$scratch/expected"
        if [ "$rc" -eq 0 ] && [ -z "$unmerged" ] &&
           cmp -s "$scratch/expected" "$repo/lib/dispatch.h"; then
            echo "PASS: without guard: clean auto-merge contains both sides' changes"
        else
            echo "FAIL: without guard: expected clean auto-merge with both changes (merge exit $rc)"
            fails=$((fails + 1))
        fi
    fi
done
[ "$fails" -eq 0 ] || exit 1
