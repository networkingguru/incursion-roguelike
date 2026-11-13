#   tools/check_aura_of_menace.sh [seed ...]    default seed: 4
#   exit 0 the aura fired as the forced save roll says, 1 it did not, 2 could not measure
#
# A seed MUST NOT change the verdict (docs/VERIFICATION.md, "A check must not
# depend on the seed"). Every fact the check reads, and what fixes it:
# fact: character (Chaotic Evil orc barbarian, stats, kit) -- fixture orc-barbarian-ce-opt0822 (INCURSION_LOAD, every session) -- orc-barbarian-ce-opt0822 is frozen old save kept as a specimen until inc-9s4u0 gives its scene a map builder (tools/fixtures/specimens/orc-barbarian-ce-opt0822.sav)
# fact: arrival level holds no other monster -- wizard "Genocide Everything"
# fact: archon placement (five squares east) -- wizard "Monster Summoning"
# fact: archon is hostile to the character -- wizard "All Monster Aggravate" (src/Target.cpp LowPriorityStatiHostility)
# fact: archon stays still -- wizard switch "Freeze Monsters"
# fact: character survives -- wizard switch "Cheat Death"
# fact: Will save fails (penalty case) -- INCURSION_FORCE_SAVE_ROLL=1
# fact: Will save is made (immunity case) -- INCURSION_FORCE_SAVE_ROLL=20
# fact: hit mode: Will save fails -- INCURSION_FORCE_SAVE_ROLL=1
# fact: hit mode: the swing lands -- INCURSION_LOF_FORCE_ROLL=20 (a natural 20 always hits: src/Fight.cpp Creature::Strike isHit)
# fact: message and Stati texts -- engine strings this check exists to read ("washes over you", "steel yourself", "You shake off", eID Aura of Menace)
@@@ next hunk
# Both must agree. Each seed runs two sessions: the save forced to fail (the
# message and the penalty rows must appear) and forced to succeed (the message
# and the immunity row must appear). Both are required for PASS.
@@@ next hunk
if [ "$#" -gt 0 ]; then SEEDS="$*"; else SEEDS="4"; fi
CHAR=tools/fixtures/specimens/orc-barbarian-ce-opt0822.sav
[ -f "$CHAR" ] || { echo "INCONCLUSIVE: fixture $CHAR is not there"; exit 2; }
@@@ next hunk
    HSEED="${HITSEED:-4}"  # any seed gives the same verdict: the facts are pinned (header)
