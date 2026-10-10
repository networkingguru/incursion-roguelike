#!/bin/bash
# gate: live
# inc-24wm: the Inflict Moderate Wounds Desc capped its damage at "1d8+10",
# though its pval 2d8 + LEVEL_MAX10 = min(10,level) dice caps at 2d8+10.
# This is a prose-only check, no build.

ROOT="$(dirname "$0")/.."
SPELLS="$ROOT/lib/pspells.irh"
OLD='maximum 1d8+10'
NEW='maximum 2d8+10'

test_file() {
    # The Inflict Moderate Wounds name also appears in a commented-out spell
    # list, so the header only starts the entry when the very next line is its
    # opening brace line (`  {`). The Desc is in that block, so the range runs
    # from the live header through the first line ending the Desc string (`";`)
    # after `Desc:`. The Desc wraps, so the entry's newlines and runs of
    # whitespace collapse to single spaces before matching.
    entry="$(awk '
      /Spell "Inflict Moderate Wounds" *:/ { hdr=$0; want=1; next }
      want {
        if (/^  \{/) { print hdr; f=1; want=0 }
        else { want=0; next }
      }
      f {
        print
        if (seen && /";/) exit
        if (/Desc:/) seen=1
      }
    ' "$1")"
    if [ -z "$entry" ]; then
        echo "FAIL: $1 has no Inflict Moderate Wounds Desc entry"
        return 1
    fi
    flat="$(printf '%s\n' "$entry" | tr -s ' \n\t' ' ')"
    if printf '%s\n' "$flat" | grep -qF "$OLD"; then
        echo "FAIL: $1 still says \"$OLD\" in the Inflict Moderate Wounds Desc"
        return 1
    fi
    if ! printf '%s\n' "$flat" | grep -qF "$NEW"; then
        echo "FAIL: $1 lacks \"$NEW\" in the Inflict Moderate Wounds Desc"
        return 1
    fi
    return 0
}

if [ "$1" = "--prove-red" ]; then
    tmp="$(mktemp "$ROOT/logs/inflict-moderate-desc.XXXXXX")"
    cp "$SPELLS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
old = '''    Desc: "Inflicts 2d8 + caster level (maximum 2d8+10) points of necromantic
      damage on the next creature you touch.";'''
new = '''    Desc: "Inflicts 2d8 + caster level (maximum 1d8+10) points of necromantic
      damage on the next creature you touch.";'''
with open(p) as f:
    data = f.read()
data = data.replace(old, new, 1)
with open(p, "w") as f:
    f.write(data)
PY
    if test_file "$tmp"; then
        rm -f "$tmp"
        echo "FAIL: --prove-red did not turn the check red"
        exit 1
    fi
    rm -f "$tmp"
    echo "PROVED RED: with the old Desc restored, the check exits 1."
    exit 0
fi

if test_file "$SPELLS"; then
    echo "PASS: Inflict Moderate Wounds Desc now says \"$NEW\""
    exit 0
fi
exit 1
