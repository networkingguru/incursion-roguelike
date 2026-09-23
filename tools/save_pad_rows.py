#!/usr/bin/env python3
"""Measure the SchemaPad rows in src/SaveV1.cpp from the compiler, so nobody
hand-writes an offsetof probe again (bead inc-xlwa).

For every archived class in SchemaPins[] (src/SaveV1.cpp), this tool:
  1. Compiles src/SaveV1.cpp with clang++'s -fdump-record-layouts, using the
     same defines/includes as build_macos.sh's BACKEND=posix (DEBUG) build,
     to get the compiler's own answer for every member's offset and the
     class's sizeof.
  2. Reads the ARCHIVE_CLASS bodies in inc/*.h to learn which byte ranges
     are covered by a FIELD_*/FIELD_SKIP/V1Cover/V1EmbedBegin call, walking
     the base-class chain (Object -> Thing -> ... -> the target class).
  3. Whatever the compiler places in the object but no FIELD_* line reaches
     is a "pad": ordinary compiler padding, OR a real member with no FIELD_
     line (printed by name in a comment, never silently folded into
     padding).

CRITICAL: this reads the COMPILER's layout and the SOURCE's FIELD_ lines --
never the save code's own runtime uncovered-byte list (v1CovEnd), which is
the thing under test. See AGENTS.md and bead inc-xlwa for why.

Never guesses: exits non-zero with a clear message when it cannot establish
a layout (clang missing, a class absent from the dump, a base class with no
ARCHIVE_CLASS and no known root, a record-layout line this parser does not
understand).
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Ordered ClassName -> which SchemaPad array it is measured against in
# src/SaveV1.cpp.  Two rows (Coin, Armour) declare no members of their own
# and reuse an earlier class's array; they are still measured independently
# and must agree with the array they reuse.
SCHEMA_PINS = [
    ("Item", "ItemPads"),
    ("QItem", "QItemPads"),
    ("Food", "FoodPads"),
    ("Corpse", "CorpsePads"),
    ("Container", "ContainerPads"),
    ("Weapon", "WeaponPads"),
    ("Coin", "ItemPads"),
    ("Armour", "QItemPads"),
    ("Creature", "CreaturePads"),
    ("Monster", "MonsterPads"),
    ("Character", "CharacterPads"),
    ("Player", "PlayerPads"),
    ("Feature", "FeaturePads"),
    ("Door", "DoorPads"),
    ("Trap", "TrapPads"),
    ("Portal", "PortalPads"),
    ("Map", "MapPads"),
    ("Game", "GamePads"),
    ("Module", "ModulePads"),
]

# The vptr / Type / myHandle "envelope": src/SaveV1.cpp's v1 writer covers
# Object::Type and Object::myHandle itself (V1Cover calls right beside the
# comment "The envelope carries Type and myHandle; no FIELD_ line"), never
# through a FIELD_ macro in an ARCHIVE_CLASS body. Hardcoded here because it
# is hardcoded there.
ENVELOPE_CLASS = "Object"
ENVELOPE_MEMBERS = {"Type", "myHandle"}

FIELD_CALL_PATTERNS = [
    # (regex matching up to and including the call's opening '(', which arg
    #  index names the member)
    (re.compile(r"FIELD_(?:U8|I8|U16|I16|U32|I32|H|RID|STR)\b\s*\("), 1),
    (re.compile(r"FIELD_ARRAY\b\s*\("), 1),
    (re.compile(r"FIELD_BLOB\b\s*\("), 1),
    (re.compile(r"FIELD_OBJ\b\s*\("), 1),
    (re.compile(r"FIELD_EMBED\b\s*\("), 1),
    (re.compile(r"FIELD_SKIP\b\s*\("), 0),
    (re.compile(r"r\.V1Cover\b\s*\("), 0),
    (re.compile(r"r\.V1EmbedBegin\b\s*\("), 1),
    # Raw r.V1* calls used directly (bypassing a FIELD_ macro), e.g.
    # GraveText (inc/Creature.h) and per-Status RidStatus staging.
    (re.compile(r"r\.V1Str\b\s*\("), 1),
    (re.compile(r"r\.V1Blob\b\s*\("), 1),
    (re.compile(r"r\.V1Array\b\s*\("), 1),
    (re.compile(r"r\.V1Rid\b\s*\("), 1),
    (re.compile(r"r\.V1RidStatus\b\s*\("), 1),
    (re.compile(r"r\.V1Field\b\s*\("), 2),
]

IDENTIFIER_RE = re.compile(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*")


class ToolError(RuntimeError):
    """A condition this tool refuses to guess past."""


# --------------------------------------------------------------------- #
#                         compiler record layout                        #
# --------------------------------------------------------------------- #

def find_clang():
    for name in ("clang++",):
        p = shutil.which(name)
        if p:
            return p
    raise ToolError(
        "clang++ not found on PATH -- cannot measure any layout. "
        "Install Xcode command line tools or put clang++ on PATH."
    )


def run_record_layout_dump():
    """Compile src/SaveV1.cpp with the same defines/includes build_macos.sh
    uses for BACKEND=posix (DEBUG), plus -fdump-record-layouts, and return
    the dump text. Raises ToolError on any compiler failure."""
    clangxx = find_clang()
    src = REPO_ROOT / "src" / "SaveV1.cpp"
    if not src.is_file():
        raise ToolError(f"expected source file missing: {src}")
    cmd = [
        clangxx, "-std=c++17", "-DDEBUG", "-DPOSIX_TERM",
        "-Iinc", "-Ilib", "-Icompat",
        "-w", "-fpermissive", "-Wno-narrowing",
        "-fsyntax-only", "-Xclang", "-fdump-record-layouts",
        str(src),
    ]
    with tempfile.TemporaryDirectory(prefix="save_pad_rows-") as td:
        out_path = Path(td) / "layout.txt"
        with open(out_path, "w") as outf:
            proc = subprocess.run(
                cmd, cwd=REPO_ROOT, stdout=outf, stderr=subprocess.STDOUT
            )
        text = out_path.read_text()
    if proc.returncode != 0:
        tail = "\n".join(text.splitlines()[-40:])
        raise ToolError(
            f"clang++ failed to compile src/SaveV1.cpp for a layout dump "
            f"(exit {proc.returncode}). Last 40 lines:\n{tail}"
        )
    return text


# --------------------------------------------------------------------- #
#                      record layout dump parsing                       #
# --------------------------------------------------------------------- #

class LayoutNode:
    __slots__ = ("depth", "offset", "raw", "size", "children")

    def __init__(self, depth, offset, raw):
        self.depth = depth
        self.offset = offset
        self.raw = raw          # text after the "N | " prefix, unstripped
        self.size = None        # filled in by span computation
        self.children = []


def parse_layout_blocks(dump_text):
    """Return {class_name: (root_node, sizeof)} for every top-level
    '*** Dumping AST Record Layout' block, keyed by the name on its first
    (depth-0) line. Only the LAST such block per name is kept, which is
    fine here: every block for the same name is produced by the same
    compiler from the same source and must agree with itself."""
    lines = dump_text.splitlines()
    blocks = {}
    i = 0
    n = len(lines)
    while i < n:
        if lines[i].strip() != "*** Dumping AST Record Layout":
            i += 1
            continue
        i += 1
        # Collect this block's lines until a blank line or EOF.
        block_lines = []
        while i < n and lines[i].strip() != "":
            block_lines.append(lines[i])
            i += 1
        if not block_lines:
            continue
        root, sizeof_val, name = _parse_one_block(block_lines)
        if root is not None and sizeof_val is not None:
            blocks[name] = (root, sizeof_val)
    return blocks


def _parse_one_block(block_lines):
    """Parse one dumped record's lines into a node tree. Returns
    (root_node, sizeof, class_name) or (None, None, None) if this block is
    not a class/struct layout (e.g. it could theoretically be something
    this parser does not recognise -- caller skips it)."""
    stack = []       # list of (depth, node)
    root = None
    name = None
    sizeof_val = None
    for raw_line in block_lines:
        if "|" not in raw_line:
            continue
        left, _, rest = raw_line.partition("|")
        left = left.strip()
        if left == "":
            m = re.search(r"sizeof=(\d+)", rest)
            if m:
                sizeof_val = int(m.group(1))
            continue
        if not re.fullmatch(r"\d+", left):
            # Not an offset line this parser understands.
            continue
        offset = int(left)
        leading = len(rest) - len(rest.lstrip(" "))
        depth = (leading - 1) // 2 if leading >= 1 else 0
        node = LayoutNode(depth, offset, rest.strip())
        if depth == 0:
            root = node
            stack = [(0, node)]
            m = re.match(r"(?:class|struct)\s+(.+)$", node.raw)
            name = m.group(1).strip() if m else node.raw.strip()
            continue
        # Find this node's parent: nearest earlier node with depth-1.
        while stack and stack[-1][0] >= depth:
            stack.pop()
        if not stack:
            # Malformed nesting -- do not guess a parent.
            raise ToolError(
                f"cannot parse record layout line (bad nesting): {raw_line!r}"
            )
        parent = stack[-1][1]
        parent.children.append(node)
        stack.append((depth, node))
    return root, sizeof_val, name


def node_type_and_name(node):
    """Split 'int16[41] Attr' into ('int16[41]', 'Attr'). The name is
    always the raw line's last whitespace-separated token; the type is
    everything before it (may itself contain spaces/commas, e.g.
    'class NArray<int, 10, 20>')."""
    m = re.match(r".+?\s(\S+)$", node.raw)
    if not m:
        raise ToolError(f"cannot split type and name in layout line: "
                         f"{node.raw!r}")
    name = m.group(1)
    type_expr = node.raw[: len(node.raw) - len(name)].rstrip()
    return type_expr, name


def collect_sizeable_nodes(roots):
    """Every node across the given root trees whose size must come from
    sizeof(its own type) -- i.e. everything except vtable-pointer lines
    (always pointer-sized) and base-class subobject headers (never sized
    directly; their own children are sized and recursed into instead)."""
    out = []

    def walk(node):
        if VTABLE_RE.match(node.raw) or BASE_RE.match(node.raw):
            for c in node.children:
                walk(c)
            return
        out.append(node)
        for c in node.children:
            walk(c)

    for root in roots:
        for c in root.children:
            walk(c)
    return out


def measure_sizes_via_compiler(nodes):
    """Ask the compiler for sizeof() of every distinct type expression
    these nodes carry, by compiling and RUNNING a tiny probe (not just
    syntax-checking): a position-based offset diff cannot see padding that
    follows the last member of a run, so every leaf and every compound
    member's size must come from the compiler's own sizeof(), never from
    inferring it against a neighbour's offset."""
    exprs = []
    seen = set()
    for node in nodes:
        type_expr, _ = node_type_and_name(node)
        norm = type_expr.replace("_Bool", "bool")
        if norm not in seen:
            seen.add(norm)
            exprs.append(norm)

    lines = ["#include \"Incursion.h\"", "#include <cstdio>", "int main(){"]
    for idx, expr in enumerate(exprs):
        lines.append(f'  printf("{idx} %zu\\n", (size_t)sizeof({expr}));')
    lines.append("  return 0;\n}\n")
    src = "\n".join(lines)

    clangxx = find_clang()
    with tempfile.TemporaryDirectory(prefix="save_pad_rows-sizes-") as td:
        src_path = Path(td) / "sizeprobe.cpp"
        bin_path = Path(td) / "sizeprobe"
        src_path.write_text(src)
        cmd = [
            clangxx, "-std=c++17", "-DDEBUG", "-DPOSIX_TERM",
            "-Iinc", "-Ilib", "-Icompat",
            "-w", "-fpermissive", "-Wno-narrowing",
            str(src_path), "-o", str(bin_path),
        ]
        proc = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
        if proc.returncode != 0:
            raise ToolError(
                "the sizeof() probe failed to compile -- a member type in "
                "the record-layout dump could not be reduced to a plain "
                "sizeof() expression. Compiler output:\n" + proc.stderr[-4000:]
            )
        run = subprocess.run([str(bin_path)], capture_output=True, text=True)
        if run.returncode != 0:
            raise ToolError(
                f"the sizeof() probe binary exited {run.returncode}"
            )
    sizes = {}
    for line in run.stdout.splitlines():
        idx_str, _, size_str = line.strip().partition(" ")
        sizes[exprs[int(idx_str)]] = int(size_str)
    if len(sizes) != len(exprs):
        raise ToolError("the sizeof() probe did not report a size for "
                         "every type expression it was asked about")
    return sizes


def apply_sizes(nodes, size_by_expr):
    for node in nodes:
        type_expr, _ = node_type_and_name(node)
        norm = type_expr.replace("_Bool", "bool")
        node.size = size_by_expr[norm]


# --------------------------------------------------------------------- #
#                    ARCHIVE_CLASS body / FIELD_ parsing                #
# --------------------------------------------------------------------- #

def load_archive_bodies():
    """Scan inc/*.h for every ARCHIVE_CLASS(Name,Base,r) ... END_ARCHIVE
    body. Returns {ClassName: (BaseName, body_text, covered_names_set)}."""
    info = {}
    decl_re = re.compile(
        r"ARCHIVE_CLASS\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*\w+\s*\)"
    )
    for path in sorted(REPO_ROOT.glob("inc/*.h")):
        text = path.read_text()
        for m in decl_re.finditer(text):
            cls, base = m.group(1), m.group(2)
            end_idx = text.find("END_ARCHIVE", m.end())
            if end_idx == -1:
                raise ToolError(
                    f"{path}: ARCHIVE_CLASS({cls},...) has no matching "
                    f"END_ARCHIVE -- cannot establish its field list"
                )
            body = text[m.end():end_idx]
            if cls in info:
                raise ToolError(
                    f"ARCHIVE_CLASS({cls},...) declared more than once "
                    f"(seen in {path} and elsewhere) -- refusing to guess "
                    f"which body is authoritative"
                )
            info[cls] = (base, body, extract_covered_names(body))
    return info


def _split_call_args(text, start_idx):
    """text[start_idx] is the character right after a call's opening '('.
    Return the list of top-level (paren-depth-aware) argument strings."""
    depth = 1
    i = start_idx
    args = []
    cur = []
    n = len(text)
    while i < n and depth > 0:
        c = text[i]
        if c == "(":
            depth += 1
            cur.append(c)
        elif c == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(cur))
                break
            cur.append(c)
        elif c == "," and depth == 1:
            args.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    return args


def _normalize_member_expr(raw):
    """Turn a raw macro argument into a bare or dotted identifier, or None
    if it is not a simple member reference (a cast, an arithmetic
    expression, etc. -- those never name a data member directly and are
    ignored, not guessed at)."""
    raw = raw.strip()
    if raw.startswith("&"):
        raw = raw[1:].strip()
    while raw.startswith("(") and raw.endswith(")"):
        inner = raw[1:-1].strip()
        if inner == raw[1:-1]:
            pass
        raw = inner
    raw = re.sub(r"\[[^\]]*\]$", "", raw).strip()
    if IDENTIFIER_RE.fullmatch(raw):
        return raw
    return None


def extract_covered_names(body_text):
    """Every identifier (bare, or dotted like 'ov.GlyphX') named as the
    'member' argument of a FIELD_*/FIELD_SKIP/V1Cover/V1EmbedBegin call
    anywhere in this ARCHIVE_CLASS body."""
    names = set()
    for call_re, arg_idx in FIELD_CALL_PATTERNS:
        for m in call_re.finditer(body_text):
            args = _split_call_args(body_text, m.end())
            if arg_idx >= len(args):
                continue
            name = _normalize_member_expr(args[arg_idx])
            if name:
                names.add(name)
    return names


# --------------------------------------------------------------------- #
#                          coverage computation                         #
# --------------------------------------------------------------------- #

BASE_RE = re.compile(
    r"^(?:class|struct)\s+(\S+)\s+\((primary base|base)\)(\s*\(empty\))?$"
)
VTABLE_RE = re.compile(r"^\(\s*\S+\s+vtable pointer\)$")
VTABLE_PTR_SIZE = 8   # arm64/LP64, same ABI every existing pad row assumes


class Finding:
    """One byte range in the object that no FIELD_ line reaches: either
    ordinary compiler padding, or a real member with no FIELD_ line."""

    def __init__(self, off, length, member_name=None):
        self.off = off
        self.length = length
        self.member_name = member_name  # None => pure padding


def compute_uncovered(root_node, class_name, archive_bodies, outer_sizeof):
    """Walk the layout tree and return the list of Finding for every byte
    the compiler places in the object that no FIELD_ line reaches, in
    offset order. Two different things produce a Finding, and this
    function does not tell them apart until the very end:

      - a byte between/around declared members: the compiler's own
        alignment padding, or the leading vtable pointer. The dump never
        prints these as their own line, so they cannot be found by
        classifying declared members one at a time -- they only show up
        as the COMPLEMENT of every byte a declared member (covered or
        not) accounts for.
      - a declared member with no FIELD_ line reaching it at all: a real
        field, deliberately or accidentally never archived.

    So this first collects every declared member's own byte range,
    whether or not a FIELD_ line covers it (an 'explained' range either
    way -- a covered field explains its bytes by being saved; an
    uncovered one explains them by being a real, named member). The
    complement of the union of all explained ranges, within
    [0, outer_sizeof), is exactly the compiler's own padding, including
    the vtable pointer, found without ever having to special-case it as
    a fixed 8 bytes at offset 0 -- it simply is the first gap.

    Raises ToolError if a base class in the chain has no known field
    list and is not the root Object class."""
    explained = []          # [(start,end)] -- every declared member's own
                             # range, covered or not
    named_findings = []     # Finding for members with no FIELD_ line

    def class_covered_names(cls):
        if cls == ENVELOPE_CLASS:
            return set()
        entry = archive_bodies.get(cls)
        if entry is None:
            raise ToolError(
                f"class '{cls}' appears in {class_name}'s base chain but "
                f"has no ARCHIVE_CLASS(...) body -- cannot classify its "
                f"members without guessing"
            )
        return entry[2]

    def walk(node, cls, dotted_prefix):
        if VTABLE_RE.match(node.raw):
            # Deliberately NOT added to `explained`: it is uncovered by
            # construction, and the complement step below finds it.
            return
        base_m = BASE_RE.match(node.raw)
        if base_m:
            base_name = base_m.group(1)
            is_empty = base_m.group(3) is not None
            if is_empty:
                return
            for child in node.children:
                walk(child, base_name, "")
            return
        # An ordinary data member.
        m = re.match(r".+?\s(\S+)$", node.raw)
        bare_name = m.group(1) if m else node.raw
        if cls == ENVELOPE_CLASS and bare_name in ENVELOPE_MEMBERS:
            explained.append((node.offset, node.offset + node.size))
            return  # covered by the v1 record envelope, not a FIELD_ line
        full_name = f"{dotted_prefix}.{bare_name}" if dotted_prefix else bare_name
        covered = class_covered_names(cls)
        if full_name in covered or bare_name in covered:
            explained.append((node.offset, node.offset + node.size))
            return
        if node.children:
            for child in node.children:
                walk(child, cls, full_name)
            return
        if node.size:
            explained.append((node.offset, node.offset + node.size))
            named_findings.append(Finding(node.offset, node.size, full_name))

    for child in root_node.children:
        walk(child, class_name, "")

    pad_findings = [
        Finding(start, end - start, None)
        for start, end in _complement(explained, outer_sizeof)
    ]
    findings = pad_findings + named_findings
    findings.sort(key=lambda f: f.off)
    return findings


def _complement(intervals, total):
    """The gaps in [0, total) not covered by any (start,end) interval."""
    if not intervals:
        return [(0, total)] if total else []
    ordered = sorted(intervals)
    gaps = []
    cursor = 0
    for start, end in ordered:
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < total:
        gaps.append((cursor, total))
    return gaps


def merge_findings(findings):
    """Merge byte-adjacent findings into SchemaPad rows. A row's comment
    names every not-saved member whose own span the merged row overlaps."""
    rows = []
    i = 0
    n = len(findings)
    while i < n:
        start = findings[i].off
        end = findings[i].off + findings[i].length
        names = [findings[i].member_name] if findings[i].member_name else []
        j = i + 1
        while j < n and findings[j].off == end:
            end += findings[j].length
            if findings[j].member_name:
                names.append(findings[j].member_name)
            j += 1
        rows.append((start, end - start, names))
        i = j
    return rows


# --------------------------------------------------------------------- #
#                                driver                                 #
# --------------------------------------------------------------------- #

def measure_class(class_name, blocks, archive_bodies, size_by_expr):
    entry = blocks.get(class_name)
    if entry is None:
        raise ToolError(
            f"class '{class_name}' never appears as its own "
            f"'*** Dumping AST Record Layout' block -- src/SaveV1.cpp no "
            f"longer instantiates sizeof({class_name}) where this tool "
            f"expects it, or the class was renamed"
        )
    root, sizeof_val = entry
    apply_sizes(collect_sizeable_nodes([root]), size_by_expr)
    findings = compute_uncovered(root, class_name, archive_bodies, sizeof_val)
    rows = merge_findings(findings)
    return sizeof_val, rows


def format_rows(rows):
    return " " + ", ".join(f"{{ {off}, {length} }}" for off, length, _ in rows)


def measure_all():
    """Measure every class in SCHEMA_PINS. Returns {ClassName: (sizeof,
    rows)}, rows being the merge_findings() output for that class. Raises
    ToolError -- callers (the CLI and the check script) decide how to
    report it."""
    dump_text = run_record_layout_dump()
    blocks = parse_layout_blocks(dump_text)
    archive_bodies = load_archive_bodies()

    target_roots = []
    seen_cls = set()
    for cls, _array in SCHEMA_PINS:
        if cls in seen_cls:
            continue
        seen_cls.add(cls)
        entry = blocks.get(cls)
        if entry is None:
            raise ToolError(
                f"class '{cls}' never appears as its own "
                f"'*** Dumping AST Record Layout' block -- "
                f"src/SaveV1.cpp no longer instantiates sizeof({cls}) "
                f"where this tool expects it, or the class was renamed"
            )
        target_roots.append(entry[0])
    size_by_expr = measure_sizes_via_compiler(
        collect_sizeable_nodes(target_roots)
    )

    measured = {}
    for cls, _array in SCHEMA_PINS:
        if cls in measured:
            continue
        measured[cls] = measure_class(cls, blocks, archive_bodies,
                                       size_by_expr)
    return measured


def main():
    global REPO_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", default=None,
        help="repo root to measure (default: this script's own checkout) "
             "-- lets tools/check_save_pad_rows.sh --selftest point this "
             "tool at a scratch copy of the tree",
    )
    args = parser.parse_args()
    if args.root:
        REPO_ROOT = Path(args.root).resolve()

    try:
        measured = measure_all()
    except ToolError as e:
        print(f"save_pad_rows: FAILED: {e}", file=sys.stderr)
        return 1

    # One C initializer per distinct pads array, measured from the first
    # class in SCHEMA_PINS that uses it.
    seen_arrays = {}
    for cls, array in SCHEMA_PINS:
        seen_arrays.setdefault(array, cls)

    print("/* Measured by tools/save_pad_rows.py -- paste over the matching")
    print("   arrays in src/SaveV1.cpp if they disagree. */")
    print()
    for array, primary_cls in seen_arrays.items():
        sizeof_val, rows = measured[primary_cls]
        print(f"static const SchemaPad {array}[] = {{")
        print(f"    {format_rows(rows).strip()}")
        print("};")
        for off, length, names in rows:
            if names:
                print(f"    /* {off},{length}: not saved (no FIELD_ line): "
                      f"{', '.join(names)} */")
        print()

    print("/* SchemaPins[] -- measured sizeof, and whether the class's own")
    print("   rows agree with the array it is pinned to. */")
    mismatches = []
    for cls, array in SCHEMA_PINS:
        sizeof_val, rows = measured[cls]
        primary_cls = seen_arrays[array]
        primary_rows = measured[primary_cls][1]
        agrees = (rows == primary_rows) or (cls == primary_cls)
        flag = "" if agrees else "  ** DISAGREES WITH " + array + " **"
        print(f"    {{ \"{cls}\", {sizeof_val}, {array}, "
              f"{len(rows)} }}{flag}")
        if not agrees:
            mismatches.append((cls, array, rows, primary_rows))

    if mismatches:
        print()
        print("/* MISMATCHES: a class pinned to a shared array does not")
        print("   measure the same as that array's own primary class. */")
        for cls, array, rows, primary_rows in mismatches:
            print(f"    {cls} (own measured rows) : {format_rows(rows).strip()}")
            print(f"    {array} (declared)         : "
                  f"{format_rows(primary_rows).strip()}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
