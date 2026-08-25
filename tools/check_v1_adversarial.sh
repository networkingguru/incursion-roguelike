#!/bin/bash
# Adversarial check for the v1 save reader (docs/SAVE-SCHEMA-SPEC.md, test
# plan). Builds one genuine RAW-mode v1 file via `-schematest` under
# INCURSION_V1_RAW=1, crafts mutants with tools/craft_bad_v1_saves.py, and
# drives each through `-schemaload`:
#
#   - every corruption case must be REFUSED (non-zero exit, the expected
#     stderr text, and no field dump printed for the refused file);
#   - the two extensibility cases (unknown tag inserted, known tag deleted)
#     must SUCCEED, with the surviving field lines intact -- the skip rule
#     and the constructed-default rule at work.
#
# One case, creature_tcount_overflow, is crafted from the creature group's
# file rather than the item group's: it needs a count field inside a Creature
# whose value the reader cannot honour.
#
# Skeleton and safety assertions as in tools/check_load_corrupt.sh: every
# headless invocation carries < /dev/null and -timeout (a binary that
# predates a flag would otherwise start an interactive session and hang),
# and the real save/ directory must be untouched throughout.
#
# Usage: tools/check_v1_adversarial.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-v1adv.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# --- 1. one genuine RAW-mode v1 file (Compression == 0, so the crafting
#        script can parse and mutate the payload byte-for-byte) ---
if ! INCURSION_V1_RAW=1 ./incursion-headless -schematest "$WORK" -timeout 120 \
        < /dev/null > "$WORK/schematest.log" 2>&1; then
    tail -20 "$WORK/schematest.log"
    fail "-schematest could not produce the base file"
    exit 1
fi
BASE="$WORK/a.sav"
[ -f "$BASE" ] || { fail "no a.sav produced"; exit 1; }
# The creature group's file. a.sav holds Item records only, and the one
# mutant that needs a count field inside a Creature needs a Monster record.
CREATURE="$WORK/c.sav"
[ -f "$CREATURE" ] || { fail "no c.sav produced"; exit 1; }

# --- 2. the genuine file itself must load, and its field lines are the
#        baseline the 'ok' mutants are compared against ---
if ! ./incursion-headless -schemaload "$BASE" -timeout 120 < /dev/null \
        > "$WORK/baseline.out" 2> "$WORK/baseline.err"; then
    cat "$WORK/baseline.err"
    fail "the genuine v1 file was refused by -schemaload"
    exit 1
fi
grep '^field ' "$WORK/baseline.out" > "$WORK/baseline.fields"
BASE_FIELD_COUNT="$(wc -l < "$WORK/baseline.fields" | tr -d ' ')"
if [ "$BASE_FIELD_COUNT" -eq 0 ]; then
    fail "the baseline -schemaload printed no field lines"
    exit 1
fi

# --- 3. craft the mutants ---
if ! python3 tools/craft_bad_v1_saves.py "$BASE" "$WORK/mutants" "$CREATURE" \
        > "$WORK/craft.log" 2> "$WORK/craft.err"; then
    cat "$WORK/craft.err"
    fail "tools/craft_bad_v1_saves.py failed -- see above (a wire-format drift check may have tripped; investigate, do not silence)"
    exit 1
fi

# --- 4. drive each mutant ---
# craft.log lines are 'name|path|expect|detail' -- see the crafting
# script's header. Not an associative array: macOS bash 3.2.
CASE_COUNT=0
while IFS='|' read -r name path expect detail; do
    [ -z "$name" ] && continue
    CASE_COUNT=$((CASE_COUNT + 1))
    OUT="$WORK/case_$name.out"
    ERR="$WORK/case_$name.err"
    ./incursion-headless -schemaload "$path" -timeout 120 < /dev/null \
        > "$OUT" 2> "$ERR"
    STATUS=$?
    case "$expect" in
      fail)
        if [ "$STATUS" -eq 0 ]; then
            fail "$name: -schemaload exited 0 on a corrupt file -- it should have been refused"
        fi
        if [ -n "$detail" ] && ! grep -qF "$detail" "$ERR"; then
            fail "$name: expected stderr to mention '$detail', got:"
            cat "$ERR"
        fi
        # A refused file must never yield the field dump or a pass line.
        if grep -q '^field ' "$OUT" || grep -q 'SCHEMATEST' "$OUT"; then
            fail "$name: a refused file still produced a field dump"
        fi
        ;;
      ok)
        if [ "$STATUS" -ne 0 ]; then
            cat "$ERR"
            fail "$name: -schemaload refused a file the skip rules must accept"
            continue
        fi
        if [ -n "$detail" ] && ! grep -qF "$detail" "$OUT"; then
            fail "$name: expected stdout to contain '$detail'"
        fi
        grep '^field ' "$OUT" > "$WORK/case_$name.fields"
        case "$name" in
          unknown_tag)
            # The inserted tag is skipped; every original field line must
            # survive byte-for-byte.
            if ! diff -q "$WORK/baseline.fields" "$WORK/case_$name.fields" \
                    > /dev/null; then
                echo "--- first differing field lines ---"
                diff "$WORK/baseline.fields" "$WORK/case_$name.fields" | head -10
                fail "$name: the field lines changed; an unknown tag must be skipped without damage"
            fi
            ;;
          deleted_tag)
            # Exactly one line changes: the deleted field reads as its
            # constructed default.
            CHANGED="$(diff "$WORK/baseline.fields" "$WORK/case_$name.fields" | grep -c '^<')"
            if [ "$CHANGED" -ne 1 ]; then
                echo "--- differing field lines ---"
                diff "$WORK/baseline.fields" "$WORK/case_$name.fields" | head -10
                fail "$name: expected exactly one field line to change (the deleted field's default), saw $CHANGED"
            fi
            ;;
        esac
        ;;
      *)
        fail "$name: unknown expectation '$expect' from the crafting script"
        ;;
    esac
done < "$WORK/craft.log"

if [ "$CASE_COUNT" -lt 15 ]; then
    fail "only $CASE_COUNT cases ran; the crafting script should emit one per record boundary twice, plus seven more"
fi

# --- 5. the safety claim: nothing touched the real save/ directory ---
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: all $CASE_COUNT v1 adversarial cases behaved: truncations and"
    echo "      the wrong-kind/bad-name/bad-ordinal/tcount mutants were"
    echo "      refused with the expected errors; the unknown-tag and"
    echo "      deleted-tag mutants loaded with the skip/default rules intact."
    exit 0
fi
exit 1
