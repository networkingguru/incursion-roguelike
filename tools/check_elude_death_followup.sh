#!/bin/bash
# gate: live
# gate-serial: --prove-red overwrites tracked src/Fight.cpp and rebuilds the shared binaries
# When Elude Death saves the player, does the attack that nearly killed him stop?
# (bd inc-6vrn)
#
# THE DEFECT. Player::Death (src/Fight.cpp) answers "You die... Die?" with n by
# restoring his hit points and calling PlaceSomewhereSafe, which moves him far
# across the map ("The world shifts!"). It never sets e.Died, so the attacker's
# sequence goes on against the moved player: the natural grab (a plain
# EV_STRIKE, which skips the reach check), the remaining natural attacks, and
# the riders of the blow that was already thrown.
#
# THE ORACLE is INCURSION_ELUDE_PROBE (src/Player.cpp EludeProbeArrange and
# src/Fight.cpp EludeProbeNote). It sets the player's hit points low, makes a
# summoned monster throw its natural-attack sequence, and writes logs/elude.log:
# one line per strike or rider thrown at him, each with moved=0 (still on the
# armed square) or moved=1 (already carried off), plus a result line.
#
# TWO CASES, both required. A fix that stops only the main path stays red on (b).
#   (a) MAIN HIT. A giant soldier ant (bite, FT_NATURAL_GRAB, sting with an acid
#       rider), player at 1 hp. The killing blow is a main hit: the log line
#       just before the first moved=1 line is a "strike". After the shift no
#       line may say moved=1, and he must not be grabbed.
#   (b) RIDER. A burning ghast (two claws, each with a 2d6 fire rider), player
#       at 5 hp: a claw does at most 4, so a claw leaves him alive and the fire
#       rider kills. The log line just before the first moved=1 line is a
#       "rider-thrown" at moved=0. That killing rider's own "rider-done" is the
#       only moved=1 line allowed; anything after it (the second claw, its
#       rider) is the defect.
#
# EACH CASE MUST PROVE IT STAGED THE SCENARIO: logs/elude.log has an "arranged:"
# line and a "result:" line with moved=1, a screen dump shows "The world
# shifts!", and the killing blow has the kind the case names. Otherwise the case
# is INCONCLUSIVE (exit 2), never a pass.
#
# THE FIX has two halves, and the mutation below (--prove-red) breaks both:
#   (1) src/Fight.cpp's FollowUpReaches returns true unconditionally, so a
#       follow-up is no longer cut off by e.Eluded or by distance; and
#   (2) Player::Death no longer sets e.Eluded = true, so nothing records that
#       Elude Death moved him.
# With both halves broken the main case keeps striking (three moved=1 lines,
# including the grab) and the rider case reaches the second claw and its rider.
# Both cases must go red, so this check exits 1 under --prove-red (steps 2 of
# docs/VERIFICATION.md). The helper restores src/Fight.cpp even on failure.
#
# Usage: tools/check_elude_death_followup.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat   # OPT_ELUDE_DEATH = SEVEN

# ---------------------------------------------------------------------------
# --prove-red (docs/VERIFICATION.md step 2). check_mutation performs only the
# FIRST declared mutation per run, but the fix has two halves and BOTH must be
# broken for both cases to go red (see the header). So this check does the
# prove-red dance itself, applying both edits, exactly as
# tools/check_command_pools.sh does.
#
# It saves src/Fight.cpp, breaks both halves, rebuilds, re-runs this check
# WITHOUT the flag, expects exit 1 (both cases red), restores the source,
# rebuilds, and reports. A trap restores the source even if the run is
# interrupted; the source is compared against its copy before the verdict.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--prove-red" ]; then
    _fix=src/Fight.cpp
    _proof="$(mktemp -d "$CHECK_ROOT/logs/elude-death-followup-proof.XXXXXX")" \
        || _check_die 2 "no temp directory for the prove-red copies"
    cp -p "$_fix" "$_proof/original" || _check_die 2 "could not copy $_fix aside"
    _pr_restore() {
        cp -p "$_proof/original" "$_fix"
        [ -f "$CHECK_ROOT/incursion-headless" ] && rm -f "$CHECK_ROOT/incursion-headless"
    }
    trap '_pr_restore; echo "restored $_fix (trap)" >&2' EXIT INT TERM HUP

    echo "--- prove red: both halves of the inc-6vrn fix ---"
    echo "  mutating   $_fix  (original copied to $_proof/original)"
    _fix="$_fix" python3 - <<'PY' || _check_die 2 "a mutation did not apply cleanly"
import os
p = os.environ["_fix"]
s = open(p, encoding="utf-8", errors="surrogateescape").read()
edits = [
    ("    if (!e.ETarget || e.Eluded)\n        return false;\n",
     "    return true;  /* MUTATED by --prove-red: follow-up always reaches */\n"),
    ("        /* inc-6vrn: tell the running attack sequence that Elude Death has moved\n"
     "           this character, so no follow-up or after-effect reaches him. */\n"
     "        e.Eluded = true;\n",
     ""),
]
for old, new in edits:
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"mutation text appears {n} times, expected 1:\n{old!r}")
    s = s.replace(old, new)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
print("  mutated: FollowUpReaches now returns true; e.Eluded = true removed")
PY

    BACKEND=posix ./build_macos.sh > "$_proof/build-red.log" 2>&1 \
        || { tail -20 "$_proof/build-red.log" | sed 's/^/      /'
             _check_die 2 "the mutated build failed; log in $_proof/build-red.log"; }

    echo "  re-running this check with the fix broken"
    echo
    # CHECK_MUTATED=1 tells the check_mutation guards below that the excerpt is
    # gone on purpose, so they get on with the run instead of stopping it.
    CHECK_MUTATED=1 "$0" > "$_proof/red.log" 2>&1
    _inner=$?
    grep -E '^(scenario:|--- case|FAIL:|ok:|PASS:|INCONCLUSIVE:)' "$_proof/red.log" \
        | sed 's/^/  | /'
    echo

    echo "  restoring  $_fix"
    _pr_restore
    trap - EXIT INT TERM HUP
    cmp -s "$_proof/original" "$_fix" || _check_die 2 \
        "THE RESTORE DID NOT TAKE. Restore by hand: cp '$_proof/original' '$_fix'"
    BACKEND=posix ./build_macos.sh > "$_proof/build-green.log" 2>&1 \
        || { tail -20 "$_proof/build-green.log" | sed 's/^/      /'
             _check_die 2 "the restore rebuild failed; log in $_proof/build-green.log"; }

    if [ "$_inner" -ne 1 ]; then
        echo "FAIL: with both halves of the fix broken this check exited $_inner,"
        echo "      not 1. It is measuring nothing (docs/VERIFICATION.md step 2)."
        echo "      proof in $_proof"
        exit 2
    fi
    echo "PROVED RED: with FollowUpReaches forced true and e.Eluded removed, this"
    echo "            check exits 1 (both cases red). Source restored and rebuilt."
    exit 0
fi

# The two excerpts above must still be present, exactly once, on every ordinary
# run: a check whose declared mutation has rotted cannot be proved any more.
# Only the first is performed by the helper if this file is ever run with the
# library's own --prove-red; the custom block above handles that flag first.
check_mutation src/Fight.cpp \
'    if (!e.ETarget || e.Eluded)
        return false;' \
'    return true;  /* MUTATED by --prove-red: follow-up always reaches */'

check_mutation src/Fight.cpp \
'        /* inc-6vrn: tell the running attack sequence that Elude Death has moved
           this character, so no follow-up or after-effect reaches him. */
        e.Eluded = true;' \
''

FAILED=0
INCONCLUSIVE=0

# screen_shows <text> <screen...> -- true if a screen carries <text>.
#
# The sidebar starts at the first '|' on a line and the message region is what
# is left of it. A long message wraps at the 64-column boundary, so
# "The world shifts!" can be split as "The " / "world shifts!" over two lines
# (inc-6vrn: a preceding message pushes it past the boundary). Joining the
# message region of every line with single spaces makes the match independent
# of that wrapping: the phrase then appears contiguously.
screen_shows() {
    local text="$1" f
    shift
    for f in "$@"; do
        [ -f "$f" ] || continue
        awk -v want="$text" '
            { sub(/\|.*/, ""); buf = buf $0 " " }
            END { gsub(/[ \t]+/, " ", buf)
                  exit (index(buf, want) ? 0 : 1) }
        ' "$f" && return 0
    done
    return 1
}

# judge <label> <main|rider>   -- reads $CHECK_RUN
judge() {
    local label="$1" kind="$2" log="$CHECK_RUN/logs/elude.log" last0 killer next post
    echo "--- case $label ($kind) ---"
    if [ ! -f "$log" ] || ! grep -q '^arranged: ' "$log"; then
        echo "INCONCLUSIVE: no 'arranged:' line, so the probe never staged the attack."
        echo "specimen: $CHECK_RUN"; INCONCLUSIVE=1; return
    fi
    if ! grep -q '^result: .* moved=1 ' "$log"; then
        echo "INCONCLUSIVE: no 'result: ... moved=1' line, so Elude Death never moved him."
        echo "specimen: $log"; INCONCLUSIVE=1; return
    fi
    if ! screen_shows 'The world shifts!' "$CHECK_RUN"/logs/screens/*.txt; then
        echo "INCONCLUSIVE: no screen dump shows 'The world shifts!'."
        echo "specimen: $CHECK_RUN"; INCONCLUSIVE=1; return
    fi
    # The killing blow is the LAST strike/rider line logged while still on the
    # armed square (moved=0). After the fix nothing is logged moved=1 at all,
    # so there is no line at the first shift to point at; the last moved=0 line
    # is the blow that killed him.
    last0="$(grep -nE '^(strike|rider-thrown|rider-done): .* moved=0 ' "$log" | tail -1 | cut -d: -f1)"
    if [ -z "$last0" ]; then
        echo "INCONCLUSIVE: no strike was logged before the shift."
        echo "specimen: $log"; INCONCLUSIVE=1; return
    fi
    killer="$(sed -n "${last0}p" "$log")"
    if [ "$kind" = main ]; then
        case "$killer" in
            "strike: "*) ;;
            *) echo "INCONCLUSIVE: the killing blow was not a main hit; last moved=0 line: $killer"
               echo "specimen: $log"; INCONCLUSIVE=1; return ;;
        esac
    else
        case "$killer" in
            "rider-thrown: "*) ;;
            *) echo "INCONCLUSIVE: the killing blow was not a rider; last moved=0 line: $killer"
               echo "specimen: $log"; INCONCLUSIVE=1; return ;;
        esac
    fi
    # Every strike/rider line after the killing blow that was carried off
    # (moved=1) is a follow-up the fix should have stopped.
    post="$(tail -n +"$((last0 + 1))" "$log" | grep -E '^(strike|rider-thrown|rider-done): .* moved=1 ')"
    if [ "$kind" = rider ]; then
        # The killing rider's own completion is the only moved=1 line allowed;
        # it is the line right after the blow. Drop exactly it.
        next="$(sed -n "$((last0 + 1))p" "$log")"
        case "$next" in
            "rider-done: "*"moved=1 "*)
                post="$(printf '%s\n' "$post" | grep -vxF "$next")" ;;
        esac
    fi
    echo "scenario: $killer"
    grep -m1 '^result: ' "$log"
    if [ -n "$post" ]; then
        echo "FAIL: the sequence kept striking after Elude Death moved him:"
        printf '%s\n' "$post" | sed 's/^/      /'
        FAILED=1
    fi
    if grep -q '^result: .* grabbed=1 ' "$log" || grep -q '^result: .* grappling=1 ' "$log"; then
        echo "FAIL: he ended the sequence grabbed (see the result line)."
        FAILED=1
    fi
    [ -z "$post" ] && echo "ok: no strike followed the shift in case $label"
    echo "specimen: $log"
}

export INCURSION_ELUDE_PROBE="giant soldier ant:1"
check_run tools/keys/elude-death-main.keys 5
judge a main

export INCURSION_ELUDE_PROBE="burning ghast:5"
check_run tools/keys/elude-death-rider.keys 5
judge b rider

if [ "$FAILED" = 1 ]; then
    echo "FAIL: Elude Death does not stop the attack sequence (inc-6vrn)"
    exit 1
fi
if [ "$INCONCLUSIVE" = 1 ]; then
    echo "INCONCLUSIVE: at least one case did not stage its scenario"
    exit 2
fi
echo "PASS: Elude Death ends the attack sequence in both cases"
exit 0
