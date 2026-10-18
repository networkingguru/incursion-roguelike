#!/bin/bash
# gate: live
# gate-serial: builds the 391e353 sandbox from git archive and times a -timeout run; CPU load could flip it
# inc-glnx recovery edge cases, docs/SAVE-SCHEMA-SPEC.md test plan:
#   case 28(c) an IS1.3 save whose manifest has an array longer than at
#              391e353 refuses, naming the array;
#   case 21    a v0 copy is refused by its stamp with the release-4 message,
#              before any write, leaving no .v0 sibling (inc-vqla).
#
# The crafted-malformed-file parts of case 28 (an out-of-range recovered rID,
# a name length past the blob, and so on) are NOT here: tools/craft_bad_v1_saves.py
# and tools/check_v1_adversarial.sh are someone else's, and AGENTS.md forbids
# this role to open or edit them. Case 28's partial-unit DT_HOBJ -> 0 is
# checked with a real value by tools/check_script_var_recovery.py (Keos.sav
# slot 31, cave entrance hRoark, a 21-bit cut unit).
#
# 28(c) needs a save whose manifest has 1189 Effects where 391e353 had 1188.
# Only a binary that WRITES schema revision 3 can produce it, so this builds
# one from the 391e353 source with git archive (read-only; AGENTS.md allows
# it). INCURSION_REV3_DIR may point at an already-built 391e353 tree (a full
# checkout carrying incursion-headless, mod/, lib/, inc/) to skip the build.
#
# Usage: tools/check_script_var_recovery_edges.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The current schema stamp, read from the source of truth rather than
# hardcoded: a literal here rots into a false failure the moment SCHEMA_REV
# moves, and the check then reports a format problem that does not exist.
SCHEMA_STAMP="IS1.$(sed -n 's/^#define SCHEMA_REV \([0-9]*\).*/\1/p' src/SaveV1.cpp)"
[ -n "${SCHEMA_STAMP#IS1.}" ] || { echo "cannot read SCHEMA_REV from src/SaveV1.cpp" >&2; exit 1; }

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

BIN=./incursion-headless
COMPILER=./incursion-headless
[ -x "$BIN" ] || { fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-recedge.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null)"

# --- the revision-3 tree, for a writer that stamps IS1.3 ----------------
REV3="${INCURSION_REV3_DIR:-}"
if [ -z "$REV3" ]; then
    REV3="$WORK/rev3"
    mkdir -p "$REV3"
    if ! git -C "$ROOT" archive 391e353 | tar -x -C "$REV3"; then
        fail "git archive 391e353 failed; history or tar missing"
        exit 1
    fi
    ( cd "$REV3" && BACKEND=posix ./build_macos.sh ) > "$WORK/rev3-build.log" 2>&1
    if [ ! -x "$REV3/incursion-headless" ] || [ ! -f "$REV3/mod/Incursion.Mod" ]; then
        tail -20 "$WORK/rev3-build.log"
        fail "the 391e353 sandbox build produced no binary/module"
        exit 1
    fi
fi
[ -x "$REV3/incursion-headless" ] || { fail "INCURSION_REV3_DIR has no incursion-headless"; exit 1; }

# --- one appended Effect, in a lib/ copy --------------------------------
append_effect() { # <libdir>
    printf '\n\n0 Effect "Recovery Edge Oracle" : EA_NOTIMP\n  { Level: 1; }\n' >> "$1/main.irc"
}

# --- case 28(c): a rev-3 save with one extra Effect ---------------------
R3S="$WORK/rev3-session"
mkdir -p "$R3S/mod" "$R3S/save" "$R3S/logs"
cp -Rf "$REV3/lib" "$R3S/lib"
ln -sfn "$REV3/inc" "$R3S/inc"
append_effect "$R3S/lib"
INCURSIONPATH="$R3S/" "$REV3/incursion-headless" -compile main.irc \
    < /dev/null > "$R3S/compile.log" 2>&1
if [ ! -f "$R3S/mod/Incursion.Mod" ]; then
    tail -10 "$R3S/compile.log"
    fail "the rev-3 appended-Effect module did not compile"
else
    cp -f "$ROOT/tools/fixtures/options-2026-08-22.dat" "$R3S/Options.Dat"
    INCURSIONPATH="$R3S/" INCURSION_SEED=1 INCURSION_OPTIONS="$R3S/Options.Dat" \
        "$REV3/incursion-headless" -keys "$ROOT/tools/keys/smoke.keys" \
        < /dev/null > "$R3S/session.log" 2>&1
    R3_SAVE="$(ls "$R3S"/save/*.sav 2>/dev/null | head -1)"
    if [ -z "$R3_SAVE" ]; then
        tail -10 "$R3S/session.log"
        fail "the rev-3 appended-Effect session produced no save"
    else
        STAMP="$(dd if="$R3_SAVE" bs=1 skip=4 count=5 2>/dev/null)"
        [ "$STAMP" = "IS1.3" ] || fail "the rev-3 save stamp is \"$STAMP\", wanted IS1.3"
        EFF="$(python3 - "$R3_SAVE" <<'PY'
import struct, sys
sys.path.insert(0, 'tools')
from script_vars_save_diff import records
fs = next(fs for (t, h), fs in records(sys.argv[1]).items() if t == 1)
print(struct.unpack('<21I', fs['816.1.4'][1][8:])[3])
PY
)"
        [ "$EFF" = "1189" ] || fail "the rev-3 save's Effect array is $EFF, wanted 1189"
        echo "28(c): rev-3 save IS1.3 with Effect array 1189 (391e353 length 1188)"

        # The HEAD module with the same appended Effect, so drift passes and
        # the recovery TABLE check is the thing that refuses.
        HEADW="$WORK/head-append"
        mkdir -p "$HEADW/mod" "$HEADW/save" "$HEADW/logs"
        cp -Rf "$ROOT/lib" "$HEADW/lib"
        ln -sfn "$ROOT/inc" "$HEADW/inc"
        append_effect "$HEADW/lib"
        INCURSIONPATH="$HEADW/" "$COMPILER" -compile main.irc \
            < /dev/null > "$HEADW/compile.log" 2>&1
        if [ ! -f "$HEADW/mod/Incursion.Mod" ]; then
            tail -10 "$HEADW/compile.log"
            fail "the HEAD appended-Effect module did not compile"
        else
            INCURSIONPATH="$HEADW/" "$BIN" -dump "$R3_SAVE" \
                > "$HEADW/dump.out" 2> "$HEADW/dump.err" < /dev/null
            STATUS=$?
            [ "$STATUS" -ne 0 ] || fail "28(c): the over-long IS1.3 save LOADED and must refuse"
            if grep -qF "recovery array Effect length 1189 exceeds 391e353 length 1188" "$HEADW/dump.err"; then
                echo "28(c): REFUSED -- $(grep -o 'recovery array Effect length [0-9]* exceeds 391e353 length [0-9]*' "$HEADW/dump.err" | head -1)"
            else
                head -5 "$HEADW/dump.err"
                fail "28(c): refused, but not by the recovery array-length check"
            fi
            grep -q '^=== Incursion save dump ===' "$HEADW/dump.out" &&
                fail "28(c): refused, yet the report was still printed"
        fi
    fi
fi

# --- case 21: a v0 save is refused by its stamp before any write ---------
# inc-vqla widened Character::Spells[], so a v0 (raw-dump) save can no longer
# be read at this build's sizes: -convert refuses it by its stamp, before the
# raw reader runs and before any .v0 backup is written.
FIX="$ROOT/docs/evidence/inc-upw.13/Furious_Fox.sav"
[ -f "$FIX" ] || fail "fixture Furious_Fox.sav is missing"

cp -f "$FIX" "$WORK/copy.sav"
INCURSIONPATH="$ROOT/" "$BIN" -headless -timeout 60 -convert "$WORK/copy.sav" \
    > "$WORK/convert.out" 2>&1 < /dev/null
STATUS=$?
[ "$STATUS" -eq 2 ] || { head -6 "$WORK/convert.out"; fail "case 21: v0 -convert exited $STATUS, wanted 2"; }
grep -qi "release 4" "$WORK/convert.out" || fail "case 21: the refusal does not carry the release-4 message"
cmp -s "$WORK/copy.sav" "$FIX" || fail "case 21: the refused run changed the target file"
[ ! -e "$WORK/copy.sav.v0" ] || fail "case 21: the refused run left a .v0 behind"
echo "case 21: v0 -convert REFUSED with the release-4 message, target intact"

# --- nothing real touched -----------------------------------------------
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null)"
[ "$REAL_SAVE_BEFORE" = "$REAL_SAVE_AFTER" ] ||
    fail "the real save/ directory's contents changed during this check"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "PASS: an over-long IS1.3 save was refused by the recovery table; a v0"
echo "      copy was refused by its stamp with the release-4 message and left"
echo "      intact with no .v0 sibling."
exit 0
