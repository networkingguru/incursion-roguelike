#!/bin/bash
# gate: cheap
# Regression check for inc-tek.3.3: the Strength domain Desc must state the
# bonus the code gives (Feat of Strength is +1 at 1st priest level and +1 more
# every four levels after), NOT "equal to your full priest level".
# fact: domain Desc text -- source-text grep of lib/domains.irh, no seed
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/domains.irh}"
block="$(sed -n '/^Domain "Strength" : 0/,/^  }/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if grep -q "equal to your full priest" <<< "$flat"; then
    echo "FAIL: the Strength domain Desc still promises a bonus equal to your full priest level."
    exit 1
fi

for phrase in "bonus of +1 to your Strength at 1st priest level and every five priest levels after" \
              "+1 at 1st priest level, and +1 more every four priest levels after"; do
    if ! grep -qF "$phrase" <<< "$flat"; then
        echo "FAIL: the Strength domain Desc lacks: $phrase"
        exit 1
    fi
done

echo "PASS: inc-tek.3.3 Strength domain Desc states the bonus the code gives."
