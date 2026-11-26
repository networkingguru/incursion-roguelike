#!/bin/bash
# gate: live
# inc-a2mso: the Elemental Disjunction Desc read "but any they can be useful"
# (stray "any"), and it and Theryan Inviolability said "favour" (British).
# This is a prose-only check, no build.
#
# Facts and their controls (this check reads only what the header names):
# fact: the two Desc texts -- lib/m_items.irh, fixed by the source file; no game run, no seed
#
# Usage: tools/check_disjunction_desc.sh [--prove-red]

ROOT="$(dirname "$0")/.."
ITEMS="$ROOT/lib/m_items.irh"

# entry_check <file> <effect name> <old text> <new text>
entry_check() {
    # The entry runs from its live header through the first line that ends
    # the Desc string (`";`) after `Desc:`. The Desc wraps, so newlines and
    # runs of whitespace collapse to single spaces before matching.
    entry="$(awk -v name="$2" '
      !f && index($0, "Effect \"" name "\"") && /Effect "[^"]*" *:/ { f=1 }
      f {
        print
        if (seen && /";/) exit
        if (/Desc:/) seen=1
      }
    ' "$1")"
    if [ -z "$entry" ]; then
        echo "FAIL: $1 has no $2 entry"
        return 1
    fi
    flat="$(printf '%s\n' "$entry" | tr -s ' \n\t' ' ')"
    if printf '%s\n' "$flat" | grep -qF "$3"; then
        echo "FAIL: $1 still says \"$3\" in the $2 Desc"
        return 1
    fi
    if ! printf '%s\n' "$flat" | grep -qF "$4"; then
        echo "FAIL: $1 lacks \"$4\" in the $2 Desc"
        return 1
    fi
    return 0
}

test_file() {
    rc=0
    entry_check "$1" "Elemental Disjunction" "but any they can be useful" \
        "favor such devices, but they can be useful in the hands of a devout priest of any faith." || rc=1
    entry_check "$1" "Elemental Disjunction" "favour such devices" "favor such devices" || rc=1
    entry_check "$1" "Theryan Inviolability" "favour such devices" "favor such devices." || rc=1
    return $rc
}

if [ "$1" = "--prove-red" ]; then
    mkdir -p "$ROOT/logs"
    tmp="$(mktemp "$ROOT/logs/disjunction-desc.XXXXXX")"
    cp "$ITEMS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
with open(p) as f:
    data = f.read()
data = data.replace("favor such devices, but they can", "favour such devices, but any they can", 1)
data = data.replace("Kysul all \n      favor such devices.", "Kysul all \n      favour such devices.", 1)
with open(p, "w") as f:
    f.write(data)
PY
    if test_file "$tmp"; then
        rm -f "$tmp"
        echo "FAIL: --prove-red did not turn the check red"
        exit 1
    fi
    rm -f "$tmp"
    echo "PROVED RED: with the old Descs restored, the check exits 1."
    exit 0
fi

if test_file "$ITEMS"; then
    echo "PASS: Elemental Disjunction and Theryan Inviolability Descs say \"favor\""
    exit 0
fi
exit 1
