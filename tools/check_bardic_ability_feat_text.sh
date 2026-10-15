#!/bin/bash
# gate: live
# inc-v8nl: the Improve Bardic Ability feat text said "You don't gain any
# additional Storycraft plusses", but AbilityLevel(CA_STORYCRAFT) adds
# IntStudy[STUDY_BARDIC]*2 to the effective level, so each study does give
# one more Storycraft plus to spend. This is a prose-only check, no build.
# stale-quote-ok: --prove-red restores the old feat text in a copy to prove the check goes red.

ROOT="$(dirname "$0")/.."
FEATS="$ROOT/src/FeatTab.cpp"
OLD='additional Storycraft plusses'
NEW='one more Storycraft plus to spend'

test_file() {
    # The entry starts at the header line and runs through the first line
    # that ends its string with \n" (the entry's last literal). The entry
    # is split across C string literals, so each line is reduced to its
    # text (leading whitespace and the surrounding quotes removed) and the
    # lines are joined before matching.
    entry="$(awk '
      /Improve Bardic Ability:/ { f=1 }
      f { print; if (/\\n"/) exit }
    ' "$1")"
    if [ -z "$entry" ]; then
        echo "FAIL: $1 has no Improve Bardic Ability feat entry"
        return 1
    fi
    flat="$(printf '%s\n' "$entry" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' | tr -d '\n')"
    if printf '%s\n' "$flat" | grep -qF "$OLD"; then
        echo "FAIL: $1 still says \"$OLD\" in the Improve Bardic Ability feat"
        return 1
    fi
    if ! printf '%s\n' "$flat" | grep -qF "$NEW"; then
        echo "FAIL: $1 lacks \"$NEW\" in the Improve Bardic Ability feat"
        return 1
    fi
    return 0
}

if [ "$1" = "--prove-red" ]; then
    tmp="$(mktemp "$ROOT/logs/bardic-ability-feat.XXXXXX")"
    cp "$FEATS" "$tmp"
    python3 - "$tmp" <<'PY'
import sys
p = sys.argv[1]
new = '''     "whichever is lower. Each point this adds to your effective bard level also "
     "gives you one more Storycraft plus to spend, and raises the maximum level of "
     "item you can augment.\\n"
'''
old = '''     "whichever is lower. You don't gain any additional Storycraft plusses, but "
     "the maximum level of item you can augment is increased.\\n"
'''
with open(p) as f:
    data = f.read()
if new not in data:
    sys.exit("prove-red: the new feat lines are not in the copy")
data = data.replace(new, old, 1)
with open(p, "w") as f:
    f.write(data)
PY
    if [ $? -ne 0 ]; then
        rm -f "$tmp"
        echo "FAIL: --prove-red could not restore the old feat text"
        exit 1
    fi
    if test_file "$tmp"; then
        rm -f "$tmp"
        echo "FAIL: --prove-red did not turn the check red"
        exit 1
    fi
    rm -f "$tmp"
    echo "PROVED RED: with the old feat text restored, the check exits 1."
    exit 0
fi

if test_file "$FEATS"; then
    echo "PASS: Improve Bardic Ability feat text now says \"$NEW\""
    exit 0
fi
exit 1
