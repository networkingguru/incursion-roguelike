#!/bin/bash
# Regression check for inc-gv1u: a `<<` in a game script must shift LEFT.
#
# Usage: tools/check_shift_opcodes.sh   (0 pass, 1 fail, 2 inconclusive)
#
# WHAT THIS PROTECTS. src/VMachine.cpp ran the two shift opcodes as each
# other -- BSHL performed `>>` and BSHR performed `<<` -- so every `<<` in
# lib/*.irh right-shifted. The visible cost was colour: GLYPH_VALUE packs a
# colour into a glyph with `colour << 12`, that shift produced 0, and every
# script-created field was stored as a bare uncoloured glyph. src/Light.cpp
# takes a light field's colour from that glyph, so twelve creatures that are
# supposed to glow cast black light and lit nothing.
#
# WHY IT CHECKS TWO THINGS. The behaviour test alone is not enough. The Rect
# member codegen in src/RComp.cpp was written against the inverted VM and is
# self-consistent with it, so correcting the VM ALONE fixes the light and
# silently breaks Rect member access in five live spells (Tree Stride, Commune
# With Nature, Detect Animals and Plants, and two more). Every light check
# still passes in that state. So the first pass pins the two halves together
# statically, and the second measures the light.
#
#   1. STATIC. The VM's BSHL performs `<<`, and RComp's Rect read path asks for
#      BSHR. Either one alone is the broken pairing.
#   2. LIVE. Summon a mote of fire and read the light probe. Its field must be
#      scanned as a RED source (128 0 0), not a black one (0 0 0).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

# --- 1. the two halves of the shift pairing ---------------------------------
grep -q 'case BSHL: REGS(0) = Value1(vc) << Value2(vc)' src/VMachine.cpp || \
    fail "src/VMachine.cpp: BSHL no longer performs a left shift."
grep -q 'ex.Code->Generate(BSHR,RT_REGISTER,0,RT_CONSTANT,shift)' src/RComp.cpp || \
    fail "src/RComp.cpp: the Rect read path no longer asks for BSHR."
grep -q 'lv.WCode->Generate(BSHL,RT_REGISTER,0,RT_CONSTANT,shift)' src/RComp.cpp || \
    fail "src/RComp.cpp: the Rect write path no longer asks for BSHL."

[ "$FAILED" -eq 0 ] || {
    echo "      The VM and the Rect codegen must swap together; one alone"
    echo "      breaks Rect member access in five spells while every light"
    echo "      check still passes. See inc-gv1u."
    exit 1
}

# --- 2. the light a script-coloured field actually casts ---------------------
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_LIGHT_PROBE=1 INCURSION_BIN="$BIN" \
       tools/headless.sh tools/keys/mote-light.keys 1 2>&1)"
status=$?
RUN="$(echo "$out" | awk '/^run:/ {print $2}')"

[ "$status" -eq 0 ] || {
    echo "INCONCLUSIVE: headless fixture exited $status. Run dir: $RUN"
    echo "$out"
    exit 2
}

log="$RUN/logs/light.log"
[ -f "$log" ] || {
    echo "INCONCLUSIVE: fixture wrote no light probe. Run dir: $RUN"
    exit 2
}

# Kind 3 is LK_FIELD (src/Light.cpp). RED is palette entry 4, {128,0,0}.
if grep -Eq '^S [0-9]+ [0-9]+ [0-9]+ 128 0 0 3 ' "$log"; then
    echo "PASS: the mote's field was scanned as a red light source."
    exit 0
fi

if grep -Eq '^S [0-9]+ [0-9]+ [0-9]+ 0 0 0 3 ' "$log"; then
    fail "the mote's field was scanned as a BLACK source -- the script <<"
    echo "      lost its colour again. Run dir: $RUN"
    exit 1
fi

echo "INCONCLUSIVE: no field source of any colour in $log."
echo "      The mote may not have been summoned; read the screen dump in $RUN."
exit 2
