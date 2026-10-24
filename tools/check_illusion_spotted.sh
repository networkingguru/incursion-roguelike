#!/bin/bash
# gate: live
# Does a watcher that identifies an illusion spell with Spellcraft while it is
# cast get +4 on its disbelief save against that cast, and nobody else? (bd inc-z1ba)
#
# WHAT IT DEFENDS. Creature::Cast (src/Magic.cpp) lets each watcher who
# perceives the caster make a Spellcraft check against 10 + spell level. A
# watcher that passes identifies the spell and gets the status ILLUS_SPOTTED
# against what the cast makes. Its disbelief save then has its DC lowered by 4
# (Thing::DisbeliefCheck, src/Creature.cpp; the force save in Magic::MagicStrike,
# src/Magic.cpp). A watcher that did not identify the cast saves at the full DC.
#
# THE ORACLE is two kinds of line the game appends to the run's
# logs/disbelief-probe.log when INCURSION_DISBELIEF_PROBE is set
# (src/DisbeliefProbe.cpp):
#
#   IDENTIFY watcher=<n> caster=<n> spell=<S> result=pass|fail
#   DISBELIEF watcher=<n> illusion=<name|force|terrain> dc=<base> spotted=0|1
#             used_dc=<dc> result=pass|fail removed=0|1
#
# The probe writes a line whether the save passes or fails, so the check never
# needs the save to come out a particular way.
#
# THE CASTER is the frozen elf mage elf-mage-spotted-seed1. His Phantasmal Force
# is NOT innate (the sheet's Known Spells list shows no innate mark), so a player
# cast reaches Creature::Cast (src/Player.cpp:1073). The sibling fixture
# elf-mage-illusions-seed1 learns its spells in wizard mode, which marks them
# innate and sends the cast to Creature::Invoke, where nobody can identify it.
#
# THE WATCHERS. A goblin vizier has Spellcraft (lib/dungeon.irh) and a plain
# goblin has none. A monster cannot cast illusions (inc-83cs), so the player
# casts and the monsters watch. Creature::IPrint is a no-op for a monster, so
# the IDENTIFY line is the only sign that a monster identified a cast.
#
# THE COUNTERSPELL RISK. Creature::Counterspell lets a watcher with a Spellcraft
# check above 15 + spell level (here 16) counter the cast, on a one-in-three
# random roll. The vizier's check is forced to d20 = 1 plus its skill, which is
# at most 16, and its spell list holds no illusion spell. No session counters.
# A countered cast would write no DISBELIEF line, and the check would exit 2.
#
# PATHS COVERED: illusory creature (Phantasmal Force, "c"), illusory force
# (Phantasmal Force, "f", the Magic::MagicStrike save). NOT COVERED: illusory
# terrain (Map::TerrainDisbelief). Its only spells are Hallucinatory Terrain
# (level 4) and Mirage Arcana (level 6), beyond a 1st-level mage, and the save
# runs only when a creature falls through, sticks in or dies on the false
# terrain (src/Move.cpp:1500-1565). No control in docs/VERIFICATION.md reaches
# either fact.
#
# THREE SESSIONS:
#   creature  vizier and goblin both watch an illusory creature
#   force-v   the force is aimed at the vizier
#   force-g   the force is aimed at the goblin
#
# fact: character -- fixture elf-mage-spotted-seed1 (INCURSION_LOAD)
# fact: Phantasmal Force is cast through Creature::Cast -- the fixture's spell is not innate
# fact: the cast succeeds -- wizard switch Ignore Spell Failure
# fact: the caster has the mana -- wizard switch Infinite Mana
# fact: monsters stand still and do not act -- wizard switch Freeze Monsters
# fact: a vizier and a goblin stand where the caster aims -- wizard Monster Summoning
# fact: the vizier's Spellcraft check passes -- INCURSION_RUNTO_SKILL_ROLL=1
# fact: the goblin has no Spellcraft -- its monster definition, lib/dungeon.irh
# fact: the watchers' disbelief saves -- INCURSION_FORCE_SAVE_ROLL=1 (the line is logged pass or fail)
# fact: nobody counterspells -- skill roll 1 puts the vizier under the counterspell threshold
# fact: the illusory creature's name -- not read; the check does not match it
# fact: the base DC -- read from the probe line; only used_dc - dc is asserted
#
# Usage: tools/check_illusion_spotted.sh [--prove-red [--site creature|force]]
# Exit: 0 all pass, 1 any fail, 2 could not measure.

# --prove-red proves BOTH arms red. check_lib performs one mutation per run, so
# the wrapper runs itself once per site (--site creature, --site force) and
# needs both to exit 0.
case " $* " in
*" --prove-red "*)
    case " $* " in
    *" --site "*) ;;
    *)
        for _site in creature force; do
            "$0" --prove-red --site "$_site" || exit $?
        done
        echo "PROVED RED: both the creature and the force arm go red."
        exit 0 ;;
    esac ;;
esac

. "$(dirname "$0")/check_lib.sh"

_SITE=creature
for _i in "${!CHECK_ARGS[@]}"; do
    [ "${CHECK_ARGS[$_i]}" = "--site" ] && _SITE="${CHECK_ARGS[$((_i + 1))]:-creature}"
done

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/elf-mage-spotted-seed1.sav
export INCURSION_DISBELIEF_PROBE=1
export INCURSION_RUNTO_SKILL_ROLL=1
export INCURSION_FORCE_SAVE_ROLL=1

# --prove-red removes the 4 from one arm per run: the creature save in
# Thing::DisbeliefCheck, or the force save in Magic::MagicStrike. Both sites are
# counted on every run; only the chosen one is mutated.
_pr=$CHECK_PROVE_RED
[ "$_SITE" = creature ] || CHECK_PROVE_RED=0
check_mutation src/Creature.cpp \
    'int16 usedDC = spotted ? baseDC - 4 : baseDC;' \
    'int16 usedDC = baseDC;'
CHECK_PROVE_RED=$_pr
[ "$_SITE" = force ] || CHECK_PROVE_RED=0
check_mutation src/Magic.cpp \
    'int16 usedDC = spotted ? baseDC - 4 : baseDC;' \
    'int16 usedDC = baseDC;'
CHECK_PROVE_RED=$_pr

# probe_verdict <label> <log> <watcher> <illusion regex> <want spotted> <identify result>
# Prints "<status> <text>": 0 pass, 1 fail, 2 could not measure.
probe_verdict() {
    python3 -I - "$@" <<'PY'
import re, sys
log, watcher, illus, want, ident = sys.argv[1:6]
want = int(want)
try:
    lines = open(log, errors="replace").read().splitlines()
except OSError:
    print("2 no logs/disbelief-probe.log: the probe wrote nothing"); sys.exit()
ids = [l for l in lines if l.startswith("IDENTIFY ") and
       re.search(r"watcher=%s caster=" % re.escape(watcher), l)]
if not ids:
    print("2 no IDENTIFY line for %s: the cast did not reach the watcher" % watcher); sys.exit()
if "result=%s" % ident not in ids[0]:
    print("2 the cast did not %s for %s: %s" % ("identify" if ident == "pass" else "stay unidentified", watcher, ids[0])); sys.exit()
saves = []
for l in lines:
    m = re.match(r"DISBELIEF watcher=(.+?) illusion=(.+?) dc=(-?\d+) spotted=(\d) used_dc=(-?\d+) result=(\w+)(?: removed=\d)?$", l)
    if m and m.group(1) == watcher and re.fullmatch(illus, m.group(2)):
        saves.append(m.groups())
if not saves:
    print("2 %s made no disbelief save against the illusion; the cast may have been countered" % watcher); sys.exit()
bad = [s for s in saves if int(s[3]) != want or
       int(s[4]) != int(s[2]) - (4 if want else 0)]
w, i, dc, sp, used, res = saves[0]
desc = "%s vs %s: dc=%s spotted=%s used_dc=%s (%s)" % (w, i, dc, sp, used, res)
if bad:
    print("1 " + desc + "; wanted spotted=%d and used_dc=dc%s" % (want, "-4" if want else ""))
else:
    print("0 " + desc)
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

echo "== creature session"
check_run tools/keys/illusion-spotted-creature.keys 1
LOG="$CHECK_RUN/logs/disbelief-probe.log"
verdict CREATURE-SPOTTED "$(probe_verdict "$LOG" "goblin vizier" '(?!force$|terrain$).+' 1 pass)" \
    "a watcher that identified the cast saves at dc - 4"
verdict CREATURE-UNSPOTTED "$(probe_verdict "$LOG" "goblin" '(?!force$|terrain$).+' 0 fail)" \
    "a watcher that did not identify the cast saves at the full dc"

echo "== force session, aimed at the vizier"
check_run tools/keys/illusion-spotted-force-vizier.keys 1
verdict FORCE-SPOTTED "$(probe_verdict "$CHECK_RUN/logs/disbelief-probe.log" "goblin vizier" 'force' 1 pass)" \
    "the force save of a watcher that identified the cast is dc - 4"

echo "== force session, aimed at the goblin"
check_run tools/keys/illusion-spotted-force-goblin.keys 1
verdict FORCE-UNSPOTTED "$(probe_verdict "$CHECK_RUN/logs/disbelief-probe.log" "goblin" 'force' 0 fail)" \
    "the force save of a watcher that did not identify is the full dc"

check_done "a watcher that identifies an illusion cast saves 4 lower, and only that watcher"
