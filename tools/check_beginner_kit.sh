#!/bin/bash
# gate: live
# Does the Beginner's Kit follow Roark's NECESSITIES list? (bd inc-rt8l)
#
# THE DESIGN. With OPT_BEGINKIT on, creation grants a share of the rows of
# Roark Ironbeard's NECESSITIES list (lib/dungeon.irh), by each row's kit count:
# 0 = not in the kit, N = exactly N, KIT_BY_TYPE = the item-type rule (potion
# or scroll: half the tier rounded up; skill tool: one, with ranks in a skill
# it serves and none held; light: half the tier, only without darkvision; food:
# 3d2+4 rations; anything else: half the tier).
#
# THE ORACLE. Each build runs twice with the same seed and key script, once
# with tools/fixtures/options-2026-08-22-kit.dat (kit on, OPT_BEGINKIT 1) and
# once with options-2026-08-22.dat (kit off, OPT_BEGINKIT 0). The kit is the
# per-item quantity difference in INCURSION_KIT_PROBE's KIT_STACK lines. The
# expected kit is derived from the NECESSITIES rows, never a typed list.
#
# BUILDS (key scripts tools/keys/kit-*.keys) and what each must exercise:
#   warrior   Human Warrior     no darkvision, Climb ranks
#   halfling  Halfling Warrior  no darkvision, no Climb ranks
#   mage      Orc Mage          darkvision, no Climb ranks
#   rogue     Orc Rogue         darkvision, Climb ranks
#   ranger    Human Ranger      Heal ranks (healing kit comes from the base grant)
#
# Usage: tools/check_beginner_kit.sh [build ...]    (default: all builds)
#        tools/check_beginner_kit.sh --selftest     (oracle only, no build)
#        tools/check_beginner_kit.sh --prove-red    (oracle without its darkvision
#                                                    rule must FAIL on the dark builds)
#   0 pass   1 a rule failed   2 could not measure
. "$(dirname "$0")/check_lib.sh"

[ "${1:-}" = "--selftest" ] && exec python3 tools/check_beginner_kit.py --selftest
PROVE=0
[ "${1:-}" = "--prove-red" ] && { PROVE=1; shift; }

ON=tools/fixtures/options-2026-08-22-kit.dat
OFF=tools/fixtures/options-2026-08-22.dat
BUILDS="warrior:dark0,climb
halfling:dark0,noclimb
mage:dark1,noclimb
rogue:dark1,climb
ranger:heal-base,climb"

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

WANT=" $* "
FAIL=0; UNMEAS=0; N=0
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
while IFS=: read -r name tags; do
    [ "$WANT" = "  " ] || case "$WANT" in *" $name "*) ;; *) continue ;; esac
    N=$((N + 1))
    bad=0
    for mode in on off; do
        opt=$ON; [ "$mode" = off ] && opt=$OFF
        RUN="$PWD/logs/runs/$STAMP-beginkit-$name-$mode"
        INCURSION_OPTIONS="$opt" INCURSION_KIT_PROBE=1 INCURSION_RUN_DIR="$RUN" \
            tools/headless.sh "tools/keys/kit-$name.keys" 1 > "$RUN.out" 2>&1
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "$name: UNMEASURED headless.sh exited $rc (see $RUN.out)"
            bad=1
        fi
    done
    if [ "$bad" -ne 0 ]; then UNMEAS=1; continue; fi
    extra=""; [ "$PROVE" -eq 1 ] && extra="--no-dark-gate"
    python3 tools/check_beginner_kit.py \
        "$PWD/logs/runs/$STAMP-beginkit-$name-on/logs/errors.log" \
        "$PWD/logs/runs/$STAMP-beginkit-$name-off/logs/errors.log" "$name" "$tags" $extra
    case $? in 0) ;; 1) FAIL=1 ;; *) UNMEAS=1 ;; esac
done <<< "$BUILDS"

echo
[ "$N" -gt 0 ] || _check_die 2 "no build matched: $*"
if [ "$PROVE" -eq 1 ]; then
    [ "$FAIL" -ne 0 ] && { echo "PROVE-RED OK: the oracle fails when the darkvision rule is dropped."; exit 0; }
    echo "PROVE-RED FAILED: the oracle did not go red."; exit 1
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: at least one kit rule failed ($N builds run)."
    exit 1
fi
if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a build could not be measured or did not exercise its tags."
    exit 2
fi
echo "PASS: the Beginner's Kit matches the NECESSITIES rules on all $N builds."
exit 0
