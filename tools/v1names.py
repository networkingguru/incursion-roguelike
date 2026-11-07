#!/usr/bin/env python3
# gate: none static; pure parsing of save bytes it is handed
# fact: the saved character, world and seed -- not read: this module only reads the name table of the file it is given
"""Find a field of a revision 7 save by (scope, name), through the save's own
name table (inc-cjos0; docs/superpowers/specs/2026-11-07-names-in-the-file-design.md 5.2).

A revision 7 field is `u16 id, u8 kind, payload`, and `id` is a row of the
group's name table: the record of type 200 that ends the group, a list of
`u16 id, u16 scopeLen, scope, u16 nameLen, name`. Ids differ from file to file,
so a tool that reads save bytes asks this module for the id instead of
writing a number.

    import v1names
    ids = v1names.table(data)                      # {(scope, name): id}
    v1names.field_id(data, "Game.MDataSeg.Segment", "PoolLengths")

A revision 3-6 file has no table; table() exits with a message saying so. A
tool that builds an old-revision file on purpose uses inc/SaveLegacyTags.h
(see tools/craft_bad_v1_saves.py to_legacy).
"""
import struct
import sys

REC_NAMES = 200
FIRST_RECORD = 124          # 96-byte file header + 28-byte group header
OBJCOUNT_AT = FIRST_RECORD - 12


def records(data):
    """Yield (type, handle, body_offset, length) for the first group's
    records. Reads a raw (uncompressed) group only."""
    if struct.unpack_from("<h", data, 90)[0] != 0:
        sys.exit("v1names: not a RAW-mode file (regenerate under INCURSION_V1_RAW=1)")
    pos = FIRST_RECORD
    for _ in range(struct.unpack_from("<i", data, OBJCOUNT_AT)[0]):
        handle, length = struct.unpack_from("<II", data, pos + 1)
        yield data[pos], handle, pos + 9, length
        pos += 9 + length


def table(data):
    ids = {}
    for typ, _, off, length in records(data):
        if typ != REC_NAMES:
            continue
        body, q = data[off:off + length], 0
        while q != len(body):
            nid, sl = struct.unpack_from("<HH", body, q)
            q += 4
            scope = body[q:q + sl].decode()
            q += sl
            nl, = struct.unpack_from("<H", body, q)
            q += 2
            ids[(scope, body[q:q + nl].decode())] = nid
            q += nl
    if not ids:
        sys.exit("v1names: the file carries no name table (a revision 3-6 file?)")
    return ids


def field_id(data, scope, name):
    ids = table(data)
    if (scope, name) not in ids:
        sys.exit('v1names: no field "%s" in scope "%s" in the save\'s name table'
                 % (name, scope))
    return ids[(scope, name)]
