#!/bin/bash
# Regression check for PA-08-F82 / inc-tek.8.8: the "Sylvan Scimitar" weapon
# description must say elves are NEUTRAL toward its bearer, matching the item's
# second block, which grants NEUTRAL_TO MA_ELF. TargetSystem::LowPriorityStati-
# Hostility (src/Target.cpp) resolves NEUTRAL_TO as a Neutral-quality attitude,
# and the character sheet (src/Sheet.cpp) labels it "Neutral"; the grant confers
# no friendly reaction. The code wins. Red while the Desc still says elves "tend
# to be friendly" to the bearer, green once it says elves "tend to be neutral".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Sylvan Scimitar block, then extract the Desc STRING itself (from
# 'Desc: "' to its first closing '";'), so the upstream: comment that quotes the
# old "friendly" wording -- it sits above the Desc line -- is excluded.
block="$(sed -n '/AI_WEAPON Effect "Sylvan Scimitar" : EA_GRANT/,/AI_WEAPON Effect "Oathbow"/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if [ -z "$desc" ]; then
    echo "FAIL: could not find the Sylvan Scimitar Desc in $SOURCE; the anchor changed."
    exit 1
fi

if printf "%s\n" "$desc" | grep -q "tend to be neutral"; then
    echo "PASS: PA-08-F82 / inc-tek.8.8 the Sylvan Scimitar description says elves are neutral toward its bearer, matching its NEUTRAL_TO MA_ELF grant."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "tend to be friendly"; then
    echo "FAIL: the Sylvan Scimitar description says elves \"tend to be friendly\" to its bearer, yet the item grants NEUTRAL_TO MA_ELF, a neutral attitude, not friendly."
    exit 1
fi

echo "FAIL: the Sylvan Scimitar description no longer contains the expected elf-attitude clause; the anchor or wording changed."
exit 1
