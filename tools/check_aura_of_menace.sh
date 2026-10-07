#!/bin/bash
# gate: live
# Does a hostile creature that walks into a monster's Aura of Menace get
# touched by it? (bd inc-bp44)
#
#   tools/check_aura_of_menace.sh [seed ...]    default seeds: 4 5
#   exit 0 the aura fired on every seed, 1 it did not, 2 could not measure
#
# THE DEFECT. CA_AURA_OF_MENACE (seven monsters carry it: lantern, torch and
# hound archons among them) was declared and described but no engine code read
# it, so the ability did nothing. The fix gives the carrier a mobile
# FI_MODIFIER field (src/Display.cpp Thing::PlaceAt) and Creature::FieldOn
# (src/Status.cpp) makes a hostile creature that enters it roll a Will save.
#
# THE SESSION is tools/keys/aura-of-menace.keys: a Chaotic Evil orc barbarian
# summons a lantern archon (wizard mode, "Monster Summoning") five squares east,
# Freeze Monsters holds it still, and the barbarian walks three squares east, to
# two squares from it (the aura's radius is the ability level, 2).
#
# THE ORACLE is what the game says and shows, read from screen dumps:
#   - the message log holds "An aura of menace washes over you!" (save failed)
#     or "You steel yourself against the aura of menace." (save made);
#   - the player's own Stati list holds an entry whose eID is "Aura of
#     Menace": three ADJUST rows (A_HIT, A_SAV, A_DEF, -2) after a failed save,
#     an EFF_FLAG1 immunity row after a made one.
# Both must agree. At least one seed must show the penalty rows, so a run of
# nothing but made saves cannot pass for the whole effect; the default seeds 4
# (fails the save) and 5 (makes it) cover both.
#
# IT CANNOT PASS BY DEFAULT. Exit 2 when a session did not play, the player
# died, the archon is not on the map, or the walk did not end two squares from
# it. Exit 1 only when the session is sound and the aura still did nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/aura-of-menace.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }
HITKEYS=tools/keys/aura-of-menace-hit.keys
[ -f "$HITKEYS" ] || { echo "INCONCLUSIVE: $HITKEYS is not there"; exit 2; }

# `--hit` runs only the CASE B mode (melee the aura's owner); anything else is a
# list of seeds for the CASE A walk-in mode. The default (no arguments) runs the
# CASE A seeds and then the CASE B hit mode, so one command covers both.
HITONLY=0
if [ "${1:-}" = "--hit" ]; then HITONLY=1; shift; fi
if [ "$#" -gt 0 ]; then SEEDS="$*"; else SEEDS="4 5"; fi
TOKEN="$$-$(date +%s)"
FIRED=0; PENALTY=0; NOTFIRED=0; TOTAL=0
BASERC=0

if [ "$HITONLY" -eq 0 ]; then
for seed in $SEEDS; do
    TOTAL=$((TOTAL+1))
    RUN="$ROOT/logs/runs/check-aura-of-menace-$TOKEN-seed$seed"
    rm -rf "$RUN"
    out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
            tools/headless.sh "$KEYS" "$seed" 2>&1)"
    S="$RUN/logs/screens"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$out" \
       || ! grep -q 'ended: *cleanly' <<< "$out"; then
        echo "INCONCLUSIVE: seed $seed did not play to the end; see $RUN"
        exit 2
    fi
    if ! grep -q 'death: *none' <<< "$out"; then
        echo "INCONCLUSIVE: seed $seed the character died; see $RUN"
        exit 2
    fi
    for n in summoned walked log stati; do
        [ -f "$(ls "$S"/*-$n.txt 2>/dev/null | head -1)" ] || {
            echo "INCONCLUSIVE: seed $seed left no '$n' screen dump; see $RUN"; exit 2; }
    done
    SUMMONED="$(ls "$S"/*-summoned.txt | head -1)"
    WALKED="$(ls "$S"/*-walked.txt | head -1)"
    LOG="$(ls "$S"/*-log.txt | head -1)"
    STATI="$(ls "$S"/*-stati.txt | head -1)"

    # The archon is on the map and listed in view when summoned...
    grep -q 'A lantern' "$SUMMONED" || {
        echo "INCONCLUSIVE: seed $seed no lantern archon in view after the summon; see $RUN"; exit 2; }
    # ...and after the walk exactly one square lies between '@' and 'A' on a row
    # of the map pane (the text left of the sidebar bar).
    if ! grep -qE '@.A' <<< "$(cut -d'|' -f1 "$WALKED")"; then
        echo "INCONCLUSIVE: seed $seed the walk did not end two squares from the archon; see $RUN"
        exit 2
    fi

    MSG=""
    grep -q 'washes over you' "$LOG" && MSG="washes"
    grep -q 'steel yourself against the aura of menace' "$LOG" && MSG="steels"
    # Stati rows name their source on the NEXT line: "(h:<owner>) (eID:<effect>)".
    ADJ="$(awk '/ADJUST from SS MISC/ {adj=$0; next} /eID:Aura of Menace/ && adj {n++} {adj=""} END {print n+0}' "$STATI")"
    IMM="$(awk '/EFF FLAG1 from SS MISC/ {f=$0; next} /eID:Aura of Menace/ && f {n++} {f=""} END {print n+0}' "$STATI")"

    if { [ "$MSG" = washes ] && [ "$ADJ" -eq 3 ]; } || { [ "$MSG" = steels ] && [ "$IMM" -ge 1 ]; }; then
        FIRED=$((FIRED+1))
        [ "$MSG" = washes ] && PENALTY=$((PENALTY+1))
        echo "seed $seed: aura fired ($MSG; ADJUST rows $ADJ, immunity rows $IMM)"
    else
        NOTFIRED=$((NOTFIRED+1))
        echo "seed $seed: aura did NOT fire (message '${MSG:-none}'; ADJUST rows $ADJ, immunity rows $IMM); see $RUN"
    fi
done

echo
if [ "$NOTFIRED" -gt 0 ]; then
    echo "FAIL: the aura fired on $FIRED of $TOTAL seeds. A hostile creature two squares"
    echo "      from a lantern archon got no message and no Aura of Menace status."
    BASERC=1
elif [ "$PENALTY" -lt 1 ]; then
    echo "INCONCLUSIVE: the aura fired on every seed but no seed failed its save, so the"
    echo "              -2 penalty rows were never seen. Add a seed that fails it."
    BASERC=2
else
    echo "PASS: the aura fired on $FIRED of $TOTAL seeds; $PENALTY showed the three -2 penalty rows."
    BASERC=0
fi
fi   # end CASE A (skipped entirely under --hit)

# ---------------------------------------------------------------------------
# CASE B: the blow that hits the aura's owner. tools/keys/aura-of-menace-hit.keys
# walks an orc barbarian into a hound archon's Aura of Menace (so the three -2
# ADJUST rows are in place), then steps adjacent and swings until a blow lands.
# The fix (src/Fight.cpp Creature::Hit) is that `this` is the ATTACKER, so on a
# landed blow it drops its own Aura of Menace ADJUST rows and gains the 24-hour
# EFF_FLAG1 immunity marker. The oracle, all three required:
#   (a) the stati dump before the blows holds three ADJUST rows with eID:Aura of
#       Menace -- so the save did fail and the penalty is really there to shed;
#   (b) the message log holds "You shake off the aura of menace.";
#   (c) the first stati dump after the landed blow holds NO Aura of Menace ADJUST
#       row and exactly one EFF FLAG1 row with eID:Aura of Menace.
# It cannot pass by default: exit 2 when the session did not play, the character
# died, no blow landed at all, or the save did not fail (no ADJUST rows before).
# Exit 1 only when a blow landed over a live penalty and the state never changed.
HITRC=0
if [ -f "$HITKEYS" ]; then
    HSEED="${HITSEED:-4}"
    HRUN="$ROOT/logs/runs/check-aura-of-menace-hit-$TOKEN-seed$HSEED"
    rm -rf "$HRUN"
    hout="$(INCURSION_RUN_DIR="$HRUN" INCURSION_OPTIONS="$OPTIONS" \
            tools/headless.sh "$HITKEYS" "$HSEED" 2>&1)"
    HS="$HRUN/logs/screens"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$hout" \
       || ! grep -q 'ended: *cleanly' <<< "$hout"; then
        echo "INCONCLUSIVE: hit mode seed $HSEED did not play to the end; see $HRUN"
        HITRC=2
    elif ! grep -q 'death: *none' <<< "$hout"; then
        echo "INCONCLUSIVE: hit mode seed $HSEED the character died; see $HRUN"
        HITRC=2
    elif ! ls "$HS"/*-log.txt >/dev/null 2>&1; then
        echo "INCONCLUSIVE: hit mode seed $HSEED left no log dump; see $HRUN"
        HITRC=2
    elif ! ls "$HS"/*-stati-before.txt >/dev/null 2>&1; then
        echo "INCONCLUSIVE: hit mode seed $HSEED left no stati-before dump; see $HRUN"
        HITRC=2
    else
        HLOG="$(ls "$HS"/*-log.txt | head -1)"
        HBEFORE="$(ls "$HS"/*-stati-before.txt | head -1)"
        hab="$(awk '/ADJUST from SS MISC/ {adj=$0; next} /eID:Aura of Menace/ && adj {n++} {adj=""} END {print n+0}' "$HBEFORE")"
        if ! grep -qE 'hitting the hound archon|You hit the hound archon|hitting .*archon' "$HLOG"; then
            echo "INCONCLUSIVE: hit mode seed $HSEED no blow landed in the session; see $HRUN"
            HITRC=2
        elif [ "$hab" -lt 1 ]; then
            echo "INCONCLUSIVE: hit mode seed $HSEED no Aura of Menace ADJUST rows before the blow"
            echo "              (the save did not fail), so there was nothing to shake off; see $HRUN"
            HITRC=2
        elif ! grep -q 'You shake off the aura of menace' "$HLOG"; then
            echo "FAIL: hit mode seed $HSEED a blow landed over $hab Aura of Menace ADJUST rows"
            echo "      but the log holds no 'You shake off the aura of menace.'; see $HRUN"
            HITRC=1
        else
            HAFTER=""; HAA=-1; HAE=-1
            for f in $(ls "$HS"/*-stati-hit*.txt 2>/dev/null | sort); do
                aa="$(awk '/ADJUST from SS MISC/ {adj=$0; next} /eID:Aura of Menace/ && adj {n++} {adj=""} END {print n+0}' "$f")"
                if [ "$aa" -eq 0 ]; then
                    HAFTER="$f"; HAA=0
                    HAE="$(awk '/EFF FLAG1 from SS MISC/ {f=$0; next} /eID:Aura of Menace/ && f {n++} {f=""} END {print n+0}' "$f")"
                    break
                fi
            done
            if [ -z "$HAFTER" ]; then
                echo "FAIL: hit mode seed $HSEED the shake-off message appeared but no post-blow"
                echo "      stati dump dropped the Aura of Menace ADJUST rows; see $HRUN"
                HITRC=1
            elif [ "$HAE" -ne 1 ]; then
                echo "FAIL: hit mode seed $HSEED after the blow ADJUST rows $HAA but EFF FLAG1"
                echo "      rows $HAE (want one immunity row); see $HAFTER; see $HRUN"
                HITRC=1
            else
                echo "hit mode seed $HSEED: PASS ($hab ADJUST rows before; after: $HAA ADJUST, $HAE EFF FLAG1; shake-off logged)"
                HITRC=0
            fi
        fi
    fi
fi

# The whole check passes only if every mode it ran passed; inconclusive (2) beats
# a clean pass but not a real failure (1), exactly as the single-mode gate did.
if [ "$BASERC" -eq 1 ] || [ "$HITRC" -eq 1 ]; then
    exit 1
fi
if [ "$BASERC" -eq 2 ] || [ "$HITRC" -eq 2 ]; then
    exit 2
fi
exit 0
