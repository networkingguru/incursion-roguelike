#!/bin/bash
# Regression check for PA-08-F50 / inc-tek.8.8: the "Brazier Commanding Fire
# Elementals" item description does NOT still claim "Once per day". The item is
# coded EF_3PERDAY (three activations per day), so its Desc must state three
# times per day, not once. Red while the Desc says "Once per day", green once it
# is restated.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the item entity block from its unique header down to the block-
# closing brace, then test the Desc line itself (Desc: "..."), NOT the whole
# block: the upstream: comment in the block also quotes the old "Once per day"
# wording, so a bare block-wide grep would false-match the comment.
block="$(sed -n "/Brazier Commanding Fire Elementals/,/^  }/p" "$SOURCE")"

if printf "%s\n" "$block" | grep -Eq "Desc: *\"Once per day"; then
    echo "FAIL: the Brazier Commanding Fire Elementals description still says \"Once per day\", contradicting its EF_3PERDAY flag."
    exit 1
fi

echo "PASS: PA-08-F50 / inc-tek.8.8 the Brazier Commanding Fire Elementals description does not claim \"Once per day\"."
