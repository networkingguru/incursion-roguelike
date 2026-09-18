#!/bin/bash
# Regression check for the headless backend (src/Wposix.cpp, inc-73g).
#
# What it protects. Everything else in this project that runs without a person
# depends on five properties, and each of them is easy to lose by accident:
#
#   1. A scripted session runs to the end with no display and no keyboard,
#      and ends by itself. A backend that blocks waiting for a key would hang
#      a nightly run instead of failing it.
#   2. The screen dump is a real picture of the game. A dump of an empty
#      buffer would still be a file, would still be 48 lines long, and would
#      still tell you nothing.
#   3. The same seed plays the same game. Without that a dump cannot be
#      compared with an earlier one, so no regression can ever be detected --
#      and the failure is silent, because every individual run still passes.
#   4. A session whose character died is reported as having died, not as an
#      ordinary clean exit (inc-loa.3). The pinned gate settings run with
#      OPT_NODEATH on, so a killing blow asks "Die? [yn]" instead of ending
#      the session, and the key script answers it blind -- with whatever
#      token comes next, because it cannot see the screen. 12 of 40 sessions
#      in the kept baseline (logs/gate/compare-dive-87655) hit that prompt and
#      exited 0 regardless, which every existing caller reads as "played".
#   5. A session frozen at the threat-disengage prompt is reported as frozen,
#      not as an ordinary clean exit (inc-loa.5). "You are in a threatened
#      area. Abort, Flee or Disengage?" (src/Move.cpp:941) has no OPT_ gate
#      at all, and tools/keys/dive.keys has no 'a'/'f'/'d'/'?'/ESC to answer
#      it with, so once it fires every remaining scripted keystroke is
#      silently swallowed. 7 of 40 sessions in the kept baseline
#      (logs/gate/record-dive-89305) hit it and exited 0 regardless.
#
# Each assertion below is exercised against known-bad input by --selftest, so
# a check that has quietly stopped testing anything says so.
#
# Usage: tools/check_headless.sh              (exits 0 on pass, 1 on fail)
#        tools/check_headless.sh --selftest   (proves the assertions bite)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

SEED=1
KEYS="tools/keys/smoke.keys"
# Since e4a6499, tools/headless.sh refuses runs without a settings file:
# settings change what a seeded session does.
SMOKE_OPTS="$ROOT/tools/fixtures/options-2026-08-22.dat"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- the assertions, as functions, so --selftest can feed them bad input ----

# A dump is a picture of the game only if the player and the floor are both in
# it. '@' alone is not enough: a status line could carry one.
assert_shows_map() { # <dumpfile>
    grep -q '@' "$1" && grep -qE '\.\.\.\.' "$1"
}

assert_reproducible() { # <dirA> <dirB>
    diff -r "$1" "$2" > /dev/null 2>&1
}

# inc-loa.3: the pinned settings run with OPT_NODEATH on, so a killing blow
# asks "You die... Die? [yn]" (src/Fight.cpp) instead of ending the session,
# and the key script -- which cannot see the screen -- answers it with
# whatever token comes next. A session can leave that prompt two ways, and a
# plain exit code cannot tell either apart from an ordinary clean run.
#
# Confirmed: the prompt got answered 'y', for real or on OPT_ELUDE_DEATH's
# last try, and Player::Death() (src/Fight.cpp) logged it.
assert_died_confirmed() { # <rundir>
    [ -f "$1/logs/death.log" ] && grep -q '^=== character died' "$1/logs/death.log"
}

# Stuck: the run's last screen still shows the prompt, unanswered. The exact
# bracket text matters -- a screen from AFTER a confirmed death still says
# "You die..." (it is the game's own message), but never "Die? [yn]" again,
# because the prompt already resolved. Losing the "[yn]" half of the match
# would call every confirmed death "stuck" too.
assert_stuck_at_prompt() { # <rundir>
    local last
    last="$(ls "$1/logs/screens" 2>/dev/null | sort | tail -1)"
    [ -n "$last" ] && grep -q 'Die? \[yn\]' "$1/logs/screens/$last" 2>/dev/null
}

# inc-loa.5: "You are in a threatened area. Abort, Flee or Disengage?"
# (src/Move.cpp:941) has no OPT_ gate and no settings-driven escape, and
# tools/keys/dive.keys has no 'a'/'f'/'d'/'?'/ESC in its vocabulary, so a
# session that hits it is frozen for the rest of its key budget -- there is
# no "confirmed, resolved cleanly" counterpart the way there is for the death
# prompt, because dive.keys can never supply the key that would resolve it.
#
# Match the prompt's OWN words, "Abort, Flee or Disengage", not the bare
# words "threatened area" that used to be matched here. The prompt's '?'
# choice opens the in-game combat manual at the {LE} anchor
# (src/Move.cpp:943, lib/help.irh:3320), and that manual page is ALSO
# titled around attacks of opportunity and says "threatened area" several
# times in its own prose. So a session that answered '?' and landed in the
# manual instead of staying at the prompt would match the old pattern and
# be reported as still frozen AT the prompt, which it is not. Measured
# 2026-09-18: tools/keys/dive.keys, seed 11, ends in the manual (mode 5,
# MO_HELP) and its last screen contains "threatened area" as help text with
# no "Abort, Flee or Disengage" anywhere on it.
assert_stuck_at_threat_prompt() { # <rundir>
    local last
    last="$(ls "$1/logs/screens" 2>/dev/null | sort | tail -1)"
    [ -n "$last" ] && grep -q 'Abort, Flee or Disengage' "$1/logs/screens/$last" 2>/dev/null
}

# inc-uh0: two sessions started in the same second must each get their own
# directory. The default name is built from a clock that resolves to the
# second, so before the process id joined it (headless.sh:90) a loop that
# started several sessions inside one second gave them all one directory --
# one save/, one logs/, and one append-mode probe log holding every session's
# lines. Both paths must exist, because "different" is also true of a name
# that was never created.
assert_distinct_run_dirs() { # <dirA> <dirB>
    [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && [ -d "$1" ] && [ -d "$2" ]
}

if [ "${1:-}" = "--selftest" ]; then
    echo "--- selftest: each assertion must reject known-bad input ---"
    ok=0

    printf 'HP:42/42 Mana:14\nnothing here\n' > "$WORK/nomap.txt"
    if assert_shows_map "$WORK/nomap.txt"; then
        echo "SELFTEST FAIL: the map assertion accepted a screen with no map"
        ok=1
    else
        echo "  map assertion rejects a screen with no map: good"
    fi

    printf '=== screen ===\n....@....\n....\n' > "$WORK/map.txt"
    if assert_shows_map "$WORK/map.txt"; then
        echo "  map assertion accepts a screen with a map: good"
    else
        echo "SELFTEST FAIL: the map assertion rejected a real map"
        ok=1
    fi

    mkdir -p "$WORK/a" "$WORK/b"
    printf 'one\n' > "$WORK/a/s.txt"
    printf 'two\n' > "$WORK/b/s.txt"
    if assert_reproducible "$WORK/a" "$WORK/b"; then
        echo "SELFTEST FAIL: the reproducibility assertion accepted two different runs"
        ok=1
    else
        echo "  reproducibility assertion rejects two different runs: good"
    fi

    cp "$WORK/b/s.txt" "$WORK/a/s.txt"
    if assert_reproducible "$WORK/a" "$WORK/b"; then
        echo "  reproducibility assertion accepts two identical runs: good"
    else
        echo "SELFTEST FAIL: the reproducibility assertion rejected two identical runs"
        ok=1
    fi

    mkdir -p "$WORK/nodeath/logs/screens" "$WORK/confirmed/logs/screens" \
        "$WORK/stuck/logs/screens"

    printf '=== screen ===\nYou walk on.\n' > "$WORK/nodeath/logs/screens/0001-final.txt"
    if assert_died_confirmed "$WORK/nodeath" || assert_stuck_at_prompt "$WORK/nodeath"; then
        echo "SELFTEST FAIL: a death assertion accepted an ordinary screen"
        ok=1
    else
        echo "  death assertions reject a session with no death prompt: good"
    fi

    printf '=== character died 2026-08-16 00:00:00  turn 1  depth 1  xp 0 ===\n' \
        > "$WORK/confirmed/logs/death.log"
    printf '=== screen ===\nYou die...\nPress [ENTER] to continue...\n' \
        > "$WORK/confirmed/logs/screens/0001-final.txt"
    if assert_died_confirmed "$WORK/confirmed"; then
        echo "  confirmed-death assertion accepts logs/death.log: good"
    else
        echo "SELFTEST FAIL: the confirmed-death assertion rejected a real death.log"
        ok=1
    fi
    if assert_stuck_at_prompt "$WORK/confirmed"; then
        echo "SELFTEST FAIL: a resolved death's own 'You die...' message was read as"
        echo "  an unanswered prompt -- every confirmed death would double as stuck"
        ok=1
    else
        echo "  stuck-at-prompt assertion does not mistake a resolved death for one: good"
    fi

    printf '=== screen ===\nYou die... Die? [yn]\n' > "$WORK/stuck/logs/screens/0001-final.txt"
    if assert_stuck_at_prompt "$WORK/stuck"; then
        echo "  stuck-at-prompt assertion accepts an unanswered prompt: good"
    else
        echo "SELFTEST FAIL: the stuck-at-prompt assertion rejected 'Die? [yn]' on screen"
        ok=1
    fi
    if assert_died_confirmed "$WORK/stuck"; then
        echo "SELFTEST FAIL: a stuck session with no death.log was read as confirmed"
        ok=1
    else
        echo "  confirmed-death assertion does not mistake a stuck prompt for one: good"
    fi

    # inc-loa.5: the threat-disengage assertion, checked the same way and
    # against the same fixtures as the death-prompt ones above, so it must
    # neither miss its own prompt nor fire on the death prompt's screens.
    if assert_stuck_at_threat_prompt "$WORK/nodeath"; then
        echo "SELFTEST FAIL: the threat-prompt assertion accepted an ordinary screen"
        ok=1
    else
        echo "  threat-prompt assertion rejects a session with no threat prompt: good"
    fi
    if assert_stuck_at_threat_prompt "$WORK/stuck" || assert_stuck_at_threat_prompt "$WORK/confirmed"; then
        echo "SELFTEST FAIL: the threat-prompt assertion fired on a death-prompt screen"
        ok=1
    else
        echo "  threat-prompt assertion does not mistake the death prompt for its own: good"
    fi

    mkdir -p "$WORK/threat/logs/screens"
    printf '=== screen ===\nYou are in a threatened area. Abort, Flee or Disengage? [afd?]\n' \
        > "$WORK/threat/logs/screens/0001-final.txt"
    if assert_stuck_at_threat_prompt "$WORK/threat"; then
        echo "  threat-prompt assertion accepts an unanswered prompt: good"
    else
        echo "SELFTEST FAIL: the threat-prompt assertion rejected its own prompt on screen"
        ok=1
    fi
    if assert_died_confirmed "$WORK/threat" || assert_stuck_at_prompt "$WORK/threat"; then
        echo "SELFTEST FAIL: the death-prompt assertions fired on a threat-prompt screen"
        ok=1
    else
        echo "  death-prompt assertions do not mistake the threat prompt for their own: good"
    fi

    # Measured 2026-09-18: the prompt's own '?' choice opens the combat manual
    # at src/Move.cpp:943, lib/help.irh:3320, and that page's own prose about
    # attacks of opportunity says "threatened area" repeatedly -- but never
    # "Abort, Flee or Disengage". A session that escaped the prompt into the
    # manual must be read as NOT stuck at the prompt. This is copied verbatim
    # from a real manual screen dumped at depth 12, seed 11
    # (tools/keys/dive.keys, tools/gates/Options.Dat).
    mkdir -p "$WORK/manual/logs/screens"
    printf '=== screen 0003 depth12  key 369  mode 5  turn 198315 ===\n%s\n%s\n%s\n' \
        '| situations provoke these attacks:                              ^|P' \
        '|   * When a character casts a spell, he provokes an attack of    |' \
        '| opportunity from any creature that has him in their             |untide' \
        > "$WORK/manual/logs/screens/0003-final.txt"
    printf '| threatened area. The Defensive Spell feat can be used to        |\n' \
        >> "$WORK/manual/logs/screens/0003-final.txt"
    if assert_stuck_at_threat_prompt "$WORK/manual"; then
        echo "SELFTEST FAIL: the threat-prompt assertion mistook the combat manual's own prose for its prompt"
        ok=1
    else
        echo "  threat-prompt assertion rejects the combat manual's 'threatened area' prose: good"
    fi

    # inc-uh0: the run-directory assertion must reject the collision it exists
    # to catch -- one name for two runs -- and must not be satisfied by two
    # names that differ but were never created.
    mkdir -p "$WORK/rundir-a" "$WORK/rundir-b"
    if assert_distinct_run_dirs "$WORK/rundir-a" "$WORK/rundir-a"; then
        echo "SELFTEST FAIL: the run-directory assertion accepted one directory for two runs"
        ok=1
    else
        echo "  run-directory assertion rejects two runs sharing one directory: good"
    fi
    if assert_distinct_run_dirs "$WORK/rundir-a" "$WORK/rundir-missing"; then
        echo "SELFTEST FAIL: the run-directory assertion accepted a directory that is not there"
        ok=1
    else
        echo "  run-directory assertion rejects a name that was never created: good"
    fi
    if assert_distinct_run_dirs "$WORK/rundir-a" "$WORK/rundir-b"; then
        echo "  run-directory assertion accepts two separate directories: good"
    else
        echo "SELFTEST FAIL: the run-directory assertion rejected two separate directories"
        ok=1
    fi

    [ "$ok" -eq 0 ] && echo "PASS: the assertions bite" && exit 0
    exit 1
fi

# --- the check itself --------------------------------------------------------

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

# 1. It runs to the end on its own, with no terminal of any kind.
INCURSION_RUN_DIR="$WORK/run1" INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out1" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- session output ---"
    tail -20 "$WORK/out1"
    case $STATUS in
        4) fail "the session hit the watchdog: the game stopped asking for keystrokes" ;;
        1) fail "the session ended in Fatal()" ;;
        *) fail "the session exited $STATUS, wanted 0" ;;
    esac
fi

# 2. It photographed the game, and the photograph has a map in it.
LAST="$(ls "$WORK/run1/logs/screens"/*walked* 2>/dev/null | tail -1)"
if [ -z "$LAST" ]; then
    fail "no screen was dumped; the run never reached the walk"
elif ! assert_shows_map "$LAST"; then
    echo "--- last screen ---"
    sed -n '1,20p' "$LAST"
    fail "the last screen has no map on it (no player, or no floor)"
fi

# 3. The same seed plays the same game.
INCURSION_RUN_DIR="$WORK/run2" INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out2" 2>&1 < /dev/null
if ! assert_reproducible "$WORK/run1/logs/screens" "$WORK/run2/logs/screens"; then
    echo "--- what differs ---"
    diff -r "$WORK/run1/logs/screens" "$WORK/run2/logs/screens" | head -20
    fail "two runs of the same script and seed drew different screens"
fi

# 4. A different seed must play a different game, or the seed is being ignored
#    and assertion 3 above would pass on a build that had lost it entirely.
INCURSION_RUN_DIR="$WORK/run3" INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" 99 > "$WORK/out3" 2>&1 < /dev/null
if assert_reproducible "$WORK/run1/logs/screens" "$WORK/run3/logs/screens"; then
    fail "two different seeds drew identical screens; the seed is being ignored"
fi

# 5. A session that never reaches gameplay must NOT report success. An empty
#    key script runs the game out of keys at the very first prompt, so it exits
#    having generated no character and entered no map -- and the game's own exit
#    code for that is 0. Before the harness promoted it, soak.sh counted such a
#    session as "clean", and 250 of them were once read as evidence that a fix
#    worked. This assertion is the reason that cannot happen again.
printf '# no keys at all: the session must not reach a map\n' > "$WORK/empty.keys"
INCURSION_RUN_DIR="$WORK/run4" INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$WORK/empty.keys" "$SEED" \
    > "$WORK/out4" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 5 ]; then
    echo "--- session output ---"
    tail -10 "$WORK/out4"
    fail "a session that never entered a map exited $STATUS, wanted 5 (NO GAMEPLAY)"
fi

# 6. Turning a DIAGNOSTIC off must not change the verdict on whether the game
#    played. This is inc-duz. The harness used to answer "did it play?" by
#    asking whether logs/mapaudit.log existed, which stopped being true the day
#    the audit gained a switch: a disabled audit writes no log, so every session
#    with INCURSION_MAP_AUDIT=0 called itself vacuous. That hit hardest in the
#    one case the switch exists for -- a timing run must set it, and would then
#    throw away all of its own data. Same seed and script on 2026-08-15: audit
#    on reached turn 199900, audit off was called NO GAMEPLAY.
#
#    Note what this must NOT be rewritten to use: screens are no evidence of
#    gameplay, because they come from @dump lines in the key script. The vacuous
#    run above leaves 11 of them.
INCURSION_MAP_AUDIT=0 INCURSION_RUN_DIR="$WORK/run5" INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" "$SEED" \
    > "$WORK/out5" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- session output ---"
    tail -10 "$WORK/out5"
    fail "with the map audit off, a session that played exited $STATUS, wanted 0"
fi
if [ ! -f "$WORK/run5/logs/session.log" ]; then
    fail "no logs/session.log with the audit off; the gameplay marker is gone"
fi

# 7. An ordinary healthy session must not be reported as dead or stuck. Read
#    against run1 from assertion 1 above, which never touches OPT_NODEATH's
#    prompt at all -- if either death assertion fires here, they fire on
#    everything and inc-loa.3's fix is worse than having nothing. Same for
#    the threat-disengage prompt (inc-loa.5): tools/keys/smoke.keys does not
#    reach a threatened area either.
if assert_died_confirmed "$WORK/run1" || assert_stuck_at_prompt "$WORK/run1"; then
    fail "an ordinary session with no death prompt was reported as died or stuck"
fi
if assert_stuck_at_threat_prompt "$WORK/run1"; then
    fail "an ordinary session with no threat prompt was reported as threat-frozen"
fi

# 8, 9 and 10 (inc-gjzx). inc-loa.3 and inc-loa.5: the harness must be able to
# tell three endings apart, and all three share an exit code (0) and an
# "ended: cleanly"-shaped report: parked at the unanswered death prompt, a
# confirmed death, and parked at the threat-disengage prompt.
#
# All three used to drive tools/keys/dive.keys at a pinned seed and wait for
# the generated world to produce the prompt they wanted. It stopped doing
# that: a scripted dive reaches whichever modal prompt the generated world
# puts in its path first, and that moves whenever lib/ moves, so all three
# scenarios drifted off the prompts they were pinned to. Measured 2026-09-18
# at b443f8f: seed 1 now stalls at a "stop searching" prompt, seed 11 lands in
# the in-game combat manual (its '?' choice, not its death prompt), seed 42
# stalls at "Confirm enter the magma?" -- none of the three prompts these
# steps test. See docs/specs/2026-09-18-headless-prompt-fixtures-brief.md.
#
# Instead: load a frozen character who is already standing next to a hostile
# monster (tools/fixtures/chars/engaged-hostile.sav, built by
# tools/keys/engaged-hostile-save.keys -- a Lizardfolk Monk 1 one square west
# of an awake, hostile, perceiving bugbear) and drive each ending on purpose
# with a dedicated key script. Same fixture, same seed, three endings.
GATE_OPTS="$ROOT/tools/gates/Options.Dat"
CHAR_FIXTURE="$ROOT/tools/fixtures/chars/engaged-hostile.sav"
if [ ! -f "$GATE_OPTS" ]; then
    fail "the pinned gate settings are missing: $GATE_OPTS"
elif [ ! -f "$CHAR_FIXTURE" ]; then
    fail "the engaged-hostile character fixture is missing: $CHAR_FIXTURE"
else
    # 8. Stuck: death-freeze.keys (tools/keys/death-freeze.keys) rests in
    #    place until the bugbear standing beside the fixture kills him, then
    #    stops. '.' cannot answer TextTerm::yn (src/Term.cpp:3338), which
    #    loops until it reads 'y' or 'n', so the session parks at
    #    "You die... Die? [yn]", unanswered, and runs out of its key budget
    #    still parked there. See that script's own header for why
    #    OPT_ELUDE_DEATH, not OPT_NODEATH, is what actually reaches this
    #    prompt under tools/gates/Options.Dat.
    INCURSION_RUN_DIR="$WORK/stuck" INCURSION_OPTIONS="$GATE_OPTS" \
    INCURSION_LOAD="$CHAR_FIXTURE" \
        ./tools/headless.sh tools/keys/death-freeze.keys 1 > "$WORK/out-stuck" 2>&1 < /dev/null
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        echo "--- session output ---"
        tail -10 "$WORK/out-stuck"
        fail "the stuck-at-prompt scenario exited $STATUS, wanted 0 (its own exit code does not change)"
    fi
    if ! grep -q '^death:.*STUCK' "$WORK/out-stuck"; then
        echo "--- session output ---"
        tail -10 "$WORK/out-stuck"
        fail "headless.sh did not report the stuck-at-prompt session as STUCK"
    fi
    if ! assert_stuck_at_prompt "$WORK/stuck"; then
        fail "the stuck-at-prompt assertion did not fire on the reproduced scenario"
    fi
    if assert_died_confirmed "$WORK/stuck"; then
        fail "the stuck-at-prompt scenario also logged a confirmed death; it should not"
    fi

    # 9. Confirmed: death-confirm.keys (tools/keys/death-confirm.keys) is the
    #    identical scenario up to the death prompt, then answers it with 'y' --
    #    twice, because two lethal hits land on the fixture in the same round
    #    at this seed and each one opens its own "You die... Die? [yn]"
    #    prompt (measured, see that script's own header). Both fall through
    #    to the real death path and each calls NoteCharacterDied
    #    (src/Fight.cpp:7819), so logs/death.log gets TWO entries here, not
    #    one -- the existing '^death:.*confirmed' grep still matches either
    #    count, so it is left as-is.
    INCURSION_RUN_DIR="$WORK/confirmed" INCURSION_OPTIONS="$GATE_OPTS" \
    INCURSION_LOAD="$CHAR_FIXTURE" \
        ./tools/headless.sh tools/keys/death-confirm.keys 1 > "$WORK/out-confirmed" 2>&1 < /dev/null
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        echo "--- session output ---"
        tail -10 "$WORK/out-confirmed"
        fail "the confirmed-death scenario exited $STATUS, wanted 0 (its own exit code does not change)"
    fi
    if ! grep -q '^death:.*confirmed' "$WORK/out-confirmed"; then
        echo "--- session output ---"
        tail -10 "$WORK/out-confirmed"
        fail "headless.sh did not report the confirmed-death session as confirmed"
    fi
    if ! assert_died_confirmed "$WORK/confirmed"; then
        fail "the confirmed-death assertion did not fire on the reproduced scenario"
    fi
    if assert_stuck_at_prompt "$WORK/confirmed"; then
        fail "the confirmed-death scenario was also read as stuck; the prompt did resolve"
    fi

    # 10. inc-loa.5: threat-freeze.keys (tools/keys/threat-freeze.keys) steps
    #     one square away from the bugbear (off the fixture's engaged square)
    #     before anything else can happen, firing "You are in a threatened
    #     area. Abort, Flee or Disengage?" (src/Move.cpp:941). Every key after
    #     that is '.' (KY_CMD_REST), which ChoicePrompt does not recognise as
    #     any of "afd?", an arrow, ENTER or ESC, so the prompt just re-asks
    #     and the session parks there, unanswered, for the rest of its key
    #     budget. See that script's own header for why a stray arrow or ENTER
    #     here would instead escape into the combat manual and never return.
    INCURSION_RUN_DIR="$WORK/threatened" INCURSION_OPTIONS="$GATE_OPTS" \
    INCURSION_LOAD="$CHAR_FIXTURE" \
        ./tools/headless.sh tools/keys/threat-freeze.keys 1 > "$WORK/out-threatened" 2>&1 < /dev/null
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        echo "--- session output ---"
        tail -10 "$WORK/out-threatened"
        fail "the threat-disengage scenario exited $STATUS, wanted 0 (its own exit code does not change)"
    fi
    if ! grep -q '^stuck-prompt:.*threat-disengage' "$WORK/out-threatened"; then
        echo "--- session output ---"
        tail -10 "$WORK/out-threatened"
        fail "headless.sh did not report the threat-disengage session as stuck"
    fi
    if ! assert_stuck_at_threat_prompt "$WORK/threatened"; then
        fail "the threat-prompt assertion did not fire on the reproduced scenario"
    fi
    if assert_died_confirmed "$WORK/threatened" || assert_stuck_at_prompt "$WORK/threatened"; then
        fail "the threat-disengage scenario was also read as a death-prompt freeze; it should not be"
    fi
fi

# 11. inc-uh0: two sessions started at the same moment must not share a run
#     directory. This is the one assertion that must NOT pass
#     INCURSION_RUN_DIR, because the defect was in the DEFAULT name -- every
#     other check here hands the harness a directory and so could never see
#     it. The two sessions run at once, so they take their stamp from the same
#     second. Both directories are removed afterwards: they are the only two
#     this check writes outside its own temporary tree, and it knows their
#     exact paths because the harness printed them.
INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out-par1" 2>&1 < /dev/null &
P1=$!
INCURSION_OPTIONS="$SMOKE_OPTS" \
    ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out-par2" 2>&1 < /dev/null &
P2=$!
wait $P1
wait $P2
DIR1="$(sed -n 's/^run:  *//p' "$WORK/out-par1" | tail -1)"
DIR2="$(sed -n 's/^run:  *//p' "$WORK/out-par2" | tail -1)"
if ! assert_distinct_run_dirs "$DIR1" "$DIR2"; then
    echo "--- what the two runs reported ---"
    echo "run 1: $DIR1"
    echo "run 2: $DIR2"
    fail "two sessions started in the same second shared a run directory"
fi
for d in "$DIR1" "$DIR2"; do
    case "$d" in
        "$ROOT/logs/runs/"*) [ -d "$d" ] && rm -rf "$d" ;;
    esac
done

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a scripted session runs unattended, draws a map, repeats itself,"
    echo "      a session that plays nothing is reported as playing nothing,"
    echo "      switching the map audit off does not change either verdict, a"
    echo "      session whose character died -- for real, or stuck at the"
    echo "      question -- is told apart from an ordinary clean exit, and so is"
    echo "      a session frozen at the unguarded threat-disengage prompt"
    echo "      -- and two sessions started at once keep their runs apart"
    exit 0
fi
exit 1
