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
# Some cases are crafted from other files than the item group's.
# creature_tcount_overflow needs a count field inside a Creature whose value
# the reader cannot honour, so it comes from the creature group's file.
# The two player_* cases need a file-fed INDEX inside a Player, so they come
# from the character group's file: one asserts the reader REFUSES a value the
# game cannot produce, the other that it CLAMPS one the game can.
# grid_mismatch needs a Map record, which no schematest group carries, so it
# comes from a real smoke-session save written under INCURSION_V1_RAW=1 and
# is driven through tools/dump_save.sh -- the real load path -- instead of
# -schemaload.
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
# The character group's file. It is the only one with a Player record, which
# is where the file-fed index bounds live.
CHARACTER="$WORK/e.sav"
[ -f "$CHARACTER" ] || { fail "no e.sav produced"; exit 1; }

# --- 1b. one genuine RAW-mode FULL save, via a real smoke session: the
#         grid_mismatch mutant needs a Map record, and no schematest group
#         carries one. Driven through tools/dump_save.sh below for the same
#         reason.
INCURSION_V1_RAW=1 INCURSION_RUN_DIR="$WORK/fullrun" ./tools/headless.sh \
    tools/keys/smoke.keys 1 > "$WORK/fullsession.log" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    tail -20 "$WORK/fullsession.log"
    fail "the smoke session that was supposed to produce a full raw save exited $STATUS, wanted 0"
    exit 1
fi
FULLSAVE="$(ls "$WORK"/fullrun/save/*.sav 2>/dev/null | head -1)"
[ -n "$FULLSAVE" ] || { fail "the smoke session produced no .sav file"; exit 1; }

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
        "$CHARACTER" "$FULLSAVE" > "$WORK/craft.log" 2> "$WORK/craft.err"; then
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
    if [ "$name" = grid_mismatch ]; then
        # The mutant is a FULL save, and only the real load path replays a
        # Map record's fields -- the -schemaload harness groups carry no
        # maps. tools/dump_save.sh is that path, sandboxed.
        INCURSION_DUMP_SANDBOX="$WORK/sandbox_$name" \
            ./tools/dump_save.sh "$path" < /dev/null > "$OUT" 2> "$ERR"
        STATUS=$?
    else
        ./incursion-headless -schemaload "$path" -timeout 120 < /dev/null \
            > "$OUT" 2> "$ERR"
        STATUS=$?
    fi
    case "$expect" in
      fail)
        if [ "$STATUS" -eq 0 ]; then
            fail "$name: -schemaload exited 0 on a corrupt file -- it should have been refused"
        fi
        if [ -n "$detail" ] && ! grep -qF "$detail" "$ERR"; then
            fail "$name: expected stderr to mention '$detail', got:"
            cat "$ERR"
        fi
        # A refused file must never yield the field dump, a pass line, or
        # (for the full-save case driven through -dump) the character report.
        if grep -q '^field ' "$OUT" || grep -q 'SCHEMATEST' "$OUT" ||
                grep -q 'Full Character Sheet' "$OUT"; then
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
          player_index_clamp)
            # The detail check above asserted the NotifiedLevel clamp; this
            # is the other half of the same rule. Both are values the game
            # itself can reach, so the file must load AND land clamped.
            if ! grep -qF 'field Player.cAutoBuff=63' "$WORK/case_$name.fields"; then
                grep -F 'field Player.' "$WORK/case_$name.fields"
                fail "$name: cAutoBuff did not land clamped to 63"
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

if [ "$CASE_COUNT" -lt 19 ]; then
    fail "only $CASE_COUNT cases ran; the crafting script should emit one per record boundary twice, plus eleven more"
fi

# --- 5. the safety claim: nothing touched the real save/ directory ---
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: all $CASE_COUNT v1 adversarial cases behaved: truncations and"
    echo "      the wrong-kind/bad-name/bad-ordinal/tcount mutants and the"
    echo "      negative Player index were refused with the expected errors;"
    echo "      the unknown-tag, deleted-tag and clamped-Player-index mutants"
    echo "      loaded with the skip/default/clamp rules intact."
    exit 0
fi
exit 1
