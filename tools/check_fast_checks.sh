#!/usr/bin/env bash
# gate: cheap
#
# Does tools/fast_checks.sh still bite? Plant fake checks in a temp directory,
# run the runner over them with --dir, and demand each verdict. The runner judges
# a fast check by the KIND of work it does (game, build, git-history, sleep, bd,
# compiler) and watches progress, never wall-clock time (bead inc-rst61).
#
#   tools/check_fast_checks.sh              run every case
#   tools/check_fast_checks.sh --prove-red  run the AC1 game case and the AC4
#                                           unwatched case against the OLD runner
#                                           (master's tools/fast_checks.sh) and
#                                           demand both FAIL: "RED as expected"
#
# Cases:
#   a.   one passing fast check                 -> exit 0
#   b.   add one failing fast check             -> exit 1, naming that check
#   d.   a check with no gate-fast marker       -> never run
#   e.   an empty directory                     -> exit 2
#   f.   check_worktree_untracked.sh clean/untracked/ignored in a scratch git repo
#        -> 0 / 1 / 0
#   i.   check_worktree_untracked.sh lists "a b.txt" as one line
#   h.   a check exiting 2 alone                -> 0, output says UNMEASURED
#   j.   a failing check and a HANG, guard faked to refuse -> OVERLOADED line, exit 1
#   j2.  the runs log one timing row per check
#   k.   a failing check, guard faked idle      -> no OVERLOADED line
#   l.   all checks pass, guard faked to refuse -> 0, no OVERLOADED line
#   m.   a check that starts a background child and exits -> the child is dead
#        after the runner returns
#   AC1  one fake per kind (game, build, git-history, sleep, bd, compiler) is
#        refused with EXPENSIVE naming the kind; `git log -1`, a killed
#        placeholder sleep, and a fake named check_upstream_label.sh calling bd
#        (vetted) are ok; a fake naming /bin/sleep by full path is EXPENSIVE; the
#        advice offers marker removal for `# gate: cheap` and not for `# gate: none`
#   AC2  one ok, one EXPENSIVE and one FAIL, run normally and under
#        `taskpolicy -c background` -> identical verdicts (seconds stripped)
#   AC3  a real fast check copied unchanged -> ok; the same copy with one line
#        calling headless.sh added -> EXPENSIVE game
#   AC4  a check blocked on a fifo: watched -> an ALERT line while the runner still
#        runs, and the fake is gone once the runner's group is stopped; unwatched
#        -> HANG (not EXPENSIVE), and the alert file holds the HANG line
#   AC4 vetted bd wait  a fake bd blocking past the stall limit under the vetted
#        check_upstream_label.sh: ok, no alert line, watched and unwatched; the
#        same call from an unvetted check is EXPENSIVE bd
#   AC5  --prove-red (above)
#
# inc-rst61: a check's verdict must not depend on how busy the machine is. Every
# fact this check reads, and the control that fixes it:
# fact: machine load, memory pressure, core type (performance or efficiency) -- every case sets INCURSION_FAST_STALL=30 and INCURSION_FAST_CPU=1000 so no ordinary fake can trip a limit, only the fakes that block forever use INCURSION_FAST_STALL=1, INCURSION_LOAD_GUARD_FAKE_LOAD/_NCPU/_PRESSURE fix the guard, and AC2 reruns the set under taskpolicy -c background
# fact: which checks pass, fail, hang or are refused -- fakes planted in a temp dir via --dir, each case sets the mode (INCURSION_FAST_WATCHED) itself
# fact: the vetted list entry for check_upstream_label.sh -- the case first greps tools/fast_checks.vetted for that line and fails by name when it is absent
# fact: the real bd, git and clang++ binaries a fake calls -- the stand-in records the call before the real binary runs, and every fake ignores the real binary's status and output
# fact: the real check copied in AC3 (check_devour_prose.sh) passes on this tree -- the case runs the original first and fails by name as a precondition when it does not
# fact: logs/fast-alert.log -- the runner always appends to it, so the case counts its lines before the run and reads only the lines after
# fact: master's tools/fast_checks.sh -- read only by --prove-red, via git show master
# fact: seed, character, map, options -- none read; no case starts a game session
#
# The fast runner globs <dir>/check_*.sh, so every fake here is one of those.
# Each is `chmod +x` and carries `# gate: cheap` (unless the case needs otherwise)
# and a `# gate-fast: <reason>` marker unless the case is about a file that must
# NOT have one.
#
# Exit: 0 every assertion held (--prove-red: both cases failed as expected)
#       1 any assertion failed
#       2 could not measure (mktemp failed, bad argument, no master copy)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
RUNNER="$ROOT/tools/fast_checks.sh"
WT="$ROOT/tools/check_worktree_untracked.sh"
ALERT_FILE="$ROOT/logs/fast-alert.log"

PROVE_RED=0
case "${1:-}" in
    "") ;;
    --prove-red) PROVE_RED=1 ;;
    *) echo "usage: $0 [--prove-red]" >&2; exit 2 ;;
esac

fails=0
report() { # report <ok|FAIL> <label>
    if [ "$1" = ok ]; then
        printf 'PASS  %s\n' "$2"
    else
        printf 'FAIL  %s\n' "$2"
        fails=$((fails + 1))
    fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check_fast_checks.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
# inc-b0ziu.8: no case may write the real timing log.
export INCURSION_CHECK_TIMING_LOG="$TMP/check-timing.tsv"
# The guard is faked idle unless a case says otherwise; limits are loose.
export INCURSION_LOAD_GUARD_FAKE_LOAD=1.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 INCURSION_LOAD_GUARD_FAKE_PRESSURE=1
export INCURSION_FAST_STALL=30 INCURSION_FAST_CPU=1000

mkdir -p "$ROOT/logs" || exit 2
touch "$ALERT_FILE" || exit 2

plant() { # plant <dir> <name> <gate-or-empty> <marker-or-empty> <body line>...
    local dir="$1" name="$2" gate="$3" marker="$4"
    shift 4
    mkdir -p "$dir"
    {
        printf '#!/usr/bin/env bash\n'
        [ -n "$gate" ] && printf '# gate: %s\n' "$gate"
        [ -n "$marker" ] && printf '# gate-fast: %s\n' "$marker"
        printf '%s\n' "$@"
    } > "$dir/$name"
    chmod +x "$dir/$name"
}

# runner <watched|unwatched> <dir> [VAR=val...] -- the runner's output, one stream.
# $PFX, when set, is a command prefix (the taskpolicy case).
PFX=""
runner() {
    local mode="$1" dir="$2" cc=""
    shift 2
    [ "$mode" = watched ] && cc=1
    # shellcheck disable=SC2086
    ( cd "$ROOT" && $PFX env -u INCURSION_FAST_WATCHED ${cc:+INCURSION_FAST_WATCHED=1} "$@" "$RUNNER" --dir "$dir" 2>&1 )
}

# block <output> <name> -- the verdict line for <name> and its indented lines.
block() {
    printf '%s\n' "$1" | awk -v n="$2" '
        index($0, "EXPENSIVE " n " ") == 1 || index($0, "HANG " n) == 1 || index($0, "FAIL " n " ") == 1 { p = 1; print; next }
        p && /^    / { print; next }
        { p = 0 }'
}

# strip elapsed seconds so two runs compare
strip_secs() { sed -E 's/\([0-9]+s\)/(Ns)/; s/, [0-9]+s\)/, Ns)/'; }

# ---- the AC cases are functions so --prove-red can run two of them against
# another runner. Each returns 0 when the verdict holds, and sets WHY otherwise.
WHY=""

case_ac1_game() {
    local d="$TMP/d_ac1g" out rc
    rm -rf "$d"
    plant "$d" check_g_game.sh cheap "fake" "\"$ROOT/tools/headless.sh\" >/dev/null 2>&1; exit 0"
    out="$(runner unwatched "$d")"; rc=$?
    case "$out" in
        *"EXPENSIVE check_g_game.sh (game:"*) [ "$rc" -eq 1 ] && return 0 ;;
    esac
    WHY="no EXPENSIVE game verdict (exit $rc): $(printf '%s' "$out" | head -4 | tr '\n' '|')"
    return 1
}

case_ac4_unwatched() {
    # args: extra VAR=val for the runner (the CLAUDECODE case passes CLAUDECODE=1)
    local d="$TMP/d_ac4u" fifo="$TMP/ac4u.fifo" base out rc lines
    rm -rf "$d" "$fifo"; mkfifo "$fifo"
    plant "$d" check_blocked.sh cheap "blocks forever" "read x < '$fifo'" "exit 0"
    base="$(wc -l < "$ALERT_FILE")"
    out="$(runner unwatched "$d" INCURSION_FAST_STALL=1 "$@")"; rc=$?
    lines="$(tail -n +$((base + 1)) "$ALERT_FILE")"
    case "$out" in *"EXPENSIVE check_blocked.sh"*) WHY="blocked check called EXPENSIVE"; return 1 ;; esac
    case "$out" in *"HANG check_blocked.sh"*) ;; *) WHY="no HANG verdict (exit $rc)"; return 1 ;; esac
    case "$lines" in *"HANG check_blocked.sh "*) ;; *) WHY="no HANG line in the alert file"; return 1 ;; esac
    [ "$rc" -eq 1 ] || { WHY="exit $rc, not 1"; return 1; }
    return 0
}

if [ "$PROVE_RED" -eq 1 ]; then
    OLD="$TMP/old_fast_checks.sh"
    git -C "$ROOT" show master:tools/fast_checks.sh > "$OLD" 2>/dev/null || {
        echo "COULD NOT MEASURE: git show master:tools/fast_checks.sh failed" >&2; exit 2; }
    chmod +x "$OLD"
    RUNNER="$OLD"
    export INCURSION_FAST_LIMIT=2     # the old runner's wall-clock limit; the new one ignores it
    red=0
    if case_ac1_game; then echo "NOT RED  AC1 game case passed under the old runner"; red=1
    else echo "red      AC1 game case failed under the old runner: $WHY"; fi
    if case_ac4_unwatched; then echo "NOT RED  AC4 unwatched case passed under the old runner"; red=1
    else echo "red      AC4 unwatched case failed under the old runner: $WHY"; fi
    if [ "$red" -eq 0 ]; then echo "RED as expected"; exit 0; fi
    exit 1
fi

DIR="$TMP/checks"
mkdir -p "$DIR"

# ---- a. one passing fast check -> exit 0
plant "$DIR" check_pass.sh cheap "static test" 'exit 0'
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 0 ]; then report ok "a: a passing fast check exits 0"; else
    report FAIL "a: a passing fast check exits 0 (got $rc)"; printf '%s\n' "$out"; fi

# ---- b. add one failing fast check -> exit 1, naming it
plant "$DIR" check_fail.sh cheap "static test" 'echo "the failure text"; exit 1'
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 1 ]; then
    case "$out" in
        *check_fail.sh*) report ok "b: a failing fast check exits 1 and names the check" ;;
        *) report FAIL "b: the failing check is not named"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "b: a failing fast check exits 1 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_fail.sh"

# ---- d. a check with no marker is not run
plant "$DIR" check_nomarker.sh cheap "" 'echo "I must not run"; exit 1'
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 0 ]; then
    case "$out" in
        *check_nomarker.sh*) report FAIL "d: an unmarked check was run"; printf '%s\n' "$out" ;;
        *) report ok "d: a check with no gate-fast marker is not run" ;;
    esac
else
    report FAIL "d: an unmarked failing check affected the run (exit $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_nomarker.sh" "$DIR/check_pass.sh"

# ---- e. an empty directory -> exit 2
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 2 ]; then report ok "e: an empty directory exits 2"; else
    report FAIL "e: an empty directory exits 2 (got $rc)"; printf '%s\n' "$out"; fi

# ---- f. check_worktree_untracked.sh in a scratch git repo
REPO="$TMP/repo"
mkdir -p "$REPO/tools"
cp "$WT" "$REPO/tools/check_worktree_untracked.sh"
if git -C "$REPO" init -q 2>/dev/null; then
    git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
    git -C "$REPO" add tools/check_worktree_untracked.sh 2>/dev/null
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then report ok "f1: a clean repo exits 0"; else
        report FAIL "f1: a clean repo exits 0 (got $rc)"; printf '%s\n' "$out"; fi

    : > "$REPO/loose.txt"
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ]; then
        case "$out" in
            *loose.txt*) report ok "f2: an untracked file exits 1 and is listed" ;;
            *) report FAIL "f2: the untracked file is not listed"; printf '%s\n' "$out" ;;
        esac
    else
        report FAIL "f2: an untracked file exits 1 (got $rc)"; printf '%s\n' "$out"
    fi

    printf 'loose.txt\n' > "$REPO/.gitignore"
    git -C "$REPO" add .gitignore 2>/dev/null
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then report ok "f3: an ignored file exits 0"; else
        report FAIL "f3: an ignored file exits 0 (got $rc)"; printf '%s\n' "$out"; fi

    # ---- i. a filename with a space is listed on one line, unsplit
    : > "$REPO/a b.txt"
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ]; then
        case "$out" in
            *"a b.txt"*) report ok "i: a filename with a space is listed whole" ;;
            *) report FAIL "i: a spaced filename is not listed on one line"; printf '%s\n' "$out" ;;
        esac
    else
        report FAIL "i: a spaced filename exits 1 (got $rc)"; printf '%s\n' "$out"
    fi
    rm -f "$REPO/a b.txt"
else
    report FAIL "f: could not git init a scratch repo"
fi

# ---- h. a check exiting 2 alone -> exit 0, output says UNMEASURED
plant "$DIR" check_unmeasured.sh cheap "static test" 'echo "cannot measure"; exit 2'
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 0 ]; then
    case "$out" in
        *UNMEASURED*) report ok "h: a check exiting 2 does not fail the run (UNMEASURED)" ;;
        *) report FAIL "h: a check exiting 2 did not say UNMEASURED"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "h: a check exiting 2 left the runner at exit $rc"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_unmeasured.sh"

# ---- j. a failing check and a HANG, guard faked to REFUSE (memory pressure 2):
# an OVERLOADED: line and a HANG line; exit 1.
plant "$DIR" check_fail_j.sh cheap "static test" 'echo "j failed"; exit 1'
plant "$DIR" check_hang_j.sh cheap "static test" "read x < '$TMP/j.fifo'" 'exit 0'
mkfifo "$TMP/j.fifo"
out="$(runner unwatched "$DIR" INCURSION_LOAD_GUARD_FAKE_PRESSURE=2 INCURSION_FAST_STALL=1)"; rc=$?
if [ "$rc" -eq 1 ]; then
    case "$out" in
        OVERLOADED:*|*$'\n'OVERLOADED:*) overloaded=1 ;;
        *) overloaded=0 ;;
    esac
    case "$out" in *"HANG check_hang_j.sh"*) hang=1 ;; *) hang=0 ;; esac
    if [ "$overloaded" -eq 1 ] && [ "$hang" -eq 1 ]; then
        report ok "j: a refusing guard labels a failure and a HANG OVERLOADED"
    else
        report FAIL "j: refusing guard (overloaded=$overloaded hang=$hang)"; printf '%s\n' "$out"
    fi
else
    report FAIL "j: failing+hanging under a refusing guard exits 1 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_fail_j.sh" "$DIR/check_hang_j.sh" "$TMP/j.fifo"
# inc-b0ziu.8: the runs above logged one row per check, after a header row.
if [ "$(head -1 "$INCURSION_CHECK_TIMING_LOG" 2>/dev/null | cut -f1)" = "utc_time" ] \
   && [ "$(grep -c "	fast	" "$INCURSION_CHECK_TIMING_LOG" 2>/dev/null)" -ge 2 ]; then
    report ok "j2: fast_checks.sh logs a timing row per check"
else
    report FAIL "j2: no timing rows in $INCURSION_CHECK_TIMING_LOG"
fi

# ---- k. a failing check, guard faked IDLE: no OVERLOADED: line
plant "$DIR" check_fail_k.sh cheap "static test" 'echo "k failed"; exit 1'
out="$(runner unwatched "$DIR")"; rc=$?
if [ "$rc" -eq 1 ]; then
    case "$out" in
        OVERLOADED:*|*$'\n'OVERLOADED:*) report FAIL "k: idle guard printed OVERLOADED:"; printf '%s\n' "$out" ;;
        *) report ok "k: an idle guard leaves no OVERLOADED: line" ;;
    esac
else
    report FAIL "k: failing check under an idle guard exits 1 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_fail_k.sh"

# ---- l. every check passes, guard faked to REFUSE: exit 0 and no OVERLOADED:
# line, because the guard must not be consulted when nothing failed.
plant "$DIR" check_pass_l.sh cheap "static test" 'exit 0'
out="$(runner unwatched "$DIR" INCURSION_LOAD_GUARD_FAKE_PRESSURE=2)"; rc=$?
if [ "$rc" -eq 0 ]; then
    case "$out" in
        OVERLOADED:*|*$'\n'OVERLOADED:*) report FAIL "l: a passing set printed OVERLOADED:"; printf '%s\n' "$out" ;;
        *) report ok "l: a passing set never consults the guard (exit 0, no OVERLOADED:)" ;;
    esac
else
    report FAIL "l: a passing set exits 0 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_pass_l.sh"

# ---- m. a check that starts a background child and exits: the child must not
# outlive the runner (the sandbox bars ps, so the stand-in's pid is the witness).
CHILDPID="$TMP/childpid"
plant "$DIR" check_child_m.sh cheap "static test" "sleep 61 & echo \$! > '$CHILDPID'" 'exit 0'
out="$(runner unwatched "$DIR")"; rc=$?
child="$(cat "$CHILDPID" 2>/dev/null)"
alive=1
if [ -n "$child" ]; then
    for _ in 1 2 3 4 5 6; do
        kill -0 "$child" 2>/dev/null || { alive=0; break; }
        sleep 0.5
    done
    [ "$alive" -eq 1 ] && kill "$child" 2>/dev/null
fi
if [ "$rc" -eq 0 ] && [ -n "$child" ] && [ "$alive" -eq 0 ]; then
    report ok "m: a check's background child is dead after the runner returns"
else
    report FAIL "m: child case (exit $rc, child='$child', alive=$alive)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_child_m.sh"

# ---- AC1. one fake per kind is refused with EXPENSIVE naming the kind
D1="$TMP/d_ac1"
plant "$D1" check_k_game.sh cheap "fake" "\"$ROOT/tools/headless.sh\" >/dev/null 2>&1; exit 0"
plant "$D1" check_k_build.sh cheap "fake" "\"$ROOT/build_macos.sh\" >/dev/null 2>&1; exit 0"
plant "$D1" check_k_git-history.sh cheap "fake" 'git log --oneline >/dev/null 2>&1; exit 0'
plant "$D1" check_k_sleep.sh cheap "fake" 'sleep 0.2; exit 0'
plant "$D1" check_k_bd.sh cheap "fake" 'bd list --limit 1 >/dev/null 2>&1; exit 0'
plant "$D1" check_k_compiler.sh cheap "fake" 'clang++ --version >/dev/null 2>&1; exit 0'
plant "$D1" check_o_bounded.sh cheap "fake" 'git log -1 >/dev/null 2>&1; exit 0'
plant "$D1" check_o_killed.sh cheap "fake" 'sleep 30 & p=$!; kill $p; wait $p 2>/dev/null; exit 0'
plant "$D1" check_upstream_label.sh cheap "fake" 'bd list --limit 1 >/dev/null 2>&1; exit 0'
plant "$D1" check_o_fullpath.sh cheap "fake" '/bin/sleep 0.1; exit 0'
plant "$D1" check_adv_cheap.sh cheap "fake" 'sleep 0.2; exit 0'
plant "$D1" check_adv_none.sh "none x" "fake" 'sleep 0.2; exit 0'
if grep -Eq '^check_upstream_label\.sh[[:space:]]+bd([[:space:],]|$)' "$ROOT/tools/fast_checks.vetted"; then
    out="$(runner unwatched "$D1")"; rc=$?
    [ "$rc" -eq 1 ] || report FAIL "AC1: the mixed set exits 1 (got $rc)"
    for kind in game build git-history sleep bd compiler; do
        case "$out" in
            *"EXPENSIVE check_k_$kind.sh ($kind:"*) report ok "AC1: a $kind fake is refused as EXPENSIVE ($kind)" ;;
            *) report FAIL "AC1: a $kind fake is not refused naming $kind"; block "$out" "check_k_$kind.sh" ;;
        esac
    done
    for name in check_o_bounded.sh check_o_killed.sh check_upstream_label.sh; do
        case "$out" in
            *"ok   $name "*) report ok "AC1: $name is ok" ;;
            *) report FAIL "AC1: $name is not ok"; printf '%s\n' "$out" | grep "$name" ;;
        esac
    done
    case "$out" in
        *"EXPENSIVE check_o_fullpath.sh ("*"/bin/sleep"*) report ok "AC1: /bin/sleep by full path is EXPENSIVE" ;;
        *) report FAIL "AC1: /bin/sleep by full path is not refused"; printf '%s\n' "$out" | grep check_o_fullpath ;;
    esac
    case "$(block "$out" check_adv_cheap.sh)" in
        *"remove its gate-fast marker"*) report ok "AC1: a refused '# gate: cheap' fake is offered marker removal" ;;
        *) report FAIL "AC1: no marker-removal advice for a '# gate: cheap' fake" ;;
    esac
    adv="$(block "$out" check_adv_none.sh)"
    case "$adv" in
        *EXPENSIVE*"remove its gate-fast marker"*) report FAIL "AC1: marker-removal advice offered for '# gate: none'" ;;
        *EXPENSIVE*) report ok "AC1: a refused '# gate: none' fake is not offered marker removal" ;;
        *) report FAIL "AC1: the '# gate: none' fake was not refused"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "AC1: tools/fast_checks.vetted has no 'check_upstream_label.sh bd' line"
fi

# ---- AC2. the same set normally and under taskpolicy -c background
D2="$TMP/d_ac2"
plant "$D2" check_s_ok.sh cheap "fake" 'exit 0'
plant "$D2" check_s_exp.sh cheap "fake" 'sleep 0.2; exit 0'
plant "$D2" check_s_fail.sh cheap "fake" 'echo "s failed"; exit 1'
norm="$(runner unwatched "$D2" | strip_secs)"; rc1=$?
bg="$(PFX="taskpolicy -c background" runner unwatched "$D2" | strip_secs)"; rc2=$?
case "$norm" in *"EXPENSIVE check_s_exp.sh"*"FAIL check_s_fail.sh"*"ok   check_s_ok.sh"*) shaped=1 ;; *) shaped=0 ;; esac
if [ "$norm" = "$bg" ] && [ "$shaped" -eq 1 ]; then
    report ok "AC2: verdicts are identical normally and under taskpolicy -c background"
else
    report FAIL "AC2: verdicts differ or are malformed (shaped=$shaped)"
    diff <(printf '%s\n' "$norm") <(printf '%s\n' "$bg")
fi

# ---- AC3. a real fast check copied unchanged is ok; with a game call added it is
# EXPENSIVE. check_devour_prose.sh does `cd "$(dirname "$0")/.."`, so the copy sits
# in a mirror tree whose lib/ and src/ are symlinks to this tree.
REAL="$ROOT/tools/check_devour_prose.sh"
M="$TMP/mirror"
mkdir -p "$M/tools"
for l in lib src inc; do ln -sfn "$ROOT/$l" "$M/$l"; done
if ! bash "$REAL" >/dev/null 2>&1; then
    report FAIL "AC3: precondition: the original check_devour_prose.sh does not pass on this tree"
else
    cp "$REAL" "$M/tools/check_devour_prose.sh"
    out="$(runner unwatched "$M/tools")"; rc=$?
    case "$out" in
        *"ok   check_devour_prose.sh "*) [ "$rc" -eq 0 ] && report ok "AC3: an unchanged copy of a real fast check is ok" \
                                                         || report FAIL "AC3: unchanged copy ok but exit $rc" ;;
        *) report FAIL "AC3: the unchanged copy is not ok"; printf '%s\n' "$out" ;;
    esac
    { sed '$d' "$REAL"; printf '"%s/tools/headless.sh" >/dev/null 2>&1\n' "$ROOT"; tail -n 1 "$REAL"; } \
        > "$M/tools/check_devour_prose.sh"
    out="$(runner unwatched "$M/tools")"; rc=$?
    case "$out" in
        *"EXPENSIVE check_devour_prose.sh (game:"*) report ok "AC3: the copy with one headless.sh call is EXPENSIVE game" ;;
        *) report FAIL "AC3: the mutated copy is not refused as game (exit $rc)"; printf '%s\n' "$out" ;;
    esac
fi

# ---- AC4 (watched). A check blocked on a fifo: an ALERT line appears while the
# runner still runs; stopping the runner's process group leaves no fake behind.
D4="$TMP/d_ac4w"; FIFO="$TMP/ac4w.fifo"; PIDF="$TMP/ac4w.pid"
mkfifo "$FIFO"
plant "$D4" check_blocked.sh cheap "blocks forever" "echo \$\$ > '$PIDF'" "read x < '$FIFO'" 'exit 0'
base="$(wc -l < "$ALERT_FILE")"
set -m
( cd "$ROOT" && exec env INCURSION_FAST_WATCHED=1 INCURSION_FAST_STALL=1 "$RUNNER" --dir "$D4" ) > "$TMP/ac4w.out" 2>&1 &
rpid=$!
set +m
seen=0
for _ in $(seq 1 80); do
    newlines="$(tail -n +$((base + 1)) "$ALERT_FILE")"
    if grep -q '^ALERT check_blocked.sh ' <<<"$newlines"; then seen=1; break; fi
    sleep 0.25
done
running=0
kill -0 "$rpid" 2>/dev/null && running=1
{
    kill -TERM -- "-$rpid"
    for _ in 1 2 3 4 5 6 7 8; do kill -0 "$rpid" 2>/dev/null || break; sleep 0.25; done
    kill -KILL -- "-$rpid"
    wait "$rpid"
} 2>/dev/null
fake="$(cat "$PIDF" 2>/dev/null)"
gone=0
if [ -n "$fake" ]; then
    for _ in 1 2 3 4 5 6 7 8; do kill -0 "$fake" 2>/dev/null || { gone=1; break; }; sleep 0.25; done
    [ "$gone" -eq 0 ] && kill -KILL "$fake" 2>/dev/null
fi
if [ "$seen" -eq 1 ] && [ "$running" -eq 1 ] && [ "$gone" -eq 1 ]; then
    report ok "AC4: a watched blocked check raises an ALERT while the runner runs, and stopping the group removes it"
else
    report FAIL "AC4: watched case (alert=$seen runner-still-running=$running fake-gone=$gone fake='$fake')"
fi
rm -f "$FIFO"

# ---- AC4 (unwatched). The same block is a HANG, not EXPENSIVE; the alert file holds HANG.
if case_ac4_unwatched; then
    report ok "AC4: an unwatched blocked check is HANG, and the alert file holds the HANG line"
else
    report FAIL "AC4: unwatched case: $WHY"
fi

# ---- AC4 (CLAUDECODE alone). CLAUDECODE=1 without INCURSION_FAST_WATCHED=1 is unwatched.
if case_ac4_unwatched CLAUDECODE=1; then
    report ok "AC4: CLAUDECODE=1 alone is unwatched: the blocked check is HANG"
else
    report FAIL "AC4: CLAUDECODE=1 alone case: $WHY"
fi

# ---- AC4 (vetted bd wait). A vetted bd may wait on the shared beads database past
# the stall limit: no ALERT watched, no HANG unwatched. The same call from a check
# that is not vetted stays EXPENSIVE bd. The fake bd is a re-signed copy of
# /bin/sleep named bd (fast_watch.py reads the executable name, so a script would
# show as bash): `bd 7` blocks 7 s with no child and no CPU, longer than the
# unwatched limit (5 x INCURSION_FAST_STALL=1).
FBD="$TMP/fakebd"; mkdir -p "$FBD"
cp /bin/sleep "$FBD/bd" && codesign -s - -f "$FBD/bd" >/dev/null 2>&1 ||
    report FAIL "AC4 vetted bd wait: cannot make the fake bd"
grep -q '^check_upstream_label.sh[[:space:]]\+bd[[:space:]]' "$ROOT/tools/fast_checks.vetted" ||
    report FAIL "AC4 vetted bd wait: tools/fast_checks.vetted has no bd line for check_upstream_label.sh"
for mode in watched unwatched; do
    D="$TMP/d_ac4bd_$mode"; rm -rf "$D"
    plant "$D" check_upstream_label.sh cheap "waits on bd" 'bd 7 >/dev/null 2>&1' 'exit 0'
    base="$(wc -l < "$ALERT_FILE")"
    out="$(runner "$mode" "$D" INCURSION_FAST_STALL=1 PATH="$FBD:$PATH")"; rc=$?
    lines="$(tail -n +$((base + 1)) "$ALERT_FILE")"
    bad=""
    [ "$rc" -eq 0 ] || bad="exit $rc"
    case "$out" in *"HANG check_upstream_label.sh"*|*"EXPENSIVE check_upstream_label.sh"*) bad="$bad verdict: $(block "$out" check_upstream_label.sh | head -2 | tr '\n' '|')" ;; esac
    case "$lines" in *"ALERT check_upstream_label.sh "*|*"HANG check_upstream_label.sh "*) bad="$bad alert line: $lines" ;; esac
    if [ -z "$bad" ]; then
        report ok "AC4 vetted bd wait: a vetted bd waiting past the stall limit is ok, no alert ($mode)"
    else
        report FAIL "AC4 vetted bd wait ($mode): $bad"
    fi
done
# control: the same wait from a check that is not vetted is EXPENSIVE bd
D="$TMP/d_ac4bd_ctl"; rm -rf "$D"
plant "$D" check_novet_bd.sh cheap "calls bd" 'bd 1 >/dev/null 2>&1' 'exit 0'
out="$(runner unwatched "$D" INCURSION_FAST_STALL=1 PATH="$FBD:$PATH")"; rc=$?
case "$out" in
    *"EXPENSIVE check_novet_bd.sh (bd"*) report ok "AC4 vetted bd wait: control, an unvetted bd call is still EXPENSIVE" ;;
    *) report FAIL "AC4 vetted bd wait: control not EXPENSIVE bd (exit $rc): $(printf '%s' "$out" | head -4 | tr '\n' '|')" ;;
esac

echo
if [ "$fails" -eq 0 ]; then
    echo "check_fast_checks: PASS"
    exit 0
fi
echo "check_fast_checks: FAIL ($fails assertion(s))"
exit 1
