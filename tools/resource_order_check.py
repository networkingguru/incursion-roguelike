#!/usr/bin/env python3
"""The build-time order check (docs/SAVE-SCHEMA-SPEC.md).

    tools/check_resource_order.sh              check the module against the ledger
    tools/check_resource_order.sh --record     re-record the ledger after a legal append
    tools/check_resource_order.sh --selftest   prove the check still bites, no build

WHAT IT CHECKS. docs/SAVE-SCHEMA-SPEC.md, "The project rule this rests on":
resource lists in lib/ are append-only. This is the check that enforces it
before a commit lands, on the compiled module, rather than at load time on a
save.

The committed ledger records, in order:

  * every entry of the module's 21 resource arrays, array by array; and
  * every script variable, grouped by owner -- a variable's owner is its
    resource, keyed by (owner array, owner position), or the module-level
    list.

The rule (docs/SAVE-SCHEMA-SPEC.md, "The build-time order check"). For every
array and every owner, compare the ledger's list with the module's. It FAILS
when:

  * the module's list is shorter than the ledger's (a removal); or
  * a name the ledger records at position P appears in the module's list at a
    position other than P -- an insertion, a removal or a reorder. A name that
    occurs more than once in the ledger's list is exempt from this test,
    because its position is already ambiguous.

A name the ledger records and the module no longer has is a rename or a
replacement, and PASSES (rule 3: a replaced slot loads as the new resource).
Entries past the ledger's length PASS, so a legal append -- a new array entry
at the end, a new variable at the end of its owner -- is accepted before the
ledger is re-recorded. The check names the array or owner, the ledger's
position, and both names.

This is NOT a prefix test: a rename changes a name in place, so the ledger is
not a prefix of the module and the check still passes. That is why a rename in
place is legal and why --record accepts one.

THE LEDGER IS THE COMPILED MODULE'S OWN REPORT. The game prints it with
`incursion-headless -resorder` (src/SaveV1.cpp, RunResourceOrder). The same
names that driver walks are what v1WriteModuleManifest writes into a v1 save,
so the ledger cannot drift from the save format it protects. `--record` writes
the report of the module in the tree, and does so ONLY when the change is one
the check accepts -- an append or an in-place rename: a change the check fails
must be fixed in lib/, not recorded over. It refuses exactly what the check
fails and accepts exactly what the check passes. `--record` with no ledger
writes the first one.

THIS CHECK WRITES NOTHING WITHOUT --record. That is a hard rule: a check that
rewrites its own baseline is a check that can be made to pass by running it.
"""

import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / "incursion-headless"
LEDGER = ROOT / "tools" / "resource_order.ledger"

# A parsed record set: the module's arrays and variable owners, in order.
#   arrays[key]  -> [entry name, ...]        key = (slot, array index)
#   owners[key]  -> [variable name, ...]     key = (slot, owner array, owner pos)
# array names and owner names are kept for the messages only.
class Report:
    def __init__(self):
        self.arrays = {}
        self.array_names = {}
        self.owners = {}
        self.owner_names = {}


def parse(text):
    """Parse -resorder output (or a ledger, which is the same lines).

    Records are tab-separated:
      A <slot> <array index> <array name>
      E <slot> <array index> <position> <entry name>
      O <slot> <owner array> <owner pos> <owner name>      (-1 -1 = module level)
      V <slot> <owner array> <owner pos> <ordinal> <ident> <type>
    Lines that are blank or start with '#' are comments and are ignored.
    """
    rep = Report()
    for lineno, line in enumerate(text.splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        kind = f[0]
        if kind == "A" and len(f) == 4:
            key = (int(f[1]), int(f[2]))
            rep.arrays.setdefault(key, [])
            rep.array_names[key] = f[3]
        elif kind == "E" and len(f) == 5:
            rep.arrays.setdefault((int(f[1]), int(f[2])), []).append(f[4])
        elif kind == "O" and len(f) == 5:
            key = (int(f[1]), int(f[2]), int(f[3]))
            rep.owners.setdefault(key, [])
            rep.owner_names[key] = f[4]
        elif kind == "V" and len(f) == 7:
            rep.owners.setdefault((int(f[1]), int(f[2]), int(f[3])), []).append(f[5])
        else:
            raise ValueError("line %d: not a -resorder record: %r" % (lineno, line))
    return rep


def describe_array(key, rep):
    slot, idx = key
    name = rep.array_names.get(key, "?")
    return "array %d (%s) in module slot %d" % (idx, name, slot)


def describe_owner(key, rep):
    slot, oa, op = key
    name = rep.owner_names.get(key, "?")
    if oa == -1 and op == -1:
        return "module-level variables of module slot %d" % slot
    return ("variable owner %s (array %d, position %d) in module slot %d"
            % (name, oa, op, slot))


def list_failures(want, have, describe, unit, verb):
    """Every way `have` breaks the ledger's `want`, in position order.

    `want` is the ledger's list, `have` the module's. `describe` renders the
    subject for a message, `unit` names one element ("entry"/"variable") and
    `verb` the forbidden move ("inserted, removed or moved").

    The rule is docs/SAVE-SCHEMA-SPEC.md, "The build-time order check":

      * `have` shorter than `want` is a removal and fails;
      * a name `want` records at P that is absent from position P but present
        somewhere in `have` has moved and fails. A name repeated in `want` is
        exempt, because its own position is already ambiguous;
      * a name `want` records that `have` lacks entirely is a rename or a
        replacement, and passes;
      * positions past the end of `want` pass: that is an append.

    `have[P] == want[P]` always passes, so an append of a name that already
    exists at its own position does not trip the moved test on that name.
    """
    failures = []
    article = "an" if unit[0] in "aeiou" else "a"
    plural = "entries" if unit == "entry" else unit + "s"
    if len(have) < len(want):
        first = len(have)
        failures.append(
            "%s: the ledger records %d %s and the module has only %d -- the "
            "%s at ledger position %d (%r) was removed"
            % (describe, len(want), plural, len(have), unit, first, want[first]))
    have_set = set(have)
    want_counts = {}
    for name in want:
        want_counts[name] = want_counts.get(name, 0) + 1
    for p, name in enumerate(want):
        if want_counts[name] > 1:
            continue  # a repeated ledger name has no single position to hold
        if name not in have_set:
            continue  # a rename or a replacement: rule 3 says it loads
        if p < len(have) and have[p] == name:
            continue  # still at its position, whatever else changed
        at = [i for i, x in enumerate(have) if x == name]
        failures.append(
            "%s: the ledger records %r at position %d, but the module has it "
            "at position %d -- %s %s was %s"
            % (describe, name, p, at[0], article, unit, verb))
    return failures


def order_failures(ledger, module):
    """Every way the module breaks the ledger, in report order.

    The ledger drives the comparison. Anything the module has beyond the
    ledger (a new array, owner or entry) is an append and is not a failure.
    """
    failures = []
    bad_arrays = set()

    for key in sorted(ledger.arrays):
        want = ledger.arrays[key]
        have = module.arrays.get(key, [])
        for line in list_failures(want, have, describe_array(key, ledger),
                                  "entry", "inserted, removed or moved"):
            failures.append(line)
            bad_arrays.add(key)

    for key in sorted(ledger.owners):
        # An owner is keyed by its resource's position, so when the array
        # itself already failed, every owner at or after the break point has
        # moved too. That is one defect, not fifty: the array line names it,
        # and reporting the cascade would bury the root cause.
        if (key[0], key[1]) in bad_arrays:
            continue
        want = ledger.owners[key]
        have = module.owners.get(key, [])
        failures.extend(list_failures(want, have, describe_owner(key, ledger),
                                      "variable", "inserted, removed or swapped"))

    return failures


def module_report(module_root):
    """Run the driver against the module in `module_root` (default ROOT)."""
    env = dict(os.environ)
    if module_root is not None:
        env["INCURSIONPATH"] = str(module_root).rstrip("/") + "/"
    proc = subprocess.run([str(BIN), "-resorder"], cwd=str(ROOT), env=env,
                          stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        raise SystemExit("FAIL: %s -resorder exited %d" % (BIN, proc.returncode))
    return proc.stdout.decode("utf-8", "replace")


def record_text(module_text):
    """The ledger file body: a short header, then the driver's report."""
    header = (
        "# tools/resource_order.ledger -- the build-time order check's baseline.\n"
        "# docs/SAVE-SCHEMA-SPEC.md, 'The build-time order check'. One line per\n"
        "# resource-array entry and per script variable, in order:\n"
        "#   A <slot> <array> <array name>\n"
        "#   E <slot> <array> <position> <entry name>\n"
        "#   O <slot> <owner array> <owner position> <owner name>\n"
        "#   V <slot> <owner array> <owner position> <ordinal> <ident> <type>\n"
        "# (owner array -1, position -1 is the module-level variable list)\n"
        "# Never edit by hand: after a LEGAL append run\n"
        "#   tools/check_resource_order.sh --record\n"
        "# It refuses anything but an append, and writes no file otherwise.\n"
    )
    return header + module_text


def load_ledger(path):
    if not path.exists():
        return None
    return parse(path.read_text(encoding="utf-8"))


def display(path):
    """Path as it reads to a person: relative to ROOT when it sits under it."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def check(module_root, ledger_path):
    if not BIN.exists():
        print("INCONCLUSIVE: %s is not built. Run: BACKEND=posix ./build_macos.sh"
              % BIN.name)
        return 2
    module = parse(module_report(module_root))
    ledger = load_ledger(ledger_path)
    if ledger is None:
        print("FAIL: no ledger at %s. Record the first one with: "
              "tools/check_resource_order.sh --record" % display(ledger_path))
        return 1
    failures = order_failures(ledger, module)
    if failures:
        print("FAIL: the module breaks the order rule recorded in %s:"
              % display(ledger_path))
        for line in failures:
            print("  " + line)
        print("The append-only rule (docs/SAVE-SCHEMA-SPEC.md) forbids this. "
              "Restore the")
        print("table's order in lib/, or -- if and only if this is a legal "
              "append or an")
        print("in-place rename -- run tools/check_resource_order.sh --record "
              "and commit the")
        print("ledger with the change.")
        return 1
    n_entries = sum(len(v) for v in module.arrays.values())
    n_vars = sum(len(v) for v in module.owners.values())
    print("PASS: the module keeps the ledger's order: %d array entries, "
          "%d owners, %d variables."
          % (n_entries, len(module.owners), n_vars))
    return 0


def record(module_root, ledger_path):
    if not BIN.exists():
        print("INCONCLUSIVE: %s is not built. Run: BACKEND=posix ./build_macos.sh"
              % BIN.name)
        return 2
    module_text = module_report(module_root)
    module = parse(module_text)
    ledger = load_ledger(ledger_path)
    if ledger is not None:
        failures = order_failures(ledger, module)
        if failures:
            print("REFUSED: %s records an order the module breaks; the ledger "
                  "is untouched." % display(ledger_path))
            for line in failures:
                print("  " + line)
            print("--record accepts only an append or an in-place rename. Fix "
                  "lib/ so the")
            print("ledger's names hold their positions, or revert the change. "
                  "See")
            print("docs/SAVE-SCHEMA-SPEC.md.")
            return 1
    tmp = ledger_path.with_suffix(ledger_path.suffix + ".tmp")
    tmp.write_text(record_text(module_text), encoding="utf-8")
    os.replace(tmp, ledger_path)
    print("RECORDED: %s (%d array entries, %d owners, %d variables)"
          % (display(ledger_path),
             sum(len(v) for v in module.arrays.values()),
             len(module.owners),
             sum(len(v) for v in module.owners.values())))
    return 0


# ---------------------------------------------------------------------------
# --selftest: prove the order rule bites, with no build and no driver.
# ---------------------------------------------------------------------------
def selftest():
    ok = True

    def report(arrays, owners, array_names=None, owner_names=None):
        r = Report()
        r.arrays = arrays
        r.owner_names = owner_names or {}
        r.owners = owners
        r.array_names = array_names or {}
        return r

    base = report(
        arrays={(0, 0): ["a", "b", "c"], (0, 1): ["x"]},
        array_names={(0, 0): "Monster", (0, 1): "Item"},
        owners={(0, 0, 0): ["v1", "v2"], (0, -1, -1): ["g"]},
        owner_names={(0, 0, 0): "Orc;race", (0, -1, -1): "(module)"})

    def variant(**kw):
        d = dict(arrays={(0, 0): ["a", "b", "c"], (0, 1): ["x"]},
                 array_names={(0, 0): "Monster", (0, 1): "Item"},
                 owners={(0, 0, 0): ["v1", "v2"], (0, -1, -1): ["g"]},
                 owner_names={(0, 0, 0): "Orc;race", (0, -1, -1): "(module)"})
        d.update(kw)
        return report(d["arrays"], d["owners"], d["array_names"], d["owner_names"])

    def expect(name, ledger, module, want_fail):
        failures = order_failures(ledger, module)
        got_fail = bool(failures)
        if got_fail == want_fail:
            print("selftest ok    %-46s -> %s"
                  % (name, "red" if got_fail else "green"))
        else:
            print("selftest FAIL  %-46s -> %s (wanted %s)\n    %s"
                  % (name, "red" if got_fail else "green",
                     "red" if want_fail else "green", failures))
            return False
        return True

    # Green: identical, legal appends, and renames in place at every level.
    ok &= expect("identical", base, base, False)
    ok &= expect("append an array entry at the end",
                 base, report({(0, 0): ["a", "b", "c", "d"], (0, 1): ["x"]},
                              {(0, 0, 0): ["v1", "v2"], (0, -1, -1): ["g"]},
                              {(0, 0): "Monster", (0, 1): "Item"},
                              {(0, 0, 0): "Orc;race", (0, -1, -1): "(module)"}),
                 False)
    ok &= expect("append a variable at the end of its owner",
                 base, report({(0, 0): ["a", "b", "c"], (0, 1): ["x"]},
                              {(0, 0, 0): ["v1", "v2", "v3"], (0, -1, -1): ["g"]},
                              {(0, 0): "Monster", (0, 1): "Item"},
                              {(0, 0, 0): "Orc;race", (0, -1, -1): "(module)"}),
                 False)
    ok &= expect("a whole new array",
                 base, report({(0, 0): ["a", "b", "c"], (0, 1): ["x"], (0, 2): ["q"]},
                              {(0, 0, 0): ["v1", "v2"], (0, -1, -1): ["g"]},
                              {(0, 0): "Monster", (0, 1): "Item", (0, 2): "Feature"},
                              {(0, 0, 0): "Orc;race", (0, -1, -1): "(module)"}),
                 False)
    ok &= expect("rename an array entry in place",
                 base, variant(arrays={(0, 0): ["a", "RENAMED", "c"], (0, 1): ["x"]}),
                 False)
    ok &= expect("rename a variable in place",
                 base, variant(owners={(0, 0, 0): ["v1", "RENAMED"], (0, -1, -1): ["g"]}),
                 False)
    ok &= expect("a replacement with a different resource entirely",
                 base, variant(arrays={(0, 0): ["a", "WHOLLY DIFFERENT", "c"],
                                       (0, 1): ["x"]}),
                 False)
    # A ledger name repeated is exempt: its position is already ambiguous.
    dup = report(arrays={(0, 0): ["crimson", "black", "crimson"]},
                 array_names={(0, 0): "Flavour"}, owners={},
                 owner_names={})
    ok &= expect("a repeated ledger name is exempt from the moved test",
                 dup, report(arrays={(0, 0): ["crimson", "black", "crimson"]},
                             array_names={(0, 0): "Flavour"}, owners={},
                             owner_names={}),
                 False)
    ok &= expect("a duplicate name appended at the end",
                 dup, report(arrays={(0, 0): ["crimson", "black", "crimson",
                                              "crimson"]},
                             array_names={(0, 0): "Flavour"}, owners={},
                             owner_names={}),
                 False)

    # Red: every forbidden move.
    ok &= expect("insert a variable before an existing one",
                 base, variant(owners={(0, 0, 0): ["v0", "v1", "v2"], (0, -1, -1): ["g"]}),
                 True)
    ok &= expect("remove a variable",
                 base, variant(owners={(0, 0, 0): ["v1"], (0, -1, -1): ["g"]}),
                 True)
    ok &= expect("swap two variables in one owner",
                 base, variant(owners={(0, 0, 0): ["v2", "v1"], (0, -1, -1): ["g"]}),
                 True)
    ok &= expect("insert an entry mid-array",
                 base, variant(arrays={(0, 0): ["a", "z", "b", "c"], (0, 1): ["x"]}),
                 True)
    ok &= expect("remove an entry",
                 base, variant(arrays={(0, 0): ["a", "c"], (0, 1): ["x"]}),
                 True)
    ok &= expect("swap two entries in one array",
                 base, variant(arrays={(0, 0): ["a", "c", "b"], (0, 1): ["x"]}),
                 True)
    ok &= expect("ledger owner missing from the module",
                 base, variant(owners={(0, -1, -1): ["g"]}),
                 True)
    ok &= expect("ledger array missing from the module",
                 base, variant(arrays={(0, 1): ["x"]}),
                 True)
    # Removal at the end: no name moved, so only the length catches it.
    ok &= expect("remove the last entry, no name moves",
                 base, variant(arrays={(0, 0): ["a", "b"], (0, 1): ["x"]}),
                 True)

    # The messages must name the moved name, both positions and the unit.
    failures = order_failures(base, variant(arrays={(0, 0): ["a", "c", "b"],
                                                      (0, 1): ["x"]}))
    needle = "the ledger records 'b' at position 1, but the module has it at position 2"
    if not any(needle in f for f in failures):
        print("selftest FAIL  the array message does not name the moved entry "
              "and both positions: %s" % failures)
        ok = False
    failures = order_failures(base, variant(owners={(0, 0, 0): ["v2", "v1"],
                                                      (0, -1, -1): ["g"]}))
    needle = "the ledger records 'v1' at position 0, but the module has it at position 1"
    if not any(needle in f for f in failures):
        print("selftest FAIL  the owner message does not name the moved "
              "variable and both positions: %s" % failures)
        ok = False

    # A short module names the removed element and the recorded name.
    failures = order_failures(base, variant(arrays={(0, 0): ["a", "b"],
                                                    (0, 1): ["x"]}))
    needle = "the ledger records 3 entries and the module has only 2"
    if not any(needle in f for f in failures):
        print("selftest FAIL  the removal message does not name the lengths: "
              "%s" % failures)
        ok = False

    # A comment-only or blank ledger is empty, not a crash.
    empty = parse("# comment\n\n")
    if empty.arrays or empty.owners:
        print("selftest FAIL  a comment-only ledger did not parse to empty")
        ok = False

    print()
    print("selftest: %s" % ("pass" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    module_root = None
    ledger_path = LEDGER
    mode = "check"
    rest = list(argv[1:])
    while rest:
        arg = rest.pop(0)
        if arg == "--record":
            mode = "record"
        elif arg == "--selftest":
            mode = "selftest"
        elif arg == "--module-root" and rest:
            module_root = rest.pop(0)
        elif arg == "--ledger" and rest:
            ledger_path = pathlib.Path(rest.pop(0))
        else:
            sys.stderr.write("usage: %s [--record] [--selftest] "
                             "[--module-root DIR] [--ledger FILE]\n" % argv[0])
            return 2
    if mode == "selftest":
        return selftest()
    if mode == "record":
        return record(module_root, ledger_path)
    return check(module_root, ledger_path)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
