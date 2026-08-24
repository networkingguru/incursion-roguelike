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


def main():
    if len(sys.argv) != 3:
        print("usage: craft_bad_v1_saves.py <raw-v1.sav> <output-dir>",
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

    # --- 4/5. name-table mutants, against the first Effect-pool entry.
    eff = [e for e in v1.names if e["pool"] == SP_EFF]
    if not eff:
        die("no Effect-pool entry in the name table")
    ent = eff[0]

    # bad_name: a name the module does not have. The load must abort with a
    # message naming it.
    new_name = b"No Such Effect Anywhere"
    ins = struct.pack("<BBHH", ent["pool"], ent["slot"], ent["ordinal"],
                      len(new_name)) + new_name
    f, delta = splice(base, ent["off"], ent["size"], ins)
    f = fix_sizes(f, delta)
    cases.append(("bad_name", f, "fail", "No Such Effect Anywhere"))

    # bad_ordinal: an ordinal at or past the count of same-named resources
    # (Effect names are unique, so 250 is far past). The abort must name the
    # entry.
    ins = struct.pack("<BBHH", ent["pool"], ent["slot"], 250,
                      len(ent["name"])) + ent["name"].encode("latin-1")
    f, delta = splice(base, ent["off"], ent["size"], ins)
    f = fix_sizes(f, delta)
    cases.append(("bad_ordinal", f, "fail", ent["name"]))

    for name, contents, expect, detail in cases:
        path = os.path.join(out_dir, name + ".sav")
        with open(path, "wb") as fh:
            fh.write(contents)
        print("%s|%s|%s|%s" % (name, path, expect, detail))

    return 0


if __name__ == "__main__":
    sys.exit(main())
