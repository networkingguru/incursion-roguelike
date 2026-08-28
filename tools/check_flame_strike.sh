#!/bin/bash
# Regression check for F2 / inc-tek.8.7: Flame Strike's description states
# 1d6 points of damage per caster level, matching its SRD-authentic
# (LEVEL_SCALED)d6 script pval. The prose read "1d8" before the fix.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/pspells.irh}"
# Anchor on the effect's unique MSG_BLASTNAME line so the check reads the real
# EA_BLAST effect block, not the commented-out spell-list index also named
# "Flame Strike" earlier in the file.
effect="$(sed -n '/pillar of flame/,/^  }/p' "$SOURCE")"

if ! printf '%s\n' "$effect" | grep -Fq '1d6 points of damage per caster level'; then
    echo "FAIL: the Flame Strike description does not state 1d6 points of damage per caster level."
    exit 1
fi

echo "PASS: F2 / inc-tek.8.7 Flame Strike description states 1d6 points of damage per caster level."
