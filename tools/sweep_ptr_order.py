#!/usr/bin/env python3
"""Report every place the code puts two pointers in ORDER.

Reads clang's parse tree on stdin, one translation unit at a time, and prints
one line per candidate. tools/sweep_ptr_order.sh produces the dumps and is the
way to run this.

WHY ORDER AND NOT EQUALITY. inc-dhc is a class of defect: the engine compares
two addresses and lets the answer change a decision. The allocator puts objects
somewhere different on every launch, so the same seed plays a different game.
Asking whether two pointers are EQUAL is fine -- either they are the same object
or they are not, and that never changes. Asking which comes FIRST is the fault,
so this reports exactly the five operators that answer that question:

    -   <   >   <=   >=

WHAT THIS DOES NOT DO. It enumerates candidates; it does not judge them.
Ordering two pointers INTO ONE ARRAY is both legal and repeatable -- `end - buf`
is a length, not an address comparison -- and it looks identical here. Every hit
needs a person to decide which kind it is. Nor does it prove absence: a table
walked in allocation order reads an address without ever comparing one, and no
operator appears for this to find. tools/check_layout.sh remains the ground
truth. This is the cheap sweep that says where to look first.
"""

import re
import sys

NODE = re.compile(r"^(?P<pre>[^A-Za-z]*)(?P<name>[A-Za-z_][A-Za-z0-9_]*) 0x[0-9a-f]+(?P<rest>.*)$")
ORDERING = {"-", "<", ">", "<=", ">="}


def take_angle(s):
    """Return the first <...> group in s, and the text after it.

    The group nests: a macro expansion prints <line:5:3 <Spelling=...>>, so
    counting brackets is the only way to find where it ends."""
    i = s.find("<")
    if i < 0:
        return None, s
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "<":
            depth += 1
        elif s[j] == ">":
            depth -= 1
            if depth == 0:
                return s[i + 1:j], s[j + 1:]
    return None, s


class Where:
    """Follows the file and line clang is talking about.

    A dump does not repeat what has not changed: a node in the same file and
    line as the one before it prints only `col:9`. So the position has to be
    carried forward, exactly as clang carries it."""

    def __init__(self):
        self.file = None
        self.line = None

    def update(self, loc):
        if not loc:
            return
        for tok in re.findall(r"[^\s,]+", loc):
            m = re.match(r"^line:(\d+):(\d+)$", tok)
            if m:
                self.line = int(m.group(1))
                continue
            if re.match(r"^col:\d+$", tok):
                continue
            m = re.match(r"^(.+):(\d+):(\d+)$", tok)
            if m:
                self.file = m.group(1)
                self.line = int(m.group(2))


def parse(stream):
    """Turn the dump into (depth, name, type, op, file, line, rest) tuples.

    `rest` is what clang printed after the location -- the type, the operator,
    and any qualifiers such as `static`. The stored-pointer sweep reads it."""
    where = Where()
    out = []
    for raw in stream:
        line = raw.rstrip("\n")
        m = NODE.match(line)
        if not m:
            continue
        depth = len(m.group("pre"))
        loc, rest = take_angle(m.group("rest"))
        where.update(loc)
        quoted = re.findall(r"'([^']*)'", rest)
        typ = quoted[0] if quoted else None
        op = quoted[1] if len(quoted) > 1 else None
        out.append((depth, m.group("name"), typ, op, where.file, where.line, rest))
    return out


def is_pointer(typ):
    return bool(typ) and typ.rstrip().endswith("*")


def find(nodes, keep):
    """Yield each ordering of two pointers, as (file, line, op, type)."""
    for i, (depth, name, _typ, op, path, line, _rest) in enumerate(nodes):
        if name != "BinaryOperator" or op not in ORDERING:
            continue
        if not path or not keep(path):
            continue
        operands = []
        for j in range(i + 1, len(nodes)):
            d = nodes[j][0]
            if d <= depth:
                break
            if d == depth + 2:
                operands.append(nodes[j][2])
                if len(operands) == 2:
                    break
        # Both sides must be pointers. `p - 1` and `p + n` are arithmetic on one
        # pointer and an integer, which is repeatable; only pointer-against-
        # pointer reads where two objects sit relative to each other.
        if len(operands) == 2 and all(is_pointer(t) for t in operands):
            yield (path, line, op, operands[0])


def find_stored(nodes, keep):
    """Yield every long-lived raw pointer to an object, as (file, line, kind, type).

    THIS IS THE OTHER HALF OF THE CLASS, and it was added because the sweep
    above could not have found the defect it was built to find. `Falling` in
    src/Move.cpp held a Creature* across a level change; the creature could die
    before anything cleared it, and then `Falling == this` matched whichever new
    creature the allocator put on the freed address. That test is an EQUALITY,
    which the ordering sweep deliberately ignores -- equality between two live
    pointers really is stable. It is not stable when one of them is dead.

    So the thing to hunt is not the comparison, it is the STORAGE: a pointer to
    a game object kept somewhere that outlives the object. A global or a static
    is exactly that. A local cannot outlive anything.

    Same limits as the ordering sweep: this enumerates, it does not judge. A
    global cache that is cleared correctly is fine and looks identical here."""
    for depth, name, typ, _op, path, line, extra in nodes:
        if name != "VarDecl" or not is_pointer(typ):
            continue
        if not path or not keep(path):
            continue
        # File scope, or a static anywhere. Both outlive the objects they point
        # at; a plain local does not.
        isstatic = " static" in extra
        if depth != 2 and not isstatic:
            continue
        pointee = typ.rstrip().rstrip("*").strip()
        # str.lstrip("const ") would strip any of those SIX CHARACTERS from the
        # left, so it turns "char" into "har" and the exclusion below silently
        # stops working. Remove the prefix, not the letters in it.
        if pointee.startswith("const "):
            pointee = pointee[6:].strip()
        # Bytes and characters are buffers, not identities, and a buffer that
        # moves does not change any decision.
        if pointee in (
            "char", "unsigned char", "void", "int", "unsigned int", "short",
            "long", "float", "double", "uint8", "int8", "uint16", "int16",
            "uint32", "int32", "FILE",
        ):
            continue
        yield (path, line, "static" if isstatic else "global", typ)


def main():
    # A translation unit drags in the whole SDK, and none of that is ours to
    # fix. Keep only what the caller asks for; with no argument, keep anything
    # that is not a system header. The self-test relies on the second form.
    args = [a for a in sys.argv[1:]]
    stored = "--stored" in args
    args = [a for a in args if a != "--stored"]
    want = args[0] if args else None
    if want:
        keep = lambda p: want in p
    else:
        keep = lambda p: not any(
            p.startswith(d) for d in ("/usr/", "/Applications/", "/Library/", "/System/")
        )
    nodes = parse(sys.stdin)
    hits = {}
    rows = find_stored(nodes, keep) if stored else find(nodes, keep)
    for path, line, what, typ in rows:
        hits[(path, line, what, typ)] = True
    for path, line, what, typ in sorted(hits):
        print("%s:%s\t%s\t%s" % (path, line, what, typ))


if __name__ == "__main__":
    main()
