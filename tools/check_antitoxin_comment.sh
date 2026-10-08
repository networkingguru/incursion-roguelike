#!/bin/bash
# gate: live
# inc-gmrj: the comment above Neutralize Poison must not claim antitoxins cover its effect.
# Antitoxin only adds to poison saves; it cures nothing. This is a prose-only check, no build.

ROOT="$(dirname "$0")/.."
SPELLS="$ROOT/lib/pspells.irh"
OLD='antitoxins cover this potion effect'
NEW='antitoxin only adds to poison saves; it does not cure'

test_file() {
    if grep -qF "$OLD" "$1"; then
        echo "FAIL: $1 still claims antitoxins cover this potion effect"
        return 1
    fi
    if ! grep -qF "$NEW" "$1"; then
        echo "FAIL: $1 lacks the corrected antitoxin comment"
        return 1
    fi
    return 0
}

if [ "$1" = "--prove-red" ]; then
    tmp="$(mktemp "$ROOT/logs/antitoxin-comment.XXXXXX")"
    cp "$SPELLS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
old = "// antitoxin only adds to poison saves; it does not cure. Neutralize Poison is the cure."
new = "// ww: antitoxins cover this potion effect"
with open(p) as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if line.rstrip("\n") == old:
        lines[i] = new + "\n"
        break
with open(p, "w") as f:
    f.writelines(lines)
PY
    if test_file "$tmp"; then
        rm -f "$tmp"
        echo "FAIL: --prove-red did not turn the check red"
        exit 1
    fi
    rm -f "$tmp"
    echo "PROVED RED: with the old comment restored, the check exits 1."
    exit 0
fi

if test_file "$SPELLS"; then
    echo "PASS: Neutralize Poison comment no longer claims antitoxins cover the effect"
    exit 0
fi
exit 1
