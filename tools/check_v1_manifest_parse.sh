#!/bin/bash
# The v1 module manifest's load-side parser refuses a malformed manifest
# (docs/SAVE-SCHEMA-SPEC.md, "The module manifest"; phase 2 of
# docs/superpowers/plans/2026-08-25-save-manifest-position-refs.md).
#
# WHY THIS CHECK EXISTS, AND WHY A ROUND TRIP IS NOT ENOUGH. The manifest is
# written by v1WriteModuleManifest() and parsed by SaveV1_SegmentFields().
# Until the conversion phase lands, NOTHING READS what the parser produces.
# A parser that never ran at all would leave tools/check_v1_full_roundtrip.sh
# and tools/check_schema_roundtrip.sh green. Only a deliberately corrupt
# manifest can tell the two apart: it must be refused, by name.
#
# METHOD. Write a real raw-mode v1 save from the deterministic seed-1 smoke
# session, prove the clean file loads, then corrupt ONE field of the manifest
# per case and require the load to fail with that case's own error text.
#
# The work directory prefix deliberately avoids the word "manifest": an
# earlier draft grepped the loader's output for it and matched its own temp
# path, reporting a pass it had not earned.
#
# NOT COVERED, on purpose. The parser's "count != 21" and "elemSize != 4"
# branches are unreachable through byte corruption: either field changes the
# K_ARRAY record's own size, so v1ScanFields desynchronises and throws before
# SaveV1_SegmentFields sees the entry. Those branches guard against a save
# crafted to stay self-consistent, which this check does not build.
#
# Usage: tools/check_v1_manifest_parse.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-p2parse.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Raw mode (DEBUG builds) leaves the records uncompressed, so the mutations
# below can find the manifest by its own wire bytes. Sandboxed run directory:
# nothing here can touch the real save/.
INCURSION_V1_RAW=1 INCURSION_RUN_DIR="$WORK/run1" \
    ./tools/headless.sh tools/keys/smoke.keys 1 \
    > "$WORK/session1.log" 2>&1 < /dev/null
SAVE="$(ls "$WORK"/run1/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE" ]; then
    echo "--- session output ---"
    tail -20 "$WORK/session1.log"
    fail "the session that was supposed to produce a raw v1 save produced none"
    exit 1
fi
echo "raw save: $(wc -c < "$SAVE" | tr -d ' ') bytes"

# The control. Without it a check that refuses everything looks like a pass.
if ! INCURSION_DUMP_SANDBOX="$WORK/sb-clean" ./tools/dump_save.sh "$SAVE" \
        > "$WORK/clean.out" 2> "$WORK/clean.err"; then
    echo "--- dump_save.sh stderr ---"
    tail -5 "$WORK/clean.err"
    fail "the UNCORRUPTED raw save did not load -- the rest proves nothing"
    exit 1
fi
echo "control: the clean raw save loads"

mutate() { # <label> <mutation> <expected message substring>
    local label="$1" mut="$2" want="$3"
    cp "$SAVE" "$WORK/bad.sav"
    if ! python3 - "$WORK/bad.sav" "$mut" 2> "$WORK/$label.craft"; then
        echo "--- crafting output ---"
        cat "$WORK/$label.craft"
        fail "[$label] the mutation could not be crafted"
        return
    fi <<'PY'
import sys, struct

path, mut = sys.argv[1], sys.argv[2]
b = bytearray(open(path, 'rb').read())

# Tag 4 of a module slot's scope: u16 tag, u8 K_ARRAY(11), u32 count 21,
# u32 elemSize 4, then 21 uint32 lengths (inc/Base.h:723-732).
pat = struct.pack('<HBII', 4, 11, 21, 4)
i = b.find(pat)
if i < 0:
    sys.exit("no manifest tag-4 record is in the save")

if mut == 'length':
    # One array longer than the format can address. An rID carries the
    # module slot in its top 8 bits (inc/Res.h:1359 reads "(xID >> 24) - 1"),
    # so the running index has 24 bits and 0xFFFFFF is the ceiling.
    struct.pack_into('<I', b, i + 11, 0x01000000)
elif mut == 'sum':
    # Every array legal on its own, the sum over the ceiling. This is the
    # case a per-array check alone would miss.
    for k in range(21):
        struct.pack_into('<I', b, i + 11 + 4 * k, 0x100000)
elif mut == 'namelen':
    # Tag 5 follows tag 4 exactly: 11 header bytes plus 21*4 payload bytes.
    j = i + 11 + 84
    tag, kind = struct.unpack_from('<HB', b, j)
    if (tag, kind) != (5, 8):          # K_BLOB is 8
        sys.exit("tag 5 is not where the writer puts it: got tag %d kind %d"
                 % (tag, kind))
    n0 = struct.unpack_from('<H', b, j + 7)[0]
    # Grow name 0 by one byte. Every later name then misparses, and the blob
    # cannot end exactly on the last name, so the parser must refuse.
    struct.pack_into('<H', b, j + 7, n0 + 1)
else:
    sys.exit("unknown mutation: " + mut)

open(path, 'wb').write(bytes(b))
PY

    INCURSION_DUMP_SANDBOX="$WORK/sb-$label" ./tools/dump_save.sh "$WORK/bad.sav" \
        > "$WORK/$label.out" 2> "$WORK/$label.err"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "[$label] the corrupt save LOADED -- the manifest parser did not run"
        return
    fi
    local hit
    hit="$(cat "$WORK/$label.err" "$WORK/$label.out" | grep -m1 -F "$want")"
    if [ -z "$hit" ]; then
        echo "--- loader output ---"
        tail -5 "$WORK/$label.err"
        fail "[$label] refused with exit $rc, but not by the manifest parser: no \"$want\""
        return
    fi
    echo "ok [$label]: $hit"
}

mutate length  length  "manifest array 0 length"
mutate sum     sum     "manifest length sum exceeds"
mutate namelen namelen "runs past the blob"

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: the v1 module manifest parser did not refuse a malformed manifest"
    exit 1
fi
echo "PASS: a real v1 save loads, and the module manifest parser refuses a"
echo "      length over the format ceiling, a length sum over it, and a name"
echo "      that runs past its blob."
exit 0
