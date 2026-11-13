#!/usr/bin/env python3
"""Print what an Options.Dat holds, by name (inc-cjos0, 9f-pre P5b).

  tools/pressure/options_values.py <Options.Dat> <out>
  tools/pressure/options_values.py --selftest

Options.Dat is a headerless byte array: byte N is option N (Player::LoadOptions, src/Player.cpp). Each output line is
`<OPT_NAME> <value>` for one byte, a signed byte; an option whose value family an `at-of` mark names (OPT_DIFFICULTY
holds a DIFF_ value) adds the value's name, `OPT_DIFFICULTY 4(DIFF_NIGHTMARE)`, or `(?)` for a value that has no name.
A byte whose index is no option (a hole in the numbering) is `?<index> <value>`. Names come from
tools/check_define_dups.py load_families(): the family opt for the index, the at-of family for the value. No hand table.
So a case can compare a settings file across a merge: same file, two builds, diff the two outputs.
Exit: 0 written; 2 could not measure (file missing or empty, longer than OPT_LAST bytes, which the game refuses
to read, or the marks unreadable). A shorter file is read: the game defaults every later option, and so does this.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import check_define_dups as cdd  # noqa: E402


def lines(data):
    fams, _problems = cdd.load_families()
    opt = fams["opt"]
    first = {}   # value -> first name in file order
    for name, value, _f, _l in opt["members"]:
        first.setdefault(int(value), name)
    top = first_value(opt, "OPT_LAST")
    if len(data) == 0 or len(data) > top:
        raise ValueError("file is %d bytes; this build reads 1..%d" % (len(data), top))
    at = {}   # option index -> value family
    for f, d in fams.items():
        for key in d["at_of"]:
            arr, idx = key[:-1].split("[")
            if arr == "Player.Options":
                at[idx] = f
    out = []
    for i, b in enumerate(data):
        v = b - 256 if b > 127 else b
        name = first.get(i)
        text = "%s %d" % (name if name else "?%d" % i, v)
        if name in at:
            nm = {int(x[1]): x[0] for x in reversed(fams[at[name]]["members"])}.get(v)
            text += "(%s)" % (nm if nm else "?")
        out.append(text)
    return out


def first_value(opt, name):
    for n, v, _f, _l in opt["members"]:
        if n == name:
            return int(v)
    raise ValueError("family opt has no %s" % name)


def selftest():
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "o.dat")
        o = os.path.join(tmp, "o.txt")
        data = bytearray(118)
        data[117] = 4      # OPT_DIFFICULTY = DIFF_NIGHTMARE
        data[116] = 1      # OPT_TRANSGRESS_HINTS: no value family, a bare number
        data[110] = 255    # OPT_FAVOURED_CLASS: a signed byte
        with open(p, "wb") as f:
            f.write(bytes(data))
        assert main([p, o]) == 0
        got = open(o).read().split("\n")
        assert "OPT_DIFFICULTY 4(DIFF_NIGHTMARE)" in got, got[117:118]
        assert "OPT_TRANSGRESS_HINTS 1" in got and "OPT_FAVOURED_CLASS -1" in got, got[110:117]
        assert len(got) - 1 == 118, len(got)
        data[117] = 9      # a value with no name
        open(p, "wb").write(bytes(data))
        assert main([p, o]) == 0 and "OPT_DIFFICULTY 9(?)" in open(o).read()
        open(p, "wb").write(bytes(901))   # longer than OPT_LAST: the game refuses it, so do we
        assert main([p, o]) == 2
        open(p, "wb").write(b"")
        assert main([p, o]) == 2
    print("options_values: selftest PASS")
    return 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 2:
        print("usage: options_values.py <Options.Dat> <out>", file=sys.stderr)
        return 2
    try:
        with open(argv[0], "rb") as f:
            data = f.read()
        text = "\n".join(lines(data)) + "\n"
    except (OSError, ValueError, cdd.Unmeasurable) as e:
        print("options_values: UNMEASURED: %s" % e, file=sys.stderr)
        return 2
    with open(argv[1], "w") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
