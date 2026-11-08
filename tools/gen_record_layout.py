#!/usr/bin/env python3
# gate: cheap
# gate-fast: --compare compiles two small probes and reads four source files; a few seconds
# fact: source tree -- the working tree (or --rev) this script runs on; the layout comes from the compiler reading it, nothing else
# fact: compiler and flags -- the ones build_macos.sh passes after "--"; with no flags the posix developer flags of tools/save_pad_rows.py, so the answer is that of the headless build
# fact: archived class list -- the "Cls" rows of SchemaPins[] in src/SaveV1.cpp, read from the tree
# fact: hand tables read by --compare -- src/SaveV1.cpp and the size static_asserts of inc/Creature.h, inc/Map.h, inc/Res.h at the tree or --rev named; frozen in git at that rev
# fact: build host -- unmeasured unless the compiler defines __clang__ or INCURSION_LAYOUT_UNMEASURED=1 forces it
"""Write the record sizes and pad tables of the archived classes from the
compiler (bead inc-cjos0, phase 8a).

WHY. The save coverage check (src/SaveV1.cpp, v1CovEnd) proves every byte of an
archived object is written by a FIELD_ line or is compiler padding. It used to
read hand-written numbers: a sizeof pin per class and a {offset, length} pad
row per gap. Two branches that each add a member write two different numbers,
and git either conflicts on a number nobody can compute by hand or merges two
wrong ones. The compiler decides the right numbers on every build, so the
build asks it.

WHAT IT WRITES (default build/gen/RecordLayout.h), per class in SchemaPins[]:
    #define LAYOUT_<Cls>_SIZE n
    #define LAYOUT_<Cls>_PADS { off, len }, { off, len }, ...
and `#define LAYOUT_MEASURED 1`. When the compiler cannot dump record layouts
(gcc, mingw, MSVC) or INCURSION_LAYOUT_UNMEASURED=1 is set, the header holds
`#define LAYOUT_MEASURED 0` only, and the coverage check reports "not measured".

PAD RULE. A pad is a byte of the object that no data member covers, plus the
vptr. Walking the class and its bases, every direct member covers its whole
sizeof, so the interior padding of a member of class type (String, a
TargetSystem, an array of structs) is NOT a pad: the FIELD_OBJ/FIELD_EMBED
that saves it marks the whole range. A member the field list does not save is
not a pad either: it must carry FIELD_SKIP, or the coverage check fails.

USAGE
    gen_record_layout.py [--root DIR] [--out FILE] [--cxx CXX] [-- FLAGS...]
    gen_record_layout.py --compare [--rev REV]     the oracle, see below
                       (the compiler reads the working tree; REV only names the
                       tables, so REV and the tree must agree on the classes)
Exit: 0 written (or equal); 1 a class could not be measured, or --compare
found a difference (printed); 2 --compare could not read the hand tables.

--compare reads the hand-written tables and size pins from the source at REV
(default: the working tree), and compares them class by class with this
generator's output plus the members the field lists do not save (those were
pads in the hand tables). It exists to prove the generator's rule equals the
hand tables before the tables are removed.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import save_pad_rows as spr  # noqa: E402

TAG = "gen_record_layout"


def fail(msg):
    print(f"{TAG}: FAILED: {msg}", file=sys.stderr)
    return 1


def read_source(root, rev, rel):
    if rev is None:
        return (root / rel).read_text()
    r = subprocess.run(["git", "-C", str(root), "show", f"{rev}:{rel}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise spr.ToolError(f"git show {rev}:{rel} failed: {r.stderr.strip()}")
    return r.stdout


def pin_classes(save_v1_text):
    """Class names of the SchemaPins[] rows, in order."""
    m = re.search(r"SchemaPins\[\]\s*=\s*\{(.*?)\n\};", save_v1_text, re.S)
    if not m:
        raise spr.ToolError("src/SaveV1.cpp has no SchemaPins[] table")
    classes = re.findall(r'SCHEMA_PIN\(\s*(\w+)\s*\)|\{\s*"(\w+)"\s*,', m.group(1))
    classes = [a or b for a, b in classes]
    if not classes:
        raise spr.ToolError("SchemaPins[] holds no rows")
    return classes


def embed_types(save_v1_text):
    """[(embed name, type)] of the SCHEMA_EMBED_TYPES(X) list in src/SaveV1.cpp:
    each embedded struct whose own compiler padding an embed may leave."""
    m = re.search(r"#define SCHEMA_EMBED_TYPES\(X\)((?:.*\\\n)*.*)", save_v1_text)
    if not m:
        raise spr.ToolError("src/SaveV1.cpp has no SCHEMA_EMBED_TYPES(X) list")
    rows = re.findall(r'X\(\s*"(\w+)"\s*,\s*(\w+)\s*\)', m.group(1))
    if not rows:
        raise spr.ToolError("SCHEMA_EMBED_TYPES(X) holds no rows")
    return rows


def str_members(save_v1_text):
    """Member names V1STR_MEMBERS lists in src/SaveV1.cpp (what V1Str accounts for)."""
    m = re.search(r"#define V1STR_MEMBERS\b([^\n]*)", save_v1_text)
    if not m:
        raise spr.ToolError("src/SaveV1.cpp has no V1STR_MEMBERS list")
    return re.findall(r'"(\w+)"', m.group(1))


def check_string_members(measured, listed):
    """V1Str saves a String by content, so there is no per-member FIELD line to
    count. The compiler's member list for String must equal the list in
    src/SaveV1.cpp, so a member added to String stops the build until a person
    decides what V1Str does with it."""
    _size, _rows, root_node = measured["String"]
    actual = []
    for c in root_node.children:
        if spr.VTABLE_RE.match(c.raw) or spr.BASE_RE.match(c.raw):
            raise spr.ToolError("String gained a vtable or a base class; "
                                "V1Str (src/SaveV1.cpp) saves it by content only")
        actual.append(spr.node_type_and_name(c)[1])
    extra = [m for m in actual if m not in listed]
    missing = [m for m in listed if m not in actual]
    if extra or missing:
        what = []
        if extra:
            what.append("String has member(s) %s that V1STR_MEMBERS does not list" % ", ".join(extra))
        if missing:
            what.append("V1STR_MEMBERS lists %s, which String no longer has" % ", ".join(missing))
        raise spr.ToolError("; ".join(what) + ". V1Str (src/SaveV1.cpp) saves a "
                            "String by content: decide whether the member must "
                            "travel, then update V1STR_MEMBERS")


def merge_ranges(ranges):
    """Sorted, byte-adjacent ranges merged: [(off, len)]."""
    out = []
    for start, end in sorted(ranges):
        if out and start <= out[-1][1]:
            out[-1][1] = max(out[-1][1], end)
        else:
            out.append([start, end])
    return [(a, b - a) for a, b in out]


def expand(rows):
    return {b for off, ln in rows for b in range(off, off + ln)}


def member_ranges(root_node):
    """(start, end) of every direct member of the class and its bases, each
    covering its whole sizeof. The vptr and empty bases cover nothing."""
    out = []

    def walk(node):
        if spr.VTABLE_RE.match(node.raw):
            return
        base = spr.BASE_RE.match(node.raw)
        if base:
            if base.group(3) is None:
                for c in node.children:
                    walk(c)
            return
        if not node.size:
            raise spr.ToolError(f"no size for layout line {node.raw!r}")
        out.append((node.offset, node.offset + node.size))

    for c in root_node.children:
        walk(c)
    return out


def strict_pad_rows(root_node, sizeof_val):
    covered = expand([(a, b - a) for a, b in member_ranges(root_node)])
    gaps = [b for b in range(sizeof_val) if b not in covered]
    return merge_ranges([(b, b + 1) for b in gaps])


def measure(root, classes, cxx, flags):
    """{class: (sizeof, strict pad rows, unsaved-member ranges, archive info)}.
    Raises spr.ToolError naming the class that could not be measured."""
    spr.REPO_ROOT = root
    if cxx:
        spr.CXX_PATH = cxx
    if flags is not None:
        spr.COMPILE_FLAGS = ["-std=c++17"] + flags
    spr.SCHEMA_PINS = [(c, c + "Pads") for c in classes]
    dump = spr.run_record_layout_dump(classes)
    blocks = spr.parse_layout_blocks(dump)
    missing = [c for c in classes if c not in blocks]
    if missing:
        raise spr.ToolError(
            f"{missing[0]}: no record layout in the compiler dump (renamed, "
            f"or no longer a complete class)")
    roots = [blocks[c][0] for c in classes]
    nodes = spr.collect_sizeable_nodes(roots)
    spr.apply_sizes(nodes, spr.measure_sizes_via_compiler(nodes))
    out = {}
    for c in classes:
        root_node, size = blocks[c]
        try:
            out[c] = (size, strict_pad_rows(root_node, size), root_node)
        except spr.ToolError as e:
            raise spr.ToolError(f"{c}: {e}")
    return out


def is_clang(cxx):
    r = subprocess.run([cxx, "-dM", "-E", "-x", "c++", "/dev/null"],
                       capture_output=True, text=True)
    return r.returncode == 0 and "__clang__" in r.stdout


def header_text(measured, classes, embeds=()):
    lines = ["/* Generated by tools/gen_record_layout.py. Do not edit and do not",
             "   commit: the compiler decides these numbers on every build. */"]
    if measured is None:
        lines.append("#define LAYOUT_MEASURED 0")
    else:
        lines.append("#define LAYOUT_MEASURED 1")
        for c in classes:
            size, rows, _n = measured[c]
            pads = ", ".join(f"{{ {o}, {l} }}" for o, l in rows)
            lines.append(f"#define LAYOUT_{c}_SIZE {size}")
            lines.append(f"#define LAYOUT_{c}_PADS {pads}")
        for _name, t in embeds:
            size, rows, _n = measured[t]
            pads = " ".join(f"{{ {o}, {l} }}," for o, l in rows)
            lines.append(f"#define LAYOUT_EMBED_{t}_SIZE {size}")
            lines.append(f"#define LAYOUT_EMBED_{t}_PADS {pads}")
    return "\n".join(lines) + "\n"


def cmd_generate(args, flags):
    root = Path(args.root).resolve()
    cxx = args.cxx or "clang++"
    out = Path(args.out) if args.out else root / "build" / "gen" / "RecordLayout.h"
    if not out.is_absolute():
        out = root / out
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        save_text = read_source(root, None, "src/SaveV1.cpp")
        classes = pin_classes(save_text)
        embeds = embed_types(save_text)
        listed = str_members(save_text)
        etypes = list(dict.fromkeys(t for _n, t in embeds))
        measured = None
        if os.environ.get("INCURSION_LAYOUT_UNMEASURED") == "1":
            print(f"{TAG}: layout: not measured (INCURSION_LAYOUT_UNMEASURED=1)")
        elif not is_clang(cxx):
            print(f"{TAG}: layout: not measured ({cxx} is not clang)")
        else:
            measured = measure(root, classes + etypes + ["String"], cxx, flags)
            check_string_members(measured, listed)
            for c in classes + etypes:
                size, rows, _n = measured[c]
                print(f"layout: {c} size {size}, {len(rows)} pads")
    except spr.ToolError as e:
        return fail(str(e))
    text = header_text(measured, classes, embeds)
    tmp = out.with_suffix(".h.tmp")
    tmp.write_text(text)
    if out.is_file() and out.read_text() == text:
        tmp.unlink()            # keep the mtime: make-style callers see no change
    else:
        tmp.replace(out)
    return 0


def parse_hand_tables(text):
    arrays = {}
    for m in re.finditer(r"static const SchemaPad (\w+)\[\]\s*=\s*\{(.*?)\};",
                         text, re.S):
        arrays[m.group(1)] = [(int(a), int(b)) for a, b in
                              re.findall(r"\{\s*(\d+)\s*,\s*(\d+)\s*\}",
                                         m.group(2))]
    rows = {}
    pins = re.search(r"SchemaPins\[\]\s*=\s*\{(.*?)\n\};", text, re.S).group(1)
    for m in re.finditer(r'\{\s*"(\w+)"\s*,\s*sizeof\(\w+\)\s*,\s*(\w+)\s*,', pins):
        rows[m.group(1)] = m.group(2)
    return arrays, rows


def cmd_compare(args, flags):
    root = Path(args.root).resolve()
    try:
        save = read_source(root, args.rev, "src/SaveV1.cpp")
        arrays, rows = parse_hand_tables(save)
        if not arrays or not rows:
            print(f"{TAG}: no hand tables in src/SaveV1.cpp at "
                  f"{args.rev or 'the working tree'}; nothing to compare "
                  f"(use --rev with a revision that has them)")
            return 2
        asserts = {}
        for rel in ("inc/Creature.h", "inc/Map.h", "inc/Res.h"):
            for m in re.finditer(r"static_assert\(\s*sizeof\((\w+)\)\s*==\s*(\d+)",
                                 read_source(root, args.rev, rel)):
                asserts[m.group(1)] = int(m.group(2))
        classes = list(rows)
        measured = measure(root, classes, args.cxx, flags)
        archive = spr.load_archive_bodies()
    except (spr.ToolError, subprocess.CalledProcessError) as e:
        print(f"{TAG}: COULD NOT COMPARE: {e}")
        return 2
    bad = 0
    for c in classes:
        size, strict, node = measured[c]
        hand_rows = arrays.get(rows[c])
        if hand_rows is None:
            print(f"DIFF {c}: hand table {rows[c]} not found")
            bad += 1
            continue
        unsaved = [f for f in spr.compute_uncovered(node, c, archive, size)
                   if f.member_name]
        gen = expand(strict) | expand([(f.off, f.length) for f in unsaved])
        hand = expand(hand_rows)
        note = ""
        if unsaved:
            note = " (+%s: not saved, was a pad)" % ", ".join(
                f"{f.member_name} {f.off},{f.length}" for f in unsaved)
        size_note = f"size {size}"
        if c in asserts:
            size_note += " == pin" if asserts[c] == size else f" != pin {asserts[c]}"
            if asserts[c] != size:
                bad += 1
        else:
            size_note += " (computed by sizeof, no hand number)"
        if gen == hand:
            print(f"EQUAL {c}: {size_note}, {len(merge_ranges([(b, b+1) for b in gen]))} pad ranges{note}")
        else:
            bad += 1
            print(f"DIFF {c}: {size_note}")
            print(f"    hand only:      {merge_ranges([(b, b+1) for b in sorted(hand - gen)])}")
            print(f"    generated only: {merge_ranges([(b, b+1) for b in sorted(gen - hand)])}")
    print("compare:", "all classes equal" if not bad else f"{bad} difference(s)")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--out", default=None)
    ap.add_argument("--cxx", default=None)
    ap.add_argument("--compare", action="store_true")
    ap.add_argument("--rev", default=None)
    ap.add_argument("flags", nargs="*", help="compiler flags after --")
    args = ap.parse_args()
    flags = args.flags or None
    return (cmd_compare if args.compare else cmd_generate)(args, flags)


if __name__ == "__main__":
    sys.exit(main())
