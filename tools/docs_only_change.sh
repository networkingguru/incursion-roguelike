#!/bin/bash
# Is every file this change touches one the running game cannot read?
#
#   tools/docs_only_change.sh                 master..HEAD
#   tools/docs_only_change.sh <base> <head>   any two refs
#   tools/docs_only_change.sh --selftest      prove the refusals fire
#
# Ends: 0 documentation only, 1 something else is in it, 2 could not measure.
#
# WHY IT EXISTS. tools/finish_bead.sh ran the whole gate on every bead, and on
# 2026-09-12 a two-file markdown edit paid for both builds, the Linux
# cross-build, the layout sweep, the soak and every live check. None of those
# can be affected by a markdown file. Brian's instruction that day: "Needs to be
# a carve out for changes that literally cannot affect behavior."
#
# WHY THE RULE IS AN ALLOWLIST AND NOT AN EXCLUSION LIST. A carve-out in a gate
# is a hole, and the only safe shape is one that must be widened on purpose. A
# list of paths that SKIP the gate fails OPEN: a directory nobody thought about
# is exempt from the day somebody creates it. A list of paths that are ALLOWED
# to skip fails CLOSED: the same new directory runs the whole gate until
# somebody argues it should not. This repository has paid for the other shape
# once. tools/check_bead_publish.py was wired into nothing for four days while
# three files said it blocked commits, and inc-b12m reached the public tracker
# with an empty body inside that window.
#
# WHY THE ALLOWLIST IS ONLY `*.md`. It is the largest set that can be defended
# with evidence instead of an opinion. Measured on 2026-09-12: no file in src/
# or inc/ opens a `.md` path, so no markdown file is read by the game, by
# either build, or by the module compiler. Every other candidate fails that
# test or cannot be tested cheaply. A .txt or a .dat under tools/ may be a
# fixture some check reads, and mod/ is game data. Widen this only with the
# same kind of evidence, and understand that widening it is a rule change.
#
# WHAT THIS DOES NOT CLAIM. "The game cannot read it" is not "no check can read
# it". Six checks in the gate parse markdown -- check_citations,
# check_doc_citations, check_comment_budget, check_commit_lane,
# check_readme_checks and check_probe_hooks -- and every one of them is
# `gate: cheap`. That is why the caller's carve-out keeps the whole cheap tier
# and drops only the builds and the live tier. A documentation change CAN break
# a documentation check, and this script must never be read as saying it cannot.
set -uo pipefail

# The selftest points this at a scratch repository. Nothing else does.
ROOT="${DOCS_ONLY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/docs_only_change.sh"

cannot() { echo "INCONCLUSIVE: $1" >&2; exit 2; }

# A path is documentation when it ends in .md. That is deliberately the whole
# rule; see the header before you add a second case to it.
is_doc_path() {
    case "$1" in
        *.md) return 0 ;;
        *)    return 1 ;;
    esac
}

classify() { # classify <base> <head>; prints the verdict, ends 0 or 1
    local base="$1" head="$2" names status total other n
    names="$(git -C "$ROOT" diff --name-only "$base" "$head" 2>/dev/null)"
    status=$?
    [ "$status" -eq 0 ] || cannot "git diff --name-only $base $head ended $status"

    # A pair of refs with no difference is not a documentation change. It is
    # this script being asked about the wrong two refs, and "yes, skip the
    # gate" is the one answer that must never come back from that question.
    if [ -z "$names" ]; then
        echo "NOT docs-only: $base..$head changes no file at all."
        return 1
    fi

    total=$(printf '%s\n' "$names" | wc -l | tr -d ' ')
    other=()
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        is_doc_path "$n" || other+=( "$n" )
    done <<< "$names"

    if [ "${#other[@]}" -gt 0 ]; then
        echo "NOT docs-only: ${#other[@]} of $total changed path(s) are not *.md:"
        printf '  %s\n' "${other[@]}" | head -10
        return 1
    fi

    echo "docs-only: all $total changed path(s) are *.md, which nothing in src/ or inc/ reads."
    printf '%s\n' "$names" | head -10 | sed 's/^/  /'
    return 0
}

# The refusals this must never get wrong, driven over a scratch repository so
# no case depends on what this repository happens to contain today.
selftest() {
    local dir fails=0 out status
    dir="$(mktemp -d -t doconly)" || return 2
    trap "rm -rf '$dir'" EXIT

    git -C "$dir" init -q                       >/dev/null 2>&1 || return 2
    git -C "$dir" config user.email t@t         >/dev/null 2>&1
    git -C "$dir" config user.name  t           >/dev/null 2>&1
    git -C "$dir" config commit.gpgsign false   >/dev/null 2>&1
    echo seed > "$dir/seed.txt"
    git -C "$dir" add -A                        >/dev/null 2>&1
    git -C "$dir" commit -q -m seed --no-verify >/dev/null 2>&1 || return 2
    git -C "$dir" branch -M base                >/dev/null 2>&1
    # Commit on a branch of its own. Committing on `base` would advance
    # base itself, and every case would compare a ref with itself.
    git -C "$dir" checkout -q -b work           >/dev/null 2>&1 || return 2

    _case() { # _case <name> <want-exit> ; the tree is already staged
        git -C "$dir" add -A >/dev/null 2>&1
        git -C "$dir" commit -q -m "$1" --no-verify >/dev/null 2>&1
        out="$( DOCS_ONLY_ROOT="$dir" "$SCRIPT" base HEAD 2>&1 )"; status=$?
        if [ "$status" -ne "$2" ]; then
            echo "SELFTEST FAIL: $1 ended $status, expected $2 -- $out"
            fails=1
        fi
        git -C "$dir" reset -q --hard base >/dev/null 2>&1
    }

    echo "# a docs change" > "$dir/NOTES.md"
    _case "one .md added" 0

    mkdir -p "$dir/docs/deep/deeper"
    echo x > "$dir/docs/deep/deeper/nested.md"
    echo y > "$dir/README.md"
    _case "two .md in different directories" 0

    mkdir -p "$dir/src"
    echo "int main(){}" > "$dir/src/Main.cpp"
    _case "a .cpp alone" 1

    echo "# doc" > "$dir/DOC.md"
    mkdir -p "$dir/src"
    echo "int main(){}" > "$dir/src/Main.cpp"
    _case "a .md AND a .cpp together" 1

    mkdir -p "$dir/tools"
    printf '#!/bin/sh\nexit 0\n' > "$dir/tools/check_thing.sh"
    _case "a check script alone" 1

    mkdir -p "$dir/tools"
    echo data > "$dir/tools/fixture.dat"
    _case "a fixture alone" 1

    echo "# doc" > "$dir/GONE.md"
    git -C "$dir" add -A >/dev/null 2>&1
    git -C "$dir" commit -q -m add-then-delete --no-verify >/dev/null 2>&1
    git -C "$dir" rm -q seed.txt >/dev/null 2>&1
    _case "a .md added and a .txt DELETED" 1

    # Two refs that differ in nothing must refuse, not wave the change through.
    out="$( DOCS_ONLY_ROOT="$dir" "$SCRIPT" base base 2>&1 )"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: identical refs ended $status, expected 1"; fails=1; }

    # A ref that does not exist must be INCONCLUSIVE, never a pass.
    out="$( DOCS_ONLY_ROOT="$dir" "$SCRIPT" base no-such-ref 2>&1 )"; status=$?
    [ "$status" -eq 2 ] || { echo "SELFTEST FAIL: bad ref ended $status, expected 2"; fails=1; }

    [ "$fails" -eq 0 ] && echo "SELFTEST PASS"
    return "$fails"
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

classify "${1:-master}" "${2:-HEAD}"
exit $?
