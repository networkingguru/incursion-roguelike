#!/usr/bin/env python3
"""Craft deliberately corrupt/mutated v1 save files from one genuine
RAW-mode v1 file, for tools/check_v1_adversarial.sh.

Unlike v0 (tools/craft_corrupt_saves.py, which must treat the payload as an
opaque memory image), v1 is parseable by design: the payload is a stream of
tagged records followed by a name table (docs/SAVE-SCHEMA-SPEC.md; the wire
format section of docs/superpowers/plans/2026-08-24-save-schema-v1.md is
normative). This parses a RAW-mode file (fileHeader.Compression == 0,
produced under INCURSION_V1_RAW=1 by a DEBUG build) and emits one mutant per
case.

Output: one line per case, '|'-separated like craft_corrupt_saves.py, but
with FOUR fields because two cases expect SUCCESS rather than refusal:

    name|path|expect|detail

  expect == "fail":  -schemaload must exit non-zero; detail is a substring
                     the stderr must contain.
  expect == "ok":    -schemaload must exit 0; detail is a substring the
                     stdout must contain ("" = no extra requirement beyond
                     the caller's baseline comparison).

Usage: craft_bad_v1_saves.py <raw-v1.sav> <output-dir>
           [<raw-creature-v1.sav> [<raw-character-v1.sav>
           [<raw-full-save.sav>]]]

The optional third file is the schematest 'creature' group's raw file (c.sav).
It carries a Monster record, which the first file does not, and yields the
one mutant that needs a creature: a count field whose value the reader cannot
honour.

The optional fourth file is the schematest 'character' group's raw file
(e.sav). It carries a Player record, which neither of the others does, and
yields the two mutants for a file-fed INDEX inside a Player.

The optional fifth file is a real save from a smoke session run under
INCURSION_V1_RAW=1. It is the only input with a Map record and a Game record,
and yields the grid_mismatch and seg_row_namelen_overrun mutants; its caller
drives both through tools/dump_save.sh, the real load path, because
-schemaload's harness groups carry no maps and no Game record.
"""
import struct
import sys
import os

FH_SIZE = 96
GH_SIZE = 28
GH_OFF = FH_SIZE
GROUPSIZE_OFF = GH_OFF + 8
COMPSIZE_OFF = GH_OFF + 12
OBJCOUNT_OFF = GH_OFF + 16
PAYLOAD_OFF = GH_OFF + GH_SIZE
SIGNATURE = 0x1234ABCD
SIGNATURE_TWO = 0xF1F2F3F4

K_U8, K_I8, K_U16, K_I16, K_U32, K_I32 = 1, 2, 3, 4, 5, 6
K_STR, K_BLOB, K_RID, K_H, K_ARRAY, K_EMBED = 7, 8, 9, 10, 11, 12
FIXED = {K_U8: 1, K_I8: 1, K_U16: 2, K_I16: 2, K_U32: 4, K_I32: 4,
         K_RID: 4, K_H: 4}
SP_EFF = 3
T_GAME = 1                        # inc/Defines.h
T_MAP = 4                         # inc/Defines.h
T_MONSTER = 6                     # inc/Defines.h
T_PLAYER = 7                      # inc/Defines.h
MAP_SIZEX_TAG = 673               # Map::sizeX, inc/Map.h
MAP_SIZEY_TAG = 674               # Map::sizeY, inc/Map.h
MAP_GRID_TAG = 672                # Map's grid record, inc/Map.h
THING_STATI_TAG = 10              # Thing::__Stati, inc/Map.h
GAME_MDATASEG_TAG = 816           # Game's segment-record scope, inc/Res.h
LAST_STATI = 237                  # inc/Defines.h
CREATURE_TS_TAG = 256             # Creature::ts, inc/Creature.h
CHAR_NOTIFIEDLEVEL_TAG = 421      # Character::NotifiedLevel, inc/Creature.h
PLAYER_CAUTOBUFF_TAG = 521        # Player::cAutoBuff, inc/Creature.h
NUM_TARGETS = 32                  # inc/Target.h
MAX_NOTIFIED_LEVEL = 25           # ExperienceChart[27], src/Tables.cpp
MAX_AUTOBUFF_CURSOR = 63          # AutoBuffs[64], inc/Creature.h

CORRUPT = "File is Corrupt"       # ECORRUPT, src/Tables.cpp FileErrors


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def patch_i32(data, offset, value):
    return data[:offset] + struct.pack("<i", value) + data[offset + 4:]


class V1File:
    """The parsed shape of one raw-mode v1 file. Offsets are absolute."""

    def __init__(self, data):
        self.data = data
        sig, = struct.unpack_from("<I", data, 0)
        if sig != SIGNATURE:
            die("fileHeader.Sig mismatch: 0x%08X" % sig)
        version = data[4:16].split(b"\0")[0].decode()
        if not version.startswith("IS1."):
            die("not a v1 file: Version=%r" % version)
        self.version = version
        compression, = struct.unpack_from("<h", data, 90)
        if compression != 0:
            die("not a RAW-mode file (Compression=%d); regenerate under "
                "INCURSION_V1_RAW=1" % compression)
        gh_sig, = struct.unpack_from("<I", data, GH_OFF)
        if gh_sig != SIGNATURE:
            die("groupHeader.Signature mismatch")
        self.group_size, = struct.unpack_from("<i", data, GROUPSIZE_OFF)
        self.comp_size, = struct.unpack_from("<i", data, COMPSIZE_OFF)
        self.obj_count, = struct.unpack_from("<i", data, OBJCOUNT_OFF)
        if self.comp_size != self.group_size:
            die("raw file has compSize != groupSize")
        if PAYLOAD_OFF + self.comp_size != len(data):
            die("compSize (%d) + headers (%d) != file size (%d)"
                % (self.comp_size, PAYLOAD_OFF, len(data)))

        # records: list of dicts {off, type, handle, length, fields}
        # fields: list of {off, tag, kind, size} -- off/size of the WHOLE
        # field (tag..payload end), absolute.
        self.records = []
        pos = PAYLOAD_OFF
        for _ in range(self.obj_count):
            rec_off = pos
            rtype = self.data[pos]
            handle, rec_len = struct.unpack_from("<II", data, pos + 1)
            pos += 9
            fields = self.parse_fields(pos, rec_len)
            self.records.append({"off": rec_off, "type": rtype,
                                 "handle": handle, "length": rec_len,
                                 "fields": fields})
            pos += rec_len
        sep, = struct.unpack_from("<I", data, pos)
        if sep != SIGNATURE_TWO:
            die("SIGNATURE_TWO not found where expected")
        pos += 4
        # name table: list of {off, size, pool, slot, ordinal, name}
        self.name_table_off = pos
        count, = struct.unpack_from("<I", data, pos)
        pos += 4
        self.names = []
        for _ in range(count):
            ent_off = pos
            pool, slot, ordinal, name_len = struct.unpack_from(
                "<BBHH", data, pos)
            pos += 6
            name = data[pos:pos + name_len].decode("latin-1")
            pos += name_len
            self.names.append({"off": ent_off, "size": 6 + name_len,
                               "pool": pool, "slot": slot,
                               "ordinal": ordinal, "name": name})
        if pos != len(data):
            die("trailing bytes after the name table")

    def parse_fields(self, start, length):
        data = self.data
        pos, end = start, start + length
        fields = []
        while True:
            tag, = struct.unpack_from("<H", data, pos)
            if tag == 0:
                pos += 2
                break
            f_off = pos
            kind = data[pos + 2]
            pos += 3
            if kind in FIXED:
                pos += FIXED[kind]
            elif kind in (K_STR, K_BLOB, K_EMBED):
                l, = struct.unpack_from("<I", data, pos)
                pos += 4 + l
            elif kind == K_ARRAY:
                c, e = struct.unpack_from("<II", data, pos)
                pos += 8 + c * e
            else:
                die("unknown kind %d at %d" % (kind, pos))
            if pos > end:
                die("field overruns record")
            fields.append({"off": f_off, "tag": tag, "kind": kind,
                           "size": pos - f_off})
        if pos != end:
            die("record length disagrees with its fields")
        return fields


def splice(base, off, remove, insert):
    """Replace base[off:off+remove] with insert, fixing the containing
    record's length (when off is inside a record) and the group sizes."""
    delta = len(insert) - remove
    out = base[:off] + insert + base[off + remove:]
    return out, delta


def fix_sizes(data, delta):
    data = patch_i32(data, GROUPSIZE_OFF,
                     struct.unpack_from("<i", data, GROUPSIZE_OFF)[0] + delta)
    data = patch_i32(data, COMPSIZE_OFF,
                     struct.unpack_from("<i", data, COMPSIZE_OFF)[0] + delta)
    return data


def fix_record_length(data, rec_off, delta):
    old, = struct.unpack_from("<I", data, rec_off + 5)
    return data[:rec_off + 5] + struct.pack("<I", old + delta) \
        + data[rec_off + 9:]


def craft_creature_tcount(src_path, cases):
    """One mutant from the creature file: TargetSystem::tCount = 255.

    tCount is a uint8 on the wire and t[] holds NUM_TARGETS == 32 slots, and
    everything that walks a TargetSystem bounds itself by tCount -- including
    TargetSystem::SanitizeLoadedTargets, which the v1 reader runs on every
    creature record and which WRITES through that loop. Unbounded, a tCount
    of 255 memsets about 11 KB past the end of the record's allocation. The
    reader must refuse the file instead.
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    recs = [r for r in v1.records if r["type"] == T_MONSTER]
    if len(recs) != 1:
        die("expected exactly one T_MONSTER record in %s, found %d"
            % (src_path, len(recs)))
    ts = [fl for fl in recs[0]["fields"] if fl["tag"] == CREATURE_TS_TAG]
    if len(ts) != 1 or ts[0]["kind"] != K_EMBED:
        die("expected exactly one tag-%d K_EMBED field (Creature::ts)"
            % CREATURE_TS_TAG)
    # tag (2) + kind (1) + embed length (4), then the nested field stream.
    inner = ts[0]["off"] + 7
    tag, kind = struct.unpack_from("<HB", base, inner)
    if tag != 1 or kind != K_U8:
        die("expected TargetSystem's first embedded field to be tag 1 K_U8 "
            "(tCount); got tag %d kind %d" % (tag, kind))
    off = inner + 3
    if base[off] > NUM_TARGETS:
        die("the genuine file already carries tCount=%d" % base[off])
    f = base[:off] + bytes([255]) + base[off + 1:]
    cases.append(("creature_tcount_overflow", f, "fail", CORRUPT))


def player_field_payload(v1, base, tag, kind, what):
    """Absolute offset of the payload of one top-level field of the single
    Player record, checked to be the kind the field list declares."""
    recs = [r for r in v1.records if r["type"] == T_PLAYER]
    if len(recs) != 1:
        die("expected exactly one T_PLAYER record, found %d" % len(recs))
    fl = [f for f in recs[0]["fields"] if f["tag"] == tag]
    if len(fl) != 1 or fl[0]["kind"] != kind:
        die("expected exactly one tag-%d kind-%d field (%s)"
            % (tag, kind, what))
    return fl[0]["off"] + 3         # tag (2) + kind (1)


def craft_player_index_mutants(src_path, cases):
    """Two mutants from the character file, one per half of the reader's
    rule for a file-fed index (inc/Creature.h): a value the game CANNOT
    produce is refused, a value it CAN produce is clamped.

    NotifiedLevel is an int8 the game uses unguarded as
    ExperienceChart[NotifiedLevel+1] (27 entries) and
    NumberNames[NotifiedLevel+1] (31 entries), then PRINTS the const char*
    the second yields (src/Create.cpp:2086-2088). Past the end of NumberNames
    that pointer is whatever follows the table. cAutoBuff is the cursor
    NextAutoBuff() reads AutoBuffs[64] through, one past the end at 64.

    player_index_clamp   both set wild and POSITIVE, which the ++ at
                         src/Create.cpp:2094 and a completed autobuff walk
                         can each reach in play. The file must LOAD, and
                         -schemaload's field lines must show the clamped
                         values -- a clamp that stopped clamping would
                         otherwise be invisible, because the file loads
                         either way.
    player_notified_level_negative
                         NotifiedLevel set negative, which nothing in the
                         game writes. That half must still be refused.

    Both are top-level fields of the Player record, so each mutation is one
    or two bytes with no length fixups. The other new bounds sit inside
    K_ARRAY payloads (RecentVerbs, AutoBuffs) or are enforced at the use
    site rather than at load (GallerySlot).
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    n_off = player_field_payload(v1, base, CHAR_NOTIFIEDLEVEL_TAG, K_I8,
                                 "Character::NotifiedLevel")
    c_off = player_field_payload(v1, base, PLAYER_CAUTOBUFF_TAG, K_I16,
                                 "Player::cAutoBuff")
    if base[n_off] > MAX_NOTIFIED_LEVEL:
        die("the genuine file already carries NotifiedLevel=%d" % base[n_off])
    cur, = struct.unpack_from("<h", base, c_off)
    if cur > MAX_AUTOBUFF_CURSOR:
        die("the genuine file already carries cAutoBuff=%d" % cur)

    f = base[:n_off] + bytes([127]) + base[n_off + 1:]
    f = f[:c_off] + struct.pack("<h", 200) + f[c_off + 2:]
    cases.append(("player_index_clamp", f, "ok",
                  "field Character.NotifiedLevel=%d" % MAX_NOTIFIED_LEVEL))

    f = base[:n_off] + bytes([0x80]) + base[n_off + 1:]   # int8 -128
    cases.append(("player_notified_level_negative", f, "fail", CORRUPT))


def craft_stati_nature_oob(base, v1, cases):
    """One mutant against the first Item record: a Stati collection of one
    Status whose Nature byte is 255.

    On load, StatiCollection::FieldsV1 (inc/Map.h) rebuilds the Idx array,
    which holds LAST_STATI == 237 uint16 entries, and indexes it as
    Idx[S[i].Nature]. A Nature byte of 237..255 would write a uint16 up to
    36 bytes past that heap allocation. The reader must refuse the file:
    Nature < LAST_STATI is the live invariant, so no clamp is defensible.

    The replacement embed is built from scratch -- Last=1, Allocated=1, one
    status embed carrying only tag 1, the nature byte. A missing inner tag
    loads as the constructed default (the deleted_tag rule), so the minimal
    status is valid on the wire and ONLY its Nature is out of range.
    """
    rec0 = v1.records[0]
    st = [fl for fl in rec0["fields"] if fl["tag"] == THING_STATI_TAG]
    if len(st) != 1 or st[0]["kind"] != K_EMBED:
        die("expected exactly one tag-%d K_EMBED field (Thing::__Stati) "
            "in the first record" % THING_STATI_TAG)
    if not 237 <= LAST_STATI <= 255:
        die("stati_nature_oob: LAST_STATI moved out of uint8 overflow "
            "range; re-derive the mutant's nature byte")
    status = struct.pack("<HBB", 1, K_U8, 255) + struct.pack("<H", 0)
    inner = struct.pack("<HBh", 1, K_I16, 1)          # Last
    inner += struct.pack("<HBh", 2, K_I16, 1)         # Allocated
    inner += struct.pack("<HBI", 3, K_EMBED, len(status)) + status
    inner += struct.pack("<H", 0)                     # embed terminator
    field = struct.pack("<HBI", THING_STATI_TAG, K_EMBED, len(inner)) + inner
    f, delta = splice(base, st[0]["off"], st[0]["size"], field)
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("stati_nature_oob", f, "fail", CORRUPT))


def craft_seg_row_namelen(src_path, cases):
    """One mutant from the full raw save, against the memory-row-blob parser
    (SaveV1_SegmentFields' load side, src/SaveV1.cpp): the first row's
    nameLen raised to 0xFFFF with the blob length untouched. Unchecked, the
    parser's memcpy of the name would read ~64KB past the row blob; its
    bound (nameLen > len - pos) must refuse the file instead. Driven
    through tools/dump_save.sh like grid_mismatch: only the real load path
    replays a Game record, and only the full save carries one.
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    recs = [r for r in v1.records if r["type"] == T_GAME]
    if len(recs) != 1:
        die("expected exactly one T_GAME record in %s, found %d"
            % (src_path, len(recs)))
    seg = [fl for fl in recs[0]["fields"] if fl["tag"] == GAME_MDATASEG_TAG]
    if len(seg) != 1 or seg[0]["kind"] != K_EMBED:
        die("expected exactly one tag-%d K_EMBED (the segment-record scope) "
            "in the Game record" % GAME_MDATASEG_TAG)
    rows_off = None
    for sl in v1.parse_fields(seg[0]["off"] + 7, seg[0]["size"] - 7):
        if sl["kind"] != K_EMBED:
            die("expected only K_EMBED slot records inside tag %d"
                % GAME_MDATASEG_TAG)
        inner = v1.parse_fields(sl["off"] + 7, sl["size"] - 7)
        count_f = [f for f in inner if f["tag"] == 2]
        rows_f = [f for f in inner if f["tag"] == 3]
        if not count_f or not rows_f:
            continue                    # an empty embed: slot not in use
        count, = struct.unpack_from("<I", base, count_f[0]["off"] + 3)
        if count == 0:
            continue
        rows_off = rows_f[0]["off"] + 7   # tag (2) + kind (1) + blob len (4)
        break
    if rows_off is None:
        die("no module slot in %s carries memory rows; the seg-row mutant "
            "needs at least one" % src_path)
    # Row header: u8 rowKind, u8 pool, u16 ordinal, u16 nameLen.
    off = rows_off + 4
    f = base[:off] + struct.pack("<H", 0xFFFF) + base[off + 2:]
    cases.append(("seg_row_namelen_overrun", f, "fail", CORRUPT))


def craft_grid_mismatch(src_path, cases):
    """One mutant from the raw-mode FULL save (the only input with a Map
    record; the schematest groups carry none): the grid record's own sizeX
    -- inner tag 1 of the tag-672 K_EMBED -- bumped by one, so it disagrees
    with the map's already-loaded sizeX (outer tag 673). The reader's
    cross-check must refuse the file with an stderr line naming the grid.
    No length fixups: the mutated field is a fixed-size K_I16.
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    recs = [r for r in v1.records if r["type"] == T_MAP]
    if not recs:
        die("no T_MAP record in %s" % src_path)
    grid = [fl for fl in recs[0]["fields"] if fl["tag"] == MAP_GRID_TAG]
    if len(grid) != 1 or grid[0]["kind"] != K_EMBED:
        die("expected exactly one tag-%d K_EMBED grid record in the Map "
            "record; found %s" % (MAP_GRID_TAG,
                                  [(g["tag"], g["kind"]) for g in grid]))
    inner = grid[0]["off"] + 7          # tag (2) + kind (1) + embed len (4)
    tag, kind = struct.unpack_from("<HB", base, inner)
    if tag != 1 or kind != K_I16:
        die("expected the grid record's first field to be tag 1 K_I16 "
            "(sizeX); got tag %d kind %d" % (tag, kind))
    off = inner + 3
    sx, = struct.unpack_from("<h", base, off)
    f = base[:off] + struct.pack("<h", sx + 1) + base[off + 2:]
    cases.append(("grid_mismatch", f, "fail", "grid"))


def craft_map_grid_overflow(cases, version):
    """version comes from a genuine file this run produced, never a
    literal: this header is synthesized from scratch, so a hardcoded
    stamp silently rots into a File Version Mismatch the moment
    SCHEMA_REV moves, and the mutant stops testing what it names."""
    """One synthesized file: a T_MAP record whose sizeX*sizeY*8 packed-grid
    product overflows 32 bits so that its LOW 32 bits equal the crafted
    blob's length exactly.

    Built from scratch rather than mutated, because no schematest group
    carries a Map record. The reader computes the expected packed-blob size
    as sizeX*sizeY*8 from the two already-loaded dimension fields; a
    compare truncated to 32 bits would pass this file and hand the game a
    128 KB grid it will index as 536 million cells. The reader must refuse
    it: the 64-bit product exceeds both 2^32 and the CFILE_SANE_MAX_SIZE
    allocation ceiling (inc/Term.h), and V1Blob checks both in full width.

    ELEM is 8, hardcoded but safe: it is the packed tile size the wire
    format pins (the packed-layout comment beside LocationInfo, inc/Map.h),
    append-only by design. The record carries the grid K_EMBED's own
    matching dimensions and elemSize, so the reader's grid cross-check
    passes and the size check is what must bite. The dimensions are the
    deterministic pick 32767 x 16385:
    8*32767*16385 = 4,295,098,360 = 2^32 + 131,064.
    """
    ELEM = 8
    SX, SY = 32767, 16385
    total = ELEM * SX * SY
    lo32 = total & 0xFFFFFFFF
    if total <= (1 << 32) or lo32 >= (1 << 21):
        die("map_grid_size_overflow: the crafted dimensions no longer "
            "overflow the way the case needs")

    inner = struct.pack("<HBh", 1, K_I16, SX)         # grid sizeX
    inner += struct.pack("<HBh", 2, K_I16, SY)        # grid sizeY
    inner += struct.pack("<HBB", 3, K_U8, ELEM)       # elemSize
    inner += struct.pack("<HBI", 4, K_BLOB, lo32) + bytes(lo32)
    inner += struct.pack("<H", 0)                     # embed terminator
    fields = struct.pack("<HBh", MAP_SIZEX_TAG, K_I16, SX)
    fields += struct.pack("<HBh", MAP_SIZEY_TAG, K_I16, SY)
    fields += struct.pack("<HBI", MAP_GRID_TAG, K_EMBED, len(inner)) + inner
    fields += struct.pack("<H", 0)                    # record terminator
    rec = struct.pack("<BII", T_MAP, 150, len(fields)) + fields
    payload = (rec + struct.pack("<I", SIGNATURE_TWO)
                   + struct.pack("<I", 0))            # empty name table

    stamp = version.encode() if isinstance(version, str) else version
    if len(stamp) > 11:
        die("schema stamp %r does not fit fileHeader.Version[12]" % stamp)
    fh = struct.pack("<I", SIGNATURE) + stamp + bytes(12 - len(stamp)) \
        + bytes(72) + struct.pack("<hhh", 1, 0, 0)    # numGroups/Comp/nDeps
    fh += bytes(FH_SIZE - len(fh))                    # tail padding
    gh = struct.pack("<IiiiiiI", SIGNATURE, 0, len(payload), len(payload),
                     1, 0, 999)
    cases.append(("map_grid_size_overflow", fh + gh + payload,
                  "fail", CORRUPT))


def main():
    if len(sys.argv) not in (3, 4, 5, 6):
        print("usage: craft_bad_v1_saves.py <raw-v1.sav> <output-dir> "
              "[<raw-creature-v1.sav> [<raw-character-v1.sav> "
              "[<raw-full-save.sav>]]]",
              file=sys.stderr)
        return 2
    src_path, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    base = open(src_path, "rb").read()
    v1 = V1File(base)
    cases = []   # (name, contents, expect, detail)

    # --- 1. truncated_at_record_N: cut immediately before record N's type
    # byte, headers untouched. The header range check (compSize > what is
    # left in the file) refuses it. One file per record boundary.
    for n, rec in enumerate(v1.records):
        cases.append(("truncated_at_record_%d" % n, base[:rec["off"]],
                      "fail", CORRUPT))

    # --- 7. truncated_fixed_sizes_at_record_N: the same cuts, but with
    # compSize/groupSize patched down so the header check passes and the
    # PER-RECORD bounds loop must catch the overrun (objCount still claims
    # the full count).
    for n, rec in enumerate(v1.records):
        cut = base[:rec["off"]]
        new_payload = rec["off"] - PAYLOAD_OFF
        f = patch_i32(cut, GROUPSIZE_OFF, new_payload)
        f = patch_i32(f, COMPSIZE_OFF, new_payload)
        cases.append(("truncated_fixed_sizes_at_record_%d" % n, f,
                      "fail", CORRUPT))

    # --- 2. unknown_tag: insert tag=999, kind=K_U32, payload 0xDEADBEEF
    # into the first Item record, lengths fixed up. The skip rule must keep
    # every original field intact: expect SUCCESS and the baseline field
    # lines (the caller compares them).
    rec0 = v1.records[0]
    ins = struct.pack("<HBI", 999, K_U32, 0xDEADBEEF)
    first_field_off = rec0["fields"][0]["off"]
    f, delta = splice(base, first_field_off, 0, ins)
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("unknown_tag", f, "ok", ""))

    # --- 3. deleted_tag: remove the tag=6 (Thing::Timeout) field from the
    # first Item record. The reader must leave the constructed default:
    # Timeout is zero. (Tag 6 sits in Thing's range; -schemaload labels the
    # field by the class that declares it.)
    tag6 = [fl for fl in rec0["fields"] if fl["tag"] == 6]
    if len(tag6) != 1 or tag6[0]["kind"] != K_I16:
        die("expected exactly one tag-6 K_I16 field in the first record")
    f, delta = splice(base, tag6[0]["off"], tag6[0]["size"], b"")
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("deleted_tag", f, "ok", "field Thing.Timeout=0"))

    # --- 6. wrong_kind: change tag 6's kind byte (K_I16) to K_U32 without
    # touching anything else. Known tag, unexpected kind: corruption, never
    # a skip and never a coercion.
    off = tag6[0]["off"] + 2
    f = base[:off] + bytes([K_U32]) + base[off + 1:]
    cases.append(("wrong_kind", f, "fail", CORRUPT))

    # --- 8. unterminated_version: fileHeader.Version is char[12] with no
    # NUL guarantee. Fill all 12 bytes ("IS1." prefix so the v1 dispatch
    # fires) and expect the bounded revision-reject. The expected substring
    # includes the closing quote DIRECTLY after the 12th byte: an unbounded
    # %s would run on into fh.Name's bytes and fail this grep.
    f = base[:4] + b"IS1.0AAAAAAA" + base[16:]
    cases.append(("unterminated_version", f, "fail",
                  'revision "IS1.0AAAAAAA"; this'))

    # --- 4/5. reference mutants, against the first non-null K_RID field.
    #
    # THESE REPLACED bad_name AND bad_ordinal. Until phase 3 of the manifest
    # work a reference travelled as a name-table index and those two mutants
    # corrupted the entry it pointed at. A reference is now the plain rID, so
    # the name table no longer keys references and there was nothing left for
    # them to corrupt. What the plain rID DID make reachable is worse, and is
    # what these two cover: a wire value flows into Modules[(rID >> 24) - 1]
    # and Module::__GetResource, and neither is safe to feed an arbitrary
    # 32-bit number. Both mutations are the same width as the field, so no
    # size fixup is needed.
    rid_off = rid_val = None
    for rec in v1.records:
        for fld in rec["fields"]:
            if fld["kind"] != K_RID:
                continue
            val, = struct.unpack_from("<I", base, fld["off"] + 3)
            if val:
                rid_off, rid_val = fld["off"] + 3, val
                break
        if rid_off is not None:
            break
    if rid_off is None:
        die("no non-null K_RID field to corrupt")

    # rid_bad_slot: a zero slot byte makes the module index -1. Modules[-1]
    # is the read the bound exists to stop.
    f = (base[:rid_off] + struct.pack("<I", rid_val & 0x00FFFFFF)
         + base[rid_off + 4:])
    cases.append(("rid_bad_slot", f, "fail", "names module slot -1"))

    # rid_past_arrays: a position past the end of the slot's last resource
    # array. Nothing may be clamped, skipped or zeroed; the load is refused.
    f = (base[:rid_off] + struct.pack("<I", (rid_val & 0xFF000000) | 0x00FFFFFF)
         + base[rid_off + 4:])
    cases.append(("rid_past_arrays", f, "fail", "past the last resource array"))

    # --- 9. creature_tcount_overflow, from the creature file when given.
    if len(sys.argv) >= 4:
        craft_creature_tcount(sys.argv[3], cases)

    # --- 13. the out-of-range Status nature, from the item file.
    craft_stati_nature_oob(base, v1, cases)

    # --- 10. the two Player index mutants, from the character file.
    if len(sys.argv) >= 5:
        craft_player_index_mutants(sys.argv[4], cases)

    # --- 11. the synthesized 32-bit-truncation grid mutant.
    craft_map_grid_overflow(cases, v1.version)

    # --- 12. the grid-dimension mismatch and the row-blob nameLen overrun,
    # both from the full raw save.
    if len(sys.argv) == 6:
        craft_grid_mismatch(sys.argv[5], cases)
        craft_seg_row_namelen(sys.argv[5], cases)

    for name, contents, expect, detail in cases:
        path = os.path.join(out_dir, name + ".sav")
        with open(path, "wb") as fh:
            fh.write(contents)
        print("%s|%s|%s|%s" % (name, path, expect, detail))

    return 0


if __name__ == "__main__":
    sys.exit(main())
