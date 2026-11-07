#!/usr/bin/env python3
"""Craft deliberately corrupt/mutated v1 save files from one genuine
RAW-mode v1 file, for tools/check_v1_adversarial.sh.

Unlike v0 (tools/craft_corrupt_saves.py, which must treat the payload as an
opaque memory image), v1 is parseable by design: the payload is a stream of
tagged records ended by SIGNATURE_TWO (docs/SAVE-SCHEMA-SPEC.md; the wire
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
and yields the grid_mismatch, seg_row_position_past_array and
seg_effmem_flavour_bad_slot mutants; its caller drives all three through
tools/dump_save.sh, the real load path, because -schemaload's harness groups
carry no maps and no Game record.
"""
import struct
import sys
import os
import re

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
# Fields are located by (scope, name) through the file's own name table
# (revision 7; docs/superpowers/specs/2026-11-07-names-in-the-file-design.md
# 5.2), never by a number: an id is a row of THAT file's table. The names
# below are the writer's contract (inc/*.h, src/SaveV1.cpp).
SEG_SCOPE = "Game.MDataSeg.Segment"
THING_STATI = ("Thing", "__Stati")                  # inc/Map.h
MAP_GRID = ("Map", "Grid")                          # inc/Map.h
GRID_GX = ("MapGrid", "gx")                         # src/SaveV1.cpp
GAME_MDATASEG = ("Game", "MDataSeg")                # inc/Res.h
CREATURE_TS = ("Creature", "ts")                    # inc/Creature.h
TS_TCOUNT = ("TargetSystem", "tCount")              # src/Target.cpp
CHAR_NOTIFIEDLEVEL = ("Character", "NotifiedLevel")   # inc/Creature.h
PLAYER_CAUTOBUFF = ("Player", "cAutoBuff")          # inc/Creature.h
LAST_STATI = 237                  # inc/Defines.h
NUM_TARGETS = 32                  # inc/Target.h
MAX_NOTIFIED_LEVEL = 25           # ExperienceChart[27], src/Tables.cpp
MAX_AUTOBUFF_CURSOR = 63          # AutoBuffs[64], inc/Creature.h

CORRUPT = "File is Corrupt"       # ECORRUPT, src/Tables.cpp FileErrors


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def patch_i32(data, offset, value):
    return data[:offset] + struct.pack("<i", value) + data[offset + 4:]


REC_NAMES = 200                   # the name-table record's type byte (src/SaveV1.cpp V1_REC_NAMES)
LEGACY_HEADER = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             os.pardir, "inc", "SaveLegacyTags.h")


def read_legacy_tags():
    """The frozen revision 3-6 tag table, parsed from inc/SaveLegacyTags.h:
    (rows, ranges) with rows = [(scope, tag, name, revLo, revHi)] and
    ranges = [(scope, baseTag, count, name)]. Only a tool that deliberately
    builds an OLD-revision file reads this."""
    text = open(LEGACY_HEADER).read()
    rows = [(m.group(1), int(m.group(2)), m.group(3), int(m.group(4)),
             int(m.group(5))) for m in re.finditer(
        r'\{\s*"([^"]*)",\s*(\d+),\s*"([^"]*)",\s*(\d+),\s*(\d+)\s*\}', text)]
    ranges = [(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4))
              for m in re.finditer(
        r'\{\s*"([^"]*)",\s*(\d+),\s*(\d+),\s*"([^"]*)"\s*\}', text)]
    if not rows:
        die("no rows parsed from %s" % LEGACY_HEADER)
    return rows, ranges


def legacy_lookup(rev):
    """{(scope, name): tag} for one revision, ranges expanded to name#i."""
    rows, ranges = read_legacy_tags()
    out = {}
    for scope, tag, name, lo, hi in rows:
        if lo <= rev <= hi:
            out[(scope, name)] = tag
    for scope, base, count, name in ranges:
        for i in range(count):
            out[(scope, "%s#%d" % (name, i))] = base + i
    return out


def read_name_table(body):
    """[(id, scope, name)] from a name-table record's body:
    u16 id, u16 scopeLen, scope, u16 nameLen, name."""
    rows, q = [], 0
    while q != len(body):
        nid, sl = struct.unpack_from("<HH", body, q)
        q += 4
        scope = body[q:q + sl].decode()
        q += sl
        nl, = struct.unpack_from("<H", body, q)
        q += 2
        name = body[q:q + nl].decode()
        q += nl
        rows.append((nid, scope, name))
    return rows


def name_row(nid, scope, name):
    s, n = scope.encode(), name.encode()
    return struct.pack("<HH", nid, len(s)) + s + struct.pack("<H", len(n)) + n


class V1File:
    """The parsed shape of one raw-mode v1 file. Offsets are absolute.

    A revision 7 file carries its own name table (record type 200); tag()
    answers with that file's id for a (scope, name). A revision 3-6 file has
    no table; tag() answers with the frozen tag number from
    inc/SaveLegacyTags.h (any revision's row: a tool that builds a revision
    3 shape asks for rev 4 tags too)."""

    def __init__(self, data):
        self.data = data
        sig, = struct.unpack_from("<I", data, 0)
        if sig != SIGNATURE:
            die("fileHeader.Sig mismatch: 0x%08X" % sig)
        version = data[4:16].split(b"\0")[0].decode()
        if not version.startswith("IS1."):
            die("not a v1 file: Version=%r" % version)
        self.version = version
        self.rev = int(version[4:]) if version[4:].isdigit() else -1
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
        # field (tag..payload end), absolute. "tag" is the wire id.
        self.records = []
        self.table = None               # the name-table record, revision 7
        self.ids = {}                   # (scope, name) -> id
        pos = PAYLOAD_OFF
        for _ in range(self.obj_count):
            rec_off = pos
            rtype = self.data[pos]
            handle, rec_len = struct.unpack_from("<II", data, pos + 1)
            pos += 9
            if rtype == REC_NAMES:
                for nid, scope, name in read_name_table(
                        data[pos:pos + rec_len]):
                    self.ids[(scope, name)] = nid
                fields = []
            else:
                fields = self.parse_fields(pos, rec_len)
            rec = {"off": rec_off, "type": rtype, "handle": handle,
                   "length": rec_len, "fields": fields}
            if rtype == REC_NAMES:
                self.table = rec
            self.records.append(rec)
            pos += rec_len
        sep, = struct.unpack_from("<I", data, pos)
        if sep != SIGNATURE_TWO:
            die("SIGNATURE_TWO not found where expected")
        pos += 4
        if pos != len(data):
            die("trailing bytes after SIGNATURE_TWO")
        if self.rev >= 7:
            if self.table is None:
                die("revision %d file carries no name table" % self.rev)
        else:
            self.ids = {k: v for k, v in
                        legacy_lookup(self.rev).items()}
            # Any revision's row: the shape mutants name a rev-3 field in a
            # rev-4+ file and the other way round.
            for rev in (4, 3, 6):
                for k, v in legacy_lookup(rev).items():
                    self.ids.setdefault(k, v)
        bind_segment_tags(self)

    def tag(self, key, name=None):
        """Wire id of (scope, name) in this file; die() when the file has no
        such field. Accepts tag((scope, name)) too."""
        if name is None:
            key, name = key
        try:
            return self.ids[(key, name)]
        except KeyError:
            die("the file carries no field \"%s\" in scope \"%s\"; the "
                "case needs it" % (name, key))

    def with_names(self, wanted):
        """Revision 7 only: (new file bytes, V1File) where every (scope,
        name) in `wanted` has a row in the name table, appended after the
        existing rows when missing. Record length and group sizes follow."""
        base, v1 = self.data, self
        add = b""
        nxt = max(self.ids.values(), default=0) + 1
        for scope, name in wanted:
            if (scope, name) in v1.ids:
                continue
            add += name_row(nxt, scope, name)
            nxt += 1
        if not add:
            return base, v1
        t = self.table
        end = t["off"] + 9 + t["length"]
        f = base[:end] + add + base[end:]
        f = fix_record_length(f, t["off"], len(add))
        f = fix_sizes(f, len(add))
        return f, V1File(f)

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


def to_legacy(data, rev=6):
    """Rewrite a revision 7 RAW file as a revision `rev` (3-6) file: every
    field id becomes the frozen tag number of its (scope, name), the name
    table record is removed, and the stamp reads IS1.<rev>. Used ONLY by the
    cases that are old-revision files by definition (IS1.3). Dies on a field
    the frozen table has no row for."""
    v1 = V1File(data)
    if v1.rev < 7:
        return data
    by_id = {nid: k for k, nid in v1.ids.items()}
    legacy = legacy_lookup(rev)
    out = bytearray(data)

    def walk(start, length):
        for f in v1.parse_fields(start, length):
            nid = f["tag"]
            key = by_id[nid]
            if key not in legacy:
                die("to_legacy: no revision %d tag for \"%s\" in scope "
                    "\"%s\"" % (rev, key[1], key[0]))
            out[f["off"]:f["off"] + 2] = struct.pack("<H", legacy[key])
            if f["kind"] == K_EMBED:
                l, = struct.unpack_from("<I", data, f["off"] + 3)
                walk(f["off"] + 7, l)

    for r in v1.records:
        if r["type"] != REC_NAMES:
            walk(r["off"] + 9, r["length"])
    t = v1.table
    cut = 9 + t["length"]
    out = out[:t["off"]] + out[t["off"] + cut:]
    out = bytes(out)
    out = patch_i32(out, OBJCOUNT_OFF, v1.obj_count - 1)
    out = fix_sizes(out, -cut)
    stamp = ("IS1.%d" % rev).encode()
    return out[:4] + stamp + b"\0" * (12 - len(stamp)) + out[16:]


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
    ts = [fl for fl in recs[0]["fields"] if fl["tag"] == v1.tag(CREATURE_TS)]
    if len(ts) != 1 or ts[0]["kind"] != K_EMBED:
        die("expected exactly one \"%s\" K_EMBED field (Creature::ts)"
            % CREATURE_TS[1])
    # tag (2) + kind (1) + embed length (4), then the nested field stream.
    inner = ts[0]["off"] + 7
    tag, kind = struct.unpack_from("<HB", base, inner)
    if tag != v1.tag(TS_TCOUNT) or kind != K_U8:
        die("expected TargetSystem's first embedded field to be K_U8 "
            "tCount; got id %d kind %d" % (tag, kind))
    off = inner + 3
    if base[off] > NUM_TARGETS:
        die("the genuine file already carries tCount=%d" % base[off])
    f = base[:off] + bytes([255]) + base[off + 1:]
    cases.append(("creature_tcount_overflow", f, "fail", CORRUPT))


def player_field_payload(v1, base, key, kind, what):
    """Absolute offset of the payload of one top-level field of the single
    Player record, checked to be the kind the field list declares."""
    recs = [r for r in v1.records if r["type"] == T_PLAYER]
    if len(recs) != 1:
        die("expected exactly one T_PLAYER record, found %d" % len(recs))
    fl = [f for f in recs[0]["fields"] if f["tag"] == v1.tag(key)]
    if len(fl) != 1 or fl[0]["kind"] != kind:
        die("expected exactly one \"%s\" kind-%d field (%s)"
            % (key[1], kind, what))
    return fl[0]["off"] + 3         # tag (2) + kind (1)


def craft_player_index_mutants(src_path, cases):
    """Two mutants from the character file, one per half of the reader's
    rule for a file-fed index (inc/Creature.h): a value the game CANNOT
    produce is refused, a value it CAN produce is clamped.

    NotifiedLevel is an int8 the game uses unguarded as
    ExperienceChart[NotifiedLevel+1] (27 entries) and
    NumberNames[NotifiedLevel+1] (31 entries), then PRINTS the const char*
    the second yields (src/Create.cpp:2147-2149). Past the end of NumberNames
    that pointer is whatever follows the table. cAutoBuff is the cursor
    NextAutoBuff() reads AutoBuffs[64] through, one past the end at 64.

    player_index_clamp   both set wild and POSITIVE, which the ++ at
                         src/Create.cpp:2155 and a completed autobuff walk
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
    n_off = player_field_payload(v1, base, CHAR_NOTIFIEDLEVEL, K_I8,
                                 "Character::NotifiedLevel")
    c_off = player_field_payload(v1, base, PLAYER_CAUTOBUFF, K_I16,
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
    st = [fl for fl in rec0["fields"] if fl["tag"] == v1.tag(THING_STATI)]
    if len(st) != 1 or st[0]["kind"] != K_EMBED:
        die("expected exactly one \"__Stati\" K_EMBED field (Thing::__Stati) "
            "in the first record")
    if not 237 <= LAST_STATI <= 255:
        die("stati_nature_oob: LAST_STATI moved out of uint8 overflow "
            "range; re-derive the mutant's nature byte")
    status = struct.pack("<HBB", v1.tag("StatiCollection.Status", "nature"),
                         K_U8, 255) + struct.pack("<H", 0)
    inner = struct.pack("<HBh", v1.tag("StatiCollection", "Last"), K_I16, 1)
    inner += struct.pack("<HBh", v1.tag("StatiCollection", "Allocated"),
                         K_I16, 1)
    inner += struct.pack("<HBI", v1.tag("StatiCollection", "Status#0"),
                         K_EMBED, len(status)) + status
    inner += struct.pack("<H", 0)                     # embed terminator
    field = struct.pack("<HBI", v1.tag(THING_STATI), K_EMBED, len(inner)) \
        + inner
    f, delta = splice(base, st[0]["off"], st[0]["size"], field)
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("stati_nature_oob", f, "fail", CORRUPT))


def craft_seg_row_mutants(src_path, cases):
    """Two mutants from the full raw save, against the memory-row path
    (SaveV1_SegmentFields' load side and v1SegPlace, src/SaveV1.cpp). Driven
    through tools/dump_save.sh like grid_mismatch: only the real load path
    replays a Game record, and only the full save carries one.

    THESE REPLACED seg_row_namelen_overrun. Until phase 4 a row carried an
    inline nameLen + name and the mutant raised that length past the end of
    the row blob. A row is now keyed by (array, position) and carries no
    name, so there is no length left to overrun. The two cases below are what
    the position key made reachable instead:

      seg_row_position_past_array -- a position no manifest length covers.
        Unchecked it would index MDataSeg far past the block v1SegStarts
        sized, so the bound is a write bound, not a tidiness check. The old
        name key DISCARDED an unmatched row; a position must refuse the file
        (docs/SAVE-SCHEMA-SPEC.md, "The resource memory segment").

      seg_effmem_flavour_bad_slot -- an EffMem flavour rID whose module slot
        byte is 0, so (rID >> 24) - 1 is -1. The flavour values became plain
        rIDs in this phase, and they reach v1ConvertManifestRid from a
        different call site than the queued references rid_bad_slot covers.
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    recs = [r for r in v1.records if r["type"] == T_GAME]
    if len(recs) != 1:
        die("expected exactly one T_GAME record in %s, found %d"
            % (src_path, len(recs)))
    seg = [fl for fl in recs[0]["fields"]
           if fl["tag"] == v1.tag(GAME_MDATASEG)]
    if len(seg) != 1 or seg[0]["kind"] != K_EMBED:
        die("expected exactly one \"MDataSeg\" K_EMBED (the segment-record "
            "scope) in the Game record")
    rows_off = None
    for sl in v1.parse_fields(seg[0]["off"] + 7, seg[0]["size"] - 7):
        if sl["kind"] != K_EMBED:
            die("expected only K_EMBED slot records inside \"MDataSeg\"")
        inner = v1.parse_fields(sl["off"] + 7, sl["size"] - 7)
        count_f = [f for f in inner if f["tag"] == segtag("RowCount")]
        rows_f = [f for f in inner if f["tag"] == segtag("Rows")]
        if not count_f or not rows_f:
            continue                    # an empty embed: slot not in use
        count, = struct.unpack_from("<I", base, count_f[0]["off"] + 3)
        if count == 0:
            continue
        rows_off = rows_f[0]["off"] + 7   # tag (2) + kind (1) + blob len (4)
        break
    if rows_off is None:
        die("no module slot in %s carries memory rows; the seg-row mutants "
            "need at least one" % src_path)
    rows_len = struct.unpack_from("<I", base, rows_f[0]["off"] + 3)[0]

    # Row wire shape: u8 rowKind, u8 pool, u32 position, u8 payLen, payload.
    # Both mutations are the same width as the bytes they replace, so no
    # length fixup is needed.
    off = rows_off + 2
    f = base[:off] + struct.pack("<I", 0xFFFFFFF0) + base[off + 4:]
    cases.append(("seg_row_position_past_array", f, "fail",
                  "memory row for module slot"))

    # Walk to the first EffMem row (kind 2) with a non-null FlavorID. Rows
    # are written in memory-layout order, so the Effect block is contiguous.
    eff_off = None
    pos = rows_off
    end = rows_off + rows_len
    while pos + 7 <= end:
        kind = base[pos]
        pay_len = base[pos + 6]
        pay_off = pos + 7
        if pay_off + pay_len > end:
            die("the row blob of %s is malformed at offset %d" % (src_path, pos))
        if kind == 2:
            flavour, = struct.unpack_from("<I", base, pay_off)
            if flavour:
                eff_off = pay_off
                break
        pos = pay_off + pay_len
    if eff_off is None:
        die("no EffMem row in %s carries a flavour rID; the flavour mutant "
            "needs one (a save written after Game::SetFlavors has them)"
            % src_path)
    f = base[:eff_off] + struct.pack("<I", 0x00FFFFFF) + base[eff_off + 4:]
    cases.append(("seg_effmem_flavour_bad_slot", f, "fail",
                  "names module slot -1"))


# --- revision-4 script-variable records (docs/SAVE-SCHEMA-SPEC.md,
#     "Script variables"; test-plan cases 25 and 28(a)) --------------------
#
# At revision 4 a slot's K_EMBED record carries inner tags 2/3 (the
# position-keyed memory rows, still handled above), 4/5 (the module manifest)
# and the two this section mutates: tag 6, a K_U32 varCount, and tag 7, the
# K_BLOB of owner/type/name/value records. Inner tag 1 (the rev-3 script
# blob) is RETIRED at revision 4 and MUST NOT appear; a rev-3 file MUST carry
# it (empty) and MUST NOT carry 6 or 7. The loader refuses every shape below.
#
# Unlike the seg-row mutants these edits sit inside the tag-7 blob or
# alongside tags 6/7, so a shape change moves the slot K_EMBED and the
# tag-816 K_EMBED that contains it. rebuild_slot() rebuilds the slot field
# and patches BOTH ancestor embed lengths, then the Game record length and
# the group sizes -- which is what the first version of these mutants got
# wrong, leaving the reader's nested field scan short.

# The segment record's inner fields, by name (src/SaveV1.cpp). segtag() asks
# the file most recently parsed for its id, so the same case code serves a
# revision 7 file (the file's table) and a revision 3-6 file (frozen tags).
SEG_FIELDS = ("ScriptSegment", "RowCount", "Rows", "PoolLengths", "PoolNames",
              "VariableCount", "Variables")
_SEG_IDS = {}


def bind_segment_tags(v1):
    """Remember v1's id for each segment field it can name; a name the file
    does not carry yet (ScriptSegment in a rev-7 file) is added by
    V1File.with_names before a case uses it."""
    _SEG_IDS.clear()
    for name in SEG_FIELDS:
        if (SEG_SCOPE, name) in v1.ids:
            _SEG_IDS[name] = v1.ids[(SEG_SCOPE, name)]


def segtag(name):
    if name not in _SEG_IDS:
        die("the file carries no segment field \"%s\"" % name)
    return _SEG_IDS[name]


VAR_REC_HEADER = 6                # owner u32 + type u8 + nameLen u8



def patch_field_len(data, field_off, delta):
    """Add delta to a K_STR/K_BLOB/K_EMBED field's 4-byte length, which sits
    just after its 2-byte tag and 1-byte kind."""
    old, = struct.unpack_from("<I", data, field_off + 3)
    return data[:field_off + 3] + struct.pack("<I", old + delta) \
        + data[field_off + 7:]


def slot_with_variables(v1, src_path):
    """The single Game record, its tag-816 scope field, the first slot whose
    K_EMBED carries BOTH variable tags 6 and 7, and that slot's inner fields.
    The writer emits the variable record for every slot with a module, so the
    first such slot exists in any genuine full save."""
    recs = [r for r in v1.records if r["type"] == T_GAME]
    if len(recs) != 1:
        die("expected exactly one T_GAME record in %s, found %d"
            % (src_path, len(recs)))
    rec = recs[0]
    seg = [fl for fl in rec["fields"] if fl["tag"] == v1.tag(GAME_MDATASEG)]
    if len(seg) != 1 or seg[0]["kind"] != K_EMBED:
        die("expected exactly one \"MDataSeg\" K_EMBED in %s" % src_path)
    seg = seg[0]
    for sl in v1.parse_fields(seg["off"] + 7, seg["size"] - 7):
        if sl["kind"] != K_EMBED:
            continue
        inner = v1.parse_fields(sl["off"] + 7, sl["size"] - 7)
        if any(f["tag"] == segtag("VariableCount") for f in inner) and \
                any(f["tag"] == segtag("Variables") for f in inner):
            return rec, seg, sl, inner
    die("no module slot in %s carries revision-4 variable records (tags "
        "6/7); the variable mutants need one" % src_path)


def rebuild_slot(base, rec, seg, slot, new_inner):
    """Replace the slot K_EMBED's inner field stream with new_inner, then fix
    the slot's own length field, the containing tag-816 K_EMBED's length, the
    Game record length and the group sizes."""
    new_slot = struct.pack("<HBI", slot["tag"], K_EMBED, len(new_inner)) \
        + new_inner
    f, delta = splice(base, slot["off"], slot["size"], new_slot)
    f = patch_field_len(f, seg["off"], delta)
    f = fix_record_length(f, rec["off"], delta)
    return fix_sizes(f, delta)


def inner_bytes(base, inner, mutate=None):
    """Re-emit the parsed inner fields (which exclude the tag-0 terminator)
    in order, then the terminator. mutate, if given, is called as
    mutate(field) -> bytes|None for each field; None keeps it, b'' drops it,
    any bytes replace it. New fields can be inserted by yielding them before
    a chosen tag with the `insert_before` helper below."""
    out = b""
    for f in inner:
        if mutate is not None:
            rep = mutate(f)
            if rep is not None:
                out += rep
                continue
        out += base[f["off"]:f["off"] + f["size"]]
    return out + struct.pack("<H", 0)


def var_first_record(base, inner):
    """(absolute offset, nameLen) of the first record in the tag-7 blob."""
    vb = [f for f in inner if f["tag"] == segtag("Variables")][0]
    return vb["off"] + 7, base[vb["off"] + 7 + 5]


def craft_var_record_mutants(src_path, cases):
    """Six in-place mutations inside the tag-7 variable blob. None changes a
    length, so no embed fixup is needed. Each MUST be refused with the
    reader's File is Corrupt error and no out-of-bounds read."""
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    rec, seg, slot, inner = slot_with_variables(v1, src_path)
    vc = [f for f in inner if f["tag"] == segtag("VariableCount")][0]
    vb = [f for f in inner if f["tag"] == segtag("Variables")][0]
    vc_pay = vc["off"] + 3                 # tag (2) + kind (1)
    blob_pay = vb["off"] + 7               # tag + kind + length
    blob_len = struct.unpack_from("<I", base, vb["off"] + 3)[0]
    if blob_len < VAR_REC_HEADER + 1:
        die("%s carries an empty variable blob" % src_path)
    first_off, first_namelen = var_first_record(base, inner)

    # The accepted type set is {2,3,4,5,7,8,9,10,11,12}. Probe the genuine
    # first record so the mutated byte is known to be one the loader accepts.
    genuine_type = base[first_off + 4]
    if genuine_type not in (2, 3, 4, 5, 7, 8, 9, 10, 11, 12):
        die("the genuine first variable record has type %d, outside the "
            "accepted set; re-derive the mutant" % genuine_type)

    # unknown_type: a byte outside the accepted set (13 is not a DT_*).
    f = base[:first_off + 4] + bytes([13]) + base[first_off + 5:]
    cases.append(("var_unknown_type", f, "fail", CORRUPT))

    # type1: DT_VOID. type6: DT_? -- both listed as refusals in the spec.
    for name, typ in (("var_type1", 1), ("var_type6", 6)):
        f = base[:first_off + 4] + bytes([typ]) + base[first_off + 5:]
        cases.append((name, f, "fail", CORRUPT))

    # name_len_past_blob: the first record's nameLen runs past the blob's
    # end. The per-record bounds check refuses it.
    f = base[:first_off + 5] + bytes([0xFF]) + base[first_off + 6:]
    cases.append(("var_name_len_past_blob", f, "fail", CORRUPT))

    # var_count_past_blob: varCount far larger than the blob can hold. The
    # parser's varCount > size/10 bound refuses it before any record walk.
    f = base[:vc_pay] + struct.pack("<I", 0xFFFFFFF0) + base[vc_pay + 4:]
    cases.append(("var_count_past_blob", f, "fail", CORRUPT))

    # owner_outside_manifest: the first record's owner rID is a position past
    # every array the manifest recorded. Conversion fails and the load MUST
    # refuse (a variable owner is a reference, not a droppable row).
    f = base[:first_off] + struct.pack("<I", 0x01FFFFFF) + base[first_off + 4:]
    cases.append(("var_owner_outside_manifest", f, "fail",
                  "past the last resource array"))


def craft_rev_tag_shape_mutants(src_path, cases):
    """Five segment-shape mutants, all refused by SaveV1_SegmentFields'
    revision-shape branch.

    The three revision-4-and-later shapes are built on the revision 7 file
    itself, by name. The two IS1.3 shapes are old-revision files by
    definition, so they are built on the same save rewritten to frozen tag
    numbers (to_legacy) and then stamped IS1.3."""
    raw = open(src_path, "rb").read()
    # ScriptSegment is a name the writer no longer emits, so the file's table
    # has no row for it; add one for the mutants that carry the field.
    base, v1 = V1File(raw).with_names([(SEG_SCOPE, "ScriptSegment")])
    rec, seg, slot, inner = slot_with_variables(v1, src_path)

    def drop(tag):
        return lambda f: b"" if f["tag"] == tag else None

    # rev4_tag1: revision 7 carrying the retired inner ScriptSegment field
    # (empty K_BLOB). Revisions 4 and later share one shape.
    t1 = struct.pack("<HBI", segtag("ScriptSegment"), K_BLOB, 0)

    def add_tag1(f):
        if f["tag"] == segtag("VariableCount"):
            return t1 + base[f["off"]:f["off"] + f["size"]]
        return None
    f = rebuild_slot(base, rec, seg, slot, inner_bytes(base, inner, add_tag1))
    cases.append(("rev4_carries_tag1", f, "fail", CORRUPT))

    # rev4_missing_tag6 / rev4_missing_tag7: VariableCount / Variables gone.
    f = rebuild_slot(base, rec, seg, slot,
                     inner_bytes(base, inner, drop(segtag("VariableCount"))))
    cases.append(("rev4_missing_tag6", f, "fail", CORRUPT))
    f = rebuild_slot(base, rec, seg, slot,
                     inner_bytes(base, inner, drop(segtag("Variables"))))
    cases.append(("rev4_missing_tag7", f, "fail", CORRUPT))

    # The IS1.3 shapes: frozen tag numbers.
    base = to_legacy(raw, 6)
    v1 = V1File(base)
    rec, seg, slot, inner = slot_with_variables(v1, src_path)

    # rev3_tag1_not_empty: a file stamped IS1.3 with tags 6/7 removed and a
    # NON-empty tag 1. Tag 1 must have length 0.
    t1_ne = struct.pack("<HBI", segtag("ScriptSegment"), K_BLOB, 3) + b"abc"

    def to_rev3_nonempty(f):
        if f["tag"] in (segtag("VariableCount"), segtag("Variables")):
            return b""
        if f["tag"] == segtag("RowCount"):
            return t1_ne + base[f["off"]:f["off"] + f["size"]]
        return None
    f = rebuild_slot(base, rec, seg, slot,
                     inner_bytes(base, inner, to_rev3_nonempty))
    f = f[:4] + b"IS1.3" + b"\0" * 7 + f[16:]
    cases.append(("rev3_tag1_not_empty", f, "fail", CORRUPT))

    # rev3_carries_tag6_and_7: a file stamped IS1.3 that still carries the
    # revision-4 variable tags. Tag 1 is required and absent.
    f = base[:4] + b"IS1.3" + b"\0" * 7 + base[16:]
    cases.append(("rev3_carries_tag6_and_7", f, "fail", CORRUPT))


def is13_slot_inner(base, rec, seg, slot, inner, row=None):
    """Build the IS1.3 inner stream from a revision-4 slot: drop tags 6/7,
    insert an empty tag-1 K_BLOB (rev 3 requires it), and optionally replace
    the tag-3 row blob with `row` (kind,pool,position,payLen,payload...) and
    the tag-2 rowCount with the number of rows it leaves."""
    t1 = struct.pack("<HBI", segtag("ScriptSegment"), K_BLOB, 0)
    out = b""
    inserted = False
    for f in inner:
        if f["tag"] in (segtag("VariableCount"), segtag("Variables")):
            continue
        if f["tag"] == segtag("RowCount"):
            if not inserted:
                out += t1
                inserted = True
            if row is None:
                out += base[f["off"]:f["off"] + f["size"]]
            else:
                out += struct.pack("<HBI", segtag("RowCount"), K_U32,
                                   struct.unpack_from("<I", base, f["off"] + 3)[0] + 1)
            continue
        if f["tag"] == segtag("Rows") and row is not None:
            pay = row + base[f["off"] + 7:f["off"] + f["size"]]
            out += struct.pack("<HBI", segtag("Rows"), K_BLOB, len(pay)) + pay
            continue
        out += base[f["off"]:f["off"] + f["size"]]
    return out + struct.pack("<H", 0)


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
V1_PREFIX_VARS_INC = os.path.join(SCRIPT_DIR, os.pardir, "src",
                                  "SaveV1PrefixVars.inc")
V1_PREFIX_ARRAY_COUNT = 21


def read_frozen_prefix_lengths(inc_path=None):
    """Parse the frozen `v1PrefixLengths[21] = {...}` line of
    src/SaveV1PrefixVars.inc (the 391e353 array geometry the IS1.3 recovery
    guard checks against). Raises RuntimeError with a clear message if the
    line cannot be found or does not hold exactly 21 numbers."""
    path = inc_path or V1_PREFIX_VARS_INC
    try:
        with open(path, "r") as fh:
            text = fh.read()
    except OSError as e:
        raise RuntimeError("cannot read frozen prefix lengths from %s: %s"
                           % (path, e))
    m = re.search(r"v1PrefixLengths\s*\[\s*21\s*\]\s*=\s*\{([^}]*)\}", text)
    if not m:
        raise RuntimeError("no 'v1PrefixLengths[21] = {...}' line in %s"
                           % path)
    nums = re.findall(r"\d+", m.group(1))
    if len(nums) != V1_PREFIX_ARRAY_COUNT:
        raise RuntimeError("v1PrefixLengths in %s holds %d numbers, expected "
                           "%d" % (path, len(nums), V1_PREFIX_ARRAY_COUNT))
    return [int(n) for n in nums]


def parse_inner_stream(stream):
    """Walk an inner field stream (tag..payload fields ended by a tag-0
    terminator) and return {tag: (kind, payload_bytes)} for every field.
    Mirrors V1File.parse_fields, but keeps the payload instead of the offset
    so a rebuilt stream can be spliced."""
    fields = {}
    pos = 0
    while pos < len(stream):
        tag, = struct.unpack_from("<H", stream, pos)
        if tag == 0:
            pos += 2
            break
        kind = stream[pos + 2]
        pos += 3
        if kind in FIXED:
            pos += FIXED[kind]
        elif kind in (K_STR, K_BLOB, K_EMBED):
            l, = struct.unpack_from("<I", stream, pos)
            pos += 4
            fields[tag] = (kind, stream[pos:pos + l])
            pos += l
        elif kind == K_ARRAY:
            c, e = struct.unpack_from("<II", stream, pos)
            fields[tag] = (kind, stream[pos:pos + 8 + c * e])
            pos += 8 + c * e
        else:
            raise RuntimeError("unknown field kind %d in inner stream" % kind)
    if pos != len(stream):
        raise RuntimeError("inner field stream has trailing bytes")
    return fields


def trim_is13_manifest(new_inner, frozen):
    """Cut every manifest array longer than its frozen 391e353 length down
    to that length, so the file passes the IS1.3 recovery guard. The tag-5
    names blob holds the entries array after array, so the tail of each
    trimmed array is dropped from the blob (keeping every later array's
    names in place) and the tag-4 length for that array shrinks to match.

    Returns (trimmed_inner, removed, new_lengths), where removed is a list
    of (array, position, name) for every entry the trim drops and
    new_lengths is the trimmed 21-array geometry."""
    fields = parse_inner_stream(new_inner)
    if segtag("PoolLengths") not in fields or segtag("PoolNames") not in fields:
        raise RuntimeError("IS1.3 inner stream carries no manifest tags 4/5")
    kind4, pay4 = fields[segtag("PoolLengths")]
    if kind4 != K_ARRAY:
        raise RuntimeError("manifest tag 4 is kind %d, expected K_ARRAY"
                           % kind4)
    count, elem = struct.unpack_from("<II", pay4, 0)
    if count != V1_PREFIX_ARRAY_COUNT or elem != 4:
        raise RuntimeError("manifest tag 4 has count %d elem %d, expected "
                           "%d/4" % (count, elem, V1_PREFIX_ARRAY_COUNT))
    lengths = list(struct.unpack_from("<%dI" % count, pay4, 8))
    kind5, pay5 = fields[segtag("PoolNames")]
    if kind5 != K_BLOB:
        raise RuntimeError("manifest tag 5 is kind %d, expected K_BLOB"
                           % kind5)
    names = []
    pos = 0
    while pos < len(pay5):
        if len(pay5) - pos < 2:
            raise RuntimeError("manifest names blob ends mid-length")
        l, = struct.unpack_from("<H", pay5, pos)
        pos += 2
        if l > len(pay5) - pos:
            raise RuntimeError("manifest name length runs past the blob")
        names.append(pay5[pos:pos + l])
        pos += l
    if sum(lengths) != len(names):
        raise RuntimeError("manifest lengths sum %d != name count %d"
                           % (sum(lengths), len(names)))

    removed = []
    new_lengths = list(lengths)
    kept = []
    base = 0
    for p in range(count):
        n = lengths[p]
        f = frozen[p]
        if n > f:
            for i in range(f, n):
                removed.append((p, i, names[base + i].decode("latin1")))
            kept.extend(names[base:base + f])
            new_lengths[p] = f
        else:
            kept.extend(names[base:base + n])
        base += n

    new4 = struct.pack("<HBII%dI" % count, segtag("PoolLengths"), K_ARRAY,
                       count, 4, *new_lengths)
    blob = b"".join(struct.pack("<H", len(nm)) + nm for nm in kept)
    new5 = struct.pack("<HBI", segtag("PoolNames"), K_BLOB, len(blob)) + blob

    out = b""
    pos = 0
    while pos < len(new_inner):
        tag, = struct.unpack_from("<H", new_inner, pos)
        if tag == 0:
            out += new_inner[pos:pos + 2]
            break
        start = pos
        kind = new_inner[pos + 2]
        pos += 3
        if kind in FIXED:
            pos += FIXED[kind]
        elif kind in (K_STR, K_BLOB, K_EMBED):
            l, = struct.unpack_from("<I", new_inner, pos)
            pos += 4 + l
        elif kind == K_ARRAY:
            c, e = struct.unpack_from("<II", new_inner, pos)
            pos += 8 + c * e
        else:
            raise RuntimeError("unknown field kind %d in inner stream" % kind)
        if tag == segtag("PoolLengths"):
            out += new4
        elif tag == segtag("PoolNames"):
            out += new5
        else:
            out += new_inner[start:pos]
    return out, removed, new_lengths


V1_POOL_NAMES = ["Monster", "Item", "Feature", "Effect", "Artifact",
                 "Quest", "Dungeon", "Routine", "NPC", "Class", "Race",
                 "Domain", "God", "Region", "Terrain", "Text", "Variable",
                 "Template", "Flavour", "Behaviour", "Encounter"]


def V1PoolName_py(pool):
    if 0 <= pool < len(V1_POOL_NAMES):
        return V1_POOL_NAMES[pool]
    return "?"


def saved_rid_parts(saved, lengths):
    """Mirror v1ConvertManifestRid's walk: map a saved flat rID index to
    (array, position) through `lengths`, or None if it is past the last
    array. Returns (slot, array, position); slot is the raw high byte."""
    slot = (saved >> 24) - 1
    index = saved & 0x00FFFFFF
    position = index
    for p in range(V1_PREFIX_ARRAY_COUNT):
        if position < lengths[p]:
            return (slot, p, position)
        position -= lengths[p]
    return (slot, None, None)


def _manifests_from_game(v1, base):
    """{module slot: [21 lengths]} for every Game-record slot that carries a
    manifest (tags 4/5). These are the SAVE's own numbering, the lengths its
    rID indices were written against."""
    out = {}
    for rec in v1.records:
        if rec["type"] != T_GAME:
            continue
        for sl in v1.parse_fields(rec["off"] + 9, rec["length"]):
            if sl["tag"] != v1.tag(GAME_MDATASEG) or sl["kind"] != K_EMBED:
                continue
            for slot_i, slot_f in enumerate(
                    v1.parse_fields(sl["off"] + 7, sl["size"] - 7)):
                if slot_f["kind"] != K_EMBED:
                    continue
                inner = v1.parse_fields(slot_f["off"] + 7,
                                        slot_f["size"] - 7)
                lens = [f for f in inner if f["tag"] == segtag("PoolLengths")]
                if len(lens) != 1 or lens[0]["kind"] != K_ARRAY:
                    continue
                pay = lens[0]["off"] + 3
                count, elem = struct.unpack_from("<II", base, pay)
                if count == V1_PREFIX_ARRAY_COUNT and elem == 4:
                    out[slot_i] = list(struct.unpack_from("<21I", base,
                                                          pay + 8))
    return out


def rewrite_is13_manifest_rids(base, v1, removed, trimmed):
    """Rewrite every saved rID the base save carries so it still names the
    same manifest entry after `trim_is13_manifest` shortens arrays, and
    refuse any rID that points at a removed entry.

    A saved rID is `((slot+1) << 24) + flat_index`, the flat index running
    across all 21 arrays in order. `trim_is13_manifest` drops the tail of
    every array longer than its frozen 391e353 length, so an rID whose
    original mapping lands past that point in ANY shortened array now
    resolves one-or-more entries too far. This walks the same reference
    sites phase 1 did:
      - every K_RID field, at the top level of a record and recursively
        inside K_EMBED fields (the slotQ/statQ object references);
      - the tag-3 memory rows' EffMem (kind 2) FlavorID/PFlavorID words.
    (rIDs inside K_ARRAY payloads are not visible to this walk, the stated
    phase-1 limit.)

    The tag-7 variable blob is dropped from an IS1.3 file, so its DT_RID
    values are not rewritten; it is scanned only to refuse a removed entry.

    For each reference the ORIGINAL manifest lengths map the rID to
    (array, position). If that (array, position) is one the trim drops,
    die() with the phase-1 "pick another seed" line. Otherwise the new flat
    index is computed with the TRIMMED lengths and the 4-byte rID value is
    written back in place (same slot byte). Because the rID field always
    carries its slot byte, only the low three bytes move; the site's own
    offset and size are unchanged. Returns a NEW bytes object; `base` is
    left untouched. The synthesized bad row is added later and is not seen
    here, so 0x01FFFFFF stays unconvertible."""
    removed_at = {(a, p): nm for (a, p, nm) in removed}
    manifests = _manifests_from_game(v1, base)
    rewritten = []

    def refuse(array, position):
        die("is13_recovered_badrid: the base save uses %s \"%s\" "
            "(position %d), added after 391e353; the fake IS1.3 save "
            "cannot be made -- pick another seed"
            % (V1PoolName_py(array), removed_at[(array, position)],
               position))

    def new_rid(saved, off):
        slot = (saved >> 24) - 1
        orig = manifests.get(slot)
        if orig is None:
            return
        _, array, position = saved_rid_parts(saved, orig)
        if array is None:
            return
        if (array, position) in removed_at:
            refuse(array, position)
        new_index = sum(trimmed[p] for p in range(array)) + position
        newval = ((slot + 1) << 24) + new_index
        if newval != saved:
            out[off:off + 4] = struct.pack("<I", newval)
        rewritten.append((off, saved, newval, slot, array, position))

    def scan_fields(start, length):
        for f in v1.parse_fields(start, length):
            if f["kind"] == K_RID:
                val, = struct.unpack_from("<I", base, f["off"] + 3)
                if val != 0:
                    new_rid(val, f["off"] + 3)
            elif f["kind"] == K_EMBED:
                l, = struct.unpack_from("<I", base, f["off"] + 3)
                scan_fields(f["off"] + 7, l)

    out = bytearray(base)
    for rec in v1.records:
        scan_fields(rec["off"] + 9, rec["length"])

    for rec in v1.records:
        if rec["type"] != T_GAME:
            continue
        for sl in v1.parse_fields(rec["off"] + 9, rec["length"]):
            if sl["tag"] != v1.tag(GAME_MDATASEG) or sl["kind"] != K_EMBED:
                continue
            inner = v1.parse_fields(sl["off"] + 7, sl["size"] - 7)
            vb = [f for f in inner if f["tag"] == segtag("Variables")]
            if vb and vb[0]["kind"] == K_BLOB:
                pay = base[vb[0]["off"] + 7:vb[0]["off"] + vb[0]["size"]]
                pos = 0
                while pos + 6 <= len(pay):
                    pos += 4
                    typ = pay[pos]
                    pos += 1
                    nl = pay[pos]
                    pos += 1
                    pos += nl
                    if pos + 4 > len(pay):
                        break
                    val, = struct.unpack_from("<I", pay, pos)
                    pos += 4
                    if typ == 5 and val != 0:
                        slot = (val >> 24) - 1
                        orig = manifests.get(slot)
                        if orig is not None:
                            _, array, position = saved_rid_parts(val, orig)
                            if array is not None and \
                                    (array, position) in removed_at:
                                refuse(array, position)
            rows = [f for f in inner if f["tag"] == segtag("Rows")]
            if rows and rows[0]["kind"] == K_BLOB:
                pay = base[rows[0]["off"] + 7:rows[0]["off"] + rows[0]["size"]]
                pos = 0
                while pos + 7 <= len(pay):
                    kind = pay[pos]
                    pos += 6
                    paylen = pay[pos]
                    pos += 1
                    if pos + paylen > len(pay):
                        break
                    if kind == 2 and paylen >= 8:
                        off = rows[0]["off"] + 7 + pos
                        for w in (0, 4):
                            val, = struct.unpack_from("<I", base, off + w)
                            if val != 0:
                                new_rid(val, off + w)
                    pos += paylen
    return bytes(out), rewritten


def craft_is13_recovered_badrid(src_path, cases):
    """Case 28(a): an IS1.3 save whose recovered whole-unit DT_RID slot holds
    a value that fails manifest conversion MUST load, with that variable 0
    and exactly one stderr line naming it.

    Of the 97 frozen slots only slot 92 (owner "Create Corporeal Undead",
    variable uID, type 5 == DT_RID) sits in a whole unit (slot % 4 == 0), so
    its image word is MonsterMemory row 23 word 0. No genuine save carries a
    row at position 23, so one is synthesized: kind 0, pool SP_MON, position
    23, a 13-byte payload whose word 0 is the unconvertible rID 0x01FFFFFF.
    Recovery reads word 0 for slot 92, conversion fails, and the value loads
    as 0 with the one stderr line.

    The expected detail is the -dump field line showing value=0 for the
    CURRENT module's Create Corporeal Undead::uID variable (the recovery
    target is found by name, not by the frozen table's own slot number --
    see check_v1_adversarial.sh's is13_recovered_badrid case, which also
    counts the stderr lines)."""
    base = to_legacy(open(src_path, "rb").read(), 6)   # an IS1.3 file: frozen tags
    v1 = V1File(base)
    frozen = read_frozen_prefix_lengths()
    rec, seg, slot, inner = slot_with_variables(v1, src_path)
    # The trim shortens arrays, so the base save's rIDs must be renumbered
    # BEFORE is13_slot_inner copies its tag-3 rows into the IS1.3 inner.
    # The manifest tags pass through is13_slot_inner unchanged, so trim a
    # manifest-only stream to learn the removed entries and the new geometry.
    # The synthesized bad row is added after, so 0x01FFFFFF stays untouched.
    manifest = b"".join(base[f["off"]:f["off"] + f["size"]] for f in inner
                        if f["tag"] in (segtag("PoolLengths"), segtag("PoolNames")))
    _, removed, new_lengths = trim_is13_manifest(manifest
                                                 + struct.pack("<H", 0),
                                                 frozen)
    base, _ = rewrite_is13_manifest_rids(base, v1, removed, new_lengths)
    bad_row = struct.pack("<BBIB", 0, 0, 23, 13) \
        + struct.pack("<I", 0x01FFFFFF) + bytes(9)
    new_inner = is13_slot_inner(base, rec, seg, slot, inner, row=bad_row)
    new_inner, _, _ = trim_is13_manifest(new_inner, frozen)
    f = rebuild_slot(base, rec, seg, slot, new_inner)
    f = f[:4] + b"IS1.3" + b"\0" * 7 + f[16:]
    cases.append(("is13_recovered_badrid", f, "ok",
                  "owner=Create Corporeal Undead ordinal=0 ident=uID "
                  "type=rID value=0"))


def craft_grid_mismatch(src_path, cases):
    """One mutant from the raw-mode FULL save (the only input with a Map
    record; the schematest groups carry none): the grid record's own sizeX
    -- gx, the first field of the Map "Grid" K_EMBED -- bumped by one, so it disagrees
    with the map's already-loaded sizeX (Map sizeX). The reader's
    cross-check must refuse the file with an stderr line naming the grid.
    No length fixups: the mutated field is a fixed-size K_I16.
    """
    base = open(src_path, "rb").read()
    v1 = V1File(base)
    recs = [r for r in v1.records if r["type"] == T_MAP]
    if not recs:
        die("no T_MAP record in %s" % src_path)
    grid = [fl for fl in recs[0]["fields"] if fl["tag"] == v1.tag(MAP_GRID)]
    if len(grid) != 1 or grid[0]["kind"] != K_EMBED:
        die("expected exactly one \"Grid\" K_EMBED grid record in the Map "
            "record; found %s" % [(g["tag"], g["kind"]) for g in grid])
    inner = grid[0]["off"] + 7          # tag (2) + kind (1) + embed len (4)
    tag, kind = struct.unpack_from("<HB", base, inner)
    if tag != v1.tag(GRID_GX) or kind != K_I16:
        die("expected the grid record's first field to be K_I16 gx (the "
            "grid's sizeX); got id %d kind %d" % (tag, kind))
    off = inner + 3
    sx, = struct.unpack_from("<h", base, off)
    f = base[:off] + struct.pack("<h", sx + 1) + base[off + 2:]
    cases.append(("grid_mismatch", f, "fail", "grid"))


MAP_OVERFLOW_NAMES = (("Map", "sizeX"), ("Map", "sizeY"), ("Map", "Grid"),
                      ("MapGrid", "gx"), ("MapGrid", "gy"),
                      ("MapGrid", "elem"), ("MapGrid", "packed"))


def craft_map_grid_overflow(cases, version, full_path):
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

    # The file needs its own name table. The names are read from the real
    # full save's table, so a rename in the writer stops this case instead of
    # leaving it refused for an unknown name (which is also ECORRUPT).
    real = V1File(open(full_path, "rb").read())
    ids = {}
    table = b""
    for n, key in enumerate(MAP_OVERFLOW_NAMES, 1):
        real.tag(key)                    # dies when the writer lost the name
        ids[key] = n
        table += name_row(n, key[0], key[1])
    names_rec = struct.pack("<BII", REC_NAMES, 0, len(table)) + table

    inner = struct.pack("<HBh", ids[("MapGrid", "gx")], K_I16, SX)
    inner += struct.pack("<HBh", ids[("MapGrid", "gy")], K_I16, SY)
    inner += struct.pack("<HBB", ids[("MapGrid", "elem")], K_U8, ELEM)
    inner += struct.pack("<HBI", ids[("MapGrid", "packed")], K_BLOB, lo32) \
        + bytes(lo32)
    inner += struct.pack("<H", 0)                     # embed terminator
    fields = struct.pack("<HBh", ids[("Map", "sizeX")], K_I16, SX)
    fields += struct.pack("<HBh", ids[("Map", "sizeY")], K_I16, SY)
    fields += struct.pack("<HBI", ids[("Map", "Grid")], K_EMBED, len(inner)) \
        + inner
    fields += struct.pack("<H", 0)                    # record terminator
    rec = struct.pack("<BII", T_MAP, 150, len(fields)) + fields
    payload = rec + names_rec + struct.pack("<I", SIGNATURE_TWO)

    stamp = version.encode() if isinstance(version, str) else version
    if len(stamp) > 11:
        die("schema stamp %r does not fit fileHeader.Version[12]" % stamp)
    fh = struct.pack("<I", SIGNATURE) + stamp + bytes(12 - len(stamp)) \
        + bytes(72) + struct.pack("<hhh", 1, 0, 0)    # numGroups/Comp/nDeps
    fh += bytes(FH_SIZE - len(fh))                    # tail padding
    gh = struct.pack("<IiiiiiI", SIGNATURE, 0, len(payload), len(payload),
                     2, 0, 999)
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

    # --- 2. unknown_tag: insert a field whose NAME no field list asks for
    # (a fresh row in the name table, id one past the last, plus the field
    # itself: K_U32 0xDEADBEEF) into the first Item record, lengths fixed up.
    #
    # THIS CASE FLIPPED IN PHASE 6. It used to expect SUCCESS, on the rule
    # that a reader skips what it does not understand. That rule was the
    # wrong half of the contract. A MISSING field is safe -- the constructed
    # default stands, and deleted_tag below still proves it. An EXTRA field
    # means the file carries state this binary cannot honour, and skipping it
    # loads an object that is silently incomplete. The refusal must name the
    # field, so this asserts the name reaches stderr (inc-cjos0: it was the
    # number 999 until names replaced tag numbers).
    ghost = ("Thing", "NoSuchField")
    gbase, gv1 = v1.with_names([ghost])
    rec0 = gv1.records[0]
    ins = struct.pack("<HBI", gv1.tag(ghost), K_U32, 0xDEADBEEF)
    first_field_off = rec0["fields"][0]["off"]
    f, delta = splice(gbase, first_field_off, 0, ins)
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("unknown_tag", f, "fail",
                  'field "NoSuchField" in scope "Thing", which is not one '
                  'this binary reads'))
    v1 = V1File(open(src_path, "rb").read())      # the genuine file again
    base = v1.data
    rec0 = v1.records[0]

    # --- 3. deleted_tag: remove the Thing::Timeout field from the first
    # Item record. The reader must leave the constructed default: Timeout is
    # zero. (-schemaload labels the field by the class that declares it.)
    tag6 = [fl for fl in rec0["fields"] if fl["tag"] == v1.tag("Thing", "Timeout")]
    if len(tag6) != 1 or tag6[0]["kind"] != K_I16:
        die("expected exactly one Thing.Timeout K_I16 field in the first record")
    f, delta = splice(base, tag6[0]["off"], tag6[0]["size"], b"")
    f = fix_record_length(f, rec0["off"], delta)
    f = fix_sizes(f, delta)
    cases.append(("deleted_tag", f, "ok", "field Thing.Timeout=0"))

    # --- 6. wrong_kind: change Timeout's kind byte (K_I16) to K_U32 without
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
    #
    # It is also the malformed-stamp case. "0AAAAAAA" starts with a digit,
    # so a parser built on atoi would read this as revision 0 and refuse it
    # for the wrong reason -- or, once revision 0 is inside a readable range,
    # accept it. The digits must be followed by NUL padding and nothing else.
    f = base[:4] + b"IS1.0AAAAAAA" + base[16:]
    cases.append(("unterminated_version", f, "fail",
                  'revision "IS1.0AAAAAAA" is not'))

    # --- 8b/8c. the two revision gates, phase 6. The stamp comes from the
    # genuine file this run produced, never from a constant: a hard-coded
    # "IS1.3" silently stops testing the gate the day SCHEMA_REV moves, and
    # starts testing the parser instead.
    def restamp(rev):
        stamp = ("IS1.%d" % rev).encode()
        if len(stamp) > 12:
            die("revision %d does not fit fileHeader.Version[12]" % rev)
        return base[:4] + stamp + b"\0" * (12 - len(stamp)) + base[16:]

    if not v1.version.startswith("IS1.") or not v1.version[4:].isdigit():
        die("genuine file carries a non-numeric revision %r" % v1.version)
    live_rev = int(v1.version[4:])

    # NEWER: one past what this binary writes. Nothing about the bytes is
    # wrong; the stamp alone must stop the load, because a later build could
    # have changed the meaning of any tag in the file.
    cases.append(("newer_revision", restamp(live_rev + 1), "fail",
                  ", NEWER than the "))

    # OLDER: revision 0. The floor is MIN_READ_REV, which this script cannot
    # see, so the case uses the lowest revision that ever existed -- it stays
    # below any floor of 1 or more, which is every floor this reader can have
    # while it still refuses something. The message names the floor; the grep
    # deliberately does not, so raising MIN_READ_REV does not rewrite it.
    cases.append(("older_revision", restamp(0), "fail",
                  ", OLDER than revision "))

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


    # --- 12. the grid-dimension mismatch and the two memory-row mutants,
    # all from the full raw save.
    if len(sys.argv) == 6:
        # --- 11. the synthesized 32-bit-truncation grid mutant; its name
        # table is checked against this real save's.
        craft_map_grid_overflow(cases, v1.version, sys.argv[5])
        craft_grid_mismatch(sys.argv[5], cases)
        craft_seg_row_mutants(sys.argv[5], cases)
        # Cases 25 and 28(a): the revision-4 script-variable records. Six
        # in-place blob edits, five tag-shape rebuilds, and the IS1.3
        # recovered-bad-rID case that must LOAD with one stderr line.
        craft_var_record_mutants(sys.argv[5], cases)
        craft_rev_tag_shape_mutants(sys.argv[5], cases)
        craft_is13_recovered_badrid(sys.argv[5], cases)

    for name, contents, expect, detail in cases:
        path = os.path.join(out_dir, name + ".sav")
        with open(path, "wb") as fh:
            fh.write(contents)
        print("%s|%s|%s|%s" % (name, path, expect, detail))

    return 0


if __name__ == "__main__":
    sys.exit(main())
