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

# ROOT is where this script's own file lives -- possibly the very worktree
# STEP 6 below destroys. SHARED is the repository, resolved from git rather
# than from $0, so it still names something real after that worktree is gone.
# git lists the main worktree first, so this is the shared checkout no matter
# which worktree the script runs from. inc-5b76.
SHARED="$(git -C "$ROOT" worktree list --porcelain \
    | sed -n '1s/^worktree //p')"
[ -n "$SHARED" ] || cannot "could not resolve the shared checkout from $ROOT"

WORKTREE_PARENT="$(dirname "$SHARED")"

is_bead_id() {
    printf '%s' "$1" | grep -Eq '^inc-[a-z0-9]+(\.[0-9]+)?$'
}

# Where a scratch checkout of master can live without colliding with anything.
scratch_dir() {
    printf '%s/.finish-bead-%s' "${TMPDIR:-/tmp}" "$$"
}

# The three checks above never reach STEP 5, so the dirty-check on the shared
# checkout's master worktree needs its own throwaway repo: a real merge, a
# real "master already checked out elsewhere" worktree, and a copy of THIS
# script (so its ROOT/SHARED resolve inside the throwaway repo, not the real
# one). Prints "<script-copy> <master-checkout>" on success.
selftest_merge_repo() {
    local tmp bead="inc-slftst"

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/finish-bead-selftest.XXXXXX")" || return 1
    mkdir -p "$tmp/work/Incursion/tools" "$tmp/work/Incursion/src" || return 1

    git -C "$tmp/work/Incursion" init -q -b trunk || return 1
    git -C "$tmp/work/Incursion" config user.email test@example.invalid || return 1
    git -C "$tmp/work/Incursion" config user.name "finish_bead selftest" || return 1
    echo base >"$tmp/work/Incursion/base.txt" || return 1
    # DOCS.md exists on master from the start and the bead branch below never
    # touches it, so the inc-oe6h cases can dirty it at the master checkout
    # and expect it to be let through. src/Foo.cpp is the rename-source case's
    # code file. inc-oe6h.
    echo "base docs" >"$tmp/work/Incursion/DOCS.md" || return 1
    echo "int Foo() { return 1; }" >"$tmp/work/Incursion/src/Foo.cpp" || return 1
    git -C "$tmp/work/Incursion" add base.txt DOCS.md src/Foo.cpp || return 1
    git -C "$tmp/work/Incursion" commit -q -m initial || return 1
    git -C "$tmp/work/Incursion" branch master trunk || return 1

    git -C "$tmp/work/Incursion" worktree add -q -b "$bead" \
        "$tmp/work/Incursion-$bead" master || return 1
    echo bead >"$tmp/work/Incursion-$bead/bead-work.txt" || return 1
    git -C "$tmp/work/Incursion-$bead" add bead-work.txt || return 1
    git -C "$tmp/work/Incursion-$bead" commit -q -m "bead work" || return 1

    git -C "$tmp/work/Incursion" worktree add -q \
        "$tmp/work/master-checkout" master || return 1

    cp "$SCRIPT" "$tmp/work/Incursion/tools/finish_bead.sh" || return 1
    cp "$ROOT/tools/docs_only_change.sh" \
        "$tmp/work/Incursion/tools/docs_only_change.sh" || return 1

    printf '%s %s %s\n' "$tmp" "$tmp/work/Incursion/tools/finish_bead.sh" \
        "$tmp/work/master-checkout"
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

    # STEP 5's dirty check on the shared checkout's master worktree, all three
    # verdicts. Each case gets its own throwaway repo, since a landing that
    # succeeds destroys the bead branch and worktree it used.
    local tmp copy masterco line

    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (untracked case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    echo stray >"$masterco/unrelated-untracked.txt"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    rm -rf "$tmp"
    [ "$status" -eq 0 ] || { echo "SELFTEST FAIL: an untracked file in master's worktree refused the merge: $out"; return 1; }
    case "$out" in *"Landed."*) ;; *) echo "SELFTEST FAIL: untracked-file case did not land: $out"; return 1;; esac

    # base.txt is deliberately non-.md, so this still exercises the (a) refusal
    # from inc-oe6h's split: a dirty tracked path that is not documentation
    # refuses exactly as before, whether or not the bead touches it.
    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (tracked case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    echo changed >"$masterco/base.txt"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    rm -rf "$tmp"
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: a modified TRACKED file in master's worktree did not refuse, status $status: $out"; return 1; }
    case "$out" in *"REFUSED"*"is checked out at"*"uncommitted"*"tracked"*) ;; *) echo "SELFTEST FAIL: tracked-file case said: $out"; return 1;; esac

    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (collision case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    echo collide >"$masterco/bead-work.txt"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    rm -rf "$tmp"
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: an untracked file colliding with the merge did not stop the run, status $status: $out"; return 1; }
    case "$out" in *"does not merge cleanly"*) ;; *) echo "SELFTEST FAIL: collision case said: $out"; return 1;; esac

    # inc-oe6h Case 1: an uncommitted edit to a tracked .md path the bead does
    # NOT touch is allowed through -- it must land, and the edit must still be
    # there afterwards, uncommitted and byte-identical.
    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (doc-allowed case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    echo "local docs edit" >>"$masterco/DOCS.md"
    want_sum="$(shasum -a 256 "$masterco/DOCS.md" | awk '{print $1}')"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    if [ "$status" -ne 0 ]; then
        echo "SELFTEST FAIL: an uncommitted .md edit the bead does not touch refused the merge, status $status: $out"
        rm -rf "$tmp"; return 1
    fi
    case "$out" in *"Landed."*) ;; *) echo "SELFTEST FAIL: doc-allowed case did not land: $out"; rm -rf "$tmp"; return 1;; esac
    got_sum="$(shasum -a 256 "$masterco/DOCS.md" | awk '{print $1}')"
    [ "$got_sum" = "$want_sum" ] || { echo "SELFTEST FAIL: doc-allowed case changed DOCS.md's content"; rm -rf "$tmp"; return 1; }
    got_dirty="$(git -C "$masterco" status --porcelain --untracked-files=no -- DOCS.md)"
    [ -n "$got_dirty" ] || { echo "SELFTEST FAIL: doc-allowed case left DOCS.md committed instead of uncommitted"; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"

    # inc-oe6h Case 3: an uncommitted edit to a tracked .md path the bead ALSO
    # touches is refused BEFORE the merge, names the path, and leaves master
    # exactly where it was.
    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (doc-conflict case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    bead_wt="$tmp/work/Incursion-inc-slftst"
    echo "bead also edits docs" >>"$bead_wt/DOCS.md"
    git -C "$bead_wt" commit -q -am "bead touches DOCS.md" \
        || { echo "SELFTEST FAIL: could not extend the bead branch (doc-conflict case)"; rm -rf "$tmp"; return 1; }
    echo "local docs edit" >>"$masterco/DOCS.md"
    before_head="$(git -C "$masterco" rev-parse HEAD)"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    after_head="$(git -C "$masterco" rev-parse HEAD)"
    rm -rf "$tmp"
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: an uncommitted .md edit the bead ALSO touches did not refuse, status $status: $out"; return 1; }
    case "$out" in *"REFUSED"*"DOCS.md"*) ;; *) echo "SELFTEST FAIL: doc-conflict case said: $out"; return 1;; esac
    [ "$before_head" = "$after_head" ] || { echo "SELFTEST FAIL: doc-conflict case moved master despite refusing"; return 1; }

    # inc-oe6h Case 4: a STAGED rename that turns a non-doc path into a
    # doc-looking one (git mv src/Foo.cpp notes.md) must still refuse with
    # the ORIGINAL message. Only checking the new name would let a code
    # file's removal ride through as "a doc edit".
    line="$(selftest_merge_repo)" || { echo "SELFTEST FAIL: could not build the merge-dirty repo (rename case)"; return 1; }
    read -r tmp copy masterco <<<"$line"
    git -C "$masterco" mv src/Foo.cpp notes.md \
        || { echo "SELFTEST FAIL: could not stage the rename (rename case)"; rm -rf "$tmp"; return 1; }
    before_head="$(git -C "$masterco" rev-parse HEAD)"
    out="$(INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1)"; status=$?
    after_head="$(git -C "$masterco" rev-parse HEAD)"
    rm -rf "$tmp"
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: a rename hiding a non-.md ORIG_PATH did not refuse, status $status: $out"; return 1; }
    case "$out" in *"REFUSED"*"uncommitted tracked changes"*"Foo.cpp"*) ;; *) echo "SELFTEST FAIL: rename case said: $out"; return 1;; esac
    [ "$before_head" = "$after_head" ] || { echo "SELFTEST FAIL: rename case moved master despite refusing"; return 1; }

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

git -C "$SHARED" show-ref --verify --quiet "refs/heads/$BEAD" \
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
would destroy anything left here, so this stops instead.

A reproduction -- the key script, the seed, the options file, the command --
belongs in tools/, committed with the bead. A specimen -- a screen dump, a log,
a save, a crash report -- belongs in docs/evidence/$BEAD/ in the shared checkout
at $SHARED, untracked and never inside a worktree."

# STEP 2. There must be something to land.
AHEAD="$(git -C "$SHARED" rev-list --count "$BASE_BRANCH..$BEAD" 2>/dev/null)"
[ -n "$AHEAD" ] || cannot "could not count commits between $BASE_BRANCH and $BEAD"
[ "$AHEAD" -gt 0 ] || die "REFUSED: $BEAD has no commits that $BASE_BRANCH lacks.
Either the work is not committed, or it already landed. Nothing to do."

# STEP 3. Bring master in FIRST, so the gate measures what master will actually
# have. A conflict stops here, with the branch and the worktree untouched apart
# from the merge git leaves in progress, which the message explains how to undo.
BEHIND="$(git -C "$SHARED" rev-list --count "$BEAD..$BASE_BRANCH" 2>/dev/null)"
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
MASTER_WT="$(git -C "$SHARED" worktree list --porcelain \
    | awk '/^worktree /{p=$2} /^branch refs\/heads\/'"$BASE_BRANCH"'$/{print p}')"

# A dirty tracked path at the shared master checkout is now allowed through
# ONLY when BOTH hold: it is a *.md path (tools/docs_only_change.sh's own
# is_doc_path, reused via --is-doc, so the rule lives in one place), and $BEAD
# does not also change that path. Anything else refuses as before. A *.md path
# $BEAD ALSO changes refuses before the merge is attempted. Fails closed: if
# $BEAD's changed-path list cannot be computed, the whole dirty tree refuses.
# inc-oe6h.
path_in_list() { # path_in_list <needle> <haystack...>
    local needle="$1"; shift; local x
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}

ALLOWED_DOC_PATHS=()
ALLOWED_DOC_SUMS=()

SCRATCH=""
if [ -n "$MASTER_WT" ]; then
    MERGE_IN="$MASTER_WT"
    # Narrowed 2026-09-19 (inc-wkyf) to ignore untracked files: they cannot
    # leak into a build the way an uncommitted TRACKED edit can (the
    # package_linux.sh hazard in the header above). A path git itself needs
    # to write is still refused -- by git's own merge collision guard, not
    # by this check.
    #
    # -z: NUL-separated porcelain, so a renamed or space-containing path
    # parses correctly. A rename/copy entry (XY holds R or C) carries a
    # second NUL-terminated ORIG_PATH field right after PATH. BOTH go into
    # DIRTY_PATHS: `git mv src/Foo.cpp notes.md` is a doc-looking PATH hiding
    # a non-doc ORIG_PATH's removal, so the old name must pass the *.md test
    # too, or the whole rename is refused like any other non-doc change. inc-oe6h.
    DIRTY_FILE="$(mktemp "${TMPDIR:-/tmp}/finish-bead-dirty.XXXXXX")" \
        || cannot "could not create a scratch file for $MERGE_IN's status"
    git -C "$MERGE_IN" status --porcelain -z --untracked-files=no \
        > "$DIRTY_FILE" 2>/dev/null \
        || { rm -f "$DIRTY_FILE"; cannot "could not read git status at $MERGE_IN"; }
    DIRTY_PATHS=()
    while IFS= read -r -d '' rec; do
        xy="${rec:0:2}"
        DIRTY_PATHS+=("${rec:3}")
        case "$xy" in
            *R*|*C*) read -r -d '' orig || true; DIRTY_PATHS+=("$orig") ;;
        esac
    done < "$DIRTY_FILE"
    rm -f "$DIRTY_FILE"

    if [ "${#DIRTY_PATHS[@]}" -gt 0 ]; then
        MERGE_DIRTY="$(git -C "$MERGE_IN" status --porcelain --untracked-files=no)"

        MERGE_BASE="$(git -C "$SHARED" merge-base "$BASE_BRANCH" "$BEAD" 2>/dev/null)"
        [ -n "$MERGE_BASE" ] \
            || cannot "could not compute the merge-base of $BASE_BRANCH and $BEAD"

        BEAD_FILE="$(mktemp "${TMPDIR:-/tmp}/finish-bead-paths.XXXXXX")" \
            || cannot "could not create a scratch file for $BEAD's changed paths"
        git -C "$SHARED" diff --name-only -z "$MERGE_BASE" "$BEAD" \
            > "$BEAD_FILE" 2>/dev/null \
            || { rm -f "$BEAD_FILE"; cannot "could not compute $BEAD's changed paths from $MERGE_BASE"; }
        BEAD_PATHS=()
        while IFS= read -r -d '' p; do BEAD_PATHS+=("$p"); done < "$BEAD_FILE"
        rm -f "$BEAD_FILE"

        BAD_PATHS=()
        CONFLICT_DOC_PATHS=()
        for p in "${DIRTY_PATHS[@]}"; do
            if "$ROOT/tools/docs_only_change.sh" --is-doc "$p"; then
                # bash 3.2 (macOS's /bin/bash) errors under set -u expanding an
                # EMPTY array with "${arr[@]}"; only expand once known non-empty.
                if [ "${#BEAD_PATHS[@]}" -gt 0 ] && path_in_list "$p" "${BEAD_PATHS[@]}"; then
                    CONFLICT_DOC_PATHS+=("$p")
                else
                    ALLOWED_DOC_PATHS+=("$p")
                fi
            else
                BAD_PATHS+=("$p")
            fi
        done

        [ "${#BAD_PATHS[@]}" -eq 0 ] || die "REFUSED: $BASE_BRANCH is checked out at $MERGE_IN and that tree has
uncommitted tracked changes:

$MERGE_DIRTY

Merging there would build on somebody else's uncommitted work. Nothing has
reached $BASE_BRANCH."

        [ "${#CONFLICT_DOC_PATHS[@]}" -eq 0 ] || die "REFUSED: $BASE_BRANCH is checked out at $MERGE_IN with uncommitted
edits to *.md path(s) that $BEAD ALSO changes:

$(printf '  %s\n' "${CONFLICT_DOC_PATHS[@]}")
Merging would overwrite or conflict with those edits. Commit or discard them
in $MERGE_IN before landing. Nothing has reached $BASE_BRANCH."

        if [ "${#ALLOWED_DOC_PATHS[@]}" -gt 0 ]; then
            echo "=== leaving uncommitted docs in place at $MERGE_IN, untouched by $BEAD: ${ALLOWED_DOC_PATHS[*]} ==="
            for i in "${!ALLOWED_DOC_PATHS[@]}"; do
                ALLOWED_DOC_SUMS[$i]="$(shasum -a 256 "$MERGE_IN/${ALLOWED_DOC_PATHS[$i]}" 2>/dev/null | awk '{print $1}')"
            done
        fi
    fi
else
    SCRATCH="$(scratch_dir)"
    git -C "$SHARED" worktree add "$SCRATCH" "$BASE_BRANCH" >/dev/null 2>&1 \
        || cannot "could not create a scratch worktree for $BASE_BRANCH at $SCRATCH"
    MERGE_IN="$SCRATCH"
fi

cleanup_scratch() {
    [ -n "$SCRATCH" ] && git -C "$SHARED" worktree remove --force "$SCRATCH" >/dev/null 2>&1
}

echo "=== merging $BEAD into $BASE_BRANCH (--no-ff) ==="
if ! git -C "$MERGE_IN" merge --no-ff --no-edit \
        -m "Merge $BEAD: $(git -C "$SHARED" log -1 --format=%s "$BEAD")" "$BEAD"; then
    git -C "$MERGE_IN" merge --abort >/dev/null 2>&1
    cleanup_scratch
    die "STOPPED: $BEAD does not merge cleanly into $BASE_BRANCH.
Nothing has reached $BASE_BRANCH and the branch and worktree are intact."
fi

MERGED="$(git -C "$SHARED" rev-parse --short "$BASE_BRANCH")"

# Prove the uncommitted docs edits let through above are still exactly as they
# were: same bytes, still uncommitted. $BEAD never touched these paths, so the
# merge should not have been able to touch them either; this is the check that
# says so rather than assuming it. inc-oe6h.
for i in "${!ALLOWED_DOC_PATHS[@]}"; do
    p="${ALLOWED_DOC_PATHS[$i]}"
    newsum="$(shasum -a 256 "$MERGE_IN/$p" 2>/dev/null | awk '{print $1}')"
    [ "$newsum" = "${ALLOWED_DOC_SUMS[$i]}" ] || die "STOPPED: $BEAD merged into $BASE_BRANCH at $MERGED, but the uncommitted
edit at $MERGE_IN/$p no longer matches what it was before the merge. This
should not be possible; look at $MERGE_IN/$p by hand before trusting anything
downstream of this run."
done
if [ "${#ALLOWED_DOC_PATHS[@]}" -gt 0 ]; then
    STILL_DIRTY="$(git -C "$MERGE_IN" status --porcelain --untracked-files=no -- "${ALLOWED_DOC_PATHS[@]}")"
    [ -n "$STILL_DIRTY" ] || die "STOPPED: $BEAD merged into $BASE_BRANCH at $MERGED, but the uncommitted docs
left in place at $MERGE_IN no longer show as uncommitted. This should not be
possible; look at $MERGE_IN by hand before trusting anything downstream."
fi

cleanup_scratch

# STEP 6. Prove the work is really on the base branch before destroying anything.
#
# `git branch -d` is NOT that proof, and an end-to-end run on 2026-09-11 showed
# why: -d asks whether the branch is merged into the CURRENT HEAD of whatever
# worktree the command runs in, which here is some other bead's branch. It
# refused a branch that had just merged cleanly, and the script went on to claim
# the branch was gone when it was not. Ask the question that is actually being
# asked -- is the branch an ancestor of the base branch -- and only then delete.
if ! git -C "$SHARED" merge-base --is-ancestor "$BEAD" "$BASE_BRANCH"; then
    die "STOPPED: the merge reported success but $BEAD is still not an ancestor of
$BASE_BRANCH. Nothing has been deleted. Look at this by hand before trusting it:
  git -C \"$SHARED\" log --oneline $BASE_BRANCH..$BEAD"
fi

git -C "$SHARED" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || {
    echo "STOPPED: $BEAD is merged into $BASE_BRANCH at $MERGED, but its worktree at" >&2
    echo "$WORKTREE could not be removed. The branch is NOT deleted either, so the" >&2
    echo "two stay consistent. Remove the worktree by hand and run this again." >&2
    exit 1
}

# -D, not -d: the ancestry test above is the real check, and -d asks a different
# question that answers wrongly here.
git -C "$SHARED" branch -D "$BEAD" >/dev/null 2>&1 || {
    echo "WARNING: the worktree is gone but branch $BEAD could not be deleted." >&2
    echo "Delete it by hand:  git -C \"$SHARED\" branch -D $BEAD" >&2
    exit 1
}

# STEP 7. Report (never block) on open beads that may duplicate the one just
# landed. inc-zu0r. This runs AFTER the landing is proven -- STEP 6's ancestry
# test, and the branch and worktree deletions -- and MUST NOT change this
# script's exit status. The check is advisory: the bead is already on master,
# and a bool it cannot prove is not a reason to tell the caller the landing
# failed. $ROOT may already be a destroyed worktree, so the engine is run from
# the shared checkout's own copy, and its absence on the base branch is just
# another failure that prints a line.
CLOSE_CHECK_RC=0
if [ -f "$SHARED/tools/bead_dupes.py" ]; then
    python3 "$SHARED/tools/bead_dupes.py" check-bead "$BEAD" --against open
    CLOSE_CHECK_RC=$?
else
    echo "finish_bead: no $SHARED/tools/bead_dupes.py on $BASE_BRANCH; skipping the duplicate check."
fi

case $CLOSE_CHECK_RC in
    0)
        : ;;
    1)
        echo ""
        echo "Open beads that may duplicate $BEAD — mark each confirmed one:"
        echo "  bd duplicate <id> --of $BEAD"
        ;;
    2|3)
        echo ""
        echo "DIRECTIVE TO THE CLOSING AGENT: the duplicate check on $BEAD could not run"
        echo "(Jev unavailable or bad input). Spawn a subagent with model haiku. Give it"
        echo "bead $BEAD and the output of \`bd list --all --json\`, and have it name any"
        echo "bead that describes the same defect or work. Mark each one you confirm with"
        echo "\`bd duplicate <id> --of $BEAD\`."
        ;;
    *)
        echo "finish_bead: the duplicate check exited $CLOSE_CHECK_RC; continuing anyway."
        ;;
esac

echo
echo "Landed. $BEAD is on $BASE_BRANCH at $MERGED, and its branch and worktree are gone."
echo "Close the bead when you are satisfied:  bd close $BEAD"
exit 0
