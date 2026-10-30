#!/bin/bash
# gate: live
# inc-nypm: a mindless monster with MS_PEACEFUL must not rate the player Enemy.
# TargetSystem::RacialHostility (src/Target.cpp:566) sends M_MINDLESS straight
# to try_self_love, skipping the MS_PEACEFUL test, so a mindless monster that
# Animal Empathy has pacified still rates the player Enemy and attacks.
# Observation, not a source grep: the LOOK line of a real monster in a real
# session. "peaceful" = friendly; "hostile ... formerly peaceful" = the defect.
#   A  mindless + pacified   MUST read peaceful, not hostile   (GREEN since inc-nypm)
#   B  non-mindless + pacified   MUST read peaceful            (control, GREEN)
#   C  mindless, not pacified    MUST read hostile             (control, GREEN)
# Needs: BACKEND=posix ./build_macos.sh. Frozen druid; any seed (inc-b4l3g.13).
# fact: the Animal Empathy pacify d20 -- INCURSION_RUNTO_SKILL_ROLL=20 (exported below)
# fact: where the summoned monster lands -- the summon square is the cursor square the script picks (src/Debug.cpp:679, Q_LOC); the pacify and look steps select the monster by name
# fact: the character (stats, skills, position) -- INCURSION_LOAD fixture
# fact: the settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the monster's hostility text -- read from the look line, asserted, not controlled
# 0 all pass; 1 any FAIL (including: could not observe).
set -uo pipefail
cd "$(dirname "$0")/.."
SEED="${1:-7}"
OPTS=tools/fixtures/options-2026-08-22.dat
FIX=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav
export INCURSION_RUNTO_SKILL_ROLL=20   # the pacify roll always succeeds: cave lion DC 21, druid +6
[ -x ./incursion-headless ] || { echo "FAIL: ./incursion-headless missing; run BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs
BASE="$(mktemp -d "$PWD/logs/peaceful-mindless-XXXXXX")"
fail=0

# run <case> <expected pacify: yes|no>; sets LOOK, echoes nothing.
run() {
    local name="$1" pacify="$2" dir="$BASE/$1" out="$BASE/$1.out" shot msg
    INCURSION_RUN_DIR="$dir" INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$FIX" \
        tools/headless.sh "tools/keys/$name.keys" "$SEED" > "$out" 2>&1
    local st=$?
    LOOK=""
    if [ "$st" -ne 0 ]; then echo "  $name: headless exit $st ($out)"; return 1; fi
    if [ "$pacify" = yes ]; then
        shot="$(ls "$dir"/logs/screens/*-after-pacify.txt 2>/dev/null | head -1)"
        msg="$([ -n "$shot" ] && sed -n 2,5p "$shot" | sed 's/|.*//' | tr -s ' \n' '  ')"
        case "$msg" in *"settles back and seems much calmer"*) ;; *) shot="" ;; esac
        if [ -z "$shot" ]; then
            echo "  $name: the Animal Empathy pacify did not succeed, nothing to observe (${shot:-no screen})"
            return 1
        fi
        echo "  $name: pacify message: $msg"
    fi
    shot="$(ls "$dir"/logs/screens/*-look.txt 2>/dev/null | head -1)"
    [ -n "$shot" ] || { echo "  $name: no look screen ($out)"; return 1; }
    LOOK="$(sed -n 2p "$shot" | sed 's/|.*//; s/ *$//')"
    echo "  $name: look line: \"$LOOK\"  ($shot)"
    return 0
}

echo "A: mindless (plague of rats), pacified"
if run peaceful-mindless-rats yes; then
    case "$LOOK" in
        *rats*) ;;
        *) echo "FAIL A: the look line is not about the plague of rats"; fail=1 ;;
    esac
    if [ "$fail" -eq 0 ]; then
        case "$LOOK" in
            *hostile*) echo "FAIL A: a pacified mindless monster still rates the player Enemy (inc-nypm)"; fail=1 ;;
            *peaceful*) echo "PASS A: pacified mindless monster reads peaceful" ;;
            *) echo "FAIL A: look line shows neither hostile nor peaceful"; fail=1 ;;
        esac
    fi
else echo "FAIL A: could not establish the observation"; fail=1; fi

echo "B: control, non-mindless (cave lion), pacified"
if run peaceful-animal-lion yes; then
    case "$LOOK" in
        *lion*hostile*|*hostile*lion*) echo "FAIL B: control broken, pacified lion reads hostile"; fail=1 ;;
        *lion*) case "$LOOK" in *peaceful*) echo "PASS B: pacified non-mindless monster reads peaceful" ;;
                  *) echo "FAIL B: lion look line lacks peaceful"; fail=1 ;; esac ;;
        *) echo "FAIL B: the look line is not about the cave lion"; fail=1 ;;
    esac
else echo "FAIL B: could not establish the observation"; fail=1; fi

echo "C: control, mindless (plague of rats), not pacified"
if run hostile-mindless-rats no; then
    case "$LOOK" in
        *rats*hostile*|*hostile*rats*)
            case "$LOOK" in *peaceful*) echo "FAIL C: unpacified rats read peaceful"; fail=1 ;;
                *) echo "PASS C: unpacified mindless monster reads hostile" ;; esac ;;
        *) echo "FAIL C: unpacified rats do not read hostile"; fail=1 ;;
    esac
else echo "FAIL C: could not establish the observation"; fail=1; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "RED (see FAIL lines); specimens: $BASE"
exit "$fail"
