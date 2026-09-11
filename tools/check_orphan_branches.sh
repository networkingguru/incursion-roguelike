#!/bin/bash
# gate: cheap
# Regression check: no fix is stranded on a branch master never got.
#
#   tools/check_orphan_branches.sh
#   tools/check_orphan_branches.sh --selftest
#
# WHY IT EXISTS. On 2026-09-04 commit b855fe2 -- the change that finally wired
# the Linux build into the nightly gate -- landed on a review branch a parallel
# session had left checked out. Master went without it, nobody noticed inside
# the session, and it took a later session reading a resume note to find it. On
# 2026-09-11 the same class happened again: a commit meant for master landed on
# inc-w26h-remaining because another session had changed branch in the shared
# checkout fifteen minutes earlier.
#
# Brian's objection to per-bead branches, stated the same day, is exactly this
# failure: "I end up with 50 branches and can't remember what goes where and
# shit I fixed ends up never getting into the fucking code." tools/worktree.sh
# and tools/finish_bead.sh make the branch transient so the pile cannot build
# up. This check is what catches the ones that escape anyway, and it runs
# unattended in tools/nightly_verify.sh so finding them does not depend on
# anybody remembering to look.
#
# WHAT IS A DEFECT HERE, and what is merely worth seeing:
#
#   FAIL  a branch whose bead is CLOSED but which master has not merged. The
#         work is finished, the tracker says so, and the code is not in the
#         product. This is the exact shape of b855fe2.
#   FAIL  a branch whose name is not a bead id. The naming rule is the whole
#         filing system -- branch inc-abcd, worktree Incursion-inc-abcd, bead
#         inc-abcd -- so an unnamed branch is one nobody can attribute, which is
#         how a branch survives long enough to be forgotten.
#   WARN  a branch master HAS merged that still exists. Harmless to the code,
#         but it means tools/finish_bead.sh did not finish, and the pile grows.
#   note  an open bead's unmerged branch. That is work in progress. It is listed
#         with its age so a branch quietly rotting for weeks is visible.
#
# Ends: 0 pass, 1 a stranded or unnamed branch, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/check_orphan_branches.sh"

BASE_BRANCH="master"

# Branches that are deliberately not bead branches. Kept short on purpose: every
# name here is a hole in the naming rule, so each one has to earn its place.
#   nightly/*  the unattended run's own branches, created and merged by the job.
EXEMPT_PATTERN='^(master|nightly/.*)$'

# Branches that PREDATE the naming rule, forgiven BY NAME rather than by moving
# a date cutoff. This is the shape a3c77b6 used for the six laneless commits, and
# for the same reason: a check that goes red on history nobody can now change is
# a check people learn to ignore, and this one has to still be trusted the day it
# catches a real stranded fix. Adding a name here is a deliberate act, and the
# list must not grow -- anything created after 2026-09-11 is named for its bead.
GRANDFATHERED="
inc-upw31-favour-int32
inc-w26h-remaining
upstream-getat-bounds
upstream-movedepth-reentrancy
upstream-targetsort-handles
"

is_grandfathered() {
    printf '%s\n' $GRANDFATHERED | grep -qx -- "$1"
}

# Does a worktree still hold this branch? This is what separates "somebody is
# working here" from "scaffolding nobody cleaned up", and tip position cannot:
# a branch opened and not yet committed to looks exactly like a branch whose
# work was merged, once master moves past both. tools/finish_bead.sh deletes
# the branch and the worktree together, so one without the other is the tell.
has_worktree() {
    git -C "$ROOT" worktree list --porcelain \
        | grep -qx "branch refs/heads/$1"
}

is_bead_id() {
    printf '%s' "$1" | grep -Eq '^inc-[a-z0-9]+(\.[0-9]+)?$'
}

bead_status() {
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
    # The real repository must answer cleanly or the check is useless as a gate;
    # a red answer here is a real finding, not a broken self-test, so the
    # self-test asserts only that the check RAN and classified every branch.
    local out status
    out="$("$SCRIPT" 2>&1)"; status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then
        echo "SELFTEST FAIL: the check returned $status, expected 0 or 1"
        echo "$out"
        return 1
    fi
    case "$out" in
        *"branches not merged into $BASE_BRANCH"*) ;;
        *) echo "SELFTEST FAIL: no summary line in the output"; echo "$out"; return 1;;
    esac

    # A branch name that is not a bead id must be classified as a failure. This
    # proves the rule fires rather than trusting that it would.
    if ! is_bead_id "review/sundered-deep-entry"; then
        : # correct: a slashed review branch is not a bead id
    else
        echo "SELFTEST FAIL: 'review/sundered-deep-entry' was accepted as a bead id"
        return 1
    fi
    if ! is_bead_id "inc-loa.40"; then
        echo "SELFTEST FAIL: 'inc-loa.40' was rejected as a bead id"
        return 1
    fi

    echo "SELFTEST PASS"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

command -v git >/dev/null 2>&1 || { echo "INCONCLUSIVE: git is not on PATH"; exit 2; }
git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BASE_BRANCH" \
    || { echo "INCONCLUSIVE: there is no $BASE_BRANCH branch to compare against"; exit 2; }

HAVE_BD=0
command -v bd >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && HAVE_BD=1

failures=0
warnings=0
listed=0

printf '%-30s %-10s %-9s %s\n' BRANCH BEAD AGE VERDICT
printf '%-30s %-10s %-9s %s\n' "------" "----" "---" "-------"

while read -r branch; do
    [ -n "$branch" ] || continue
    printf '%s' "$branch" | grep -Eq "$EXEMPT_PATTERN" && continue

    age="$(git -C "$ROOT" log -1 --format='%cr' "$branch" 2>/dev/null \
           | sed 's/ ago//; s/ minutes*/m/; s/ hours*/h/; s/ days*/d/; s/ weeks*/w/; s/ months*/mo/')"

    merged=no
    git -C "$ROOT" merge-base --is-ancestor "$branch" "$BASE_BRANCH" 2>/dev/null && merged=yes

    live=no
    has_worktree "$branch" && live=yes

    # Merged and nobody is working in it: the scaffolding outlived the work.
    # Said before the naming rule, because deleting a merged branch is safe
    # advice whatever it is called, and a grandfathered name is still clutter
    # once its work is in.
    if [ "$merged" = "yes" ] && [ "$live" = "no" ]; then
        printf '%-30s %-10s %-9s %s\n' "$branch" "-" "${age:-?}" \
            "WARN  merged, no worktree; delete it: git branch -d $branch"
        warnings=$((warnings + 1))
        listed=$((listed + 1))
        continue
    fi

    if ! is_bead_id "$branch"; then
        if is_grandfathered "$branch"; then
            printf '%-30s %-10s %-9s %s\n' "$branch" "-" "${age:-?}" \
                "note  predates the naming rule, forgiven by name"
            listed=$((listed + 1))
            continue
        fi
        printf '%-30s %-10s %-9s %s\n' "$branch" "-" "${age:-?}" "FAIL  name is not a bead id"
        failures=$((failures + 1))
        listed=$((listed + 1))
        continue
    fi

    status="unknown"
    [ "$HAVE_BD" -eq 1 ] && status="$(bead_status "$branch")"
    [ -n "$status" ] || status="no bead"

    listed=$((listed + 1))

    # Merged, and a worktree is still open on it: somebody is working there and
    # has nothing unlanded yet. That is the normal state right after
    # tools/worktree.sh, and for the whole time master moves ahead of a bead
    # nobody has committed to.
    if [ "$merged" = "yes" ]; then
        printf '%-30s %-10s %-9s %s\n' "$branch" "$status" "${age:-?}" \
            "note  open in its worktree, nothing to land yet"
        continue
    fi

    case "$status" in
        closed)
            printf '%-30s %-10s %-9s %s\n' "$branch" "$status" "${age:-?}" \
                "FAIL  bead closed, work NOT on $BASE_BRANCH"
            failures=$((failures + 1))
            ;;
        "no bead")
            printf '%-30s %-10s %-9s %s\n' "$branch" "$status" "${age:-?}" \
                "FAIL  no bead of this name"
            failures=$((failures + 1))
            ;;
        unknown)
            printf '%-30s %-10s %-9s %s\n' "$branch" "$status" "${age:-?}" \
                "note  bd unavailable, bead not checked"
            ;;
        *)
            printf '%-30s %-10s %-9s %s\n' "$branch" "$status" "${age:-?}" \
                "note  work in progress"
            ;;
    esac
done <<EOF
$(git -C "$ROOT" for-each-ref --format='%(refname:short)' refs/heads/)
EOF

echo
if [ "$failures" -gt 0 ]; then
    echo "FAIL: $listed branches not merged into $BASE_BRANCH or awaiting cleanup; $failures need attention, $warnings warned."
    echo "A closed bead whose branch is unmerged means the fix is not in the product."
    exit 1
fi
echo "PASS: $listed branches not merged into $BASE_BRANCH or awaiting cleanup; none stranded, $warnings warned."
exit 0
