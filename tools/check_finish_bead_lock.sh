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
# Cases 7-9 (inc-7sx7t) check the first-come, first-served queue: landings that
# start waiting in the order A, B, C take the lock in that order; a kill -9 of
# the head waiter, or of the holder, does not stall or reorder those behind it.
# Case 3 also plants a ticket on a different base to show the queue is per base.
# Cases 10-12 (inc-7sx7t) check the hung-landing guard (tools/slow_check_watch.py
# --hung-landing, started by acquire_lock): a landing that runs past 2x a faked
# predicted time writes exactly one ALERT with a sample and still finishes with
# its own exit code; one within 2x, or with no predicted time, writes nothing.
# Cases 7-12 run side by side, each in its own scratch repo, to keep the wall time.
#
#   tools/check_finish_bead_lock.sh --prove-red   (0 when both mutations go red)
#
# --prove-red runs two mutations. (1) The head test takes the HIGHEST live ticket,
# not the lowest, on the copied script: cases 7-9 must fail. (2) SLOW_WATCH_MUTATE=
# invert-threshold breaks the 2x comparison: case 10 must fail.
#
# fact: landing order -- each landing's gate appends its bead to a file, and a landing waits on a ticket held by its predecessor (wait_ticket), not on a sleep
# fact: when a landing holds its place -- wait_ticket polls for its ticket file with a deadline
# fact: the holder is released -- the check creates a go file; INCURSION_FINISH_GATE waits on it with a 60 s cap
# fact: poll interval -- INCURSION_FINISH_LOCK_POLL=0.3
# fact: machine load -- INCURSION_LOAD_GUARD_OFF=1, and gate: cheap, gate-serial
# fact: the gate's predicted time (cases 10-12) -- INCURSION_LANDING_PREDICTED_S, a test-only fake: 1 s, 4 s, unset; the real gate status file is never read (scratch logs/gate-status is empty)
# fact: how long a guarded landing runs (cases 10-12) -- INCURSION_FINISH_GATE is a fixed sleep (5 s, 1 s, 2 s) against a 2 s, 8 s, none limit
# fact: the load named in the alert -- INCURSION_LOAD_GUARD_FAKE_LOAD=7.25
# fact: the alert file and sample directory -- INCURSION_FAST_ALERT_FILE in the case's own mktemp dir
# fact: the sample's content -- only that it exists and is not empty, never matched
# fact: the real bead database and repository -- a scratch repo and a fake bd under mktemp (build_repo)
#
# It is `gate: cheap` so the gate runs it automatically, which means it MUST
# finish fast and MUST NOT hang. INCURSION_FINISH_GATE below substitutes a
# sleep or `true` for the real gate, INCURSION_FINISH_LOCK_POLL=0.3 keeps the
# wait loop snappy, and every wait has a deadline; a bug that would hang the
# gate fails the case instead.
set -uo pipefail

# A scratch repository answers to nothing the person running this has configured.
unset INCURSION_FINISH_GATE INCURSION_BASE_BRANCH INCURSION_FINISH_LOCK_POLL \
      NIGHTLY_VERIFY_STATE NIGHTLY_CHECK_DIR NIGHTLY_BASE_REF \
      INCURSION_LANDING_PREDICTED_S INCURSION_FAST_ALERT_FILE SLOW_WATCH_MUTATE \
      INCURSION_GATE_STATUS_DIR INCURSION_CHECK_TIMING_LOG

# A fixture landing tests the lock and merge, not machine load (inc-rwha).
export INCURSION_LOAD_GUARD_OFF=1

PROVE_RED=0
MUTATE=0
case "${1:-}" in
    --prove-red) PROVE_RED=1; MUTATE=1 ;;
    "") ;;
    *) echo "usage: $0 [--prove-red]" >&2; exit 2 ;;
esac

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
    git -C "$tmp/work/Incursion" config merge.landed.driver true || return 1
    git -C "$tmp/work/Incursion" config merge.landed-ledger.driver true || return 1
    echo base >"$tmp/work/Incursion/base.txt" || return 1
    echo "base docs" >"$tmp/work/Incursion/DOCS.md" || return 1
    git -C "$tmp/work/Incursion" add base.txt DOCS.md || return 1
    git -C "$tmp/work/Incursion" commit -q -m initial || return 1
    git -C "$tmp/work/Incursion" branch master trunk || return 1

    cp "$SCRIPT" "$tmp/work/Incursion/tools/finish_bead.sh" || return 1
    cp "$DOCS_ONLY" "$tmp/work/Incursion/tools/docs_only_change.sh" || return 1
    if [ "$MUTATE" -eq 1 ]; then
        # The head test takes the highest live ticket. The copy MUST change.
        sed -i '' 's/sort # queue-order/sort -r # queue-order/' \
            "$tmp/work/Incursion/tools/finish_bead.sh" || return 1
        cmp -s "$SCRIPT" "$tmp/work/Incursion/tools/finish_bead.sh" && return 1
    fi
    # STEP 2b runs check_bead_evidence.py, which runs bd show. The fake bd
    # gives every bead one acceptance criterion and never reaches the real
    # bead database (inc-v4xe). Each bead branch carries the AC1 evidence
    # commit its criterion needs; with none, the landing refuses (inc-ut6bb).
    cp "$ROOT/tools/slow_check_watch.py" \
        "$tmp/work/Incursion/tools/slow_check_watch.py" || return 1
    cp "$ROOT/tools/check_bead_evidence.py" \
        "$tmp/work/Incursion/tools/check_bead_evidence.py" || return 1
    mkdir -p "$tmp/bin" || return 1
    cat >"$tmp/bin/bd" <<'FAKE' || return 1
#!/bin/sh
if [ "$1" = show ] && [ "$3" = --json ]; then
    printf '[{"id":"%s","status":"open","description":"## Acceptance Criteria\\n- the scratch bead lands\\n","notes":""}]\n' "$2"
    exit 0
fi
echo "unknown bead" >&2
exit 1
FAKE
    chmod +x "$tmp/bin/bd" || return 1

    for bead in "$@"; do
        git -C "$tmp/work/Incursion" worktree add -q -b "$bead" \
            "$tmp/work/Incursion-$bead" master || return 1
        echo "$bead" >"$tmp/work/Incursion-$bead/$bead.txt" || return 1
        git -C "$tmp/work/Incursion-$bead" add "$bead.txt" || return 1
        git -C "$tmp/work/Incursion-$bead" commit -q -m "$bead work" || return 1
        git -C "$tmp/work/Incursion-$bead" commit -q --allow-empty \
            -m "evidence ($bead)" -m "AC1: observed the scratch bead work" || return 1
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

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="sleep 3" INCURSION_FINISH_LOCK_POLL=0.3 \
        "$copy" inc-lcka >"$tmp/a.out" 2>&1 &
    pida=$!
    CHILD_PIDS+=("$pida")

    if ! wait_for_lock "$lock" 10; then
        bad "case 1: inc-lcka never took the lock (could not measure)"; rm -rf "$tmp"; return 2
    fi

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=0.3 \
        "$copy" inc-lckb >"$tmp/b.out" 2>&1 &
    pidb=$!
    CHILD_PIDS+=("$pidb")

    sleep 1
    if is_ancestor "$tmp" "$sha_b"; then
        bad "case 1: inc-lckb was already merged while inc-lcka held the lock"
    else
        ok "case 1: inc-lckb had not merged 1 s in"
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

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=0.3 \
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
    local other_q="$tmp/work/Incursion/.git/finish-bead-locks/other-branch.queue"
    local copy="$tmp/work/Incursion/tools/finish_bead.sh"
    sha="$(bead_sha "$tmp" inc-lckd)" || { bad "case 3: no inc-lckd commit"; rm -rf "$tmp"; return 2; }

    mkdir -p "$other"
    printf '%s\n' "$$" >"$other/pid"
    printf '%s\n' "check_finish_bead_lock" >"$other/bead"
    ps -o lstart= -p "$$" >"$other/started" 2>/dev/null || printf 'live\n' >"$other/started"

    # A live waiter's ticket on the other base must not delay a master landing.
    mkdir -p "$other_q/0000000001"
    printf '%s\n' "$$" >"$other_q/0000000001/pid"
    printf '%s\n' "check_finish_bead_lock" >"$other_q/0000000001/bead"
    ps -o lstart= -p "$$" >"$other_q/0000000001/started" 2>/dev/null || printf 'live\n' >"$other_q/0000000001/started"

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=0.3 \
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
    if grep -q "waiting on master" "$tmp/d.out"; then
        bad "case 3: inc-lckd queued behind a ticket on the other base"
    else
        ok "case 3: no queue wait behind a ticket on a different base"
    fi
    [ -d "$other_q/0000000001" ] && ok "case 3: the other-branch ticket is still there" \
        || bad "case 3: the other-branch ticket was removed"
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

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="sleep 2" INCURSION_FINISH_LOCK_POLL=0.3 \
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

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="true" INCURSION_FINISH_LOCK_POLL=0.3 \
        "$copy" inc-lckf >"$tmp/f.out" 2>&1 &
    pid=$!
    CHILD_PIDS+=("$pid")

    sleep 1.5
    if is_ancestor "$tmp" "$sha"; then
        bad "case 5: inc-lckf merged while a live holder had not written started"
    else
        ok "case 5: inc-lckf had not merged 1.5 s in"
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
    printf '#!/bin/sh\nsleep 1.5\nexec /bin/ps "$@"\n' >"$tmp/bin/ps" || {
        bad "case 6: could not write the ps stub"; rm -rf "$tmp"; return 2; }
    chmod +x "$tmp/bin/ps" || { bad "case 6: could not chmod the ps stub"; rm -rf "$tmp"; return 2; }

    PATH="$tmp/bin:$PATH" INCURSION_FINISH_GATE="sleep 3" INCURSION_FINISH_LOCK_POLL=0.3 \
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

# ---------------------------------------------------------------------------
# Cases 7-9: the landing queue. inc-7sx7t. Holder H holds the lock until the
# check creates a go file; A, B, C then start waiting in that order, each holding
# its ticket before the next starts. Every gate appends its bead to an order file.
#   order:      A, B, C take the lock in order A, B, C.
#   killhead:   kill -9 on A while it waits; B then C follow.
#   killholder: kill -9 on H; A takes the lock by stale recovery, then B, C.
# ---------------------------------------------------------------------------
wait_ticket() { # wait_ticket <queuedir> <bead> <seconds>
    local deadline=$(( $(date +%s) + $3 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        grep -lx "$2" "$1"/*/bead >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    return 1
}

LPID=0
start_landing() { # start_landing <tmp> <bead> <gate>; sets LPID
    PATH="$1/bin:$PATH" INCURSION_FINISH_GATE="$3" INCURSION_FINISH_LOCK_POLL=0.3 \
        "$1/work/Incursion/tools/finish_bead.sh" "$2" >"$1/$2.out" 2>&1 &
    LPID=$!
    CHILD_PIDS+=("$LPID")
}

run_queue_case() { # run_queue_case <n> <order|killhead|killholder>
    local n="$1" mode="$2" tmp q lock order go want got p
    local pids=() holdpid apid
    tmp="$(build_repo inc-qlh inc-qla inc-qlb inc-qlc)" || { bad "case $n: could not build the repo"; return 2; }
    q="$tmp/work/Incursion/.git/finish-bead-locks/master.queue"
    lock="$tmp/work/Incursion/.git/finish-bead-locks/master.lock"
    order="$tmp/order"; go="$tmp/go"
    : >"$order"

    start_landing "$tmp" inc-qlh "echo inc-qlh >>$order; i=0; while [ ! -f $go ] && [ \$i -lt 300 ]; do sleep 0.2; i=\$((i+1)); done"
    holdpid=$LPID
    if ! wait_for_lock "$lock" 15; then
        bad "case $n: inc-qlh never took the lock (could not measure)"
        touch "$go"; rm -rf "$tmp"; return 2
    fi
    local dl=$(( $(date +%s) + 30 ))
    while [ ! -s "$order" ] && [ "$(date +%s)" -lt "$dl" ]; do sleep 0.2; done
    if [ ! -s "$order" ]; then
        bad "case $n: inc-qlh never reached its gate (could not measure)"
        touch "$go"; rm -rf "$tmp"; return 2
    fi

    start_landing "$tmp" inc-qla "echo inc-qla >>$order"; apid=$LPID; pids+=("$apid")
    wait_ticket "$q" inc-qla 15 || { bad "case $n: inc-qla took no ticket"; touch "$go"; rm -rf "$tmp"; return 2; }
    start_landing "$tmp" inc-qlb "echo inc-qlb >>$order"; pids+=("$LPID")
    wait_ticket "$q" inc-qlb 15 || { bad "case $n: inc-qlb took no ticket"; touch "$go"; rm -rf "$tmp"; return 2; }
    start_landing "$tmp" inc-qlc "echo inc-qlc >>$order"; pids+=("$LPID")
    wait_ticket "$q" inc-qlc 15 || { bad "case $n: inc-qlc took no ticket"; touch "$go"; rm -rf "$tmp"; return 2; }

    case "$mode" in
        order)
            want="inc-qlh inc-qla inc-qlb inc-qlc"
            grep -q "position 1, behind inc-qlh" "$tmp/inc-qla.out" \
                && ok "case $n: inc-qla is position 1 behind inc-qlh" \
                || bad "case $n: inc-qla did not report position 1 behind inc-qlh"
            grep -q "position 2, behind inc-qla" "$tmp/inc-qlb.out" \
                && ok "case $n: inc-qlb is position 2 behind inc-qla" \
                || bad "case $n: inc-qlb did not report position 2 behind inc-qla"
            grep -q "position 3, behind inc-qlb" "$tmp/inc-qlc.out" \
                && ok "case $n: inc-qlc is position 3 behind inc-qlb" \
                || bad "case $n: inc-qlc did not report position 3 behind inc-qlb"
            touch "$go" ;;
        killhead)
            want="inc-qlh inc-qlb inc-qlc"
            kill -KILL "$apid" 2>/dev/null; wait "$apid" 2>/dev/null
            pids=("${pids[@]:1}")
            touch "$go" ;;
        killholder)
            want="inc-qlh inc-qla inc-qlb inc-qlc"
            kill -KILL "$holdpid" 2>/dev/null; wait "$holdpid" 2>/dev/null
            holdpid=0
            touch "$go" ;;
    esac

    for p in "${pids[@]}"; do
        if wait_pid "$p" 60; then
            [ "$WAIT_RC" -eq 0 ] || bad "case $n: a landing exited $WAIT_RC, wanted 0"
        else
            kill "$p" 2>/dev/null
            bad "case $n: a landing did not finish within 60 s"
        fi
    done
    [ "$holdpid" -ne 0 ] && { wait_pid "$holdpid" 30 || bad "case $n: inc-qlh did not finish"; }

    got="$(tr '\n' ' ' <"$order" | sed 's/ $//')"
    [ "$got" = "$want" ] && ok "case $n ($mode): landings took the lock in order: $got" \
        || bad "case $n ($mode): lock order was '$got', wanted '$want'"
    [ -z "$(ls "$q" 2>/dev/null)" ] && ok "case $n ($mode): no ticket is left" \
        || bad "case $n ($mode): tickets left in the queue: $(ls "$q" | tr '\n' ' ')"
    [ -d "$lock" ] && bad "case $n ($mode): the lock dir survived" \
        || ok "case $n ($mode): the lock dir is gone"
    if [ "$FAIL" -ne 0 ]; then
        for p in inc-qlh inc-qla inc-qlb inc-qlc; do
            echo "---- $p output ----"; cat "$tmp/$p.out"
        done
    fi
    rm -rf "$tmp"
    return 0
}

case_queue_order()      { run_queue_case 7 order; }
case_queue_killhead()   { run_queue_case 8 killhead; }
case_queue_killholder() { run_queue_case 9 killholder; }

# ---------------------------------------------------------------------------
# Cases 10-12: the hung-landing guard. inc-7sx7t. Three landings run side by
# side, each with its own scratch repo and alert file:
#   10: gate sleeps 5 s, predicted 1 s -> one ALERT after 2 s, with a sample.
#   11: gate sleeps 1 s, predicted 4 s -> within 2x: no ALERT, no sample.
#   12: gate sleeps 2 s, no predicted time -> no ALERT, no sample.
# The landing's exit code and merge must not change in any of them.
# ---------------------------------------------------------------------------
start_guarded() { # start_guarded <tmp> <bead> <gate> <predicted|-> ; sets LPID
    local pred=()
    [ "$4" != "-" ] && pred=(INCURSION_LANDING_PREDICTED_S="$4")
    env PATH="$1/bin:$PATH" INCURSION_FINISH_GATE="$3" INCURSION_FINISH_LOCK_POLL=0.3 \
        INCURSION_FAST_ALERT_FILE="$1/alert/fast-alert.log" INCURSION_LOAD_GUARD_FAKE_LOAD=7.25 \
        ${pred[@]+"${pred[@]}"} \
        "$1/work/Incursion/tools/finish_bead.sh" "$2" >"$1/$2.out" 2>&1 &
    LPID=$!
    CHILD_PIDS+=("$LPID")
}

case_hung_guard() {
    local ta tb tc pa pb pc sha_a sha_b sha_c alert line n el pr sample dl
    ta="$(build_repo inc-hga)" || { bad "case 10: could not build the repo"; return 2; }
    tb="$(build_repo inc-hgb)" || { bad "case 11: could not build the repo"; return 2; }
    tc="$(build_repo inc-hgc)" || { bad "case 12: could not build the repo"; return 2; }
    sha_a="$(bead_sha "$ta" inc-hga)"; sha_b="$(bead_sha "$tb" inc-hgb)"; sha_c="$(bead_sha "$tc" inc-hgc)"
    start_guarded "$ta" inc-hga "sleep 5" 1; pa=$LPID
    start_guarded "$tb" inc-hgb "sleep 1" 4; pb=$LPID
    start_guarded "$tc" inc-hgc "sleep 2" -; pc=$LPID

    wait_pid "$pa" 60 && { [ "$WAIT_RC" -eq 0 ] && ok "case 10: the over-long landing still exited 0" \
        || bad "case 10: the over-long landing exited $WAIT_RC, wanted 0"; } || { kill "$pa" 2>/dev/null; bad "case 10: landing did not finish"; }
    wait_pid "$pb" 60 && { [ "$WAIT_RC" -eq 0 ] && ok "case 11: the landing within 2x exited 0" \
        || bad "case 11: the landing within 2x exited $WAIT_RC, wanted 0"; } || { kill "$pb" 2>/dev/null; bad "case 11: landing did not finish"; }
    wait_pid "$pc" 60 && { [ "$WAIT_RC" -eq 0 ] && ok "case 12: the landing with no prediction exited 0" \
        || bad "case 12: the landing with no prediction exited $WAIT_RC, wanted 0"; } || { kill "$pc" 2>/dev/null; bad "case 12: landing did not finish"; }
    is_ancestor "$ta" "$sha_a" && ok "case 10: the landing reached master" || bad "case 10: the landing did not reach master"
    is_ancestor "$tb" "$sha_b" && ok "case 11: the landing reached master" || bad "case 11: the landing did not reach master"
    is_ancestor "$tc" "$sha_c" && ok "case 12: the landing reached master" || bad "case 12: the landing did not reach master"

    # The sample may still be running when the landing is gone; wait for the line.
    alert="$ta/alert/fast-alert.log"
    dl=$(( $(date +%s) + 15 ))
    while ! grep -q '^ALERT hung-landing' "$alert" 2>/dev/null && [ "$(date +%s)" -lt "$dl" ]; do sleep 0.3; done
    sleep 1
    n="$(grep -c '^ALERT hung-landing' "$alert" 2>/dev/null)"
    [ "${n:-0}" = 1 ] && ok "case 10: exactly one ALERT hung-landing" || bad "case 10: want one ALERT, found ${n:-0}"
    line="$(grep '^ALERT hung-landing' "$alert" 2>/dev/null | head -1)"
    for pat in 'inc-hga on master:' 'predicted 1s' 'load 7.25' 'sample /'; do
        grep -q -- "$pat" <<<"$line" && ok "case 10: the alert names: $pat" || bad "case 10: the alert lacks: $pat"
    done
    el="$(sed -n 's/.* elapsed \([0-9]*\)s .*/\1/p' <<<"$line")"; pr="$(sed -n 's/.* predicted \([0-9]*\)s .*/\1/p' <<<"$line")"
    [ -n "$el" ] && [ -n "$pr" ] && [ "$el" -ge $((2 * pr)) ] && ok "case 10: the alert came at or after 2x predicted (${el}s >= 2 x ${pr}s)" \
        || bad "case 10: the alert came before 2x predicted (elapsed '${el}', predicted '${pr}')"
    sample="$(sed -n 's/.* sample //p' <<<"$line")"
    [ -n "$sample" ] && [ -s "$sample" ] && ok "case 10: the sample file exists and is not empty" \
        || bad "case 10: the sample file is missing or empty: '$sample'"
    [ "$(ls "$ta"/alert/hung-sample-* 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "case 10: exactly one sample file" \
        || bad "case 10: want exactly one sample file"

    [ ! -s "$tb/alert/fast-alert.log" ] && [ -z "$(ls "$tb/alert" 2>/dev/null | grep -v '^fast-alert.log$')" ] \
        && ok "case 11: no ALERT and no sample within 2x" || bad "case 11: an alert or sample appeared within 2x"
    [ ! -s "$tc/alert/fast-alert.log" ] && [ -z "$(ls "$tc/alert" 2>/dev/null | grep -v '^fast-alert.log$')" ] \
        && ok "case 12: no ALERT and no sample without a predicted time" || bad "case 12: an alert or sample appeared with no prediction"
    if [ "$FAIL" -ne 0 ]; then
        echo "---- case 10 alert ----"; cat "$alert" 2>/dev/null; echo "---- inc-hga output ----"; cat "$ta/inc-hga.out"
    fi
    rm -rf "$ta" "$tb" "$tc"
    return 0
}

# run_parallel <case>...: run each case in a subshell side by side, then print
# their output in order. A case reports through FAIL:/PASS: lines and rc 2 (could
# not measure); the subshell's own FAIL variable is lost, so read it from the text.
PAR_OUT=""
run_parallel() {
    local c i=0 pids=() outs=() rc
    PAR_OUT="$(mktemp -d "${TMPDIR:-/tmp}/finish-bead-par.XXXXXX")" || { bad "could not make the output dir"; return 2; }
    for c in "$@"; do
        ( CHILD_PIDS=(); trap cleanup EXIT; "$c"; echo $? >"$PAR_OUT/$i.rc" ) >"$PAR_OUT/$i.out" 2>&1 &
        pids+=($!); outs+=("$PAR_OUT/$i.out"); i=$((i + 1))
    done
    for i in "${!pids[@]}"; do wait "${pids[$i]}"; done
    PAR_RC=0
    for i in "${!outs[@]}"; do
        cat "${outs[$i]}"
        rc="$(cat "$PAR_OUT/$i.rc" 2>/dev/null || echo 2)"
        [ "$rc" -eq 2 ] && PAR_RC=2
    done
    grep -q '^FAIL' "$PAR_OUT"/*.out 2>/dev/null && FAIL=1
    rm -rf "$PAR_OUT"
    return "$PAR_RC"
}

PAR_RC=0
if [ "$PROVE_RED" -eq 1 ]; then
    RED=0
    out="$(run_parallel case_queue_order case_queue_killhead case_queue_killholder 2>&1)"
    for n in 7 8 9; do
        if grep -q "^FAIL: case $n (" <<<"$out"; then
            echo "RED (wanted): case $n failed under the broken queue order"
        else
            echo "NOT RED: case $n passed or could not run under the broken queue order"
            printf '%s\n' "$out" | grep -E "^(PASS|FAIL): case $n" | head -8
            RED=1
        fi
    done
    MUTATE=0
    SLOW_WATCH_MUTATE=invert-threshold
    export SLOW_WATCH_MUTATE
    out="$(run_parallel case_hung_guard 2>&1)"
    if grep -q '^FAIL: case 10:' <<<"$out"; then
        echo "RED (wanted): case 10 failed under the broken 2x comparison"
    else
        echo "NOT RED: case 10 passed or could not run under the broken 2x comparison"
        printf '%s\n' "$out" | grep -E '^(PASS|FAIL): case 1[0-2]' | head -8
        RED=1
    fi
    unset SLOW_WATCH_MUTATE
    # Restored: the same cases must be green again without the mutations.
    MUTATE=0
    out="$(run_parallel case_queue_order case_hung_guard 2>&1)"
    if grep -q '^FAIL' <<<"$out"; then
        echo "NOT GREEN: cases 7 and 10-12 failed with the mutations removed"
        printf '%s\n' "$out" | grep '^FAIL' | head -8
        RED=1
    else
        echo "GREEN (wanted): cases 7 and 10-12 pass with the mutations removed"
    fi
    exit "$RED"
fi

MEASURED=0
for c in case_serialisation case_stale case_per_branch case_interrupt case_live_no_started case_interrupt_in_window; do
    "$c"; rc=$?
    [ "$rc" -eq 2 ] && MEASURED=1
done
run_parallel case_queue_order case_queue_killhead case_queue_killholder case_hung_guard
[ "$PAR_RC" -eq 2 ] && MEASURED=1

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
if [ "$MEASURED" -ne 0 ]; then
    exit 2
fi
echo "PASS"
exit 0
