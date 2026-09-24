#!/bin/bash
# Regression check for bd inc-5zhp / inc-tek.8.3 finding PA-03-F3: the Master
# Archer's class page advertised "Concentration +10" while the entry gate and
# the refusal message both require Concentration 7. The ruling is that the
# number is 7 and the prose was wrong, so the three must agree.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/prestige.irh}"

# Anchor on the class declaration itself so the check reads only the Master
# Archer block, not some other class's gate or prose. The block runs from
# "Class \"Master Archer\"" to the next top-level "Class " line.
class_block="$(awk '/^Class "Master Archer"/ { inblock=1 } inblock && /^Class "/ && !/^Class "Master Archer"/ { exit } inblock { print }' "$SOURCE")"

if [ -z "$class_block" ]; then
    echo "FAIL: could not find the Master Archer class block in $SOURCE -- cannot establish what it looks at."
    exit 1
fi

gate="$(printf '%s\n' "$class_block" | sed -n 's/.*ISkillLevel(SK_CONCENT)[[:space:]]*<[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
refusal="$(printf '%s\n' "$class_block" | sed -n 's/.*You must have Concentration \([0-9][0-9]*\)+.*/\1/p' | head -1)"
prose="$(printf '%s\n' "$class_block" | sed -n 's/.*Skills Levels<2> -- Concentration +\([0-9][0-9]*\).*/\1/p' | head -1)"

if [ -z "$gate" ] || [ -z "$refusal" ] || [ -z "$prose" ]; then
    echo "FAIL: could not extract all three Concentration numbers from the Master Archer block"
    echo "      gate=$gate refusal=$refusal prose=$prose -- cannot establish what it looks at."
    exit 1
fi

if [ "$gate" != "$refusal" ] || [ "$gate" != "$prose" ]; then
    echo "FAIL: Master Archer Concentration numbers disagree: gate <$gate, refusal ${refusal}+, prose +${prose}."
    exit 1
fi

echo "PASS: inc-5zhp / inc-tek.8.3 PA-03-F3 Master Archer requires Concentration $gate in the gate, the refusal message and the class page prose."
