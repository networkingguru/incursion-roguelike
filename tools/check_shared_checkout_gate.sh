#!/usr/bin/env bash
# gate: cheap
#
# Does .beads/hooks/pre-commit still refuse new work in the shared checkout, and
# still let the overnight harness through?
#
#   tools/check_shared_checkout_gate.sh      run every case
#
# WHY THIS EXISTS. That hook carries two rules that pull against each other. It
# must REFUSE a non-merge commit in ~/Scripts/Incursion, because one directory
# has one HEAD and a second session's branch change silently redirects your
# commit (inc-uw8s). It must ALLOW the overnight harness, which commits on
# branch nightly/<date> in that same directory and has no worktree to move to
# (inc-loa.46). One condition decides both, and a wrong edit to it fails in a
# direction nobody sees until 01:00: too loose and the hazard returns silently,
# too tight and the night's work cannot be committed at all.
#
# IT TESTS A SCRATCH REPOSITORY, NOT THIS ONE. Every case makes its own git
# repository under TMPDIR, points core.hooksPath at a copy of the hook, and
# tries a real commit. Nothing here touches the repository it is run from.
#
# THE SUITE CANNOT PASS VACUOUSLY. Four cases demand a refusal and three demand
# a commit, so a hook that never runs fails the first four and a hook that
# refuses everything fails the last three.
#
# PATH IS CUT DOWN ON PURPOSE. The beads block at the top of the hook shells out
# to `bd`, which would resolve a database from the scratch directory. With bd
# off PATH that block skips itself, and what remains under test is this
# project's own two blocks.
#
# Exit: 0 every case behaved
#       1 a case did not
#       2 could not measure
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/.beads/hooks/pre-commit"
NIGHTLY_BRANCH_NAME="nightly/2026-09-13"

[ -r "$HOOK" ] || { echo "check_shared_checkout_gate: no hook at $HOOK" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "check_shared_checkout_gate: no git" >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/shared-checkout-gate.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# A scratch repository answers to nothing the person running this has configured.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export PATH=/usr/bin:/bin
unset NIGHTLY_BRANCH

REPO="$TMP/checkout"
HOOKS="$TMP/hooks"
mkdir -p "$REPO" "$HOOKS"
cp "$HOOK" "$HOOKS/pre-commit"
chmod +x "$HOOKS/pre-commit"

git init -q "$REPO" || exit 2
git -C "$REPO" symbolic-ref HEAD refs/heads/master
git -C "$REPO" config user.name "gate"
git -C "$REPO" config user.email "gate@example.invalid"
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config core.hooksPath "$HOOKS"
echo base > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q --no-verify -m "base" || exit 2

fails=0
n=0

# try <dir> <allow|refuse> <label>; NIGHTLY_BRANCH comes from the caller's
# environment, which is the whole point of the exemption under test.
try() {
    local dir=$1 want=$2 label=$3 out rc verdict
    n=$(( n + 1 ))
    echo "line $n" >> "$dir/file.txt"
    git -C "$dir" add file.txt
    out=$(git -C "$dir" commit -m "docs: case $n" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then verdict=allow; else verdict=refuse; fi
    if [ "$verdict" = "$want" ]; then
        echo "ok       $label ($verdict)"
        return 0
    fi
    echo "FAIL     $label: wanted $want, got $verdict (exit $rc)"
    echo "$out" | sed 's/^/         | /'
    git -C "$dir" reset -q HEAD -- file.txt
    git -C "$dir" checkout -q -- file.txt
    fails=$(( fails + 1 ))
}

# 1. The hazard the hook was built for: a session starting new work here.
try "$REPO" refuse "shared checkout, master, no harness"

# 2. A stray NIGHTLY_BRANCH must not wave a commit through on master. The
#    branch itself has to be a nightly one.
NIGHTLY_BRANCH=master try "$REPO" refuse "shared checkout, master, NIGHTLY_BRANCH=master"

git -C "$REPO" checkout -q -b "$NIGHTLY_BRANCH_NAME"

# 3. A second session on the harness's branch has no NIGHTLY_BRANCH of its own,
#    and is still refused. This is the 2026-09-11 failure in its newest clothes.
try "$REPO" refuse "shared checkout, nightly branch, no NIGHTLY_BRANCH"

# 4. Set, but naming a different branch: the harness is not what is committing.
NIGHTLY_BRANCH=nightly/1999-01-01 try "$REPO" refuse "shared checkout, nightly branch, NIGHTLY_BRANCH names another"

# 5. The harness itself. This is the case inc-loa.46 asked for.
NIGHTLY_BRANCH="$NIGHTLY_BRANCH_NAME" try "$REPO" allow "shared checkout, nightly branch, NIGHTLY_BRANCH matches"

git -C "$REPO" checkout -q master

# 6. Integration is this tree's job, so a merge commit is allowed. --no-commit
#    leaves MERGE_HEAD set and hands the commit to the hook, which is what
#    tools/finish_bead.sh does after a conflict. The branch merged here is made
#    for this case alone, so a failure above cannot make this one fail too.
git -C "$REPO" checkout -q -b merge-source master
echo merged > "$REPO/other.txt"
git -C "$REPO" add other.txt
git -C "$REPO" commit -q --no-verify -m "docs: a branch to merge"
git -C "$REPO" checkout -q master
git -C "$REPO" merge -q --no-ff --no-commit merge-source >/dev/null 2>&1
if [ -e "$REPO/.git/MERGE_HEAD" ]; then
    n=$(( n + 1 ))
    if git -C "$REPO" commit -q -m "Merge case $n" >/dev/null 2>&1; then
        echo "ok       shared checkout, merge commit (allow)"
    else
        echo "FAIL     shared checkout, merge commit: wanted allow, got refuse"
        fails=$(( fails + 1 ))
    fi
else
    echo "FAIL     shared checkout, merge commit: could not set up MERGE_HEAD"
    fails=$(( fails + 1 ))
fi

# 7. A linked worktree has its own git dir, so the block never fires there.
#    This is where every bead is supposed to be worked.
WORK="$TMP/worktree"
if git -C "$REPO" worktree add -q -b inc-test "$WORK" master >/dev/null 2>&1; then
    try "$WORK" allow "linked worktree, ordinary commit"
else
    echo "FAIL     linked worktree: could not create one"
    fails=$(( fails + 1 ))
fi

echo
if [ $fails -eq 0 ]; then
    echo "=== PASS: the shared-checkout gate refuses new work and admits the harness ==="
    exit 0
fi
echo "=== FAIL: $fails case(s) behaved differently from the rule in .beads/hooks/pre-commit ==="
exit 1
