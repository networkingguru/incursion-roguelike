#!/bin/bash
# Regression check for inc-ragf: a Holy weapon smites non-evil undead.
#
# The oracle is the unconditional "Holy power smites ..." VPrint in each
# landed-hit dump. Seed 4 supplies a neutral black bear given the zombie
# template (the red-to-green subject), an evil mummy (positive control), and a
# distinct neutral living brown bear (negative control).
#
# Usage: tools/check_holy_undead.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
KEYS=tools/keys/smite-holy-undead-probe.keys
CONTROLS=tools/keys/smite-holy-undead-controls.keys
BIN="${INCURSION_BIN:-./incursion-headless}"
OPT_BYTE=204          # OPT_AUTOPICKUP, see inc/Defines.h

[ -x "$BIN" ] || {
    echo "FAIL: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/options.Dat" "$OPT_BYTE" <<'PY' || exit 1
import io, sys
path, idx = sys.argv[1], int(sys.argv[2])
data = bytearray(io.open('tools/gates/Options.Dat', 'rb').read())
if len(data) <= idx:
    raise SystemExit('Options.Dat is too short for OPT_AUTOPICKUP')
data[idx] = 0
io.open(path, 'wb').write(bytes(data))
PY

run_keys() {
    local keys="$1" out run
    out="$(INCURSION_BIN="$BIN" INCURSION_OPTIONS="$tmp/options.Dat" \
        tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "FAIL: $keys never entered a map, so it measured nothing." >&2
        echo "$out" >&2
        return 1
    fi
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "FAIL: $keys did not find an expected screen; read" >&2
        echo "      $run/logs/screens." >&2
        return 1
    fi
    echo "$run/logs/screens"
}

scr="$(run_keys "$KEYS")" || exit 1
control_scr="$(run_keys "$CONTROLS")" || exit 1
zombie="$(ls "$scr"/*-zombie-black-bear-hit.txt 2>/dev/null | head -1)"
mummy="$(ls "$control_scr"/*-mummy-hit.txt 2>/dev/null | head -1)"
bear="$(ls "$control_scr"/*-brown-bear-hit.txt 2>/dev/null | head -1)"

for pair in "black bear zombie:$zombie" "mummy:$mummy" "brown bear:$bear"; do
    name="${pair%%:*}"
    file="${pair#*:}"
    [ -n "$file" ] || {
        echo "FAIL: no landed-hit dump for the $name in $scr"
        exit 1
    }
    grep -qi "hitting the $name" "$file" || {
        echo "FAIL: $file shows no landed blow on the $name."
        exit 1
    }
done

fail=0
if ! grep -qi "Holy power smites the black bear zombie" "$zombie"; then
    echo "FAIL: Holy power did not smite the non-evil black bear zombie."
    echo "      This is the inc-ragf red-to-green subject."
    fail=1
fi
if ! grep -qi "Holy power smites the mummy" "$mummy"; then
    echo "FAIL: Holy power did not smite the evil-undead mummy control."
    fail=1
fi
if grep -qi "Holy power smites the brown bear" "$bear"; then
    echo "FAIL: Holy power smote the neutral living brown bear control."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: Holy power smites both non-evil and evil undead, while the"
    echo "      neutral living control remains unsmitten."
fi
exit "$fail"
