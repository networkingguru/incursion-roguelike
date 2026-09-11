#!/bin/bash
# gate: cheap
#
# Does lib/ still match the whole EF_PROTECTS_ITEMS ruling table?
#
#   tools/check_gear_protection_roster.sh               every part
#   tools/check_gear_protection_roster.sh --part C1     one part
#   tools/check_gear_protection_roster.sh --prove-red   break each part in turn
#
# THE DEFECT THIS DEFENDS. The repo owner ruled, grant by grant, which grants of
# immunity or resistance protect a bearer's carried GEAR and which protect only
# the bearer. A session implemented six of those rulings, left the rest, and
# closed the tracking bead as complete. Nothing in the tree held the ruling
# table, so nothing noticed. This check holds it, and fails the moment the tree
# stops matching it.
#
# WHERE THE TABLE COMES FROM. THE REPO OWNER RULED EVERY ROW OF IT, one at a
# time, in one long session. It is his ruling and not an inference: part A is
# the 36 effects he ruled y, part B the 22 grants he ruled n, and part C the two
# general rules he gave -- spells are y in general, and domains, gods, races and
# subraces are n. A row is changed only when he changes his ruling.
#
# THE MECHANISM. EF_PROTECTS_ITEMS (inc/Defines.h:3295) is a flag on an effect
# declaration. Creature::GearResistLevel (src/Values.cpp) counts only flagged
# grants, except for the four blanket gear-only damage types. The flag is per
# EFFECT and not per clause: lang/Grammar.acc:642-681 builds one TEffect per
# `Effect "name" : ... { } and ... { }` declaration, so a flag in any clause
# covers the whole effect. The roster therefore keys on the effect NAME, never
# on a line number.
#
# WHAT PART C1 MEASURES. The gear-relevant damage types are derived from
# MaterialHardness (src/Item.cpp): a type that returns -1 whatever the material
# can never hurt an item, so a grant against it needs no flag. Every other type
# reaches the material switch, where MAT_BONE returns 6 unconditionally, so an
# item CAN take it. That sweep finds two unflagged priest spells -- Rooting and
# Free Action -- which grant immunity to AD_TRIP, AD_CRIT, AD_PLYS, AD_STUK and
# AD_STON. Either the owner's "spells are y" rule reaches them, or
# MaterialHardness should return -1 for those five types as it already does for
# AD_SLEE, AD_STUN and AD_SLOW. Both are his call, so both spells sit in
# PENDING_RULING (tools/gear_protection_roster.py) under bd inc-taoa: the check
# names them on every run and does not fail on them. That list is not an
# excuse and cannot rot into one -- a THIRD bare spell fails C1, and a name in
# the list that stops being bare fails C1 too, so the list and the tree must go
# on agreeing in both directions until he answers.
#
# WHY IT DOES NOT USE check_lib.sh's --prove-red. This --prove-red proves more
# than an exit code: for each mutation it reads the ONE part's verdict line
# before and after, and demands that line turn from PASS to FAIL and name what
# was mutated.
#
# Exit: 0 every part passed, 1 a part failed, 2 could not measure.
#
# PROVED RED (2026-09-11), three mutations, each restored:
#   strip the flag from Protection from Elements  -> A 36/36 to 35/36, and C1
#                                                    grows from 2 spells to 3
#   flag the Amulet of Bile                       -> B 22/22 to 21/22
#   flag the Fire domain                          -> C2 0/0 to 1/0

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
ORACLE=tools/gear_protection_roster.py

command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
[ -f "$ORACLE" ] || { echo "COULD NOT MEASURE: $ORACLE is missing"; exit 2; }

# ---------------------------------------------------------------------------
# Replace literal text, counted first. sed is wrong for this: `[`, `.` and `+`
# are live characters to sed and all three are in the text being replaced.
replace() { # <file> <literal from> <literal to>
    INC_FILE="$1" INC_FROM="$2" INC_TO="$3" python3 -c '
import os, sys
p, a, b = os.environ["INC_FILE"], os.environ["INC_FROM"], os.environ["INC_TO"]
s = open(p, encoding="utf-8", errors="surrogateescape").read()
if s.count(a) != 1:
    sys.exit("the text to replace appears %d times in %s, and must appear once"
             % (s.count(a), p))
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(a, b))
'
}

KEEP=""
TOUCHED=""
restore() {
    [ -n "$TOUCHED" ] || return 0
    if ! cp -f "$KEEP" "$TOUCHED" || ! cmp -s "$KEEP" "$TOUCHED"; then
        echo "COULD NOT MEASURE: restore failed for $TOUCHED; the original is at $KEEP" >&2
        exit 2
    fi
    TOUCHED=""
}

# The part's one verdict line, PASS or FAIL, out of a captured run.
verdict() { # <output> <part>
    printf '%s\n' "$1" | grep -E "^(PASS|FAIL): \[$2\] " | head -1
}

# ---------------------------------------------------------------------------
# prove <label> <file> <from> <to> <part> <part...> -- break one thing, and
# require each named part's own verdict line to turn from PASS to FAIL and to
# name the thing. A part that is already FAIL before the mutation passes on the
# weaker test: its line must not name the thing first, and must name it after.
prove() { # <label> <name it must print> <file> <from> <to> <part>...
    local label="$1" names="$2" file="$3" from="$4" to="$5"; shift 5
    local before after line_before line_after part rc=0

    echo "--- prove red: $label ---"
    before="$(python3 "$ORACLE" all 2>&1)"

    KEEP="$(mktemp -t gear_roster)" || { echo "COULD NOT MEASURE: no temp file"; exit 2; }
    cp -p "$file" "$KEEP" || { echo "COULD NOT MEASURE: could not copy $file aside"; exit 2; }
    TOUCHED="$file"
    trap 'restore; exit 2' INT TERM HUP
    trap restore EXIT

    replace "$file" "$from" "$to" || { restore; echo "COULD NOT MEASURE: the mutation did not apply"; exit 2; }
    after="$(python3 "$ORACLE" all 2>&1)"
    restore
    trap - EXIT INT TERM HUP
    rm -f "$KEEP"

    for part in "$@"; do
        line_before="$(verdict "$before" "$part")"
        line_after="$(verdict "$after" "$part")"
        printf '  before %s\n  after  %s\n' "${line_before:-<no line>}" "${line_after:-<no line>}"
        case "$line_before" in
            *"$names"*) echo "  NOT PROVED: part $part already named \"$names\""; rc=1; continue ;;
        esac
        case "$line_after" in
            FAIL*"$names"*) echo "  proved: part $part goes red and names \"$names\"" ;;
            *) echo "  NOT PROVED: part $part did not fail naming \"$names\""; rc=1 ;;
        esac
    done
    return "$rc"
}

prove_red() {
    local rc=0
    prove "remove the flag from one spell" "Protection from Elements" \
        lib/wspells.irh \
'  { Flags: EF_PROTECTS_ITEMS; SC_ABJ; IS_A_BUFF(COST_5); Level: 6; qval: Q_TAR;' \
'  { SC_ABJ; IS_A_BUFF(COST_5); Level: 6; qval: Q_TAR;' \
        A C1 || rc=1
    echo
    prove "flag a grant the owner ruled wearer-only" "Amulet of Bile" \
        lib/m_items.irh \
'AI_AMULET Effect "Bile" : EA_GRANT
  { SC_ABJ; xval: RESIST;' \
'AI_AMULET Effect "Bile" : EA_GRANT
  { Flags: EF_PROTECTS_ITEMS; SC_ABJ; xval: RESIST;' \
        B || rc=1
    echo
    prove "flag a domain" 'Domain "Fire"' \
        lib/domains.irh \
'      Stati[RESIST,AD_FIRE,+1] at every 2nd level starting at 1st;' \
'      Stati[RESIST,AD_FIRE,+1] at every 2nd level starting at 1st,
      EF_PROTECTS_ITEMS;' \
        C2 || rc=1
    echo
    if [ "$rc" -eq 0 ]; then
        echo "PROVED RED: all three mutations turn their own part from PASS to FAIL."
        echo "            Record these lines where the work is."
    else
        echo "NOT PROVED: read the lines above. The check is measuring less than it claims."
    fi
    return "$rc"
}

case "${1:-}" in
    "")          exec python3 "$ORACLE" all ;;
    --part)      [ $# -ge 2 ] || { echo "COULD NOT MEASURE: --part needs A, B, C1 or C2"; exit 2; }
                 exec python3 "$ORACLE" "$2" ;;
    --prove-red) prove_red; exit $? ;;
    *)           sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
