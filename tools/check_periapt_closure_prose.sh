#!/bin/bash
# Regression check for PA-08-F59 / inc-tek.8.8: the "Periapt of Wound Closure"
# item description must not claim it "removes infections". Nothing in the
# entity removes disease or infection, and the SRD item has no infection
# removal; it only stops bleeding and speeds healing. Red while the Desc still
# says "removes infections", green once that claim is gone.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
block="$(sed -n '/AI_AMULET Effect "Periapt of Wound Closure" : EA_GRANT/,/";/p' "$SOURCE")"
# End the range at the Desc's closing ";, not a brace, because nested On Event
# braces precede the Desc. Scope the check to the Desc string itself to avoid
# false-matching the upstream: comment, which quotes the old wording.
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "removes infections"; then
    echo "FAIL: the Periapt of Wound Closure description still claims 'removes infections'."
    exit 1
fi

echo "PASS: PA-08-F59 / inc-tek.8.8 the Periapt of Wound Closure description no longer claims to remove infections."
exit 0
