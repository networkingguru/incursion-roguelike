#!/usr/bin/env bash
# gate: cheap --selftest
#
# Does .beads/hooks/pre-commit still refuse a bare `git merge master` committed
# ON an epic branch?
#
#   tools/check_epic_merge.sh             run the refusal the hook runs
#   tools/check_epic_merge.sh --selftest  prove every case, against a scratch repo
#
# WHY THIS EXISTS. An epic branch (a bead of type `epic`, e.g. inc-pu6v) is a
# base other beads branch from and land into. A merge runs no gate: the hook
# allows merge commits and tools/check_commit_lane.sh exempts them, so a hand
# `git merge master` on an epic broke two checks and nobody saw it until the
# next bead's landing gate, about fifty minutes later, on someone else's work.
#
# IT ONLY REFUSES A MERGE THAT BRINGS IN MASTER. Any sha in MERGE_HEAD that is
# an ancestor of, or equal to, refs/heads/master is master's work; merging some
# other bead branch into an epic is the ordinary way work arrives. Detached HEAD
# and a non-epic branch are left alone.
#
# THE WAY OUT is the gated path, which this prints and then refuses:
#   tools/bead_new.sh "<title>" ... --parent <epic>
#   tools/worktree.sh <bead> <epic>
#   git merge master there and run the gate
#   INCURSION_BASE_BRANCH=<epic> tools/finish_bead.sh <bead>
# INCURSION_EPIC_SYNC_OK=1 is the escape hatch, for an emergency only.
#
# Exit: 0 no bare epic merge is being committed
#       1 it is, and the commit is refused
#       2 could not measure
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# An epic bead, asked of bd. Anything at all that is not a clean yes -- bd
# missing, a parse failure, a bead that is not an epic -- is a no. Refusing a
# merge is a big hammer, and a branch we cannot identify must not be hit by it.
is_epic() { # is_epic <branch>
    command -v python3 >/dev/null 2>&1 || return 1
    ( cd "$ROOT" 2>/dev/null || exit 1
      "${INCURSION_BD:-bd}" show "$1" --json 2>/dev/null ) \
        | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if isinstance(d, list):
    d = d[0] if d else {}
print("yes" if isinstance(d, dict) and d.get("issue_type") == "epic" else "no")' \
        2>/dev/null | grep -qx yes
}

# The refusal, and the four lines that say how to do it properly.
refuse() { # refuse <branch>
    echo >&2 "pre-commit: REFUSED. You are merging master into epic branch $1."
    echo >&2 "An epic is a base other beads branch from and land into. This merge runs"
    echo >&2 "no gate, so its breakage surfaces at the next bead's landing gate, about"
    echo >&2 "fifty minutes later, on someone else's work."
    echo >&2 ""
    echo >&2 "Take it through a bead instead:"
    echo >&2 "    tools/bead_new.sh \"<title>\" ... --parent $1"
    echo >&2 "    tools/worktree.sh <bead> $1"
    echo >&2 "    git merge master there, run the gate, then:"
    echo >&2 "    INCURSION_BASE_BRANCH=$1 tools/finish_bead.sh <bead>"
    echo >&2 ""
    echo >&2 "INCURSION_EPIC_SYNC_OK=1 bypasses this, for an emergency only."
}

check() { # check <cwd>
    local dir=$1 gitdir branch sha
    gitdir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || return 2
    case "$gitdir" in /*) ;; *) gitdir="$dir/$gitdir" ;; esac
    [ -e "$gitdir/MERGE_HEAD" ] || return 0
    [ "${INCURSION_EPIC_SYNC_OK:-}" = "1" ] && return 0
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || return 0
    is_epic "$branch" || return 0
    while read -r sha; do
        [ -n "$sha" ] || continue
        git -C "$dir" merge-base --is-ancestor "$sha" master 2>/dev/null && {
            refuse "$branch"; return 1; }
    done < "$gitdir/MERGE_HEAD"
    return 0
}

selftest() {
    local fails=0
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/epic-merge.XXXXXX") || return 2
    trap 'rm -rf "$TMP"' EXIT
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    unset INCURSION_EPIC_SYNC_OK

    local repo="$TMP/repo"
    git init -q "$repo" || return 2
    git -C "$repo" checkout -q -b master
    git -C "$repo" config user.name gate
    git -C "$repo" config user.email gate@example.invalid
    git -C "$repo" config commit.gpgsign false
    echo base > "$repo/base"
    git -C "$repo" add base
    git -C "$repo" commit -q --no-verify -m "base"
    # Each branch adds its OWN file, so the merges below are clean: inc-epic and
    # inc-task both diverge from base, then master advances on its own file.
    git -C "$repo" checkout -q -b inc-epic
    echo epic > "$repo/epic"
    git -C "$repo" add epic
    git -C "$repo" commit -q --no-verify -m "epic"
    git -C "$repo" checkout -q master
    git -C "$repo" checkout -q -b inc-task
    echo task > "$repo/task"
    git -C "$repo" add task
    git -C "$repo" commit -q --no-verify -m "task"
    git -C "$repo" checkout -q master
    echo master > "$repo/mstr"
    git -C "$repo" add mstr
    git -C "$repo" commit -q --no-verify -m "master"
    # A second master commit, so master~1 is a real commit that no epic
    # contains: merging it is a genuine two-parent merge, not "up to date".
    echo later > "$repo/later"
    git -C "$repo" add later
    git -C "$repo" commit -q --no-verify -m "later"

    # A fake bd: epic for inc-epic, task for anything else, failure when asked
    # to fail. $INCURSION_BD_FAIL lets one case prove the fallthrough.
    cat > "$TMP/fake-bd" <<'FAKE'
#!/bin/sh
[ "${INCURSION_BD_FAIL:-}" = 1 ] && exit 1
case "$2" in
    inc-epic) echo '[{"issue_type": "epic"}]' ;;
    *)        echo '[{"issue_type": "task"}]' ;;
esac
FAKE
    chmod +x "$TMP/fake-bd"
    export INCURSION_BD="$TMP/fake-bd"

    # Start a merge of <source> into <branch> without committing it, so the
    # check (which the hook runs during the commit) can inspect MERGE_HEAD.
    # --abort afterwards rewinds the working tree and leaves the branches put.
    start_merge() { # start_merge <branch> <source>
        git -C "$repo" checkout -q "$1" 2>/dev/null || return 2
        git -C "$repo" merge -q --no-ff --no-commit "$2" >/dev/null 2>&1
        return 0
    }
    abort_merge() { git -C "$repo" merge --abort >/dev/null 2>&1; }

    case_run() { # case_run <want-rc> <label>
        local want=$1 label=$2 out rc
        out=$(check "$repo" 2>&1); rc=$?
        if [ "$rc" = "$want" ]; then
            echo "ok       $label (exit $rc)"
        else
            echo "FAIL     $label: wanted $want, got $rc"
            echo "$out" | sed 's/^/         | /'
            fails=$(( fails + 1 ))
        fi
    }

    # 1. merging master into an epic is refused.
    start_merge inc-epic master
    case_run 1 "merge master into inc-epic is refused"
    abort_merge

    # 2. the escape hatch allows it.
    start_merge inc-epic master
    INCURSION_EPIC_SYNC_OK=1 case_run 0 "INCURSION_EPIC_SYNC_OK=1 allows it"
    abort_merge

    # 3. a non-epic branch is allowed.
    start_merge inc-task master
    case_run 0 "merge master into inc-task is allowed"
    abort_merge

    # 4. a non-master branch into an epic is allowed.
    start_merge inc-epic inc-task
    case_run 0 "merge a non-master branch into inc-epic is allowed"
    abort_merge

    # 5. a commit that is already on master is refused, not just the tip.
    start_merge inc-epic 'master~1'
    case_run 1 "merge master~1 into inc-epic is refused"
    abort_merge

    # 6. no merge in progress is allowed.
    git -C "$repo" checkout -q inc-epic
    case_run 0 "no merge in progress is allowed"

    # 7. an unreadable bd is not an epic, so the merge is allowed.
    start_merge inc-epic master
    INCURSION_BD_FAIL=1 case_run 0 "a failing bd is allowed (treat as not an epic)"
    abort_merge

    echo
    if [ $fails -eq 0 ]; then
        echo "=== PASS: all seven cases ok"
        return 0
    fi
    echo "=== FAIL: $fails case(s) behaved differently from the rule"
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "")         check "$(pwd)"; exit $? ;;
    -h|--help)  sed -n '3,30p' "$0"; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 2 ;;
esac
