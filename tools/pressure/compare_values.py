#!/usr/bin/env python3
"""Compare two field-value files from tools/pressure/field_values.sh.

  tools/pressure/compare_values.py <before> <after>

A line is "<scope path> <field> <kind> <value>". The key is (scope path, field, n), where n numbers repeats
of one (scope, field) in file order. Prints each changed value ("changed"), each field present before and
missing after ("missing"), and each field only after ("added"; not a failure).
Exit: 0 equal (added fields allowed), 1 a value changed or a field is missing, 2 could not measure.
With INCURSION_PRESSURE_GROWS=1 (a case that adds, renames or retires resources: route.sh sets it for a `grows-module` or `renames` file) the module-shape lines of the data segment may differ
(printed `shape`), except a pool length or variable count that shrank.
Narrow bookkeeping rules, each printed under its own word and none a failure (inc-cjos0 phase 9, A1-A4, A7):
  rowlen    a uint field named <x>Row (hpRollsRow, manaRollsRow, SacValsRow) that GREW: a limit grew, the row is longer.
            Every cell is still compared by its own (row, column) key. A row that shrank, or any other kind, fails.
  migrated  Game.Migrations after holds every name before holds (a migration was applied). A name gone fails.
  newslot   an array slot (<x>[<n>]) of 0 that had no name, `0(?)`, and now has one, `0(@NAME)`. Any other value fails.
  renamed   a field that INCURSION_PRESSURE_RENAME_FILE (a retired_field_names.txt) renames, `rename <scope> <old> <new>`,
            is compared old-name before to new-name after: the same kind and value, or it fails.

  ownerren  (A8) a Game.ScriptVariable `<owner>.<name>` missing after whose owner INCURSION_PRESSURE_RENAMES renames
            (a renamed or retired resource): compared with `<new owner>.<name>`, the same kind and value, or it fails.

  retired   (A7) a field missing after whose (scope, name) is a `<scope> <name>` row of that same file: branch B
            retired it, so it is expected to be gone. A missing field with no such row still fails.

  regrouped (9c3b) a long array's value file prints a hash per 32 entries, `Name[a..b]`, and a `Name{bytes}` helper row
            (es=<entry size>:<hex of every entry>; read, never compared). A group key missing after (the array grew,
            so the last group's bounds moved) passes when the after side's entries a..b hash to the same value. An entry
            changed, or past the end of the after array, fails.

  gonezero  (INCURSION_PRESSURE_REMOVED_ZERO=1, AC9 values1) a field or script variable missing after, with no other rule
            covering it, whose master value is 0 (an int or uint of 0, or a null rid): the merged tree no longer has it and
            it held nothing. A missing field that held a nonzero value still fails.

  tools/pressure/compare_values.py --selftest
runs every rule on made-up value files, and a planted real change of each kind must still exit 1. Exit 0 pass, 1 fail.

  tools/pressure/compare_values.py --planted <fixture-values> <content-values>
prints what planting changed, for a human: `added` lines first, then `changed` ones, up to 8 lines, leaving out the
Game-scope counters (a call count differs between any two loads). Exit 0.
"""
import os
import re
import sys


def load(path):
    rows = {}
    seen = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split(" ", 3)
            if len(parts) != 4:
                raise ValueError("malformed line: %r" % line[:80])
            scope, field, kind, value = parts
            n = seen.get((scope, field), 0)
            seen[(scope, field)] = n + 1
            rows[(scope, field, n)] = (kind, value)
    return rows


def fnv_hash(raw):
    """The v1FvHash of src/SaveV1.cpp: FNV-1a 64 over the bytes."""
    h = 1469598103934665603
    for b in raw:
        h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h


def split_bytes(rows):
    """Take the `Name{bytes}` helper rows out of `rows`: {(scope, Name, n): (es, raw)}. They are not fields the game holds."""
    out = {}
    for k in [k for k in rows if k[1].endswith("{bytes}")]:
        kind, value = rows.pop(k)
        m = re.fullmatch(r"es=(\d+):([0-9a-f]*)", value)
        if kind == "bytes" and m and len(m.group(2)) % 2 == 0:
            out[(k[0], k[1][:-len("{bytes}")], k[2])] = (int(m.group(1)), bytes.fromhex(m.group(2)))
    return out


def regrouped(k, kind, value, abytes):
    """9c3b: a before group `Name[a..b]` whose key is gone after. Returns (ok, why) comparing entries a..b of the
    after array; None when the key is not such a group or the after side has no bytes for the array."""
    m = re.fullmatch(r"(\w+)\[(\d+)\.\.(\d+)\]", k[1])
    v = re.search(r"len=(\d+) h=([0-9a-f]{16})$", value)
    if kind != "arr" or not m or not v or (k[0], m.group(1), 0) not in abytes:
        return None
    es, raw = abytes[(k[0], m.group(1), 0)]
    lo, hi = int(m.group(2)), int(m.group(3))
    if fnv_hash(raw[lo * es:(hi + 1) * es]) != v.group(2):   # an entry past the end makes the slice short, so the hash differs
        return False, "an entry of %d..%d holds another value or is gone (the after array has %d entries)" % (lo, hi, len(raw) // es)
    return True, "entries %d..%d keep their values" % (lo, hi)


def shape_line(scope, field):
    """A line that describes the SHAPE of the module the writer ran in (the pool lengths and names of the data
    segment, its variable list and size), not a value the character holds. A case that adds resources to the
    module (a `grows-module` file in its directory; route.sh sets INCURSION_PRESSURE_GROWS=1) changes these lines
    for every save, by construction. Never set for any other case."""
    if scope.endswith("/Game") and field.startswith("MDataSegSize["):
        return True
    return "/Game.MDataSeg.Segment#" in scope and field.split("[")[0] in ("PoolLengths", "PoolNames", "Rows", "Variables", "VariableCount")


def renames():
    """INCURSION_PRESSURE_RENAMES="old>new|old2>new2": the resource renames the case makes on purpose (a `renames`
    file in its directory). A resource-id value that names `old` before and `new` after is the same resource: the
    value files print rIDs by name, so a legal rename would otherwise read as a change."""
    out = {}
    for pair in os.environ.get("INCURSION_PRESSURE_RENAMES", "").split("|"):
        if ">" in pair:
            o, n = pair.split(">", 1)
            out[o] = n
    return out


def renamed(kind, before, after, table):
    if kind != "rid" or "=" not in before or "=" not in after:
        return False
    bm, bv = before.split("=", 1)
    am, av = after.split("=", 1)
    return bm == am and table.get(bv) == av


def owner_renamed(scope, field, table):
    """A8: the key a ScriptVariable has after its owner was renamed, or None. The game keeps the value (the owner is an
    rID through the manifest); the value file prints the owner by NAME, so the key moves with the rename."""
    if not scope.endswith("/Game.ScriptVariable") or "." not in field:
        return None
    owner, _, var = field.rpartition(".")
    new = table.get(owner)
    return None if new is None else new + "." + var


def split_mem(value):
    """"hpRollsRow=11" -> ("hpRollsRow", "11"): the member the FIELD_ line names, and what it holds."""
    i = value.find("=")
    return (value[:i], value[i + 1:]) if i >= 0 else (value, "")


def row_grew(field, bkind, before, akind, after):
    """A1: the bookkeeping field of a row array whose limit grew."""
    if not field.endswith("Row") or len(field) <= 3 or bkind != "uint" or akind != "uint":
        return False
    bm, bv = split_mem(before)
    am, av = split_mem(after)
    return bm == am and bv.isdigit() and av.isdigit() and int(av) > int(bv)


def names_of(value):
    return [n for n in split_mem(value)[1].strip('"').split(",") if n]


def migrated(scope, field, bkind, before, akind, after):
    """A2: Game.Migrations gained names and lost none."""
    if field != "Migrations" or not scope.endswith("/Game") or bkind != "str" or akind != "str":
        return False
    b, a = names_of(before), names_of(after)
    return set(b) <= set(a) and len(a) > len(b)


def new_slot(field, bkind, before, akind, after):
    """A3: an empty array slot that had no name and now has one."""
    if "[" not in field or bkind != "uint" or akind != "uint":
        return False
    bm, bv = split_mem(before)
    am, av = split_mem(after)
    return bm == am and bv == "0(?)" and re.fullmatch(r"0\(@[A-Za-z0-9_]+\)", av) is not None


def rename_table():
    """A4: {(scope, old): new} from the `rename <scope> <old> <new>` rows of INCURSION_PRESSURE_RENAME_FILE."""
    out = {}
    path = os.environ.get("INCURSION_PRESSURE_RENAME_FILE", "")
    if not path:
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            w = line.split()
            if len(w) == 4 and w[0] == "rename":
                out[(w[1], w[2])] = w[3]
    return out


def retired_table():
    """A7: {(scope, name)} from the `<scope> <name>` rows (two words, not `rename`) of INCURSION_PRESSURE_RENAME_FILE."""
    out = set()
    path = os.environ.get("INCURSION_PRESSURE_RENAME_FILE", "")
    if not path:
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            w = line.split()
            if len(w) == 2 and not w[0].startswith("#") and w[0] != "rename":
                out.add((w[0], w[1]))
    return out


def bare_scope(scope):
    """"h129:t7/Character.Ac8Left" -> "Character.Ac8Left": the scope without the record prefix."""
    return scope.split("/", 1)[1] if "/" in scope else scope


def zero_value(kind, value):
    """gonezero: an int or uint of 0 (`0[dt=DT_INT32]`, `Anger=0`, `x=0(?)`), or a null rid (`{null}[dt=DT_RID]`, `eID={null}`)."""
    v = re.sub(r"\[dt=[A-Za-z0-9_]+\]$", "", value)
    v = v.split("=", 1)[1] if "=" in v else v
    if kind in ("int", "uint"):
        return re.fullmatch(r"0(\(.*\))?", v) is not None
    return kind == "rid" and v == "{null}"


def count_of(value):
    try:
        return int(value.rsplit("=", 1)[1])
    except (IndexError, ValueError):
        return None


def planted(argv):
    try:
        before, after = load(argv[2]), load(argv[3])
    except (OSError, ValueError) as e:
        print("compare_values: %s" % e, file=sys.stderr)
        return 2
    added = ["planted: added   %s %s %s" % (k[0], k[1], " ".join(v)) for k, v in sorted(after.items()) if k not in before]
    changed = ["planted: changed %s %s: %s %s -> %s %s" % (k[0], k[1], *before[k], *v) for k, v in sorted(after.items())
               if k in before and before[k] != v]
    for line in [x for x in added + changed if "/Game " not in x][:8]:
        print(line)
    return 0


def selftest():
    """Each relaxation accepts its own narrow case, and a planted REAL change of the same field kind still fails."""
    import subprocess
    import tempfile
    here = os.path.abspath(__file__)
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        rf = os.path.join(d, "retired.txt")
        with open(rf, "w") as f:
            f.write("# t\nrename Character RageCount RageCounter\nrename Character.Ac8Left value renamedValue\nCharacter Ac8Retire\n")

        def run(before, after, name, env=None):
            bp, ap = os.path.join(d, name + ".b"), os.path.join(d, name + ".a")
            open(bp, "w").write("\n".join(before) + "\n")
            open(ap, "w").write("\n".join(after) + "\n")
            e = dict(os.environ, INCURSION_PRESSURE_RENAME_FILE=rf)
            e.update(env or {})
            r = subprocess.run([sys.executable, here, bp, ap], capture_output=True, text=True, env=e)
            return r.returncode, r.stdout

        C = "h1:t7/Character"
        G = "h1:t1/Game"
        REN = {"INCURSION_PRESSURE_RENAMES": "barbazu>barbazu;grw|flask>flask;retired"}
        GROWS = {"INCURSION_PRESSURE_GROWS": "1"}
        RZ = {"INCURSION_PRESSURE_REMOVED_ZERO": "1"}
        H4, H5 = fnv_hash(bytes([1, 2, 3, 4])), fnv_hash(bytes([1, 2, 3, 4, 5]))
        Z = "00" * 896   # entries 0..895 are empty
        RAW5, RAW5C = Z + "0102030405", Z + "0102090405"
        cases = [
            # (name, before, after, expected rc, expected word)
            ("A1 ok", [C + " hpRollsRow uint hpRollsRow=11", C + " hpRolls[0][10] int hpRolls=5"],
             [C + " hpRollsRow uint hpRollsRow=12", C + " hpRolls[0][10] int hpRolls=5"], 0, "rowlen"),
            ("A1 cell changed", [C + " hpRollsRow uint hpRollsRow=11", C + " hpRolls[0][10] int hpRolls=5"],
             [C + " hpRollsRow uint hpRollsRow=12", C + " hpRolls[0][10] int hpRolls=6"], 1, "changed"),
            ("A1 row shrank", [C + " hpRollsRow uint hpRollsRow=12"], [C + " hpRollsRow uint hpRollsRow=11"], 1, "changed"),
            ("A1 other field", [C + " hpRolls uint hpRolls=12"], [C + " hpRolls uint hpRolls=13"], 1, "changed"),
            ("A2 ok", ["h1:t1/Game Migrations str -=\"A,B\""], ["h1:t1/Game Migrations str -=\"A,B,C\""], 0, "migrated"),
            ("A2 name gone", ["h1:t1/Game Migrations str -=\"A,B\""], ["h1:t1/Game Migrations str -=\"A,C\""], 1, "changed"),
            ("A2 name replaced and added", ["h1:t1/Game Migrations str -=\"A,B\""], ["h1:t1/Game Migrations str -=\"A,C,D\""], 1, "changed"),
            ("A2 other str", [C + " Name str Name=\"A\""], [C + " Name str Name=\"A,B\""], 1, "changed"),
            ("A3 ok", [C + " KAttr[41] uint KAttr=0(?)"], [C + " KAttr[41] uint KAttr=0(@A_END)"], 0, "newslot"),
            ("A3 value set", [C + " KAttr[41] uint KAttr=0(?)"], [C + " KAttr[41] uint KAttr=5(@A_END)"], 1, "changed"),
            ("A3 old slot value", [C + " KAttr[3] uint KAttr=7(@A_X)"], [C + " KAttr[3] uint KAttr=8(@A_X)"], 1, "changed"),
            ("A3 name lost", [C + " KAttr[3] uint KAttr=0(@A_X)"], [C + " KAttr[3] uint KAttr=0(?)"], 1, "changed"),
            ("A4 ok", [C + " RageCount uint RageCount=0"], [C + " RageCounter uint RageCount=0"], 0, "renamed"),
            ("A4 value changed", [C + " RageCount uint RageCount=0"], [C + " RageCounter uint RageCount=9"], 1, "changed"),
            ("A4 embed ok", [C + ".Ac8Left value uint ac8LeftValue=17"], [C + ".Ac8Left renamedValue uint ac8LeftValue=17"], 0, "renamed"),
            ("A4 embed changed", [C + ".Ac8Left value uint ac8LeftValue=17"], [C + ".Ac8Left renamedValue uint ac8LeftValue=18"], 1, "changed"),
            ("A7 retired", [C + " Ac8Retire uint ac8Retire=17"], [C + " Other uint Other=1"], 0, "retired"),
            ("A7 not retired", [C + " Ac8Keep uint ac8Keep=17"], [C + " Other uint Other=1"], 1, "missing"),
            ("A7 other scope", [C + "X Ac8Retire uint ac8Retire=17"], [C + " Other uint Other=1"], 1, "missing"),
            ("A8 ok", [G + ".ScriptVariable barbazu.claw_hits int 5"], [G + ".ScriptVariable barbazu;grw.claw_hits int 5"], 0, "ownerren", REN),
            ("A8 value changed", [G + ".ScriptVariable barbazu.claw_hits int 5"], [G + ".ScriptVariable barbazu;grw.claw_hits int 6"], 1, "changed", REN),
            ("A8 owner not renamed", [G + ".ScriptVariable Dance_of_Ruin.vrock_count int 0"], [G + ".ScriptVariable Dance_of_Ruin.vrock_total int 0"], 1, "missing", REN),
            ("A8 not a variable", [C + " barbazu.claw_hits int 5"], [C + " barbazu;grw.claw_hits int 5"], 1, "missing", REN),
            ("A8 tombstone ok", [G + ".ScriptVariable flask.n int 1"], [G + ".ScriptVariable flask;retired.n int 1"], 0, "ownerren", REN),
            ("A9 shape grows ok", [G + ".MDataSeg.Segment#0 PoolNames blob h=1"], [G + ".MDataSeg.Segment#0 PoolNames blob h=2"], 0, "shape", GROWS),
            ("A9 shape, lib unchanged", [G + ".MDataSeg.Segment#0 PoolNames blob h=1"], [G + ".MDataSeg.Segment#0 PoolNames blob h=2"], 1, "changed"),
            ("A9 pool shrank", [G + ".MDataSeg.Segment#0 PoolLengths blob PoolLengths=5"], [G + ".MDataSeg.Segment#0 PoolLengths blob PoolLengths=4"], 1, "changed", GROWS),
            ("C3b grew", [C + " Options[896..899] arr Options=len=4 h=" + H4], [C + " Options[896..900] arr Options=len=5 h=" + H5, C + " Options{bytes} bytes es=1:" + RAW5], 0, "regrouped"),
            ("C3b split", [C + " Options[896..899] arr Options=len=4 h=" + H4], [C + " Options[896..898] arr Options=len=3 h=x", C + " Options[899..900] arr Options=len=2 h=y", C + " Options{bytes} bytes es=1:" + RAW5], 0, "regrouped"),
            ("C3b value changed", [C + " Options[896..899] arr Options=len=4 h=" + H4], [C + " Options[896..900] arr Options=len=5 h=x", C + " Options{bytes} bytes es=1:" + RAW5C], 1, "changed"),
            ("C3b entry gone", [C + " Options[896..899] arr Options=len=4 h=" + H4], [C + " Options[896..897] arr Options=len=2 h=x", C + " Options{bytes} bytes es=1:" + Z + "0102"], 1, "changed"),
            ("C3b no bytes", [C + " Options[896..899] arr Options=len=4 h=" + H4], [C + " Options[896..900] arr Options=len=5 h=" + H5], 1, "missing"),
            ("gonezero int", [G + ".ScriptVariable Xel.dailySac int 0[dt=DT_INT16]"], [G + " Day int Day=0"], 0, "gonezero", RZ),
            ("gonezero uint slot", [C + " Anger[3] uint Anger=0"], [C + " Other uint Other=1"], 0, "gonezero", RZ),
            ("gonezero null rid", [C + " eID rid eID={null}"], [C + " Other uint Other=1"], 0, "gonezero", RZ),
            ("gonezero nonzero fails", [G + ".ScriptVariable Xel.dailySac int 3[dt=DT_INT16]"], [G + " Day int Day=0"], 1, "missing", RZ),
            ("gonezero nonzero uint fails", [C + " Anger[3] uint Anger=7"], [C + " Other uint Other=1"], 1, "missing", RZ),
            ("gonezero named rid fails", [C + " eID rid eID=Essiah"], [C + " Other uint Other=1"], 1, "missing", RZ),
            ("gonezero kept value changed fails", [C + " Kept uint Kept=0"], [C + " Kept uint Kept=1"], 1, "changed", RZ),
            ("gonezero off by default", [C + " Anger[3] uint Anger=0"], [C + " Other uint Other=1"], 1, "missing"),
            ("A4 not in table", [C + " Other uint Other=1"], [C + " Other2 uint Other=1"], 1, "missing"),
        ]
        for name, b, a, rc, word, *env in cases:
            got, out = run(b, a, name.replace(" ", "_"), env[0] if env else None)
            ok = got == rc and any(l.startswith(word) for l in out.splitlines())
            print("%s %s (rc %d, want %d)" % ("ok  " if ok else "FAIL", name, got, rc))
            bad += 0 if ok else 1
    print("compare_values selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) == 4 and argv[1] == "--planted":
        return planted(argv)
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        before, after = load(argv[1]), load(argv[2])
    except (OSError, ValueError) as e:
        print("compare_values: %s" % e, file=sys.stderr)
        return 2
    bbytes, abytes = split_bytes(before), split_bytes(after)
    if not before or not after:
        print("compare_values: an input has no rows", file=sys.stderr)
        return 2
    bad = 0
    grows = os.environ.get("INCURSION_PRESSURE_GROWS") == "1"
    ren = renames()
    removed_zero = os.environ.get("INCURSION_PRESSURE_REMOVED_ZERO") == "1"
    try:
        fren = rename_table()
        retired = retired_table()
    except OSError as e:
        print("compare_values: %s" % e, file=sys.stderr)
        return 2
    taken = set()   # keys of `after` that a rename consumed
    for k in sorted(before):
        tag = "%s %s" % (k[0], k[1])
        if k not in after:
            rg = regrouped(k, before[k][0], before[k][1], abytes)
            if rg is not None:
                print("%s %s: %s" % ("regrouped" if rg[0] else "changed  ", tag, rg[1]))
                bad += 0 if rg[0] else 1
                continue
            nf = fren.get((bare_scope(k[0]), k[1]))
            if nf is not None and (k[0], nf, k[2]) in after:
                k2 = (k[0], nf, k[2])
                taken.add(k2)
                if before[k][0] == after[k2][0] and split_mem(before[k][1])[1] == split_mem(after[k2][1])[1]:
                    print("renamed  %s -> %s: %s" % (tag, nf, before[k][1]))
                else:
                    print("changed  %s -> %s: %s %s -> %s %s" % (tag, nf, *before[k], *after[k2]))
                    bad += 1
                continue
            f2 = owner_renamed(k[0], k[1], ren)
            if f2 is not None and (k[0], f2, k[2]) in after:
                k2 = (k[0], f2, k[2])
                taken.add(k2)
                if before[k] == after[k2]:
                    print("ownerren %s -> %s: %s" % (tag, f2, before[k][1]))
                else:
                    print("changed  %s -> %s: %s %s -> %s %s" % (tag, f2, *before[k], *after[k2]))
                    bad += 1
                continue
            if (bare_scope(k[0]), k[1]) in retired:
                print("retired  %s (was %s %s)" % (tag, *before[k]))
                continue
            if grows and shape_line(k[0], k[1]):
                print("shape    %s gone" % tag)
                continue
            if removed_zero and zero_value(*before[k]):
                print("gonezero %s (was %s %s)" % (tag, *before[k]))
                continue
            print("missing  %s (was %s %s)" % (tag, *before[k]))
            bad += 1
        elif after[k] != before[k]:
            if before[k][0] == after[k][0] and renamed(before[k][0], before[k][1], after[k][1], ren):
                print("renamed  %s: %s -> %s" % (tag, before[k][1], after[k][1]))
                continue
            if row_grew(k[1], before[k][0], before[k][1], after[k][0], after[k][1]):
                print("rowlen   %s: %s -> %s" % (tag, before[k][1], after[k][1]))
                continue
            if migrated(k[0], k[1], before[k][0], before[k][1], after[k][0], after[k][1]):
                print("migrated %s: %s -> %s" % (tag, before[k][1], after[k][1]))
                continue
            if new_slot(k[1], before[k][0], before[k][1], after[k][0], after[k][1]):
                print("newslot  %s: %s -> %s" % (tag, before[k][1], after[k][1]))
                continue
            if grows and shape_line(k[0], k[1]):
                # a module that grew keeps every pool at least as long and every variable it had; any other
                # difference of these lines is the new shape. A pool or count that SHRANK is still a failure.
                if k[1].split("[")[0] in ("PoolLengths", "VariableCount"):
                    b, a = count_of(before[k][1]), count_of(after[k][1])
                    if b is not None and a is not None and a < b:
                        print("changed  %s: %s %s -> %s %s" % (tag, *before[k], *after[k]))
                        bad += 1
                        continue
                print("shape    %s: %s -> %s" % (tag, before[k][1][-40:], after[k][1][-40:]))
                continue
            print("changed  %s: %s %s -> %s %s" % (tag, *before[k], *after[k]))
            bad += 1
    for k in sorted(after):
        if k not in before and k not in taken:
            print("added    %s %s %s" % (k[0], k[1], " ".join(after[k])))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
