#!/bin/bash
# gate: cheap
# Does a landing started from ANY worktree run the shared checkout's process
# machinery? inc-x604.
#
#   tools/check_landing_uses_shared.sh      (0 pass, 1 fail, 2 could not measure)
#
# A worktree's tools/ is frozen when the worktree is made, so a landing started
# from an old one skipped the load guard and STEP 2b. Three things close that:
#   (a) tools/finish_bead.sh hands over to the shared checkout's copy;
#   (b) tools/nightly_verify.sh refuses a landing diff ref that lacks the marker
#       only the current finish_bead.sh exports (the net for a pre-fix copy);
#   (c) .beads/hooks run the process scripts from the shared checkout.
#
# Scratch repos only: the real repo is read, never written, and no bead is
# touched. No game runs, so no seed is read.
# fact: the game, a seed, a character -- none read (scripts and git only)
# fact: the load average and the machine's CPU count -- INCURSION_LOAD_GUARD_OFF=1
# fact: the shared checkout's path -- a mktemp scratch repo, never the real one
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/landing-shared.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()  { echo "OK    $1"; }
bad() { echo "FAIL  $1"; FAIL=1; }

export INCURSION_LOAD_GUARD_OFF=1
unset INCURSION_FINISH_GATE INCURSION_BASE_BRANCH INCURSION_FINISH_HANDED_OVER \
      INCURSION_LANDING_DIFF_REF INCURSION_LANDING_VIA_SHARED

# A scratch shared checkout S holding the real scripts and hooks, plus a
# worktree W made from it (so W holds its own frozen copy of each).
S="$TMP/shared/Incursion"; W="$TMP/shared/Incursion-inc-zzzzzz"
mkdir -p "$S/tools" "$S/.beads" || exit 2
cp "$ROOT/tools/finish_bead.sh" "$ROOT/tools/nightly_verify.sh" "$S/tools/" || exit 2
cp -R "$ROOT/.beads/hooks" "$S/.beads/hooks" || exit 2
for n in check_commit_lane.sh check_epic_merge.sh sync_issues.sh publish_wiki.sh \
         check_bead_publish.py fast_checks.sh; do
    printf '#!/bin/sh\necho "RAN-FROM:$0" >> "$LOG_FILE"\nexit 0\n' > "$S/tools/$n"
    chmod +x "$S/tools/$n"
done
git -C "$S" init -q -b master || exit 2
git -C "$S" config user.email t@example.invalid; git -C "$S" config user.name t
git -C "$S" config commit.gpgsign false
git -C "$S" add -A && git -C "$S" commit -q --no-verify -m "base" || exit 2
git -C "$S" worktree add -q -b inc-zzzzzz "$W" || exit 2

# ---- (a) the worktree copy hands over; --selftest does not ------------------
# S's copy becomes a stub that says it ran, so no landing logic is needed.
printf '#!/bin/sh\necho "SHARED-RAN args=$* handed=${INCURSION_FINISH_HANDED_OVER:-}"\n' \
    > "$S/tools/finish_bead.sh"
out="$("$W/tools/finish_bead.sh" inc-zzzzzz 2>&1)"
if grep -q 'SHARED-RAN args=inc-zzzzzz handed=1' <<< "$out" \
   && grep -q 'handing over' <<< "$out"; then
    ok "(a) a worktree copy hands the run over to the shared copy"
else
    bad "(a) a worktree copy ran its own logic: $out"
fi
out="$(INCURSION_FINISH_HANDED_OVER=1 "$W/tools/finish_bead.sh" inc-zzzzzz 2>&1)"
if grep -q 'SHARED-RAN' <<< "$out"; then
    bad "(a) the exec-loop marker did not stop a second hand-over"
else
    ok "(a) the loop marker stops a second hand-over"
fi
out="$("$W/tools/finish_bead.sh" --selftest 2>&1)"
if grep -q 'SHARED-RAN' <<< "$out"; then
    bad "(a) --selftest was handed over instead of testing the copy under edit"
else
    ok "(a) --selftest runs the copy it was started as"
fi

# ---- (b) nightly_verify refuses a diff ref without the marker ---------------
mkdir -p "$TMP/nochecks"
nv() { # nv <env prefix words...> -- <args>  (run S's copy)
    ( cd "$S" && env NIGHTLY_CHECK_DIR="$TMP/nochecks" \
        NIGHTLY_VERIFY_STATE="$TMP/state.txt" "$@" 2>&1 )
}
for mode in "--landing" "--landing --reuse-pass" "--docs-only"; do
    # shellcheck disable=SC2086
    out="$(nv INCURSION_LANDING_DIFF_REF=master tools/nightly_verify.sh $mode)"; rc=$?
    if [ "$rc" -ne 0 ] && grep -q 'REFUSED' <<< "$out" \
       && grep -q '/Users/brianhill/Scripts/Incursion/tools/finish_bead.sh <bead>' <<< "$out"; then
        ok "(b) $mode with a diff ref and no marker is refused (exit $rc)"
    else
        bad "(b) $mode with a diff ref and no marker was not refused (exit $rc): $out"
    fi
    # shellcheck disable=SC2086
    out="$(nv INCURSION_LANDING_DIFF_REF=master INCURSION_LANDING_VIA_SHARED=1 tools/nightly_verify.sh $mode)"
    if grep -q 'REFUSED' <<< "$out"; then
        bad "(b) $mode with the marker was refused"
    else
        ok "(b) $mode with the marker is not refused"
    fi
done
out="$(nv tools/nightly_verify.sh --docs-only)"
if grep -q 'REFUSED' <<< "$out"; then
    bad "(b) a run with no diff ref (by hand, the nightly) was refused"
else
    ok "(b) a run with no diff ref is unaffected"
fi
if grep -q 'INCURSION_LANDING_VIA_SHARED=1' "$ROOT/tools/finish_bead.sh"; then
    ok "(b) finish_bead.sh exports the marker into its gate run"
else
    bad "(b) finish_bead.sh never exports INCURSION_LANDING_VIA_SHARED=1"
fi

# ---- (c) hooks: process scripts from the shared checkout --------------------
PROCESS='check_commit_lane\.sh|check_bead_publish\.py|check_epic_merge\.sh|sync_issues\.sh|publish_wiki\.sh'
bad_lines="$(grep -nE "\\\$_inc_root/tools/($PROCESS)" "$ROOT"/.beads/hooks/pre-commit \
    "$ROOT"/.beads/hooks/commit-msg "$ROOT"/.beads/hooks/pre-push)"
if [ -n "$bad_lines" ]; then
    bad "(c) a hook runs a process script from the worktree root: $bad_lines"
else
    ok "(c) no hook runs a process script from the worktree root"
fi
for n in check_commit_lane.sh check_bead_publish.py check_epic_merge.sh sync_issues.sh publish_wiki.sh; do
    if grep -q "\$_inc_shared/tools/$n" "$ROOT"/.beads/hooks/pre-commit \
           "$ROOT"/.beads/hooks/commit-msg "$ROOT"/.beads/hooks/pre-push; then
        ok "(c) a hook runs $n from the shared checkout"
    else
        bad "(c) no hook runs $n from \$_inc_shared"
    fi
done
# Behavior: a commit in W fires S's check_commit_lane.sh, not W's own copy.
git -C "$S" config core.hooksPath "$S/.beads/hooks"
export LOG_FILE="$TMP/hook.log"; : > "$LOG_FILE"
( cd "$W" && echo x > f && git add f && \
  INCURSION_NO_BEAD_SYNC=1 git commit -q -m "tools: scratch" >/dev/null 2>&1 )
if grep -q "RAN-FROM:$S/tools/check_commit_lane.sh" "$LOG_FILE" \
   && ! grep -qE "RAN-FROM:$W/tools/($PROCESS)" "$LOG_FILE" \
   && grep -q "RAN-FROM:$W/tools/fast_checks.sh" "$LOG_FILE"; then
    ok "(c) a commit in a worktree runs check_commit_lane.sh from the shared checkout"
else
    bad "(c) a commit in a worktree did not run process scripts from the shared checkout and content checks from the branch: $(cat "$LOG_FILE")"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: a landing uses the shared checkout's process machinery" && exit 0
exit 1
