#!/bin/bash
# gate: live
# Do the four illusion rules of bd inc-yam9 hold? (one disbelieving viewer ends a
# low-tier illusion; Spectral stays; hits and collapses give a save at every tier)
#
# WHAT IT DEFENDS. The tier flags are on the spell's yval (inc/Defines.h):
# IL_SPECTRAL 1, IL_IMPROVED 2, IL_ADVANCED 4.
#
#   R1  Thing::DisbeliefCheck (src/Creature.cpp): a watcher that passes its Will
#       save against an illusion WITHOUT IL_SPECTRAL ends it (RemoveStati, "winks
#       out of existence"). Phantasmal Force, yval 0.
#   R2  Against an illusion WITH IL_SPECTRAL a passed save only gives that watcher
#       DISBELIEVED. The illusion stays and every other watcher still saves.
#       Spectral Force, yval IL_SPECTRAL.
#   R3  Creature::Damage (src/Fight.cpp): a landed hit on an illusion gives the
#       attacker a disbelief save at every tier. Before, IL_IMPROVED skipped it.
#       Improved Phantasmal Force, yval IL_IMPROVED.
#   R4  Creature::PDamage (src/Fight.cpp): when an illusion's psychosomatic damage
#       makes a victim collapse instead of die, the illusion triggers a disbelief
#       check at every tier. Before, IL_ADVANCED skipped it. Advanced Illusion,
#       yval IL_SPECTRAL|IL_IMPROVED|IL_ADVANCED.
#
# THE ORACLE. With INCURSION_DISBELIEF_PROBE set the game appends one line per
# save, pass or fail, to the run's logs/disbelief-probe.log (src/DisbeliefProbe.cpp):
#
#   DISBELIEF watcher=<n> illusion=<n> dc=<base> spotted=0|1 used_dc=<dc> result=pass|fail
#
# R1 and R2 add the screen text "winks out of existence". R3 and R4 add
# logs/true-illusion.log (src/TrueIllusionProbe.cpp): SETUP names the player and
# the spell's flags as the game reads them, SHOT / STRIKE says the hit landed or
# the victim collapsed. A save line from the PLAYER after that is the assertion.
#
# SESSIONS. R1 and R2 cast the spell for real (the fixture's spells are innate, so
# the cast goes through Creature::Invoke) and walk into the illusion, which runs
# DisbeliefCheck for every watcher that perceives it. The caster holds DISBELIEVED
# against his own illusory creature (src/Encounter.cpp enBuildMon) and a monster
# cannot cast illusions (inc-83cs), so the watchers are summoned monsters.
# R3 and R4 use a test probe instead of a cast, for two reasons. A cast needs a
# monster to attack the illusion, or an illusion to attack a victim, and monster
# AI choice has no control. And Advanced Illusion is level 5, beyond the fixture.
# The probe turns a placed monster into an illusion of the named spell, as
# src/RangedIllusionProbe.cpp does, and the player (not the caster of a probe-made
# illusion, so holding no DISBELIEVED) is the watcher. R3: the player throws a
# dagger at the illusion. R4: the illusory goblin strikes a real kobold that has
# 3 hit points.
#
# fact: character -- fixture elf-mage-illusions-seed1 (INCURSION_LOAD)
# fact: the spells known, and cast without a failure roll -- the fixture; its spells are innate
# fact: wizard mode, Infinite Mana, Freeze Monsters -- saved in the fixture
# fact: two watchers where the caster aims (R1, R2) -- wizard Monster Summoning
# fact: the watchers differ by name (R2) -- goblin and goblin vizier, lib/dungeon.irh
# fact: each watcher's Will save passes (R1, R2) -- INCURSION_FORCE_SAVE_ROLL=20
# fact: each save fails, so no illusion is removed by the very save asserted (R3, R4) -- INCURSION_FORCE_SAVE_ROLL=1
# fact: the thrown dagger and the illusory goblin hit (R3, R4) -- INCURSION_LOF_FORCE_ROLL=20
# fact: the illusory goblin's damage is at least the kobold's 3 hit points (R4) -- INCURSION_FORCE_DAMAGE_ROLL=99, and the probe sets the kobold's hit points
# fact: the illusion's tier (R3, R4) -- the spell's yval in lib/wspells.irh, read back by the probe into SETUP flags=; asserted equal to 2 and 7
# fact: the spell's tier (R1, R2) -- not read; R1 and R2 name the spell and assert on behavior, and the probe line's dc rises with the spell level
# fact: where the probe puts the actors (R3, R4) -- the first clear line from the player on the fixture's map; the save pins the map
# fact: the player's name -- read from the SETUP line, never matched as text
# fact: the illusory creature's name (R1, R2) -- not read; the check does not match it
# fact: the base DC -- not read
#
# EXIT. 0 all assertions pass, 1 any fails, 2 when the check cannot establish what
# it looks at (no probe line, no hit, no collapse, wrong tier, no gameplay).
#
# Usage: tools/check_true_illusions.sh [--prove-red [--site r1|r2|r3|r4]]

# --prove-red proves all four arms red. check_lib performs one mutation per run,
# so the wrapper runs itself once per site and needs every one to exit 0.
case " $* " in
*" --prove-red "*)
    case " $* " in
    *" --site "*) ;;
    *)
        for _site in r1 r2 r3 r4; do
            "$0" --prove-red --site "$_site" || exit $?
        done
        echo "PROVED RED: R1, R2, R3 and R4 each go red."
        exit 0 ;;
    esac ;;
esac

. "$(dirname "$0")/check_lib.sh"

_SITE=r1
for _i in "${!CHECK_ARGS[@]}"; do
    [ "${CHECK_ARGS[$_i]}" = "--site" ] && _SITE="${CHECK_ARGS[$((_i + 1))]:-r1}"
done

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/elf-mage-illusions-seed1.sav
export INCURSION_DISBELIEF_PROBE=1
export INCURSION_LOF_FORCE_ROLL=20
export INCURSION_FORCE_DAMAGE_ROLL=99

# Each site is declared on every run (the count guard fails if the fix moved);
# only the chosen one is mutated under --prove-red.
_pr=$CHECK_PROVE_RED
[ "$_SITE" = r1 ] || CHECK_PROVE_RED=0
check_mutation src/Creature.cpp \
    'if (!(fl & IL_SPECTRAL)) {' \
    'if (0) {'
CHECK_PROVE_RED=$_pr
[ "$_SITE" = r2 ] || CHECK_PROVE_RED=0
check_mutation src/Creature.cpp \
    'if (!(fl & IL_SPECTRAL)) {' \
    'if (1) {'
CHECK_PROVE_RED=$_pr
[ "$_SITE" = r3 ] || CHECK_PROVE_RED=0
check_mutation src/Fight.cpp \
    'e.EVictim->DisbeliefCheck(e.EActor);' \
    'if (!(e.EVictim->getIllusionFlags() & IL_IMPROVED)) e.EVictim->DisbeliefCheck(e.EActor);'
CHECK_PROVE_RED=$_pr
[ "$_SITE" = r4 ] || CHECK_PROVE_RED=0
check_mutation src/Fight.cpp \
    'if (e.actIllusion)
          e.EActor->DisbeliefCheck();' \
    'if (e.actIllusion && !(e.EActor->getIllusionFlags() & IL_ADVANCED))
          e.EActor->DisbeliefCheck();'
CHECK_PROVE_RED=$_pr

# verdict_cast <spell tier> <log> <screens dir>
#   tier r1: want exactly the removal. tier r2: want two watchers saving, no removal.
# verdict_probe <log> <probe log> <want flags> <event word>
# Both print "<status> <text>": 0 pass, 1 fail, 2 could not measure.
verdict_cast() {
    python3 -I - "$@" <<'PY'
import glob, re, sys
rule, log, screens = sys.argv[1:4]
try:
    lines = open(log, errors="replace").read().splitlines()
except OSError:
    print("2 no logs/disbelief-probe.log: no save was made"); sys.exit()
saves = []
for l in lines:
    m = re.match(r"DISBELIEF watcher=(.+?) illusion=(.+?) dc=(-?\d+) spotted=(\d) used_dc=(-?\d+) result=(\w+)$", l)
    if m and m.group(2) not in ("force", "terrain"):
        saves.append(m.groups())
passes = [s for s in saves if s[5] == "pass"]
if not passes:
    print("2 no watcher passed a save against the illusion (%d save lines); the cast or the walk did not reach it" % len(saves)); sys.exit()
shots = sorted(glob.glob(screens + "/*-after.txt")) + sorted(glob.glob(screens + "/*-final.txt"))
if not shots:
    print("2 no after/final screen dump"); sys.exit()
text = " ".join(open(f, errors="replace").read() for f in shots)
text = re.sub(r"\s+", " ", text)
winks = "winks out of existence" in text
who = sorted(set(s[0] for s in passes))
desc = "passes by %s; winks out %s" % (", ".join(who), "shown" if winks else "not shown")
if rule == "r1":
    print(("0 " if winks else "1 ") + desc + ("" if winks else "; wanted the illusion gone"))
else:
    ok = len(who) >= 2 and not winks
    print(("0 " if ok else "1 ") + desc + ("" if ok else "; wanted two watchers saving and the illusion still there"))
PY
}

verdict_probe() {
    python3 -I - "$@" <<'PY'
import re, sys
til, dlog, want_flags, event = sys.argv[1:5]
try:
    t = open(til, errors="replace").read().splitlines()
except OSError:
    print("2 no logs/true-illusion.log: the probe did not run"); sys.exit()
setup = [l for l in t if l.startswith("SETUP ")]
if not setup:
    print("2 no SETUP line: %s" % (t[0] if t else "empty log")); sys.exit()
m = re.match(r"SETUP mode=\S+ player=(.+?) spell=(.+) flags=(\d+)$", setup[0])
if not m:
    print("2 unreadable SETUP line: " + setup[0]); sys.exit()
player, spell, flags = m.group(1), m.group(2), int(m.group(3))
if flags != int(want_flags):
    print("2 %s declares flags %d, wanted %s: the tier under test moved" % (spell, flags, want_flags)); sys.exit()
ev = [l for l in t if l.startswith(event + " ")]
if not ev:
    print("2 no %s line: the scenario did not run to the event" % event); sys.exit()
if event == "SHOT":
    hp = int(re.search(r"targetHP=(\d+)", ev[0]).group(1))
    if hp >= 10000:
        print("2 the dagger did not hit (target hit points %d)" % hp); sys.exit()
else:
    if "victimAsleep=1" not in ev[0]:
        print("2 the kobold did not collapse: " + ev[0]); sys.exit()
try:
    d = open(dlog, errors="replace").read().splitlines()
except OSError:
    d = []
mine = []
for l in d:
    m = re.match(r"DISBELIEF watcher=(.+?) illusion=(.+?) dc=", l)
    if m and m.group(1) == player and m.group(2) not in ("force", "terrain"):
        mine.append(l)
desc = "%s (flags %d): %s; save lines by %s: %d" % (spell, flags, ev[0], player, len(mine))
print(("0 " if mine else "1 ") + desc + ("" if mine else "; wanted a disbelief save"))
PY
}

verdict() { # <label> <verdict text> <ok text>
    local st="${2%% *}" txt="${2#* }"
    if [ "$st" = 0 ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %s: %s\n        evidence: %s\n' "$1" "$3" "$txt"
    elif [ "$st" = 2 ]; then
        _check_die 2 "$1: $txt"
    else
        printf '  FAIL  %s: %s\n' "$1" "$txt"
        CHECK_FAIL=1
    fi
}

unset INCURSION_TRUE_ILLUSION_PROBE INCURSION_TRUE_ILLUSION_SPELL

echo "== R1 session: Phantasmal Force, two watchers pass"
export INCURSION_FORCE_SAVE_ROLL=20
check_run tools/keys/yam9-removal.keys 1
verdict R1-REMOVED "$(verdict_cast r1 "$CHECK_RUN/logs/disbelief-probe.log" "$CHECK_RUN/logs/screens")" \
    "a passed save against a non-Spectral illusion ends it"

echo "== R2 session: Spectral Force, two watchers pass"
check_run tools/keys/yam9-spectral.keys 1
verdict R2-SPECTRAL-STAYS "$(verdict_cast r2 "$CHECK_RUN/logs/disbelief-probe.log" "$CHECK_RUN/logs/screens")" \
    "a passed save against Spectral Force leaves it, and the second watcher still saves"

export INCURSION_FORCE_SAVE_ROLL=1

echo "== R3 session: Improved Phantasmal Force, the player's dagger hits it"
export INCURSION_TRUE_ILLUSION_PROBE=r3 INCURSION_TRUE_ILLUSION_SPELL="Improved Phantasmal Force"
check_run tools/keys/yam9-probe.keys 1
verdict R3-HIT-SAVE "$(verdict_probe "$CHECK_RUN/logs/true-illusion.log" "$CHECK_RUN/logs/disbelief-probe.log" 2 SHOT)" \
    "a landed hit on an IL_IMPROVED illusion gives the attacker a save"

echo "== R4 session: Advanced Illusion goblin makes a kobold collapse"
export INCURSION_TRUE_ILLUSION_PROBE=r4 INCURSION_TRUE_ILLUSION_SPELL="Advanced Illusion"
check_run tools/keys/yam9-probe.keys 1
verdict R4-COLLAPSE-SAVE "$(verdict_probe "$CHECK_RUN/logs/true-illusion.log" "$CHECK_RUN/logs/disbelief-probe.log" 7 STRIKE)" \
    "a psychosomatic collapse from an IL_ADVANCED illusion triggers a save"

check_done "disbelief ends a non-Spectral illusion, Spectral stays, and hits and collapses give a save at every tier"
