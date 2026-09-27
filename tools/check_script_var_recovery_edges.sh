#!/bin/bash
# gate: live
# inc-glnx recovery edge cases, docs/SAVE-SCHEMA-SPEC.md test plan:
#   case 28(c) an IS1.3 save whose manifest has an array longer than at
#              391e353 refuses, naming the array;
#   case 28(d) a v0 copy whose block size does not match refuses;
#   case 21    a v0 copy converts against a matching module, keeping the
#              original bytes at <file>.v0 (the v0 recovery path).
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

# --- case 28(d) and case 21: the v0 -convert path -----------------------
# The fixture predates 4ba035b (the immolation Effect), so the matching
# module is HEAD scripts with lib/m_items.irh and lib/main.irc reverted to
# 4ba035b^ -- the exact procedure tools/check_convert_guard.sh uses (it may
# not be run by this role). The mismatch module is HEAD plus one Effect.
FIX="$ROOT/docs/evidence/inc-upw.13/Furious_Fox.sav"
[ -f "$FIX" ] || fail "fixture Furious_Fox.sav is missing"

PRE="$WORK/pre4ba035b"
mkdir -p "$PRE/mod" "$PRE/save" "$PRE/logs"
cp -Rf "$ROOT/lib" "$PRE/lib"
ln -sfn "$ROOT/inc" "$PRE/inc"
for f in lib/m_items.irh lib/main.irc; do
    if ! git -C "$ROOT" show "4ba035b^:$f" > "$PRE/$f"; then
        fail "git show 4ba035b^:$f failed"
        exit 1
    fi
done
INCURSIONPATH="$PRE/" "$COMPILER" -compile main.irc < /dev/null > "$PRE/compile.log" 2>&1
[ -f "$PRE/mod/Incursion.Mod" ] || { tail -10 "$PRE/compile.log"; fail "the pre-4ba035b module did not compile"; }

convert() { # <sandbox> <path> <log>
    INCURSIONPATH="$1/" INCURSION_MAX_KEYS=40 \
        "$BIN" -headless -timeout 60 -convert "$2" > "$3" 2>&1 < /dev/null
}

# 28(d): the mismatched HEAD+1 Effect module refuses with the target intact.
if [ -n "${HEADW:-}" ] && [ -f "$HEADW/mod/Incursion.Mod" ]; then
    cp -f "$FIX" "$WORK/copy_mismatch.sav"
    convert "$HEADW" "$WORK/copy_mismatch.sav" "$WORK/mismatch.out"
    STATUS=$?
    [ "$STATUS" -eq 2 ] || { head -6 "$WORK/mismatch.out"; fail "28(d): mismatched-module -convert exited $STATUS, wanted 2"; }
    cmp -s "$WORK/copy_mismatch.sav" "$FIX" || fail "28(d): the mismatched run changed the target file"
    [ ! -e "$WORK/copy_mismatch.sav.v0" ] || fail "28(d): the mismatched run left a .v0 behind"
    grep -qi "does not match" "$WORK/mismatch.out" || fail "28(d): the refusal does not say the module does not match"
    echo "28(d): REFUSED -- $(grep -o 'v0 block slot 0 size [0-9]* does not match loaded row total [0-9]*' "$WORK/mismatch.out" | head -1)"
fi

# 21: the matching pre-4ba035b module converts the copy.
cp -f "$FIX" "$WORK/copy.sav"
convert "$PRE" "$WORK/copy.sav" "$WORK/copy.out"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    tail -10 "$WORK/copy.out"
    fail "case 21: -convert on a scratch copy (matching module) exited $STATUS, wanted 0"
else
    [ -f "$WORK/copy.sav.v0" ] || fail "case 21: conversion left no copy.sav.v0 backup"
    cmp -s "$WORK/copy.sav.v0" "$FIX" || fail "case 21: copy.sav.v0 does not hold the original v0 bytes"
    STAMP="$(dd if="$WORK/copy.sav" bs=1 skip=4 count=5 2>/dev/null)"
    [ "$STAMP" = "IS1.4" ] || fail "case 21: the converted file's stamp is \"$STAMP\", wanted IS1.4"
    echo "case 21: converted to IS1.4 with a byte-exact .v0 backup"
fi

# --- nothing real touched -----------------------------------------------
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null)"
[ "$REAL_SAVE_BEFORE" = "$REAL_SAVE_AFTER" ] ||
    fail "the real save/ directory's contents changed during this check"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "PASS: an over-long IS1.3 save was refused by the recovery table; a"
echo "      mismatched v0 module refused with the target intact; a matching"
echo "      v0 module converted with a byte-exact .v0 backup."
exit 0
