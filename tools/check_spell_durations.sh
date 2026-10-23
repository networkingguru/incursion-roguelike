#!/bin/bash
# gate: live
# inc-nt3z: spell duration classes (docs/specs/2026-10-22-spell-durations-spec.md
# sections 2 and 9). Runs INCURSION_DURATION_PROBE, which calls EffectDuration
# (src/Magic.cpp), the function Magic::CalcEffect uses, at caster levels 1, 6
# and 20 with plain, Extend, Anchor+Extend, Anchor+Mystic Preparation+Extend
# and Persistent. INCURSION_DURATION_PROBE_FLAG forces each class onto one
# spell, so every class is measured whatever the spells carry today.
# Does not build; run BACKEND=posix ./build_macos.sh first.
# Phase 2 (spec section 3): runs the 15 buff spells as they ship, no forced flag,
# and requires plain duration -2 (EF_PERSISTANT) at CL 1, 6 and 20. It also greps
# lib/program.i for EF_LOSEMANA (78) and EF_PERSISTANT (85) in each spell, for no
# timer flag (23-26, 110-113), and for the section 3b mana costs.
# Phase 3 (spec section 4): runs the 47 class-flag spells as they ship and requires
# the plain duration at CL 1, 6 and 20 to equal the class in the section 4 table.
# Phase 4 (spec sections 5a and 5c): runs INCURSION_DURATION_PROBE_HANDLER, which
# runs the spell's compiled EV_CALC_EFFECT handler after EffectDuration as
# Magic::CalcEffect does. The 5a dice-in-rounds spells (8 rows: Cause Fear, Unholy
# Blight, Chaos Hammer, Othello's Irresistable Dance, Hypnotism, Ghoul Touch, Cause
# Blindness spell and monster ray) are measured as the min and max over 2000 runs
# at CL 1, 6 and 20. Chill Metal, Heat Metal and Dancing Lights are measured at CL
# 1, 6 and 20. All 11 are measured plain, with Extend, with Anchor+Extend and with
# Persistent: each handler calls ApplyDurationMetamagic (the rule EffectDuration
# uses), so the expected value is the metamagic rule applied to the base min and
# max. Vampiric Touch keeps EF_DLONG and has no handler (ruled 2026-10-23): it is
# a shipped-spell class row and a structural row. The check also greps
# lib/program.i for the exact script line and for no EF_DSHORT (23) or EF_DLONG
# (25) in each of the 11 handler spells (structural).
# Phase 5 (spec section 5b): script durations written in rounds convert exactly
# once. Measured through the compiled handler (INCURSION_DURATION_PROBE_HANDLER,
# 20000 samples, min and max): Scare, Convulsion (plain and Anchor),
# Nemesis Spell and Music of the Spheres (part 0 stays in rounds, part 1 is the
# paralysis in units). The other converted sites are structural: the new script
# line is in lib/program.i (or src/Fight.cpp for Dirty Fighting) and the old
# line is absent. Music of the Spheres drops 2*choir and slow gets its own
# duration; tools/check_music_spheres_area.sh measures the god conditions.
# Phase 6 (spec section 5d): Blasphemy is the SRD spell. INCURSION_DURATION_PROBE_BLASPHEMY
# (src/DurationProbe.cpp BlasTierProbe) casts the shipped spell through ReThrow(EV_EFFECT)
# at caster level 10 on real monsters of Challenge Rating (the HD measure) 11, 10, 9 and 5,
# 1000 casts each plain, Extend and Persistent, and prints the count, min and max of each
# condition. One cast each for a living CR 0 monster (killed), a nonevil undead (destroyed)
# and a nonevil outsider with the Will save forced to 1 (banished) and 20 (not banished).
# A structural pass greps the compiled Blasphemy block in lib/program.i.
# FAILS when the probe prints nothing or prints a wrong value.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: spell resource exists -- FIND("Sleep") by name; a missing name prints INCONCLUSIVE
# fact: duration class -- INCURSION_DURATION_PROBE_FLAG forces it (NONE = default class)
# fact: caster level -- the probe passes 1, 6 and 20 itself
# fact: duration roll -- none; EF_DSHORT (1d4+1) is not exercised
# fact: shipped spell flags -- the probe reads the compiled module, no forced flag
# fact: spell block in lib/program.i -- from its header line to the next Spell/Effect header
# fact: handler dice -- min and max over INCURSION_DURATION_PROBE_SAMPLES=2000 runs;
#       the least likely extreme (Cause Blindness min, 1/128 per run) is missed
#       with probability 1.5e-7, so the result does not depend on the seed
# fact: phase 5 handler dice -- min and max over INCURSION_DURATION_PROBE_SAMPLES=20000
#       runs; the least likely extreme (Scare min at cl 6 or 20, 1/8 per run) is
#       missed with probability e^-2500, so the result does not depend on the seed
# fact: effect part -- INCURSION_DURATION_PROBE_EFNUM names it (Music of the Spheres)
# fact: key script -- tools/keys/bane-radius.keys (loads, runs one turn, quits)
# fact: phase 6 key script -- tools/keys/blasphemy-tiers.keys (40000 SPACE keys answer the -More- prompts)
# fact: phase 6 caster level -- INCURSION_DURATION_PROBE_BLASPHEMY_CL=10 (the probe adds spellcasting levels)
# fact: phase 6 victims -- the probe scans the module for a monster of the wanted Challenge
#       Rating that is not evil, has no magic resistance and is not immune to paralysis or
#       death, and places it on an open line; the result does not depend on which one it picks
# fact: phase 6 Will save -- LOFSetForcedSaveThrowRoll(1) and (20) inside the probe
# fact: phase 6 dice -- min and max over INCURSION_DURATION_PROBE_BLASPHEMY=1000 casts; the
#       least likely extreme (Strength penalty 2d6 = 2, 1/36 per cast) is missed with
#       probability 6e-13, so the result does not depend on the seed
# fact: phase 6 fatigue and caster stati -- the probe resets them before every cast
# Usage: tools/check_spell_durations.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav
SPELL="Sleep"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# base <flag> <cl>: the class duration before any doubling (spec section 2).
base() {
    case "$1" in
        EF_D1ROUND)    echo 2 ;;
        EF_DLONG)      echo $((100 + $2 * 10)) ;;
        EF_DXLONG)     echo $((1000 + $2 * 100)) ;;
        EF_DROUND)     r=$((($2 + 1) / 2)); echo $((r < 1 ? 1 : r)) ;;
        EF_DMIN)       echo $((5 * $2)) ;;
        EF_D10MIN)     echo $((50 * $2)) ;;
        EF_DHOUR)      echo $((300 * $2)) ;;
        EF_PERSISTANT) echo -2 ;;
        EF_PERMANANT)  echo -1 ;;
        NONE)          echo $((10 + $2 * 2)) ;;
    esac
}

# want <flag> <cl> <mod>: spec value; above 32767 becomes -2.
want() {
    local d anchor=0 mystic=0 ext=0 pers=0
    d=$(base "$1" "$2")
    case "$3" in
        extend) ext=1 ;;
        anchor+extend) anchor=1; ext=1 ;;
        anchor+mystic+extend) anchor=1; mystic=1; ext=1 ;;
        persistent) pers=1 ;;
    esac
    [ $anchor = 1 ] && [ "$d" -gt 1 ] && d=$((d * 2))
    [ $mystic = 1 ] && [ "$d" -gt 1 ] && d=$((d * 2))
    if [ $pers = 1 ] && [ "$d" -ge 10 ]; then d=-2
    elif [ $ext = 1 ] && [ "$d" -ge 1 ]; then d=$((d * 2)); fi
    [ "$d" -gt 32767 ] && d=-2
    echo "$d"
}

fail=0
rows=0
for flag in EF_DROUND EF_DMIN EF_D10MIN EF_DHOUR EF_DLONG EF_DXLONG NONE; do
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-$flag"
    INCURSION_DURATION_PROBE="$SPELL" INCURSION_DURATION_PROBE_FLAG="$flag" \
        INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" 1 >/dev/null 2>&1
    log="$RUN_DIR/logs/errors.log"
    lines="$(grep 'DURATION_PROBE: spell=' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "FAIL: $flag: probe printed nothing ($log). Is DurationProbe still called from Game::Play()?"
        fail=1
        continue
    fi
    n=0
    for cl in 1 6 20; do
        for mod in plain extend anchor+extend anchor+mystic+extend persistent; do
            got="$(grep " flag=$flag cl=$cl mod=$mod " <<< "$lines" | sed -n 's/.* dur=\(-\{0,1\}[0-9]*\)$/\1/p')"
            w="$(want "$flag" "$cl" "$mod")"
            n=$((n + 1)); rows=$((rows + 1))
            if [ "$got" = "$w" ]; then
                echo "PASS: $flag cl=$cl $mod dur=$got"
            else
                echo "FAIL: $flag cl=$cl $mod got='${got}' want=$w"
                fail=1
            fi
        done
    done
    [ "$n" -eq 15 ] || { echo "FAIL: $flag: $n rows, want 15"; fail=1; }
done


# Real spells (spec sections 3a and 3b): no forced flag, plain duration is -2.
BUFFS=("Rainstorm" "Protection from Undead" "Gaze Reflection" "Iron Mind"
    "Endure the Elements" "Resist the Elements" "Protection from Elements"
    "Invisibility" "Levitation" "Divine Power" "Righteous Might" "Shield Other"
    "Tevlar's Transformation" "Slow Poison" "Neutralize Poison")
real=0
for sp in "${BUFFS[@]}"; do
    tag="${sp//[^A-Za-z]/}"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-real-$tag"
    INCURSION_DURATION_PROBE="$sp" \
        INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" 1 >/dev/null 2>&1
    log="$RUN_DIR/logs/errors.log"
    lines="$(grep 'DURATION_PROBE: spell=' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "FAIL: $sp: probe printed nothing ($log)"
        fail=1
        continue
    fi
    for cl in 1 6 20; do
        got="$(grep "^.*DURATION_PROBE: spell=$sp flag=own cl=$cl mod=plain " <<< "$lines" | sed -n 's/.* dur=\(-\{0,1\}[0-9]*\)$/\1/p')"
        real=$((real + 1))
        if [ "$got" = "-2" ]; then
            echo "PASS: $sp as shipped cl=$cl plain dur=$got"
        else
            echo "FAIL: $sp as shipped cl=$cl plain got='${got}' want=-2"
            fail=1
        fi
    done
done
[ "$real" -eq 45 ] || { echo "FAIL: $real shipped-spell rows, want 45"; fail=1; }

# Phase 3 (spec section 4): the class-flag spells as they ship, no forced flag.
# Plain duration at CL 1, 6 and 20 MUST equal the class named in the table.
CLASSES=(
    "Grease:EF_DROUND" "Halt Undead:EF_DROUND" "Hold Person:EF_DROUND"
    "Hold Monster:EF_DROUND" "Hold Beast:EF_DROUND" "Slow:EF_DROUND"
    "Confusion:EF_DROUND" "Fear:EF_DROUND" "Glitterdust:EF_DROUND"
    "Dominate Animal:EF_DROUND" "Dominate Reptile:EF_DROUND" "Wind Wall:EF_DROUND"
    "Hideous Laughter:EF_DROUND" "Ethereal Jaunt:EF_DROUND" "Dispel Evil:EF_DROUND"
    "Spiritual Hammer:EF_DROUND" "Flaming Sphere:EF_DROUND" "Calm Emotions:EF_DROUND"
    "Divine Sacrifice:EF_DROUND"
    "Wall of Fog:EF_DMIN" "Sleep:EF_DMIN" "Deep Slumber:EF_DMIN" "Bane:EF_DMIN"
    "Doom:EF_DMIN" "Polymorph Other:EF_DMIN" "Polymorph Self:EF_DMIN"
    "Reduce:EF_DMIN" "Mirror Image:EF_DMIN" "Clairvoyance:EF_DMIN"
    "Solid Fog:EF_DMIN" "Crushing Despair:EF_DMIN" "Dimensional Anchor:EF_DMIN"
    "Faerie Fire:EF_DMIN" "Spectral Hand:EF_DMIN"
    "Change Self:EF_D10MIN" "Web:EF_D10MIN" "Fire Seeds;spell:EF_D10MIN"
    "Charm Person:EF_DHOUR"
    "Holy Smite:EF_D1ROUND" "Order's Wrath:EF_D1ROUND" "Command:EF_D1ROUND"
    "Charm Monster:EF_PERSISTANT" "Dominate Person:EF_PERSISTANT"
    "Dominate Monster:EF_PERSISTANT" "Control Plant:EF_PERSISTANT"
    "Consecrate:EF_PERSISTANT"
    "Wall of Stone:EF_PERMANANT" "Vampiric Touch:EF_DLONG")
cls=0
for entry in "${CLASSES[@]}"; do
    sp="${entry%%:*}"; cflag="${entry##*:}"
    tag="${sp//[^A-Za-z]/}"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-class-$tag"
    INCURSION_DURATION_PROBE="$sp" \
        INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" 1 >/dev/null 2>&1
    log="$RUN_DIR/logs/errors.log"
    lines="$(grep 'DURATION_PROBE: spell=' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "FAIL: $sp: probe printed nothing ($log)"
        fail=1
        continue
    fi
    for cl in 1 6 20; do
        got="$(grep "^.*DURATION_PROBE: spell=$sp flag=own cl=$cl mod=plain " <<< "$lines" | sed -n 's/.* dur=\(-\{0,1\}[0-9]*\)$/\1/p')"
        w="$(base "$cflag" "$cl")"
        cls=$((cls + 1))
        if [ "$got" = "$w" ]; then
            echo "PASS: $sp as shipped cl=$cl plain dur=$got ($cflag)"
        else
            echo "FAIL: $sp as shipped cl=$cl plain got='${got}' want=$w ($cflag)"
            fail=1
        fi
    done
done
[ "$cls" -eq 144 ] || { echo "FAIL: $cls class-flag rows, want 144"; fail=1; }

# Structural: each spell block in lib/program.i has EF_LOSEMANA (78) and
# EF_PERSISTANT (85), no timer flag, and the section 3b cost.
[ -f lib/program.i ] || { echo "FAIL: lib/program.i missing. Run: BACKEND=posix ./build_macos.sh"; exit 1; }
# cost_of <spell>: section 3b cost; empty for a spell with no cost ruling.
cost_of() {
    case "$1" in
        Invisibility|Levitation|"Shield Other") echo 15 ;;
        "Slow Poison") echo 5 ;;
        "Divine Power") echo 35 ;;
        "Righteous Might") echo 45 ;;
        "Tevlar's Transformation") echo 55 ;;
        "Neutralize Poison") echo 7 ;;
    esac
}
structural=0
for sp in "${BUFFS[@]}"; do
    block="$(awk -v n="$sp" '
        /(Spell|Effect) "[^"]*" *:/ {
            if (f) exit
            if (index($0, "\"" n "\" :") > 0) f = 1
        }
        f { print }' lib/program.i)"
    if [ -z "$block" ]; then
        echo "FAIL: $sp: no block in lib/program.i"
        fail=1
        continue
    fi
    flags="$(grep -o 'Flags: [0-9, ]*' <<< "$block" | sed 's/Flags://' | tr ',' '\n' | tr -d ' ' | sort -u)"
    structural=$((structural + 1))
    for need in 78 85; do
        grep -qx "$need" <<< "$flags" || { echo "FAIL: $sp lacks flag $need (78 EF_LOSEMANA, 85 EF_PERSISTANT)"; fail=1; }
    done
    for bad in 23 24 25 26 110 111 112 113; do
        grep -qx "$bad" <<< "$flags" && { echo "FAIL: $sp still carries timer flag $bad"; fail=1; }
    done
    want_cost="$(cost_of "$sp")"
    if [ -n "$want_cost" ]; then
        cost="$(grep -o 'Cost: [0-9]*' <<< "$block" | head -1 | sed 's/Cost: //')"
        if [ "$cost" = "$want_cost" ]; then
            echo "PASS: $sp cost $cost"
        else
            echo "FAIL: $sp cost got='$cost' want=$want_cost"
            fail=1
        fi
    fi
done
[ "$structural" -eq 15 ] || { echo "FAIL: $structural structural spells, want 15"; fail=1; }

# Phase 4 (spec sections 5a and 5c): measured through the compiled handler.
# Line format: "spell|samples|min|max". Every CL 1, 6, 20 plain row must match.
HANDLERS=(
    "Cause Fear|2000|1|2" "Unholy Blight|2000|1|2" "Chaos Hammer|2000|1|3"
    "Othello's Irresistable Dance|2000|1|3" "Hypnotism|2000|1|4"
    "Ghoul Touch|2000|1|4" "Cause Blindness|2000|1|6"
    "Cause Blindness;ray|2000|1|6"
    "Chill Metal|1|4|4" "Heat Metal|1|4|4" "Dancing Lights|1|5|5")
# mm_want <duration> <mod>: ApplyDurationMetamagic (spec 2) on a base duration.
# It never decreases a duration, so the min and max map to the min and max.
mm_want() {
    local d=$1
    case "$2" in
        extend) [ "$d" -ge 1 ] && d=$((d * 2)) ;;
        anchor+extend)
            [ "$d" -gt 1 ] && d=$((d * 2))
            [ "$d" -ge 1 ] && d=$((d * 2)) ;;
        persistent) [ "$d" -ge 10 ] && d=-2 ;;
    esac
    [ "$d" -gt 32767 ] && d=-2
    echo "$d"
}
measured=0
for entry in "${HANDLERS[@]}"; do
    IFS='|' read -r sp samples emin emax <<< "$entry"
    tag="${sp//[^A-Za-z]/}"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-handler-$tag"
    INCURSION_DURATION_PROBE="$sp" INCURSION_DURATION_PROBE_HANDLER=1 \
        INCURSION_DURATION_PROBE_SAMPLES="$samples" \
        INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" 1 >/dev/null 2>&1
    log="$RUN_DIR/logs/errors.log"
    lines="$(grep 'DURATION_PROBE_HANDLER: spell=' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "FAIL: $sp: handler probe printed nothing ($log)"
        fail=1
        continue
    fi
    mods="plain extend anchor+extend persistent"
    for cl in 1 6 20; do
        for mod in $mods; do
            row="$(grep "DURATION_PROBE_HANDLER: spell=$sp cl=$cl mod=$mod " <<< "$lines")"
            gmin="$(sed -n 's/.* min=\(-\{0,1\}[0-9]*\) max=.*/\1/p' <<< "$row")"
            gmax="$(sed -n 's/.* max=\(-\{0,1\}[0-9]*\)$/\1/p' <<< "$row")"
            wmin="$(mm_want "$emin" "$mod")"; wmax="$(mm_want "$emax" "$mod")"
            measured=$((measured + 1))
            if [ "$gmin" = "$wmin" ] && [ "$gmax" = "$wmax" ]; then
                echo "PASS: $sp handler cl=$cl $mod min=$gmin max=$gmax"
            else
                echo "FAIL: $sp handler cl=$cl $mod got min='$gmin' max='$gmax' want min=$wmin max=$wmax"
                fail=1
            fi
        done
    done
done
[ "$measured" -eq 132 ] || { echo "FAIL: $measured handler rows, want 132"; fail=1; }

# Phase 4 structural: the script line, and no EF_DSHORT (23) or EF_DLONG (25).
# "spell|exact script line"
SCRIPTS=(
    "Cause Fear|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(1d4), e.MM, 0);"
    "Unholy Blight|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(1d4), e.MM, 0);"
    "Chaos Hammer|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(1d6), e.MM, 0);"
    "Othello's Irresistable Dance|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(1d4+1), e.MM, 0);"
    "Hypnotism|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(2d4), e.MM, 0);"
    "Ghoul Touch|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(1d6+2), e.MM, 0);"
    "Cause Blindness|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(3d4), e.MM, 0);"
    "Cause Blindness;ray|e.vDuration = ApplyDurationMetamagic(RoundsToUnits(3d4), e.MM, 0);"
    "Chill Metal|e.vDuration = ApplyDurationMetamagic(4, e.MM, 0);"
    "Heat Metal|e.vDuration = ApplyDurationMetamagic(4, e.MM, 0);"
    "Dancing Lights|e.vDuration = ApplyDurationMetamagic(5, e.MM, 0);")
p4struct=0
for entry in "${SCRIPTS[@]}"; do
    sp="${entry%%|*}"; line="${entry#*|}"
    block="$(awk -v n="$sp" '
        /^([0-9 \/]*)?(Spell|Effect|Monster) "[^"]*" *:/ {
            if (f) exit
            if (index($0, "\"" n "\" :") > 0) f = 1
        }
        f { print }' lib/program.i)"
    p4struct=$((p4struct + 1))
    if [ -z "$block" ]; then
        echo "FAIL: $sp: no block in lib/program.i"
        fail=1
        continue
    fi
    if grep -qF -- "$line" <<< "$block"; then
        echo "PASS: $sp script line: $line"
    else
        echo "FAIL: $sp lacks script line: $line"
        fail=1
    fi
    if [ "$sp" != "Dancing Lights" ]; then
        flags="$(grep -o 'Flags: [0-9, ]*' <<< "$block" | sed 's/Flags://' | tr ',' '\n' | tr -d ' ' | sort -u)"
        for bad in 23 25; do
            grep -qx "$bad" <<< "$flags" && { echo "FAIL: $sp still carries duration flag $bad"; fail=1; }
        done
    fi
done
[ "$p4struct" -eq 11 ] || { echo "FAIL: $p4struct phase 4 structural spells, want 11"; fail=1; }

# Vampiric Touch (ruled 2026-10-23): keeps EF_DLONG (25), has no duration handler.
vblock="$(awk '
    /^([0-9 \/]*)?(Spell|Effect|Monster) "[^"]*" *:/ {
        if (f) exit
        if (index($0, "\"Vampiric Touch\" :") > 0) f = 1
    }
    f { print }' lib/program.i)"
vflags="$(grep -o 'Flags: [0-9, ]*' <<< "$vblock" | sed 's/Flags://' | tr ',' '\n' | tr -d ' ' | sort -u)"
if [ -z "$vblock" ]; then
    echo "FAIL: Vampiric Touch: no block in lib/program.i"; fail=1
else
    grep -qx 25 <<< "$vflags" && echo "PASS: Vampiric Touch carries EF_DLONG" || { echo "FAIL: Vampiric Touch lacks EF_DLONG (25)"; fail=1; }
    if grep -q 'vDuration' <<< "$vblock"; then echo "FAIL: Vampiric Touch has a duration handler"; fail=1; else echo "PASS: Vampiric Touch has no duration handler"; fi
fi

# Phase 5 (spec section 5b): rounds converted once. ru_lo and ru_hi give the
# smallest and largest unit count RoundsToUnits returns for a round count:
# half the rounds rounded down or up, and never below 1.
ru_lo() { local u=$(($1 / 2)); echo $((u < 1 ? 1 : u)); }
ru_hi() { local u=$((($1 + 1) / 2)); echo $((u < 1 ? 1 : u)); }
# p5_want <spell> <cl> <mod>: "min max" over the samples.
p5_want() {
    local sp="$1" cl="$2" mod="$3"
    case "$sp" in
        Scare) echo "$(ru_lo $((1 + cl / 3))) $(ru_hi $((4 + cl / 3)))" ;;
        Convulsion)
            if [ "$mod" = "anchor+extend" ]; then echo "$(ru_lo 2) $(ru_hi 8)"
            else echo "$(ru_lo 1) $(ru_hi 4)"; fi ;;
        "Nemesis Spell")
            if [ "$mod" = "anchor+extend" ]; then echo "$((2 * $(ru_lo 13))) $((2 * $(ru_hi 13)))"
            else echo "$(ru_lo 13) $(ru_hi 13)"; fi ;;
        "Music of the Spheres;0") echo "$cl $cl" ;;
        "Music of the Spheres;1") echo "$(ru_lo 1) $(ru_hi 4)" ;;
    esac
}
P5=("Scare" "Convulsion" "Nemesis Spell"
    "Music of the Spheres;0" "Music of the Spheres;1")
p5meas=0
for entry in "${P5[@]}"; do
    sp="${entry%%;*}"; part="${entry#*;}"; [ "$part" = "$entry" ] && part=0
    tag="${entry//[^A-Za-z0-9]/}"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-p5-$tag"
    INCURSION_DURATION_PROBE="$sp" INCURSION_DURATION_PROBE_HANDLER=1 \
        INCURSION_DURATION_PROBE_SAMPLES=20000 INCURSION_DURATION_PROBE_EFNUM="$part" \
        INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" 1 >/dev/null 2>&1
    log="$RUN_DIR/logs/errors.log"
    lines="$(grep 'DURATION_PROBE_HANDLER: spell=' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "FAIL: $entry: phase 5 handler probe printed nothing ($log)"
        fail=1
        continue
    fi
    for cl in 1 6 20; do
        for mod in plain extend anchor+extend persistent; do
            row="$(grep "DURATION_PROBE_HANDLER: spell=$sp cl=$cl mod=$mod " <<< "$lines")"
            gmin="$(sed -n 's/.* min=\(-\{0,1\}[0-9]*\) max=.*/\1/p' <<< "$row")"
            gmax="$(sed -n 's/.* max=\(-\{0,1\}[0-9]*\)$/\1/p' <<< "$row")"
            read -r wmin wmax <<< "$(p5_want "$entry" "$cl" "$mod")"
            p5meas=$((p5meas + 1))
            if [ "$gmin" = "$wmin" ] && [ "$gmax" = "$wmax" ]; then
                echo "PASS: $entry handler cl=$cl $mod min=$gmin max=$gmax"
            else
                echo "FAIL: $entry handler cl=$cl $mod got min='$gmin' max='$gmax' want min=$wmin max=$wmax"
                fail=1
            fi
        done
    done
done
[ "$p5meas" -eq 60 ] || { echo "FAIL: $p5meas phase 5 handler rows, want 60"; fail=1; }

# Phase 5 structural: "file|new ERE|old ERE|count". The new pattern MUST match
# exactly count lines and the old pattern (when given) MUST match none. The
# compiled script text is lib/program.i (constants are numbers there); Dirty
# Fighting is in src/Fight.cpp.
P5S=(
 'lib/program.i|e\.vDuration = RoundsToUnits\(1d4 \+ e\.vCasterLev / 3\);|e\.vDuration = 1d4 \+ e\.vCasterLev / 3;|1'
 'lib/program.i|RoundsToUnits\(2d4\) : RoundsToUnits\(1d4\);|\? 2d4 : 1d4;|1'
 'lib/program.i|e\.vDuration = RoundsToUnits\(1d4\);||2'
 'lib/program.i|e\.vDuration = RoundsToUnits\(3d6\);||1'
 'lib/program.i|e\.vDuration = RoundsToUnits\(10d6\);|e\.vDuration = 10d6;|1'
 'lib/program.i|GainTempStati\([0-9]+,EItem,RoundsToUnits\(1d4\),|GainTempStati\([0-9]+,EItem,1d4,|1'
 'lib/program.i|GainTempStati\([0-9]+,EItem,RoundsToUnits\(1d6\+1\),|GainTempStati\([0-9]+,EItem,1d6\+1,|1'
 'lib/program.i|GainTempStati\([0-9]+,EItem,RoundsToUnits\(2d8\),|GainTempStati\([0-9]+,EItem,2d8,|1'
 'lib/program.i|GainTempStati\(189,NULL,RoundsToUnits\(1d4\+1\),|GainTempStati\(189,NULL,1d4\+1,|1'
 'lib/program.i|EVictim->GainTempStati\(20,EActor,RoundsToUnits\(2d4\),|EVictim->GainTempStati\(20,EActor,2d4,|1'
 'lib/program.i|GainTempStati\(9,EActor,RoundsToUnits\(1d4\),2,1,0,\$"emotion"\)|GainTempStati\(9,EActor,1d4\+1,|1'
 'lib/program.i|GainTempStati\(5,NULL,RoundsToUnits\(1d4\+1\),7\);|GainTempStati\(5,NULL,1d4\+1,7\);|1'
 'lib/program.i|e\.vDuration = RoundsToUnits\(13\);|e\.vDuration = 13;|1'
 'lib/program.i|e\.vDuration = e\.vCasterLev;|2\*choir|1'
 'src/Fight.cpp|GainTempStati\(BLIND,NULL,RoundsToUnits\(Dice::Roll\(1,4,1\)\),SS_ATTK\);|GainTempStati\(BLIND,NULL,Dice::Roll\(1,4,1\),SS_ATTK\);|1'
 'lib/program.i|SetEffStatiDur\(106,\$"slow",RoundsToUnits\(e\.vDuration\),|2\*choir|2'
)
p5struct=0
for entry in "${P5S[@]}"; do
    IFS='|' read -r f newf oldf want <<< "$entry"
    p5struct=$((p5struct + 1))
    n="$(grep -cE -- "$newf" "$f")"
    if [ "$n" != "$want" ]; then
        echo "FAIL: $f has $n lines matching $newf, want $want"
        fail=1
    elif [ -n "$oldf" ] && grep -qE -- "$oldf" "$f"; then
        echo "FAIL: $f still matches old pattern $oldf"
        fail=1
    else
        echo "PASS: $f has $n x $newf"
    fi
done
[ "$p5struct" -eq 16 ] || { echo "FAIL: $p5struct phase 5 structural rows, want 16"; fail=1; }

# Phase 6 (spec section 5d): Blasphemy tiers, measured through the real cast.
# bl_range <lo> <hi> <mod>: ApplyDurationMetamagic on both extremes, as "min max".
bl_range() {
    local a b
    a="$(mm_want "$1" "$3")"; b="$(mm_want "$2" "$3")"
    if [ "$a" -le "$b" ]; then echo "$a $b"; else echo "$b $a"; fi
}
BL_RUN="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-spell-dur-blasphemy"
INCURSION_DURATION_PROBE_BLASPHEMY=1000 INCURSION_DURATION_PROBE_BLASPHEMY_CL=10 \
    INCURSION_RUN_DIR="$BL_RUN" INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh tools/keys/blasphemy-tiers.keys 1 >/dev/null 2>&1
bl_log="$BL_RUN/logs/errors.log"
bl_rows=0
if ! grep -q 'BLASPHEMY_TIER: hit tier=' "$bl_log" 2>/dev/null; then
    echo "FAIL: Blasphemy probe printed nothing ($bl_log)"
    fail=1
fi
if grep -q 'BLASPHEMY_TIER: INCONCLUSIVE' "$bl_log" 2>/dev/null; then
    echo "FAIL: Blasphemy probe INCONCLUSIVE: $(grep -m1 'BLASPHEMY_TIER: INCONCLUSIVE' "$bl_log" | sed 's/.*INCONCLUSIVE/INCONCLUSIVE/')"
    fail=1
fi
for mod in plain extend persistent; do
    read -r dlo dhi <<< "$(bl_range 2 2 $mod)"
    read -r hlo hhi <<< "$(bl_range 5 50 $mod)"
    read -r wlo whi <<< "$(bl_range 1 4 $mod)"
    for tier in above:11 equal:10 minus1:9 minus5:5; do
        name="${tier%%:*}"; cr="${tier##*:}"
        case "$name" in
            above)  want="daze=0:0..0 held=0:0..0 weak=0:0..0 str=0..0" ;;
            equal)  want="daze=1000:$dlo..$dhi held=0:0..0 weak=0:0..0 str=0..0" ;;
            minus1) want="daze=1000:$dlo..$dhi held=0:0..0 weak=1000:$wlo..$whi str=2..12" ;;
            minus5) want="daze=1000:$dlo..$dhi held=1000:$hlo..$hhi weak=1000:$wlo..$whi str=2..12" ;;
        esac
        got="$(grep "BLASPHEMY_TIER: hit tier=$name cr=$cr mod=$mod " "$bl_log" | sed 's/.* mod=[a-z]* //')"
        bl_rows=$((bl_rows + 1))
        if [ "$got" = "$want" ]; then
            echo "PASS: Blasphemy $name (cr $cr) $mod $got"
        else
            echo "FAIL: Blasphemy $name (cr $cr) $mod got='$got' want='$want'"
            fail=1
        fi
    done
done
for entry in 'kill tier=minus10 cr=0 dead=1' 'undead cr=0 dead=1' \
             'banish roll=1 cr=5 dead=1' 'banish roll=20 cr=5 dead=0'; do
    bl_rows=$((bl_rows + 1))
    if grep -q "BLASPHEMY_TIER: $entry\$" "$bl_log" 2>/dev/null; then
        echo "PASS: Blasphemy $entry"
    else
        echo "FAIL: Blasphemy lacks line '$entry'"
        fail=1
    fi
done
# Structural: the compiled Blasphemy block carries the new durations and none of the old power test.
bl_block="$(awk '
    /^([0-9 \/]*)?(Spell|Effect|Monster) "[^"]*" *:/ {
        if (f) exit
        if (index($0, "\"Blasphemy\" :") > 0) f = 1
    }
    f { print }' lib/program.i)"
for need in 'ApplyDurationMetamagic(2,e.MM,0)' 'ApplyDurationMetamagic(5\*1d10,e.MM,0)' \
            'ApplyDurationMetamagic(RoundsToUnits(2d4),e.MM,0)'; do
    bl_rows=$((bl_rows + 1))
    if grep -q -- "$need" <<< "$bl_block"; then echo "PASS: Blasphemy block has $need"
    else echo "FAIL: Blasphemy block lacks $need"; fail=1; fi
done
bl_rows=$((bl_rows + 1))
if grep -qE 'vPower|vCR|ChallengeRating\(\) *\+ *[369]|GainTempStati\(5,' <<< "$bl_block"; then
    echo "FAIL: Blasphemy block still holds the old power test or stun"; fail=1
else echo "PASS: Blasphemy block holds no old power test or stun"; fi
[ "$bl_rows" -eq 20 ] || { echo "FAIL: $bl_rows Blasphemy rows, want 20"; fail=1; }

[ "$rows" -eq 105 ] || { echo "FAIL: $rows rows, want 105"; fail=1; }
if [ $fail -ne 0 ]; then
    echo "FAIL: spell duration check"
    exit 1
fi
echo "PASS: $rows duration rows, $real buff rows, $cls class rows, $measured handler rows, $p4struct structural spells, $p5meas phase 5 handler rows, $p5struct phase 5 structural rows and $bl_rows Blasphemy rows match the spec."
