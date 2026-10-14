#!/usr/bin/env python3
"""Family parsing for the number-band allocator (inc-24cc).

Reads inc/Defines.h text on stdin and prints "<value> <name>" lines, one per
member of the family named in argv[1]. Families are defined in the spec
docs/specs/2026-10-13-number-bands-brief.md:

  STATI  every "#define NAME <int>" between "#define GENERIC_STATI" and
         "#define LAST_STATI", minus TG_*, SUBSPELL_*, COMPEL_WALK_STEP_MS and
         LAST_STATI itself.
  EV     every "#define EV_<NAME> <int>" whose value is a decimal integer.
  MSG_<FAMILY>
         every "#define MSG_<NAME> <int>" whose name does not start with
         MSG_BAND_ and whose value lies in that family's thousand range. The
         god message families and their ranges are MSG_RANGES below (only
         inc-pu6v bands them today; MSG_SINGLE 1000-1999, MSG_BADSAC
         2000-2999, MSG_BLESSING 3000-3999, MSG_CUSTOM 4000-4999, MSG_AID
         5000-5999, MSG_FALL 6000-6999, MSG_HATE 7000-7999, MSG_SHEET
         8000-8999).

The allocator (tools/next_number.sh) calls this with "python3 -I".

Argument "--nature-width" reads inc/Res.h text on stdin and prints the width N
of the `unsigned int Nature :N;` bitfield (exit 2 when no such line is found);
the check uses it for the stati width rule.
"""

import re
import sys

DEFINE_RE = re.compile(r"^\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)\s*$")
INT_RE = re.compile(r"^[0-9]+$")
TRAILING_COMMENT_RE = re.compile(r"\s*(/\*.*?\*/|//.*)$")
NATURE_RE = re.compile(r"^\s*unsigned\s+int\s+Nature\s*:\s*(\d+)\s*;")

# God message families: family -> (low, high), inclusive. God messages live only
# on the epic branch inc-pu6v, banded 1000 codes apart by MSG_BAND_* constants.
# This is the ONE table the MSG parsers and the usage text draw on.
MSG_RANGES = {
    "MSG_SINGLE": (1000, 1999),
    "MSG_BADSAC": (2000, 2999),
    "MSG_BLESSING": (3000, 3999),
    "MSG_CUSTOM": (4000, 4999),
    "MSG_AID": (5000, 5999),
    "MSG_FALL": (6000, 6999),
    "MSG_HATE": (7000, 7999),
    "MSG_SHEET": (8000, 8999),
}


def define_value(rest):
    """First token after the name, after dropping a trailing comment.

    "243 /* Mag = ... */" -> "243"; "301 // note" -> "301"; "EV_MOVE" -> "EV_MOVE".
    """
    rest = TRAILING_COMMENT_RE.sub("", rest).strip()
    if not rest:
        return ""
    return rest.split()[0]


def parse_stati(text):
    out = []
    inside = False
    for line in text.splitlines():
        m = DEFINE_RE.match(line)
        if not m:
            continue
        name, value = m.group(1), define_value(m.group(2))
        if name == "GENERIC_STATI":
            inside = True
            continue
        if name == "LAST_STATI":
            inside = False
            continue
        if not inside:
            continue
        if name.startswith("TG_") or name.startswith("SUBSPELL_"):
            continue
        if name == "COMPEL_WALK_STEP_MS":
            continue
        if not INT_RE.match(value):
            continue
        out.append((int(value), name))
    return out


def nature_width(text):
    """Width N of the `unsigned int Nature :N;` bitfield, or None.

    The line is `Status::Nature` in inc/Res.h (spec: docs/specs/
    2026-10-13-number-bands-brief.md, "Size limits"). Returns None when no
    line matches.
    """
    for line in text.splitlines():
        m = NATURE_RE.match(line)
        if m:
            return int(m.group(1))
    return None


def parse_events(text):
    out = []
    for line in text.splitlines():
        m = DEFINE_RE.match(line)
        if not m:
            continue
        name, value = m.group(1), define_value(m.group(2))
        if not name.startswith("EV_"):
            continue
        if not INT_RE.match(value):
            continue
        out.append((int(value), name))
    return out


def parse_msg(text, family):
    """MSG members of <family>: "#define MSG_<NAME> <int>" in its range.

    MSG_BAND_* band-boundary constants are ignored, as are values outside the
    family's MSG_RANGES range. Trailing comments are allowed, as for EV.
    """
    low, high = MSG_RANGES[family]
    out = []
    for line in text.splitlines():
        m = DEFINE_RE.match(line)
        if not m:
            continue
        name, value = m.group(1), define_value(m.group(2))
        if not name.startswith("MSG_"):
            continue
        if name.startswith("MSG_BAND_"):
            continue
        if not INT_RE.match(value):
            continue
        v = int(value)
        if low <= v <= high:
            out.append((v, name))
    return out


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--nature-width":
        width = nature_width(sys.stdin.read())
        if width is None:
            sys.stderr.write("number_bands: no Nature bitfield in input\n")
            return 2
        print(width)
        return 0
    if len(sys.argv) != 2:
        sys.stderr.write("usage: number_bands.py <STATI|EV|%s>|--nature-width\n"
                         % "|".join(sorted(MSG_RANGES)))
        return 2
    family = sys.argv[1]
    if family == "STATI":
        members = parse_stati(sys.stdin.read())
    elif family == "EV":
        members = parse_events(sys.stdin.read())
    elif family in MSG_RANGES:
        members = parse_msg(sys.stdin.read(), family)
    else:
        sys.stderr.write("unknown family: %s\n" % family)
        return 2
    for value, name in members:
        print("%d %s" % (value, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
