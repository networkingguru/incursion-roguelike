#!/bin/bash
# Regression check for PA-08-F72 / inc-tek.8.8: the Wand of Striking's
# knockback rider is folded into the telekinetic bolt's single Reflex save,
# instead of rolling a second, independent save. Two structural facts must
# hold: the AD_KNOC rider shares the bolt's strike (aval: AR_BOLT), so
# MagicStrike makes no reroll for it, and the wand carries the handler that
# drops the knockback segment (efNum 1) when the target made that one save
# (e.Resist). RED on a tree with either fact missing, GREEN once both hold.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
block="$(sed -n '
  /^AI_WAND Effect "Striking;wand" : EA_BLAST/,/^AI_WAND Effect "the Hellstorm"/ {
    /^AI_WAND Effect "the Hellstorm"/q
    p
  }
' "$SOURCE")"

if [[ -z "$block" ]]; then
    echo "FAIL: could not find the Wand of Striking block in $SOURCE."
    exit 1
fi

rider="$(printf '%s\n' "$block" | grep 'AD_KNOC')"
if [[ -z "$rider" ]]; then
    echo "FAIL: could not find the Wand of Striking AD_KNOC knockback rider."
    exit 1
fi
if ! printf '%s\n' "$rider" | grep -q 'aval:[[:space:]]*AR_BOLT'; then
    echo "FAIL: the AD_KNOC rider must carry aval: AR_BOLT so it shares the bolt's single Reflex save (found: $rider)."
    exit 1
fi

if ! printf '%s\n' "$block" | grep -Eq 'e\.efNum[[:space:]]*==[[:space:]]*1[[:space:]]*&&[[:space:]]*e\.Resist'; then
    echo "FAIL: the wand must drop the knockback on a made Reflex save (an efNum == 1 && e.Resist handler)."
    exit 1
fi

echo "PASS: PA-08-F72 / inc-tek.8.8 Wand of Striking knockback folded into one Reflex save."
exit 0
