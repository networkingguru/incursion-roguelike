#!/bin/bash
# Regression check for F48 / inc-tek.8.8: the Horn of the Sewers' description
# states that its summoned rodents have CR equal to twice its magical plus.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '/^AI_HORN Effect "the Sewers"/,/^AI_HORN Effect "the Tritons"/p' "$SOURCE")"

if ! printf '%s\n' "$effect" | grep -Fq 'twice its magical plus'; then
    echo "FAIL: the Horn of the Sewers description does not state twice its magical plus."
    exit 1
fi

echo "PASS: F48 / inc-tek.8.8 Horn of the Sewers description states twice its magical plus."
