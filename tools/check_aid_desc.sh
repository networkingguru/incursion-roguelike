#!/bin/bash
# gate: live
# inc-1o01: the Aid Desc said the temporary hit points stepped every four
# caster levels from 3rd (2d8 at 7th), though its pval LEVEL_EVERY4 gives 2d8 at 5th.
# This is a prose-only check, no build.

ROOT="$(dirname "$0")/.."
SPELLS="$ROOT/lib/pspells.irh"
OLD='starting with 1d8 at 3rd level'
NEW='2d8 at 5th'

test_file() {
    # The Aid name also appears in a commented-out spell list, so the
    # header only starts the entry when the very next line is its opening brace
    # line (`  {`). Aid has two effect blocks (`and EA_INFLICT`); the Desc is in
    # the second block, so the range runs from the live header through the first
    # line ending the Desc string (`";`) after `Desc:`. The Desc wraps, so the
    # entry's newlines and runs of whitespace collapse to single spaces before
    # matching.
    entry="$(awk '
      /Spell "Aid" *:/ { hdr=$0; want=1; next }
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
        echo "FAIL: $1 has no Aid Desc entry"
        return 1
    fi
    flat="$(printf '%s\n' "$entry" | tr -s ' \n\t' ' ')"
    if printf '%s\n' "$flat" | grep -qF "$OLD"; then
        echo "FAIL: $1 still says \"$OLD\" in the Aid Desc"
        return 1
    fi
    if ! printf '%s\n' "$flat" | grep -qF "$NEW"; then
        echo "FAIL: $1 lacks \"$NEW\" in the Aid Desc"
        return 1
    fi
    return 0
}

if [ "$1" = "--prove-red" ]; then
    tmp="$(mktemp "$ROOT/logs/aid-desc.XXXXXX")"
    cp "$SPELLS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
old = '''    Desc: "Grants the chosen subject a +1 bonus to hit and damage,
      as well as 1d8 temporary hit points at 3rd level, 2d8 at 5th,
      and 1d8 more every four caster levels after that.";'''
new = '''    Desc: "Grants the chosen subject a +1 bonus to hit and damage,
      as well as 1d8 temporary hit points for every four caster
      levels, starting with 1d8 at 3rd level.";'''
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
    echo "PASS: Aid Desc now says \"$NEW\""
    exit 0
fi
exit 1
