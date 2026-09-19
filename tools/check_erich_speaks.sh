#!/bin/bash
# Structural regression check for inc-tek.7.
#
# Erich's own script (lib/religion.irh) calls MSG_CUSTOM1 through MSG_CUSTOM5
# via EActor->GodMessage($"Erich", MSG_CUSTOMn). Character::GodMessage
# (src/Prayer.cpp) only finds a custom message if it is LIVE in the god's
# GODSPEAK_LIST -- not disabled inside a #if 0 block. Before the fix, all five
# were fully written but sat inside GODSPEAK_LIST's #if 0 block, so every call
# fell through to the engine's placeholder line ("<Res> says something, but
# you aren't sure what it is! (God messages still in progress!)").
#
# This check extracts the LIVE portion of Erich's GODSPEAK_LIST -- the text
# between the "* GODSPEAK_LIST" marker and whichever comes first, the block's
# "#if 0" or the next "* " list marker -- and fails if any of the five
# MSG_CUSTOMn constants Erich's script calls is missing from that live text.
#
# Usage: tools/check_erich_speaks.sh    (exits 0 on pass, 1 on fail)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FILE="lib/religion.irh"

live="$(awk '
  /^God "Erich"/                { in_god=1 }
  in_god && /\* GODSPEAK_LIST/  { in_list=1; next }
  in_list && /^[ \t]*#if 0/     { exit }
  in_list && /^[ \t]*\*[ \t]/   { exit }
  in_list { print }
' "$FILE")"

[ -n "$live" ] || {
    echo "FAIL: could not find Erich's live GODSPEAK_LIST in $FILE."
    exit 1
}

fail=0
for msg in MSG_CUSTOM1 MSG_CUSTOM2 MSG_CUSTOM3 MSG_CUSTOM4 MSG_CUSTOM5; do
    if ! printf '%s\n' "$live" | grep -q "^\s*${msg}\s*$"; then
        echo "FAIL: $msg is not live in Erich's GODSPEAK_LIST (still disabled, or missing)."
        fail=1
    fi
done

# Erich's script (this file) calls exactly these five MSG_CUSTOMn constants.
# If a future edit adds a call to a sixth, this check would pass while the
# new one silently falls through -- so also confirm the call sites still
# match the set above.
called="$(grep -oE 'GodMessage\(\$"Erich", *MSG_CUSTOM[0-9]+\)' "$FILE" \
          | grep -oE 'MSG_CUSTOM[0-9]+' | sort -u)"
expected="$(printf 'MSG_CUSTOM1\nMSG_CUSTOM2\nMSG_CUSTOM3\nMSG_CUSTOM4\nMSG_CUSTOM5\n' | sort -u)"
if [ "$called" != "$expected" ]; then
    echo "FAIL: the set of MSG_CUSTOMn constants Erich's script calls changed:"
    echo "  called:   $(printf '%s' "$called" | tr '\n' ' ')"
    echo "  expected: $(printf '%s' "$expected" | tr '\n' ' ')"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: all five MSG_CUSTOMn messages Erich's script calls are live in his GODSPEAK_LIST."
fi
exit "$fail"
