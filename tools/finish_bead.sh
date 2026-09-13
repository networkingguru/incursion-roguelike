#!/bin/bash
# Land a finished bead on master and destroy its scaffolding.
#
#   tools/finish_bead.sh inc-abcd       gate, merge, delete branch, drop worktree
#   tools/finish_bead.sh inc-abcd --no-gate
#   tools/finish_bead.sh --selftest
#
# A bead whose whole diff is *.md gets the cheap gate; see STEP 4. So does a
# bead whose exact files passed the full gate in the last 24 hours.
#
# WHY IT IS ONE SCRIPT AND NOT A CHECKLIST. tools/worktree.sh isolates a bead so
# two sessions cannot tread on each other. Isolation alone was NOT acceptable to
# Brian on 2026-09-11: "I end up with 50 branches and can't remember what goes
# where and shit I fixed ends up never getting into the fucking code." He is
# describing b855fe2, a gate fix that sat on somebody's review branch on
# 2026-09-04 while master went without it.
#
# So a branch is scaffolding with a fixed lifetime. It is created when the bead
# is started and destroyed when the work lands, and the destruction is not a
# step anybody has to remember -- it is the same command as the landing. You
# cannot accumulate fifty of something that is deleted on completion.
#
# IT DOES NOT COMMIT FOR YOU, and that is deliberate. The commit gate is where
# the user's approval and the review statement live, and where an unfit bead is
# refused. This script starts from work that is ALREADY committed on the branch
# and only lands it, so nothing here can route around that gate.
#
# ALL OF IT OR NONE OF IT. A conflict or a red gate stops the run and leaves the
# branch and the worktree exactly as they were. The half-landed state this
# guards against -- branch merged, worktree deleted, work not actually on master
# -- is the state nobody notices until a release ships without the fix.
#
# WHY IT MERGES IN A TEMPORARY WORKTREE. master is usually not checked out
# anywhere, and when it is, it is in the shared checkout where another session
# may have a dirty tree. Merging in scratch space touches neither.
#
# WHY --no-ff. Brian chose merge-on-completion over review-before-merge on
# 2026-09-11, on the grounds that nothing merges until he says commit, so he is
# the review. A --no-ff merge keeps each bead one identifiable, revertible unit
# in the log rather than a scatter of commits that have to be picked apart
# later.
#
# Ends: 0 landed, 1 refused or stopped, 2 the run could not be attempted.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/finish_bead.sh"

WORKTREE_PARENT="$(dirname "$ROOT")"
WORKTREE_PREFIX="Incursion-"

# master, except when the end-to-end self-test is driving. The merge and the two
# deletions below are the half of this script the refusal tests cannot reach, and
# proving them on master would mean putting a junk commit on master to do it. The
# override exists so that path is exercised against a scratch branch instead.
BASE_BRANCH="${INCURSION_BASE_BRANCH:-master}"

# The gate that must be green before anything reaches master. Overridable so a
# caller can substitute a cheaper check knowingly; the default is the one
# CLAUDE.md names as this project's answer to hosted CI.
GATE_CMD="${INCURSION_FINISH_GATE:-tools/nightly_verify.sh --compare}"
GATE_OVERRIDDEN=0
[ -n "${INCURSION_FINISH_GATE:-}" ] && GATE_OVERRIDDEN=1

die()    { echo "$1" >&2; exit 1; }
cannot() { echo "INCONCLUSIVE: $1" >&2; exit 2; }

is_bead_id() {
    printf '%s' "$1" | grep -Eq '^inc-[a-z0-9]+(\.[0-9]+)?$'
}

# Where a scratch checkout of master can live without colliding with anything.
scratch_dir() {
    printf '%s/.finish-bead-%s' "${TMPDIR:-/tmp}" "$$"
}

selftest() {
    local out status

    out="$("$SCRIPT" 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: no argument returned $status, expected 1"; return 1; }

    out="$("$SCRIPT" not-a-bead-id 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: malformed id returned $status, expected 1"; return 1; }
    case "$out" in *"is not a bead id"*) ;; *) echo "SELFTEST FAIL: malformed id said: $out"; return 1;; esac

    out="$("$SCRIPT" inc-zzzzzz 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: unknown branch returned $status, expected 1"; return 1; }
    case "$out" in *"no branch"*) ;; *) echo "SELFTEST FAIL: unknown branch said: $out"; return 1;; esac

    echo "SELFTEST PASS"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

BEAD="${1:-}"
RUN_GATE=1
[ "${2:-}" = "--no-gate" ] && RUN_GATE=0

[ -n "$BEAD" ] || die "usage: tools/finish_bead.sh <bead-id> [--no-gate]
Land a finished bead on $BASE_BRANCH and delete its branch and worktree."

is_bead_id "$BEAD" || die "REFUSED: '$BEAD' is not a bead id."

git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BEAD" \
    || die "REFUSED: there is no branch $BEAD.
Nothing to land. tools/worktree.sh $BEAD starts one."

WORKTREE="$WORKTREE_PARENT/$WORKTREE_PREFIX$BEAD"
[ -d "$WORKTREE" ] || die "REFUSED: branch $BEAD has no worktree at $WORKTREE.
Restore it before landing, so the gate runs against the tree the work was done in:
  git worktree add \"$WORKTREE\" $BEAD"

# STEP 1. The branch must carry every intended change. A file left uncommitted
# in the worktree is destroyed with the worktree, so this refuses rather than
# silently discarding somebody's afternoon.
DIRTY="$(git -C "$WORKTREE" status --porcelain)"
[ -z "$DIRTY" ] || die "REFUSED: $WORKTREE is not clean:

$DIRTY

Commit what belongs to $BEAD, or remove what does not. Removing the worktree
would destroy anything left here, so this stops instead."

# STEP 2. There must be something to land.
AHEAD="$(git -C "$ROOT" rev-list --count "$BASE_BRANCH..$BEAD" 2>/dev/null)"
[ -n "$AHEAD" ] || cannot "could not count commits between $BASE_BRANCH and $BEAD"
[ "$AHEAD" -gt 0 ] || die "REFUSED: $BEAD has no commits that $BASE_BRANCH lacks.
Either the work is not committed, or it already landed. Nothing to do."

# STEP 3. Bring master in FIRST, so the gate measures what master will actually
# have. A conflict stops here, with the branch and the worktree untouched apart
# from the merge git leaves in progress, which the message explains how to undo.
BEHIND="$(git -C "$ROOT" rev-list --count "$BEAD..$BASE_BRANCH" 2>/dev/null)"
if [ "${BEHIND:-0}" -gt 0 ]; then
    echo "=== bringing $BASE_BRANCH ($BEHIND commit(s)) into $BEAD ==="
    if ! git -C "$WORKTREE" merge --no-edit "$BASE_BRANCH"; then
        die "STOPPED: $BASE_BRANCH does not merge cleanly into $BEAD.
Resolve it in $WORKTREE and run this again, or abandon the attempt with:
  git -C \"$WORKTREE\" merge --abort
Nothing has reached $BASE_BRANCH."
    fi
fi

# STEP 4. The gate, run in the worktree, against the merged result.
#
# THE CARVE-OUT. A bead that changes nothing but markdown used to pay for both
# builds, the Linux cross-build, the layout sweep, the soak and every live
# check. On 2026-09-12 a two-file documentation edit did exactly that, and
# Brian's instruction was "needs to be a carve out for changes that literally
# cannot affect behavior". tools/docs_only_change.sh is the only thing that
# decides a bead qualifies, and it is an allowlist, so anything it has not been
# taught about gets the whole gate.
#
# IT DROPS THE BUILDS AND THE LIVE TIER, AND NOTHING ELSE. The entire cheap
# tier still runs, because six checks in it parse markdown and a documentation
# change is perfectly capable of breaking one. A carve-out that skipped those
# would be the hole this comment exists to deny.
#
# IT FAILS CLOSED, THREE WAYS. An explicit INCURSION_FINISH_GATE is honoured
# untouched, a verdict of 1 runs the full gate, and a verdict of 2 -- the
# classifier could not measure -- runs the full gate too. The only path to the
# cheap gate is a classifier that ran and said yes.
#
# THE SECOND CARVE-OUT asks a different question: have these exact files
# already passed the full gate? A landing interrupted after a green gate, or a
# gate run before the commit, used to pay for the whole gate again (inc-689z).
# So a verdict of 1 runs --reuse-pass. It looks for the record that a full
# pass leaves, re-runs the cheap tier when one matches, and runs the full gate
# when none does. It does not widen the docs-only allowlist, and a verdict of
# 2 does not reach it.
if [ "$RUN_GATE" -eq 1 ] && [ "$GATE_OVERRIDDEN" -eq 0 ]; then
    DOCS_VERDICT="$("$ROOT/tools/docs_only_change.sh" "$BASE_BRANCH" "$BEAD" 2>&1)"
    case $? in
        0) echo "=== $DOCS_VERDICT ==="
           echo "=== gate scaled down: builds and the live tier cannot be reached by *.md ==="
           GATE_CMD="tools/nightly_verify.sh --docs-only" ;;
        1) GATE_CMD="tools/nightly_verify.sh --reuse-pass" ;;
        *) echo "=== docs-only classifier could not measure; running the full gate ==="
           echo "$DOCS_VERDICT" ;;
    esac
fi

if [ "$RUN_GATE" -eq 1 ]; then
    echo "=== gate: $GATE_CMD ==="
    if ! ( cd "$WORKTREE" && eval "$GATE_CMD" ); then
        die "STOPPED: the gate is red on $BEAD after merging $BASE_BRANCH.
Nothing has reached $BASE_BRANCH. Fix it in $WORKTREE and run this again.
If the gate cannot measure here rather than failing, re-run with --no-gate and
say so in your report."
    fi
else
    echo "=== gate SKIPPED (--no-gate) ==="
fi

# STEP 5. Merge to master. In scratch space unless master is already checked
# out somewhere, in which case git would refuse a second checkout of it anyway.
MASTER_WT="$(git -C "$ROOT" worktree list --porcelain \
    | awk '/^worktree /{p=$2} /^branch refs\/heads\/'"$BASE_BRANCH"'$/{print p}')"

SCRATCH=""
if [ -n "$MASTER_WT" ]; then
    MERGE_IN="$MASTER_WT"
    MERGE_DIRTY="$(git -C "$MERGE_IN" status --porcelain)"
    [ -z "$MERGE_DIRTY" ] || die "REFUSED: $BASE_BRANCH is checked out at $MERGE_IN and that tree is dirty.
Merging there would build on somebody else's uncommitted work. Nothing has
reached $BASE_BRANCH."
else
    SCRATCH="$(scratch_dir)"
    git -C "$ROOT" worktree add "$SCRATCH" "$BASE_BRANCH" >/dev/null 2>&1 \
        || cannot "could not create a scratch worktree for $BASE_BRANCH at $SCRATCH"
    MERGE_IN="$SCRATCH"
fi

cleanup_scratch() {
    [ -n "$SCRATCH" ] && git -C "$ROOT" worktree remove --force "$SCRATCH" >/dev/null 2>&1
}

echo "=== merging $BEAD into $BASE_BRANCH (--no-ff) ==="
if ! git -C "$MERGE_IN" merge --no-ff --no-edit \
        -m "Merge $BEAD: $(git -C "$ROOT" log -1 --format=%s "$BEAD")" "$BEAD"; then
    git -C "$MERGE_IN" merge --abort >/dev/null 2>&1
    cleanup_scratch
    die "STOPPED: $BEAD does not merge cleanly into $BASE_BRANCH.
Nothing has reached $BASE_BRANCH and the branch and worktree are intact."
fi

MERGED="$(git -C "$ROOT" rev-parse --short "$BASE_BRANCH")"
cleanup_scratch

# STEP 6. Prove the work is really on the base branch before destroying anything.
#
# `git branch -d` is NOT that proof, and an end-to-end run on 2026-09-11 showed
# why: -d asks whether the branch is merged into the CURRENT HEAD of whatever
# worktree the command runs in, which here is some other bead's branch. It
# refused a branch that had just merged cleanly, and the script went on to claim
# the branch was gone when it was not. Ask the question that is actually being
# asked -- is the branch an ancestor of the base branch -- and only then delete.
if ! git -C "$ROOT" merge-base --is-ancestor "$BEAD" "$BASE_BRANCH"; then
    die "STOPPED: the merge reported success but $BEAD is still not an ancestor of
$BASE_BRANCH. Nothing has been deleted. Look at this by hand before trusting it:
  git -C \"$ROOT\" log --oneline $BASE_BRANCH..$BEAD"
fi

git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || {
    echo "STOPPED: $BEAD is merged into $BASE_BRANCH at $MERGED, but its worktree at" >&2
    echo "$WORKTREE could not be removed. The branch is NOT deleted either, so the" >&2
    echo "two stay consistent. Remove the worktree by hand and run this again." >&2
    exit 1
}

# -D, not -d: the ancestry test above is the real check, and -d asks a different
# question that answers wrongly here.
git -C "$ROOT" branch -D "$BEAD" >/dev/null 2>&1 || {
    echo "WARNING: the worktree is gone but branch $BEAD could not be deleted." >&2
    echo "Delete it by hand:  git -C \"$ROOT\" branch -D $BEAD" >&2
    exit 1
}

echo
echo "Landed. $BEAD is on $BASE_BRANCH at $MERGED, and its branch and worktree are gone."
echo "Close the bead when you are satisfied:  bd close $BEAD"
exit 0
