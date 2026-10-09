#!/bin/bash
# gate: live
# inc-5hp1: the Divine Favour Desc said "+5 at 21st" though its pval LEVEL_EVERY4 gives +6.
# This is a prose-only check, no build.

ROOT="$(dirname "$0")/.."
SPELLS="$ROOT/lib/pspells.irh"
OLD='+5 at 21st'
NEW='+6 at 21st'

test_file() {
    # The Divine Favour name also appears in a commented-out spell list, so the
    # header only starts the entry when the very next line is its opening brace
    # line (`  {`). The range then prints from that header through the first
    # line at or after `Desc:` that ends the Desc string with `";`, which is
    # several lines below `Desc:` itself.
    entry="$(awk '
      /Spell "Divine Favour" *:/ { hdr=$0; want=1; next }
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
        echo "FAIL: $1 has no Divine Favour Desc entry"
        return 1
    fi
    if printf '%s\n' "$entry" | grep -qF "$OLD"; then
        echo "FAIL: $1 still says \"$OLD\" in the Divine Favour Desc"
        return 1
    fi
    if ! printf '%s\n' "$entry" | grep -qF "$NEW"; then
        echo "FAIL: $1 lacks \"$NEW\" in the Divine Favour Desc"
        return 1
    fi
    return 0
}

if [ "$1" = "--prove-red" ]; then
    tmp="$(mktemp "$ROOT/logs/divine-favor-desc.XXXXXX")"
    cp "$SPELLS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
old = "+6 at 21st"
new = "+5 at 21st"
with open(p) as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if old in line:
        lines[i] = line.replace(old, new)
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
    echo "PROVED RED: with the old Desc restored, the check exits 1."
    exit 0
fi

if test_file "$SPELLS"; then
    echo "PASS: Divine Favour Desc now says \"$NEW\""
    exit 0
fi
exit 1
