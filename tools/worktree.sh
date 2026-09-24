#!/bin/bash
# Start work on a bead in a worktree of its own.
#
#   tools/worktree.sh inc-abcd                 create branch inc-abcd from master
#   tools/worktree.sh inc-abcd inc-pu6v        ... or from another base branch
#   tools/worktree.sh --selftest               prove the refusals fire
#
# WHY THIS EXISTS. Several agent sessions work in this repository at once, and
# before 2026-09-11 they all worked in the SAME checkout. One directory has one
# HEAD, one index and one working tree, so a session that changes branch changes
# it for everybody, silently. It failed twice in one hour that day:
#
#   * A session ran `git checkout -b inc-w26h-remaining` at 13:54:55. A second
#     session, which had read "current branch: master" when it started and never
#     touched HEAD, committed at 16:09 and landed on that branch. `git commit`
#     takes no branch argument -- it advances whatever branch HEAD names. Master
#     did not get the fix. The same class stranded b855fe2 on a review branch on
#     2026-09-04.
#   * tools/package_linux.sh exports the WORKING TREE, so another session's
#     uncommitted src/Values.cpp and three lib/*.irh files compiled into
#     published release assets (inc-iezk).
#
# A worktree has its own HEAD, its own index and its own files, and shares only
# the object database. Neither failure can happen across two of them.
#
# THE BRANCH IS NAMED BY THE BEAD, AND THAT IS THE WHOLE FILING SYSTEM. Branch
# inc-abcd, worktree Incursion-inc-abcd, bead inc-abcd. Nobody has to remember
# what a branch was for, because nothing is remembered -- it is derivable. A
# branch whose name is not a bead id is itself a defect, and
# tools/check_orphan_branches.sh reports it as one.
#
# IT REFUSES A CLOSED BEAD ON PURPOSE. Brian's constraint on 2026-09-11 was that
# isolation alone is not acceptable, because branches accumulate and fixes never
# reach master. The branch is scaffolding: tools/finish_bead.sh destroys it when
# the work lands. Opening a worktree for a bead that is already closed means one
# of those two has gone wrong, so it stops and says so rather than growing the
# pile this exists to prevent.
#
# Ends: 0 the worktree is ready, 1 refused, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/worktree.sh"

# Worktrees sit beside the checkout, which is where Incursion-upw31 already
# lives. Keeping them out of the repository means no .gitignore entry and no
# chance of one worktree being scanned as part of another's tree.
WORKTREE_PARENT="$(dirname "$ROOT")"
WORKTREE_PREFIX="Incursion-"

# The branch every bead starts from. Not origin/master: the remote is not always
# reachable, and this repository's master is the integration branch by local
# convention. A second argument names another base -- an epic branch, e.g.
# inc-pu6v, so a bead builds on the epic instead of on master.
BASE_BRANCH="master"
[ -n "${2:-}" ] && BASE_BRANCH="$2"

die()  { echo "$1" >&2; exit 1; }
cannot() { echo "INCONCLUSIVE: $1" >&2; exit 2; }

# A bead id as this repository spells it: the `inc-` prefix, then the short id,
# optionally a dotted sub-id (inc-loa.40 is a real bead).
is_bead_id() {
    printf '%s' "$1" | grep -Eq '^inc-[a-z0-9]+(\.[0-9]+)?$'
}

bead_status() {
    # Prints the bead's status, or nothing at all when there is no such bead.
    # `bd show` writes its own diagnostics to stderr; we want only the answer.
    bd show "$1" --json 2>/dev/null \
        | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, list):
    d = d[0] if d else {}
print(d.get("status", ""))' 2>/dev/null
}

selftest() {
    local out status

    out="$("$SCRIPT" 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: no argument returned $status, expected 1"; return 1; }

    out="$("$SCRIPT" not-a-bead-id 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: malformed id returned $status, expected 1"; return 1; }
    case "$out" in *"is not a bead id"*) ;; *) echo "SELFTEST FAIL: malformed id said: $out"; return 1;; esac

    # An id that is well formed but names nothing. inc-zzzzzz is not allocated;
    # if it ever is, this refuses for the closed-bead reason instead and the
    # message check below catches the drift.
    out="$("$SCRIPT" inc-zzzzzz 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: unknown bead returned $status, expected 1"; return 1; }
    case "$out" in *"no bead"*) ;; *) echo "SELFTEST FAIL: unknown bead said: $out"; return 1;; esac

    # The second argument names the base branch. A well-formed, open bead with
    # a base branch that does not exist must be refused for THAT reason, before
    # any worktree is made. bd is stubbed for this one case so the run files
    # nothing and touches no real bead.
    local stubdir out2 status2
    stubdir="$(mktemp -d "${TMPDIR:-/tmp}/worktree-selftest.XXXXXX")" || return 1
    cat > "$stubdir/bd" <<'STUB'
#!/bin/sh
echo '[{"status":"open","issue_type":"task"}]'
STUB
    chmod +x "$stubdir/bd"
    out2="$(PATH="$stubdir:$PATH" "$SCRIPT" inc-testbase no-such-base 2>&1)"; status2=$?
    rm -rf "$stubdir"
    [ "$status2" -eq 2 ] || { echo "SELFTEST FAIL: bad base returned $status2, expected 2"; return 1; }
    case "$out2" in *"no-such-base"*) ;; *) echo "SELFTEST FAIL: bad base said: $out2"; return 1;; esac

    echo "SELFTEST PASS"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

BEAD="${1:-}"
[ -n "$BEAD" ] || die "usage: tools/worktree.sh <bead-id>
Start work on a bead in a worktree of its own. Run tools/worktree.sh --selftest
to prove the refusals still fire."

is_bead_id "$BEAD" || die "REFUSED: '$BEAD' is not a bead id.
A branch is named by its bead so that nobody has to remember what it was for.
Expected something like inc-abcd or inc-loa.40."

command -v bd >/dev/null 2>&1 || cannot "bd is not on PATH, so the bead cannot be checked"
command -v python3 >/dev/null 2>&1 || cannot "python3 is not on PATH, so the bead cannot be read"

STATUS="$(bead_status "$BEAD")"
[ -n "$STATUS" ] || die "REFUSED: there is no bead $BEAD.
File it first -- tools/bead_new.sh \"title\" --type bug -d \"...\" --label internal
-- so the branch, the worktree and the tracker agree on one name."

if [ "$STATUS" = "closed" ]; then
    die "REFUSED: bead $BEAD is already closed.
A branch exists only while its bead is open; tools/finish_bead.sh deletes it
when the work lands. Opening one for a closed bead means either the bead was
closed early or the earlier branch was never merged. Check
tools/check_orphan_branches.sh before reopening anything."
fi

WORKTREE="$WORKTREE_PARENT/$WORKTREE_PREFIX$BEAD"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BEAD"; then
    if [ -d "$WORKTREE" ]; then
        echo "Branch $BEAD and its worktree already exist. Work there:"
        echo "  $WORKTREE"
        exit 0
    fi
    die "REFUSED: branch $BEAD exists but has no worktree at $WORKTREE.
Somebody started this bead and the worktree is gone. Either restore it with
  git worktree add \"$WORKTREE\" $BEAD
or, if the work is finished and merged, delete the branch."
fi

[ -e "$WORKTREE" ] && die "REFUSED: $WORKTREE already exists and is not a worktree of this branch.
Move it aside before starting $BEAD."

git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BASE_BRANCH" \
    || cannot "there is no $BASE_BRANCH branch to start from"

git -C "$ROOT" worktree add -b "$BEAD" "$WORKTREE" "$BASE_BRANCH" >/dev/null 2>&1 \
    || die "FAILED: git worktree add refused. Run it by hand to see why:
  git -C \"$ROOT\" worktree add -b \"$BEAD\" \"$WORKTREE\" \"$BASE_BRANCH\""

echo "Bead $BEAD is open in a worktree of its own."
echo "  branch:   $BEAD (from $BASE_BRANCH at $(git -C "$ROOT" rev-parse --short "$BASE_BRANCH"))"
echo "  worktree: $WORKTREE"
echo
echo "Work there and nowhere else. When Brian says commit, finish it with:"
echo "  tools/finish_bead.sh $BEAD"
exit 0
