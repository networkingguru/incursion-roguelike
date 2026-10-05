#!/bin/bash
# gate: cheap
# gate-serial: races wall-clock landing-lock deadlines (sleep 2/3 s windows); CPU load could flip them
#
# Does the per-base-branch landing lock in tools/finish_bead.sh actually
# serialise two landings, clear a stale lock, spare a different base branch,
# and release on a signal? inc-1npn.
#
#   tools/check_finish_bead_lock.sh      (0 pass, 1 fail, 2 could not measure)
#
# A gate nobody has watched bite is a gate trusted on its comments. The lock's
# whole value is the case a human cannot stage by hand: two landings reaching
# the SAME base branch at once, each about to merge into a base the other is
# still changing. So this builds a throwaway repo -- nothing outside its own
# mktemp dir is touched, no real bead, no real branch -- and drives the copied
# script through five cases: serialisation, stale clear, per-branch isolation,
# interrupt release, and a live holder that has not written `started` yet.
#
# It is `gate: cheap` so the gate runs it automatically, which means it MUST
# finish fast and MUST NOT hang. INCURSION_FINISH_GATE below substitutes a
# sleep or `true` for the real gate, INCURSION_FINISH_LOCK_POLL=1 keeps the
# wait loop snappy, and every wait has a deadline; a bug that would hang the
# gate fails the case instead.
set -uo pipefail

# A scratch repository answers to nothing the person running this has configured.
unset INCURSION_FINISH_GATE INCURSION_BASE_BRANCH INCURSION_FINISH_LOCK_POLL \
      NIGHTLY_VERIFY_STATE NIGHTLY_CHECK_DIR NIGHTLY_BASE_REF

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/finish_bead.sh"
DOCS_ONLY="$ROOT/tools/docs_only_change.sh"

FAIL=0
ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }

TMP=""
CHILD_PIDS=()
cleanup() {
    local p
    for p in "${CHILD_PIDS[@]:-}"; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    [ -n "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

# The scratch repo. Modeled on selftest_merge_repo in finish_bead.sh: the main
# worktree is the shared checkout (so SHARED resolves inside the scratch repo,
# not the real one), master is checked out at master-checkout so the merge lands
# there, and each bead gets its own worktree with one commit adding a file.
build_repo() { # build_repo <bead>... ; prints the scratch root
    local tmp bead
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/finish-bead-lock-check.XXXXXX")" || return 1
    mkdir -p "$tmp/work/Incursion/tools" "$tmp/work/Incursion/src" || return 1

    git -C "$tmp/work/Incursion" init -q -b trunk || return 1
    git -C "$tmp/work/Incursion" config user.email test@example.invalid || return 1
    git -C "$tmp/work/Incursion" config user.name "finish_bead lock check" || return 1
    echo base >"$tmp/work/Incursion/base.txt" || return 1
    echo "base docs" >"$tmp/work/Incursion/DOCS.md" || return 1
    git -C "$tmp/work/Incursion" add base.txt DOCS.md || return 1
    git -C "$tmp/work/Incursion" commit -q -m initial || return 1
    git -C "$tmp/work/Incursion" branch master trunk || return 1

    cp "$SCRIPT" "$tmp/work/Incursion/tools/finish_bead.sh" || return 1
    cp "$DOCS_ONLY" "$tmp/work/Incursion/tools/docs_only_change.sh" || return 1

    for bead in "$@"; do
        git -C "$tmp/work/Incursion" worktree add -q -b "$bead" \
            "$tmp/work/Incursion-$bead" master || return 1
        echo "$bead" >"$tmp/work/Incursion-$bead/$bead.txt" || return 1
        git -C "$tmp/work/Incursion-$bead" add "$bead.txt" || return 1
        git -C "$tmp/work/Incursion-$bead" commit -q -m "$bead work" || return 1
    done

    git -C "$tmp/work/Incursion" worktree add -q \
        "$tmp/work/master-checkout" master || return 1

    printf '%s\n' "$tmp"
}

# wait_for_lock <lockdir> <seconds>; 0 when it appears, 1 on timeout.
wait_for_lock() {
    local lock="$1" deadline=$(( $(date +%s) + $2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ -d "$lock" ] && return 0
        sleep 0.2
    done
    return 1
}

# wait_pid <pid> <seconds>; 0 when it exits (WAIT_RC holds its status), 1 on
# timeout. The landing destroys its own branch on success, so callers must ask
# about a commit SHA captured before the run, never the branch name.
WAIT_RC=0
wait_pid() {
    local pid="$1" deadline=$(( $(date +%s) + $2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"; WAIT_RC=$?
            return 0
        fi
        # A killed pid can linger as a zombie until waited on; kill -0 still
        # succeeds. `kill -0` plus a wait is the portable-enough pair here.
        sleep 0.2
    done
    return 1
}

# Is commit <sha> an ancestor of master in the scratch repo at $1?
is_ancestor() { # is_ancestor <repo> <sha>
    git -C "$1/work/Incursion" merge-base --is-ancestor "$2" master
}

bead_sha() { # bead_sha <repo> <bead>
    git -C "$1/work/Incursion" rev-parse "$2"
}

# ---------------------------------------------------------------------------
# Case 1: serialisation. Two landings onto master; the second must wait for the
# first, not race it.
# ---------------------------------------------------------------------------
case_serialisation() {
    local tmp outa outb pida pidb sha_a sha_b lock
    tmp="$(build_repo inc-lcka inc-lckb)" || { bad "case 1: could not build the repo"; return 2; }
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha_a="$(bead_sha "$tmp" inc-lcka)" || { bad "case 1: no inc-lcka commit"; rm -rf "$tmp"; return 2; }
    sha_b="$(bead_sha "$tmp" inc-lckb)" || { bad "case 1: no inc-lckb commit"; rm -rf "$tmp"; return 2; }

    INCURSION_FINISH_GATE="sleep 6" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lcka >"$tmp/a.out" 2>&1 &
    pida=$!
    CHILD_PIDS+=("$pida")

    if ! wait_for_lock "$lock" 10; then
        bad "case 1: inc-lcka never took the lock (could not measure)"; rm -rf "$tmp"; return 2
    fi

    INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lckb >"$tmp/b.out" 2>&1 &
    pidb=$!
    CHILD_PIDS+=("$pidb")

    sleep 2
    if is_ancestor "$tmp" "$sha_b"; then
        bad "case 1: inc-lckb was already merged while inc-lcka held the lock"
    else
        ok "case 1: inc-lckb had not merged 2 s in"
    fi
    if grep -q "inc-lcka is landing on master" "$tmp/b.out"; then
        ok "case 1: inc-lckb printed the waiting line naming inc-lcka"
    else
        bad "case 1: inc-lckb never named inc-lcka as the holder"
    fi

    if ! wait_pid "$pida" 30; then bad "case 1: inc-lcka did not finish"
    else [ "$WAIT_RC" -eq 0 ] || bad "case 1: inc-lcka exited $WAIT_RC, wanted 0"; fi
    if ! wait_pid "$pidb" 30; then bad "case 1: inc-lckb did not finish"
    else [ "$WAIT_RC" -eq 0 ] || bad "case 1: inc-lckb exited $WAIT_RC, wanted 0"; fi
    is_ancestor "$tmp" "$sha_a" && ok "case 1: inc-lcka is an ancestor of master" \
        || bad "case 1: inc-lcka is not an ancestor of master"
    is_ancestor "$tmp" "$sha_b" && ok "case 1: inc-lckb is an ancestor of master" \
        || bad "case 1: inc-lckb is not an ancestor of master"
    [ -d "$lock" ] && bad "case 1: the lock dir survived both landings" \
        || ok "case 1: the lock dir is gone"

    outa="$(cat "$tmp/a.out")"; outb="$(cat "$tmp/b.out")"
    # Kept for debugging a failure only if one of the above already failed.
    if [ "$FAIL" -ne 0 ]; then
        echo "---- inc-lcka output ----"; echo "$outa"
        echo "---- inc-lckb output ----"; echo "$outb"
    fi
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Case 2: a stale lock -- holder pid gone -- must be cleared, and the landing
# must go through.
# ---------------------------------------------------------------------------
case_stale() {
    local tmp lock sha status deadpid
    tmp="$(build_repo inc-lckc)" || { bad "case 2: could not build the repo"; return 2; }
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lckc)" || { bad "case 2: no inc-lckc commit"; rm -rf "$tmp"; return 2; }

    sh -c 'sleep 0' &
    deadpid=$!
    wait "$deadpid"
    if kill -0 "$deadpid" 2>/dev/null; then
        bad "case 2: could not produce a dead pid (could not measure)"
        rm -rf "$tmp"; return 2
    fi

    mkdir -p "$lock"
    printf '%s\n' "$deadpid" >"$lock/pid"
    printf '%s\n' "inc-dead" >"$lock/bead"
    printf '%s\n' "stale" >"$lock/started"

    INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lckc >"$tmp/c.out" 2>&1 &
    local pid=$!
    CHILD_PIDS+=("$pid")
    if wait_pid "$pid" 10; then
        status=$WAIT_RC
    else
        kill "$pid" 2>/dev/null
        bad "case 2: inc-lckc did not finish within 10 s"
        rm -rf "$tmp"; return 1
    fi
    [ "$status" -eq 0 ] || bad "case 2: inc-lckc exited $status, wanted 0"
    if grep -q "clearing a stale landing lock on master left by inc-dead" "$tmp/c.out"; then
        ok "case 2: named the stale holder inc-dead"
    else
        bad "case 2: did not print the stale-clearing line naming inc-dead"
    fi
    is_ancestor "$tmp" "$sha" && ok "case 2: inc-lckc is an ancestor of master" \
        || bad "case 2: inc-lckc is not an ancestor of master"
    [ -d "$lock" ] && bad "case 2: the stale lock dir survived" \
        || ok "case 2: the lock dir is gone"
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Case 3: a lock on a DIFFERENT base branch must not block a master landing,
# and must not even draw a waiting line.
# ---------------------------------------------------------------------------
case_per_branch() {
    local tmp other sha status
    tmp="$(build_repo inc-lckd)" || { bad "case 3: could not build the repo"; return 2; }
    other="$tmp/work/Incursion/.git/finish-bead-locks/other-branch.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lckd)" || { bad "case 3: no inc-lckd commit"; rm -rf "$tmp"; return 2; }

    mkdir -p "$other"
    printf '%s\n' "$$" >"$other/pid"
    printf '%s\n' "check_finish_bead_lock" >"$other/bead"
    ps -o lstart= -p "$$" >"$other/started" 2>/dev/null || printf 'live\n' >"$other/started"

    INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lckd >"$tmp/d.out" 2>&1 &
    local pid=$!
    CHILD_PIDS+=("$pid")
    if wait_pid "$pid" 10; then
        status=$WAIT_RC
    else
        kill "$pid" 2>/dev/null
        bad "case 3: inc-lckd did not finish within 10 s"
        rm -rf "$tmp"; return 1
    fi
    [ "$status" -eq 0 ] || bad "case 3: inc-lckd exited $status, wanted 0"
    if grep -q "is landing on master" "$tmp/d.out"; then
        bad "case 3: inc-lckd waited on the other-branch lock"
    else
        ok "case 3: no waiting line on a different base branch"
    fi
    is_ancestor "$tmp" "$sha" && ok "case 3: inc-lckd is an ancestor of master" \
        || bad "case 3: inc-lckd is not an ancestor of master"
    [ -d "$other" ] && ok "case 3: the other-branch lock is still there" \
        || bad "case 3: the other-branch lock was removed"
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Case 4: a landing killed mid-gate must release its lock, and leave master
# untouched.
# ---------------------------------------------------------------------------
case_interrupt() {
    local tmp lock sha pid status
    tmp="$(build_repo inc-lcke)" || { bad "case 4: could not build the repo"; return 2; }
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lcke)" || { bad "case 4: no inc-lcke commit"; rm -rf "$tmp"; return 2; }

    INCURSION_FINISH_GATE="sleep 3" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lcke >"$tmp/e.out" 2>&1 &
    pid=$!
    CHILD_PIDS+=("$pid")

    if ! wait_for_lock "$lock" 10; then
        kill "$pid" 2>/dev/null
        bad "case 4: inc-lcke never took the lock (could not measure)"
        rm -rf "$tmp"; return 2
    fi
    kill -TERM "$pid" 2>/dev/null
    if ! wait_pid "$pid" 15; then
        kill -KILL "$pid" 2>/dev/null
        bad "case 4: inc-lcke survived SIGTERM"
        rm -rf "$tmp"; return 1
    fi
    status=$WAIT_RC
    [ "$status" -ne 0 ] && ok "case 4: inc-lcke exited non-zero ($status) on SIGTERM" \
        || bad "case 4: inc-lcke exited 0 despite SIGTERM"
    [ -d "$lock" ] && bad "case 4: the lock dir survived the interrupt" \
        || ok "case 4: the lock dir is gone after SIGTERM"
    is_ancestor "$tmp" "$sha" && bad "case 4: inc-lcke reached master despite SIGTERM" \
        || ok "case 4: inc-lcke did not reach master"
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Case 5: a lock whose holder is LIVE but has not yet written `started` -- the
# window between acquire_lock's pid write and its started write -- must NOT be
# judged dead. A waiter used to compare lstart against "" (unequal for any live
# pid), clear a fresh lock, and let two landings run at once. inc-1npn.
#
# The planted lock holds the check's OWN pid, so kill -0 says it is alive;
# `started` is absent, so only the age rule can save it. The dir is fresh, so
# the live holder must be honoured: the landing waits. Removing the dir then
# lets the landing finish.
# ---------------------------------------------------------------------------
case_live_no_started() {
    local tmp lock sha pid status
    tmp="$(build_repo inc-lckf)" || { bad "case 5: could not build the repo"; return 2; }
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lckf)" || { bad "case 5: no inc-lckf commit"; rm -rf "$tmp"; return 2; }

    # A fresh lock held by a live pid, mid-write: pid and bead present, started
    # absent. $$ is this check's pid and is certainly alive.
    mkdir -p "$lock"
    printf '%s\n' "$$" >"$lock/pid"
    printf '%s\n' "inc-midwrite" >"$lock/bead"

    INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lckf >"$tmp/f.out" 2>&1 &
    pid=$!
    CHILD_PIDS+=("$pid")

    sleep 3
    if is_ancestor "$tmp" "$sha"; then
        bad "case 5: inc-lckf merged while a live holder had not written started"
    else
        ok "case 5: inc-lckf had not merged 3 s in"
    fi
    if grep -q "inc-midwrite is landing on master" "$tmp/f.out"; then
        ok "case 5: inc-lckf printed the waiting line naming inc-midwrite"
    else
        bad "case 5: inc-lckf never named inc-midwrite as the holder"
    fi

    # The live holder is gone now; the landing must proceed.
    rm -rf "$lock"
    if wait_pid "$pid" 10; then
        status=$WAIT_RC
        [ "$status" -eq 0 ] || bad "case 5: inc-lckf exited $status, wanted 0"
    else
        kill "$pid" 2>/dev/null
        bad "case 5: inc-lckf did not finish within 10 s of the lock being removed"
        rm -rf "$tmp"; return 1
    fi
    is_ancestor "$tmp" "$sha" && ok "case 5: inc-lckf is an ancestor of master" \
        || bad "case 5: inc-lckf is not an ancestor of master"

    if [ "$FAIL" -ne 0 ]; then
        echo "---- inc-lckf output ----"; cat "$tmp/f.out"
    fi
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Case 6: a landing killed INSIDE acquire_lock's critical section -- between
# mkdir taking the lock dir and LOCK_HELD=1 -- must still release the lock and
# leave master untouched. A SIGTERM landing in that window used to exit with the
# lock dir left behind, so the next landing waited on a corpse. `ps` is stubbed
# to sleep, stretching the window wide enough to hit reliably. inc-fdkz.
# ---------------------------------------------------------------------------
case_interrupt_in_window() {
    local tmp lock sha pid status
    tmp="$(build_repo inc-lckw)" || { bad "case 6: could not build the repo"; return 2; }
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lckw)" || { bad "case 6: no inc-lckw commit"; rm -rf "$tmp"; return 2; }

    mkdir -p "$tmp/bin" || { bad "case 6: could not make the stub bin"; rm -rf "$tmp"; return 2; }
    printf '#!/bin/sh\nsleep 3\nexec /bin/ps "$@"\n' >"$tmp/bin/ps" || {
        bad "case 6: could not write the ps stub"; rm -rf "$tmp"; return 2; }
    chmod +x "$tmp/bin/ps" || { bad "case 6: could not chmod the ps stub"; rm -rf "$tmp"; return 2; }

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="sleep 3" INCURSION_FINISH_LOCK_POLL=1 \
        "$copy" inc-lckw >"$tmp/w.out" 2>&1 &
    pid=$!
    CHILD_PIDS+=("$pid")

    if ! wait_for_lock "$lock" 10; then
        kill "$pid" 2>/dev/null
        bad "case 6: inc-lckw never took the lock (could not measure)"
        rm -rf "$tmp"; return 2
    fi
    # The child is inside its slow `ps`, i.e. inside the window.
    kill -TERM "$pid" 2>/dev/null
    if ! wait_pid "$pid" 15; then
        kill -KILL "$pid" 2>/dev/null
        bad "case 6: inc-lckw survived SIGTERM"
        rm -rf "$tmp"; return 1
    fi
    status=$WAIT_RC
    [ "$status" -ne 0 ] && ok "case 6: inc-lckw exited non-zero ($status) on SIGTERM" \
        || bad "case 6: inc-lckw exited 0 despite SIGTERM"
    [ -d "$lock" ] && bad "case 6: the lock dir survived the interrupt" \
        || ok "case 6: the lock dir is gone after SIGTERM"
    is_ancestor "$tmp" "$sha" && bad "case 6: inc-lckw reached master despite SIGTERM" \
        || ok "case 6: inc-lckw did not reach master"
    if [ "$FAIL" -ne 0 ]; then
        echo "---- inc-lckw output ----"; cat "$tmp/w.out"
    fi
    rm -rf "$tmp"
    return 0
}

MEASURED=0
for c in case_serialisation case_stale case_per_branch case_interrupt case_live_no_started case_interrupt_in_window; do
    "$c"; rc=$?
    [ "$rc" -eq 2 ] && MEASURED=1
done

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
if [ "$MEASURED" -ne 0 ]; then
    exit 2
fi
echo "PASS"
exit 0
