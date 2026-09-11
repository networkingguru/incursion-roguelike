#!/bin/bash
# Does a reflected gaze name the monster that gazed? (bd inc-upw.30)
#
# WHAT WENT WRONG. src/Magic.cpp:944 answers a gaze effect aimed at a creature
# carrying GAZE_REFLECTION / GR_REFLECT by turning the effect around and telling
# every onlooker about it. The string used two bare <Obj> tokens and the call
# supplied one object. __XPrint (src/Message.cpp:471-480) reads a tag whose
# lowercased form is exactly "obj", "mon" or "itm" as "take the NEXT argument",
# so the first token consumed the only argument and the second read past the end
# of the vararg list, then handed the result to Thing::Name().
#
# This is the same shape as the A_DEQU save line of 2026-08-15, which looked
# right in source and printed "the orcish bastard sword +1 protects its orcish
# bastard sword +1" on screen. tools/check_xprint_tokens.sh counts tokens in
# source text and is blind to what reaches the player, which is why this check
# plays the game instead.
#
# THE ORACLE is the literal sentence on the screen, read after a bodak has
# gazed at a character who carries the stati.
#
# WHY A BODAK, and how it separates the two reflection sites. Two places answer
# a reflected gaze. src/Fight.cpp:1868 handles the A_GAZE row of a monster's
# attack table and prints "The <EActor>'s gaze is reflected!"; src/Magic.cpp:944
# handles an EF_GAZE magical effect and prints the sentence this check reads. A
# bodak has no A_GAZE row -- its attacks are A_SLAM and A_SEEM -- so the
# Fight.cpp branch cannot run for it, and its one spell is an EF_GAZE effect.
# The wording separates them a second time: only the Magic.cpp line says "back
# at", and the assertions below reject the Fight.cpp line by name.
#
# WHAT THE FIXED BUILD PRINTS, copied from the screen:
#
#     The bodak's gaze is reflected back at it!
#
# PROVED RED on 2026-09-11 by putting the unnumbered tags back:
#
#     "The <Obj>'s gaze is reflected back at <him:Obj>!"
#
# The mutated build printed no sentence at all. It died where it formatted one,
# and logged this first:
#
#     Probable parameter mismatch in __XPrint; msg = "The <Obj>'s gaze is
#     reflected back at <him:Obj>!", POV=31017435136, Subject=0
#
# with a call stack of Monster::ChooseAction -> ThrowEff -> Creature::Invoke ->
# Magic::MagicEvent -> Magic::ABallBeamBolt -> Magic::MagicStrike ->
# Thing::IDPrint -> Player::__IPrint -> __XPrint -> Error, and then the process
# took SIGBUS (tools/headless.sh reported "ended: exit 138"). That is the first
# observation of this defect biting in play rather than in a source scan.
#
# Usage: tools/check_gaze_reflect_message.sh              (0 pass, 1 fail, 2 no measurement)
#        tools/check_gaze_reflect_message.sh --prove-red
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# ---------------------------------------------------------------------------
# check_run with one rule changed, and only one.
#
# check_run stops with INCONCLUSIVE on any session that did not end normally,
# because for nearly every check a session that died measured nothing. Here the
# death IS the measurement: with the fix reverted this session dies inside
# Thing::IDPrint while it formats the very sentence under test, so check_run's
# rule would report exit 2, and --prove-red reads exit 2 as "nothing is proved".
# The check would then be unprovable against the defect it defends.
#
# So a FATAL, a watchdog stop or a killing signal counts as a FAIL here. Every
# other bad ending -- no gameplay, an unreadable key script, an @expect that
# found nothing, an unlisted ASSERT -- keeps check_run's verdict, because those
# say the harness or the key script drifted rather than that the game misbehaved.
# The override only ever turns a green into a red, never the other way.
gaze_run() { # <keyscript> <seed>
    local keys="$1" seed="$2" out status

    [ -x "./incursion-headless" ] || _check_die 2 \
        "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

    out="$(INCURSION_OPTIONS="$CHECK_OPTIONS" tools/headless.sh "$keys" "$seed" 2>&1 </dev/null)"
    status=$?
    CHECK_RUN="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
    [ -n "$CHECK_RUN" ] && printf '%s\n' "$out" > "$CHECK_RUN/harness.txt"

    if [ "$status" -eq 1 ] || [ "$status" -eq 4 ] || [ "$status" -ge 128 ]; then
        echo "  FAIL  the game died (tools/headless.sh exit $status) before it could"
        echo "        finish the session, and the last thing it was asked to do was"
        echo "        print the reflected-gaze line."
        if [ -n "$CHECK_RUN" ] && [ -f "$CHECK_RUN/logs/errors.log" ]; then
            grep -m2 '__XPrint' "$CHECK_RUN/logs/errors.log" | sed 's/^/        /'
        fi
        echo
        echo "FAIL: the reflected-gaze line killed the session instead of printing"
        echo "      the screens and the log are in ${CHECK_RUN:-logs/runs}"
        exit 1
    fi

    if [ "$status" -ne 0 ] && [ "$status" -ne 3 ]; then
        printf '%s\n' "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/      /'
        _check_die 2 \
            "the session ended badly (tools/headless.sh exit $status), so it" \
            "measured nothing. See ${CHECK_RUN:-the output above}."
    fi

    printf '%s\n' "$out" | grep -E '^(death:|stuck-prompt:) *(STUCK|threat)' | sed 's/^/  note: /'
    echo "  session: $CHECK_RUN (seed $seed, $(basename "$CHECK_OPTIONS"))"
}

check_mutation src/Magic.cpp \
    "The <Obj1>'s gaze is reflected back at <him:Obj1>!" \
    "The <Obj>'s gaze is reflected back at <him:Obj>!"

gaze_run tools/keys/gaze-reflect-message.keys 4

# The stati is on the character before any gaze arrives. src/Sheet.cpp:653
# writes this row of the sheet's Specials column.
check_screens '*-sheet-specials'
check_expect "Gaze Reflection" "the caster carries the stati before any gaze arrives"

check_screens '*-wait*'
check_expect "eyes glow with a black aura" \
    "the bodak really cast its gaze, so a reflection had something to answer"
check_expect "The bodak's gaze is reflected back at it!" \
    "the sentence names the gazing monster once, then pronouns it"
check_reject "<Obj" \
    "no raw format tag reached the screen"
check_reject "gaze is reflected back at the bodak" \
    "the monster is named once, not twice"
check_reject "The bodak's gaze is reflected!" \
    "the line came from src/Magic.cpp, not from src/Fight.cpp's A_GAZE branch"

check_done "a reflected gaze names the gazer once, in a sentence that parses"
