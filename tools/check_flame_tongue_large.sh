#!/bin/bash
# Regression check for PA-08-F70 / inc-tek.8.8: the flame tongue sword's
# tongue-of-flame lash must be able to yank a LARGE corporeal creature.
#
# THE PROMISE. The sword's own page (lib/m_items.irh, the "flame tongue"
# entity) says the lash acts "if the victim still lives and is a Large or
# smaller corporeal creature".
#
# THE DEFECT. The lash effect ("tongue of flame" EA_BLAST) gated the
# opposed-Strength yank on `if (EVictim->GetAttr(A_SIZ) >= SZ_LARGE) return
# NOTHING;` -- an off-by-one that bailed for Large AND everything larger, so
# only Medium-and-smaller creatures ever reached the contest. Brian ruled prose
# wins: include Large, exclude only LARGER, so the gate must read `> SZ_LARGE`.
#
# This check anchors the "tongue of flame" EA_BLAST block and reads its size
# gate -- the `if (EVictim->GetAttr(A_SIZ) ...)` CODE line, not the `>=`/`>`
# prose in the upstream comment above it. Red while the gate reads
# `>= SZ_LARGE`, green once it reads `> SZ_LARGE`. Behaviour is proved
# separately by the Observed oracle tools/keys/flame-tongue-large-yank.keys.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the tongue-of-flame block, from its header to the next entity.
block="$(sed -n '/^0 Effect "tongue of flame" : EA_BLAST/,/^AI_SHIELD Effect "Dragonshield"/p' "$SOURCE")"

if [ -z "$block" ]; then
    echo "FAIL: could not find the \"tongue of flame\" EA_BLAST block in $SOURCE."
    exit 1
fi

# The gate is the only `if (EVictim->GetAttr(A_SIZ) ...)` code line; the upstream
# comment mentions A_SIZ only inside backticks, never as that expression.
gate="$(printf '%s\n' "$block" | grep 'if (EVictim->GetAttr(A_SIZ)')"

if [ -z "$gate" ]; then
    echo "FAIL: no A_SIZ size gate in the \"tongue of flame\" block of $SOURCE."
    exit 1
fi

if printf '%s\n' "$gate" | grep -qF 'A_SIZ) >= SZ_LARGE'; then
    echo "FAIL: the tongue-of-flame size gate reads \`>= SZ_LARGE\`, which excludes"
    echo "      Large as well as larger, so a Large creature is never yanked. The"
    echo "      page promises the lash acts on \"a Large or smaller corporeal"
    echo "      creature\" (PA-08-F70). The gate must read \`> SZ_LARGE\`."
    echo "      gate:$gate"
    exit 1
fi

if ! printf '%s\n' "$gate" | grep -qF 'A_SIZ) > SZ_LARGE'; then
    echo "FAIL: the tongue-of-flame size gate is not the expected \`A_SIZ > SZ_LARGE\` test."
    echo "      gate:$gate"
    exit 1
fi

echo "PASS: PA-08-F70 / inc-tek.8.8 the tongue-of-flame lash gates its yank on \`> SZ_LARGE\`, so a Large corporeal creature is inside the rule."
