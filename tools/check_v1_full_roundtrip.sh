#!/bin/bash
# The v1 schema's whole-save round trip (docs/SAVE-SCHEMA-SPEC.md, Task 6 of
# docs/superpowers/plans/2026-08-24-save-schema-v1.md).
#
# What it proves, in order:
#   1. a real game session writes its save in the v1 format ("IS1." stamp);
#   2. that save reloads to the same character (-dump reads it and reports
#      the exact fields a deterministic seed must produce);
#   3. the FIXPOINT byte identity: save1 -> load -> save2 -> load -> save3,
#      and save2 equals save3 field for field, except an explicit, named
#      allowlist of volatile fields.
#
# WHY A FIXPOINT AND NOT save1 == save2. The spec's save-load-save wording
# assumed load+save is the identity. Measured (2026-08-24, field-level diff
# of two raw-mode generations), it is not, for reasons that are real state
# and not serialization defects:
#   - one-time load normalisation: SanitizeLoadedTargets() zeroes a
#     monster's stale targets whose handles died; the FIRST reload
#     canonicalises them, after which they are stable. Comparing save2
#     against save3 absorbs exactly this class.
#   - permanently volatile fields: wall-clock time stats, profiling
#     counters that count the load path's own work, and the one game tick
#     a quick-quit save costs. Those differ between EVERY pair of
#     generations; they are the allowlist below, each entry with its
#     reason. If save2 vs save3 differs OUTSIDE the allowlist, that is a
#     real serialization defect: investigate it, never widen the list.
#
# The comparison is field-aware, not offset-based: the fixpoint sessions
# save in raw mode (INCURSION_V1_RAW=1, DEBUG builds only), the records are
# parsed tag by tag, and every differing byte must fall inside an
# allowlisted field's payload. A raw byte-offset cmp would go blind the
# moment a variable-length field moved the tail of the file.
#
# It also MEASURES the save's size (spec risk 6: measure, never assume).
# It prints "v1=<bytes>" always (the REAL, compressed save). When the
# caller passes V0_BASELINE_BYTES=<n> -- the byte size of the same seed's
# save from a pre-flip binary -- it prints "v0=<n>" and the percentage
# delta too. No pass/fail threshold here; the numbers are judged by the
# task that reads them (Task 6 step 4, re-recorded in docs in Task 11).
#
# Modelled on tools/check_dump_save.sh: same deterministic seed-1 +
# smoke.keys save, same sandboxing (nothing here can touch the real save/).
#
# Usage: tools/check_v1_full_roundtrip.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

SEED=1
KEYS="tools/keys/smoke.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-v1roundtrip.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# 1. A real session produces a save (sandboxed run directory; see
#    tools/headless.sh's own header for why never the binary directly).
INCURSION_RUN_DIR="$WORK/run1" ./tools/headless.sh "$KEYS" "$SEED" \
    > "$WORK/session1.log" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- session 1 output ---"
    tail -20 "$WORK/session1.log"
    fail "the session that was supposed to produce a save exited $STATUS, wanted 0"
    exit 1
fi

SAVE1="$(ls "$WORK"/run1/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE1" ]; then
    fail "session 1 produced no .sav file"
    exit 1
fi

# The size measurement, before any assertion can bail out: the number must
# be printed even on the expected pre-flip failure, because that failing run
# is where the v0 baseline comes from.
V1_BYTES="$(wc -c < "$SAVE1" | tr -d ' ')"
echo "v1=$V1_BYTES"
if [ -n "${V0_BASELINE_BYTES:-}" ]; then
    DELTA="$(awk -v a="$V0_BASELINE_BYTES" -v b="$V1_BYTES" \
        'BEGIN { printf "%+.2f", (b - a) * 100.0 / a }')"
    echo "v0=$V0_BASELINE_BYTES delta=${DELTA}%"
fi

# 2. The file's own Version field says v1. Offset 4 because fileHeader is
#    { uint32 Sig; char Version[12]; ... } (inc/Base.h).
STAMP="$(dd if="$SAVE1" bs=1 skip=4 count=5 2>/dev/null)"
if [ "$STAMP" != "IS1.3" ]; then
    fail "save Version field reads \"$STAMP\", wanted \"IS1.3\" -- real saves are not at the current v1 revision"
fi

# 3. The v1 save reloads to the same character. Exact values, not "present":
#    seed 1 + smoke.keys chargen is deterministic (the premise
#    tools/check_dump_save.sh and tools/check_headless.sh already rely on).
if ! INCURSION_DUMP_SANDBOX="$WORK/dumpsandbox" ./tools/dump_save.sh "$SAVE1" \
        > "$WORK/dump1.txt" 2> "$WORK/dump1.stderr"; then
    echo "--- dump_save.sh stderr ---"
    cat "$WORK/dump1.stderr"
    fail "tools/dump_save.sh exited non-zero on the v1 save"
fi
grep -qE '^Name:      Varag the Deathbringer$' "$WORK/dump1.txt" ||
    fail "Name: line missing or not 'Varag the Deathbringer' -- the v1 save did not reload to the same character"
grep -qE '^HP:        42 / 42' "$WORK/dump1.txt" ||
    fail "HP: line missing or not '42 / 42' after the v1 reload"
grep -qE '^Format:    IS1\.3$' "$WORK/dump1.txt" ||
    fail "Format: line missing or not IS1.3 -- -dump does not name the file's own stamp"
grep -qE 'Race   Orc' "$WORK/dump1.txt" ||
    fail "the character-sheet dump lost the expected race line after the v1 reload"

# 4. The fixpoint. Each generation session gets a COPY of the previous save
#    (quick-quit overwrites the file it loaded), loads it -- the load menu
#    is deterministic with exactly one save present -- and quick-quits,
#    which saves on the way out (tools/keys/loadsave.keys). Raw mode, so
#    the field parser below can read the records.
generation() { # <input-save> <runtag>  -> path of the new save on stdout
    local in="$1" tag="$2"
    mkdir -p "$WORK/$tag/save"
    cp "$in" "$WORK/$tag/save/"
    INCURSION_V1_RAW=1 INCURSION_RUN_DIR="$WORK/$tag" \
        ./tools/headless.sh tools/keys/loadsave.keys "$SEED" \
        > "$WORK/$tag.log" 2>&1 < /dev/null
    local st=$?
    if [ "$st" -ne 0 ]; then
        tail -20 "$WORK/$tag.log" >&2
        return 1
    fi
    ls "$WORK/$tag"/save/*.sav 2>/dev/null | head -1
}

SAVE2="$(generation "$SAVE1" run2)" ||
    { fail "the first load-then-save session failed"; SAVE2=""; }
SAVE3=""
if [ -n "$SAVE2" ]; then
    SAVE3="$(generation "$SAVE2" run3)" ||
        { fail "the second load-then-save session failed"; SAVE3=""; }
fi

if [ -n "$SAVE2" ] && [ -n "$SAVE3" ]; then
    # Field-aware comparison with the volatile-field allowlist. Every entry
    # is (record type byte, tag path) and carries its measured reason;
    # everything else must be byte-identical. Type bytes: T_GAME=1,
    # T_PLAYER=7 (inc/Defines.h:313,319). Tag numbers: Game's list in
    # inc/Res.h, Player's GameTimeInfo embed (tag 527) in inc/Creature.h.
    if ! python3 - "$SAVE2" "$SAVE3" <<'PYEOF'
import struct, sys

# (type byte, tag path) -> why this field may differ between generations.
# Keep this MINIMAL: only fields MEASURED to differ for a reason that is
# not a serialization defect. Notably absent on purpose: Game tags 808-810
# (inPerceive/inChooseAct/inCalcVal) are re-entrancy DEPTH state, not
# profiling totals -- they must be 0 at every save, so a difference there
# is a real defect and must fail.
ALLOW = {
    # Game: the cc* profiling counters (tags 800-807) and their two
    # per-nature arrays (811, 812) count perception/AI/CalcValues work
    # done since process start; the load path itself does such work.
    **{(1, str(t)): "profiling counter" for t in range(800, 808)},
    (1, "811"): "profiling counter array",
    (1, "812"): "profiling counter array",
    # Game.Turn: the quick-quit save costs one game tick, every
    # generation (measured: exactly +1 per cycle).
    (1, "814"): "quick-quit tick",
    # Player.GameTimeInfo.LTI[]: StoreLevelStats folds wall-clock seconds
    # and the session's menu keystrokes into the depth row on every save.
    (7, "527.1"): "wall-clock/keystroke level stats",
    # Player.GameTimeInfo.start_turn: reset to Game.Turn on save.
    (7, "527.2"): "follows Turn",
    # Player.GameTimeInfo.start_second: time(NULL) at the save.
    (7, "527.5"): "wall clock",
}

def parse(path):
    d = open(path, "rb").read()
    sig, = struct.unpack_from("<I", d, 0)
    # fileHeader (inc/Base.h): Sig 0, Version 4, Name 16, numGroups 88,
    # Compression 90. (Offset 94 is tail padding -- always 0 -- and reading
    # it here once made this assertion inert; tools/craft_bad_v1_saves.py
    # reads 90 and is the reference.)
    comp, = struct.unpack_from("<h", d, 90)
    if sig != 0x1234ABCD or comp != 0:
        sys.exit(f"{path}: not a raw v1 save (sig={sig:#x} comp={comp})")
    gsize, csize, objc = struct.unpack_from("<iii", d, 104)
    if csize != gsize:
        sys.exit(f"{path}: raw file but compSize != groupSize")
    pos = 124
    recs = []
    for _ in range(objc):
        typ = d[pos]
        handle, reclen = struct.unpack_from("<II", d, pos + 1)
        recs.append((handle, typ, d[pos + 9:pos + 9 + reclen]))
        pos += 9 + reclen
    return recs

FIXED = {1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 9: 4, 10: 4}

def fields(stream, prefix=""):
    """Leaf fields of one record's field stream as {tagpath: (kind, bytes)}."""
    pos, out = 0, {}
    while True:
        tag, = struct.unpack_from("<H", stream, pos); pos += 2
        if tag == 0:
            break
        kind = stream[pos]; pos += 1
        if kind in FIXED:
            n = FIXED[kind]; pay = stream[pos:pos + n]; pos += n
        elif kind in (7, 8, 12):        # K_STR, K_BLOB, K_EMBED
            l, = struct.unpack_from("<I", stream, pos); pos += 4
            pay = stream[pos:pos + l]; pos += l
        elif kind == 11:                # K_ARRAY
            c, e = struct.unpack_from("<II", stream, pos)
            n = 8 + c * e; pay = stream[pos:pos + n]; pos += n
        else:
            sys.exit(f"unknown kind {kind}")
        tp = f"{prefix}{tag}"
        if kind == 12:
            out.update(fields(pay, tp + "."))
        else:
            out[tp] = (kind, pay)
    return out

# Records only, not the trailing separator/name table. Sound because the
# table is a pure function of the record walk (entries are interned in
# first-use order as the rID fields are written, and the separator is a
# constant), and no rID-kind field is allowlisted -- so any table
# divergence necessarily shows up as a differing K_RID index inside a
# record, which this compare catches.
a, b = parse(sys.argv[1]), parse(sys.argv[2])
if [(h, t) for h, t, s in a] != [(h, t) for h, t, s in b]:
    sys.exit("record sets differ between the two generations")

bad = 0
for (h, t, sa), (_, _, sb) in zip(a, b):
    if sa == sb:
        continue
    fa, fb = fields(sa), fields(sb)
    for tp in sorted(set(fa) | set(fb)):
        if fa.get(tp) == fb.get(tp):
            continue
        # An allowlisted embed covers its leaves: "527.1" allows "527.1.*".
        allowed = any(k[0] == t and (tp == k[1] or tp.startswith(k[1] + "."))
                      for k in ALLOW)
        if not allowed:
            bad += 1
            pa = fa.get(tp, (None, b""))[1].hex()[:40]
            pb = fb.get(tp, (None, b""))[1].hex()[:40]
            print(f"NOT ALLOWLISTED: handle {h} type {t} tag {tp}: "
                  f"{pa} != {pb}")
if bad:
    sys.exit(f"{bad} field(s) differ outside the volatile allowlist -- "
             "a real serialization defect; do NOT widen the list to pass")
print("fixpoint: save2 == save3 outside the documented volatile fields")
PYEOF
    then
        fail "the save2-vs-save3 fixpoint comparison found differences outside the allowlist"
    fi
fi

# 5. Nothing above may have touched the real save/ directory.
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi
if [ -d "$WORK/dumpsandbox" ]; then
    fail "tools/dump_save.sh left dumpsandbox behind: something was written where nothing should be"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a real session saved in v1, the save reloaded to the exact"
    echo "      expected character, and the save-load-save fixpoint was"
    echo "      field-identical outside the documented volatile fields."
    exit 0
fi
exit 1
