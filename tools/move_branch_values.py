#!/usr/bin/env python3
# gate: cheap
# gate-fast: static plus read-only git; the selftest builds temporary git repos, about 3 s
"""Move the colliding stored values of this branch to free ones.

WHY THIS EXISTS. A save, Options.Dat or another file on disk holds the VALUE of
a stored #define or enumerator. When this branch adds a name whose value a
master name already holds (or a retired value held), tools/check_stored_values.py
rule 3 fails. Master's number stays; the branch's own name moves. Nobody edits
that number by hand. Spec docs/superpowers/specs/2026-11-07-names-in-the-file-
design.md section 6 and AC5 (bead inc-cjos0, phase 5c).

WHAT IT DOES. It reads the base ref (--base, default master) and the working
tree the way check_stored_values.py does, and takes every rule-3 collision (a
tree-only name whose value a base name or a retired value holds in the same
stored family). It rewrites the tree-only name's value in its source line by
the shape of the family:
  ordinal  the next value after the maximum of the merged family (base names,
           tree names, retired values; sentinel names left out). When the mark
           names `bound <NAME>` (the value that sizes the array the family
           indexes, OPT_LAST), the new value MUST be below the bound: the next
           value when it is below, else the highest free value below the bound,
           else REFUSED naming the family. The bound itself never moves.
  bits     the lowest free bit of the storage width, free of every base, tree
           and retired value. No free bit: REFUSED, the word is full.
  enum     the enumerator's line moves to the end of its enum (before the
           sentinel names that end it) with an explicit `= <value>` chosen as
           for ordinal (a `bound` binds here too), so no base enumerator shifts. An enumerator that
           followed it gets an explicit value only when the move would change
           its value; each is reported.
Then, in each family that moved a name, every `sentinel <NAME>` of the mark is
rewritten to max+1 of the merged family (ordinal and enum families; a bits
sentinel has no meaning and is left). A sentinel whose line carries an `alias of <NAME>`
note equals the last member instead: it takes the highest member value over every family
that lists it (one move), and its note names the real member that holds that value. A `grows <NAME>` limit (spec 6.1) is no
stored value: it stays out of the merged family. A moved value in such a family
takes the first free index at or above the base's limit (so the index range grows
by one per moved value), and the limit is raised to (largest moved index + 1) and
never lowered. A base member at or above the base limit (A_HIT.., SL_ARCHERY) is no
index: it is never counted, and a move that would reach one is REFUSED naming the
family, the limit and that member. A bound that is also `grows`
(OPT_LAST) is raised the same way instead of refusing. A `block <N>` clause overrides both: a moved value
takes the lowest free value of its own block of N (old // N * N), or the mover REFUSES naming the family
and the block, and the limit never moves. Two moved names never take one value. A
new value that does not fit the storage width is REFUSED naming bead inc-xm3nq.
A value written as an expression (`FT_FIRST + 3`) is rewritten to the literal;
the report line says so. It changes no base name, no base value, and no line
outside the moved names and the sentinels (and the enum followers above).
Afterwards it runs check_stored_values again and exits 1 if that still fails.

ON MASTER (the current branch is the base ref, or HEAD is the base commit) it
prints "no-op on master" and changes nothing.

Output: one line per move, `family NAME old -> new file:line`, then
`move_branch_values: moved N value(s)`. tools/finish_bead.sh reads that last line.

Usage: tools/move_branch_values.py [--base REF] [--dry-run] [--selftest]
Exit:  0 done (or nothing to do)   1 refused, or the check still fails   2 unmeasured

# fact: the base tree -- a git ref read with `git archive`; default master, re-read on every run
# fact: define and enumerator values -- the compiler at the posix flags (check_stored_values.py); no game run, no seed
# fact: family, class, shape, width -- the marks in inc/ and src/ of each tree; no randomness
# fact: retired values -- tools/retired_values.txt, a tracked file
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_define_dups as cdd  # noqa: E402
import check_stored_values as csv  # noqa: E402

ROOT = cdd.ROOT
LITERAL = re.compile(r"-?(0[xX][0-9a-fA-F]+|\d+)[uUlL]*")
ALIAS_NAME = re.compile(r"(\balias\s+of\s+)[A-Za-z_]\w*")
# The name of an end-of-table marker. A marker is no stored value, so a family mark MUST say
# so (`sentinel`, `grows` or `bound`); an unmarked one that holds a collision is refused.
END_MARKER = re.compile(r"(_LAST|_MAX|_COUNT|_END)$|^(NUM|LAST)_")
ENUM_LINE = re.compile(r"^(\s*)([A-Za-z_]\w*)(?:\s*=\s*(.*?))?\s*(,?)\s*$")


class Refused(Exception):
    pass


def where_of(m):
    return "%s:%d" % (m[2], m[3])


# ---------------------------------------------------------------- planning

def grow_limit(bfam, tvals, grows):
    """The base's value of the family's `grows` limit (the tree's when the base lacks
    it), or None when the family has no `grows` limit with a value."""
    if not grows:
        return None
    bv = {m[0]: m[1] for m in bfam.get("members", [])}
    vals = [bv[g] if g in bv else tvals[g][1] for g in grows if g in bv or g in tvals]
    return max(vals) if vals else None


def alias_note(root, m):
    """The `alias of <NAME>` note of the define or enumerator member m (name, value,
    file, line), the way check_define_dups reads it: the line, else a comment-only
    line above. Return (NAME, offset) with offset 0 (same line) or -1 (the line
    above), or None."""
    if root is None:
        return None
    with open(os.path.join(root, m[2]), encoding="latin-1", newline="") as f:
        raw = f.read().split("\n")
    for off in (0, -1):
        i = m[3] - 1 + off
        if i < 0 or (off and not cdd.COMMENT_ONLY.match(raw[i])):
            continue
        a = cdd.ALIAS.search(raw[i])
        if a:
            return a.group(1), off
    return None


def alias_moves(tree, moves, root):
    """A sentinel that carries an `alias of <NAME>` note EQUALS the last member of
    its families. After the moves it takes the highest member value over every
    family that lists it, and its note names a real member that holds that value.
    One move per sentinel, however many families list it."""
    newv = {mv["name"]: mv["new"] for mv in moves if not mv["sentinel"]}
    fams = {}
    for fam in sorted(tree):
        if tree[fam]["class"] == "stored":
            for s in tree[fam]["sentinels"]:
                fams.setdefault(s, []).append(fam)
    sentinels = {s for t in tree.values() for s in t["sentinels"]}
    out = []
    for s, fl in sorted(fams.items()):
        if not any(mv["fam"] in fl for mv in moves if not mv["sentinel"]):
            continue
        m = next((x for f in fl for x in tree[f]["members"] if x[0] == s), None)
        note = alias_note(root, m) if m else None
        if note is None:
            continue
        held = {}
        for f in fl:
            skip = set(tree[f]["sentinels"]) | set(tree[f].get("grows", []))
            for x in tree[f]["members"]:
                if x[0] not in skip and x[0] not in sentinels:
                    held.setdefault(newv.get(x[0], x[1]), []).append(x)
        if not held:
            continue
        top = max(held)
        real = [x for x in held[top] if alias_note(root, x) is None]
        if not real:
            raise Refused("sentinel %s: no real member holds the top value %d, so its "
                          "`alias of` note has nothing to name (bead inc-cjos0)" % (s, top))
        holder = min(real, key=lambda x: (x[0] not in newv, x[0]))[0]
        if m[1] == top and note[0] == holder:
            continue
        out.append(dict(fam=fl[0], name=s, old=m[1], new=top, file=m[2], line=m[3],
                        shape=tree[fl[0]]["shape"], sentinel=True, alias=holder,
                        alias_off=note[1]))
    return out


def repair_moves(base, tree, retired, root, skip):
    """A family that no collision moved may still hold a member that is new or changed
    since the base and sits at or past its exclusive end marker (a `sentinel` with no
    `alias of` note): an earlier merge moved it past the marker. Move each one to the
    next value after the highest taken one below the marker, else the highest free value below it, or REFUSE when none is free (bead
    inc-pu6v.478.7). Families in `skip` already took their moves."""
    out = []
    for fam in sorted(tree):
        t = tree[fam]
        if t["class"] != "stored" or t["shape"] == "bits" or t.get("block") or fam in skip:
            continue
        tvals = {}
        for m in t["members"]:
            tvals.setdefault(m[0], m)
        bvals = {m[0]: m[1] for m in base.get(fam, {}).get("members", [])}
        marks = set(t["sentinels"]) | set(t.get("grows", [])) | set(t.get("bounds", []))
        lims = [tvals[s][1] for s in t["sentinels"]
                if s in tvals and alias_note(root, tvals[s]) is None]
        lims += [tvals[b][1] for b in t.get("bounds", []) if b in tvals]
        if not lims:
            continue
        lim = min(lims)
        bad = sorted((m for n, m in tvals.items()
                      if n not in marks and m[1] >= lim and bvals.get(n) != m[1]),
                     key=lambda m: (m[2], m[3]))
        if not bad:
            continue
        taken = {m[1] for m in base.get(fam, {}).get("members", []) if m[0] not in marks}
        taken |= {m[1] for n, m in tvals.items() if n not in marks and m not in bad}
        taken |= set(dict(retired.get(fam, [])).values())
        for m in bad:
            mx = max((v for v in taken if v < lim), default=-1)
            free = [mx + 1] if mx + 1 < lim else \
                [v for v in range(lim - 1, -1, -1) if v not in taken and v > min(taken, default=0)]
            if not free or not csv.fits(free[0], t["shape"], t["width"]):
                raise Refused("family %s: %s = %d is at or past its end marker %s = %d and no "
                              "free value is left below it (bead inc-pu6v.478.7)"
                              % (fam, m[0], m[1], ",".join(sorted(marks)), lim))
            taken.add(free[0])
            out.append(dict(fam=fam, name=m[0], old=m[1], new=free[0], file=m[2], line=m[3],
                            shape=t["shape"], sentinel=False))
    return out


def bound_guard(tree, moves, root):
    """No moved value may land at or past its family's exclusive end marker (a `bound`, or
    a `sentinel` with no `alias of` note), as that marker stands after the moves. Raise
    Refused naming the family, the value and the marker."""
    newv = {mv["name"]: mv["new"] for mv in moves}
    for mv in moves:
        if mv["sentinel"] or mv["shape"] == "bits":
            continue
        t = tree[mv["fam"]]
        for mk in t["sentinels"] + t.get("bounds", []):
            m = next((x for x in t["members"] if x[0] == mk), None)
            if m is None or (mk in t["sentinels"] and alias_note(root, m) is not None):
                continue
            lim = newv.get(mk, m[1])
            if mv["new"] >= lim:
                raise Refused("family %s: %s would take %d, at or past its end marker %s = %d "
                              "(bead inc-pu6v.478.7)" % (mv["fam"], mv["name"], mv["new"], mk, lim))


def plan(base, tree, retired, root=None):
    """Return a list of moves. A move is a dict: fam, name, old, new, file, line,
    shape, sentinel (bool). Raises Refused."""
    moves = []
    for fam in sorted(tree):
        t = tree[fam]
        if t["class"] != "stored":
            continue
        ret = dict(retired.get(fam, []))
        hits = csv.family_collisions(t, base.get(fam, {}), ret)
        if not hits:
            continue
        shape, width = t["shape"], t["width"]
        sent = set(t["sentinels"])
        grows = set(t.get("grows", []))
        tvals = {}
        for m in t["members"]:
            tvals.setdefault(m[0], m)
        marked = sent | grows | set(t.get("bounds", []))
        if shape != "bits":
            held_by = sorted({h[2] for h in hits if END_MARKER.search(h[2]) and h[2] not in marked})
            if held_by:
                raise Refused("family %s: the value of a tree name is held by %s, which looks like "
                              "an end-of-table marker but the family mark does not say so. An end "
                              "marker is no taken value: add `sentinel`, `grows` or `bound` %s to "
                              "the mark of family %s first (bead inc-pu6v.478.7)"
                              % (fam, ", ".join(held_by), held_by[0], fam))
        names = {}
        for name, m, _hn, _hv, _why in hits:
            names[name] = m
        order = sorted(names, key=lambda n: (names[n][2], names[n][3]))
        merged = [m[1] for m in base.get(fam, {}).get("members", [])
                  if m[0] not in sent and m[0] not in grows]
        merged += [m[1] for n, m in tvals.items() if n not in sent and n not in grows]
        merged += list(ret.values())
        if shape == "bits":
            held = 0
            for v in merged:
                held |= csv.pattern(v, width)
            # A family that shares a member name with this one shares its word: its
            # members hold bits of this word too (sc and sc_all).
            mine = {m[0] for m in t["members"]} | {m[0] for m in base.get(fam, {}).get("members", [])}
            for other in sorted(set(tree) | set(base)):
                if other == fam:
                    continue
                om = (tree.get(other, {}).get("members", []) + base.get(other, {}).get("members", []))
                if any(m[0] in mine for m in om):
                    for m in om:
                        held |= csv.pattern(m[1], width)
            for name in order:
                free = [k for k in range(csv.BITS[width]) if not (held >> k) & 1]
                if not free:
                    raise Refused("family %s: the %s word is full, no free bit for %s "
                                  "(bead inc-xm3nq)" % (fam, width, name))
                new = 1 << free[0]
                held |= new
                moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                                  file=names[name][2], line=names[name][3],
                                  shape=shape, sentinel=False))
            continue
        if t.get("block"):
            # `block <N>`: a moved value stays in its own block of N. No `grows` or
            # `bound` placement, and no limit move (bead inc-cjos0).
            taken = set(merged)
            for name in order:
                lo = names[name][1] // t["block"] * t["block"]
                free = [v for v in range(lo, lo + t["block"]) if v not in taken]
                if not free:
                    raise Refused("family %s: block %d is full, no free value for %s "
                                  "(bead inc-cjos0)" % (fam, lo, name))
                new = free[0]
                if not csv.fits(new, shape, width):
                    raise Refused("family %s: %s would take %d, which does not fit %s "
                                  "(bead inc-xm3nq)" % (fam, name, new, width))
                taken.add(new)
                moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                                  file=names[name][2], line=names[name][3],
                                  shape=shape, sentinel=False))
            continue
        glim = grow_limit(base.get(fam, {}), tvals, grows)
        if glim is not None:
            # A `grows` family: a moved value takes the first free index at or above
            # the base's limit. A base member at or above that limit (A_HIT.., SL_ARCHERY)
            # is no index: it is reserved, and reaching one refuses.
            taken = set(merged)
            reserved = {m[1]: m[0] for m in base.get(fam, {}).get("members", [])
                        if m[0] not in sent and m[0] not in grows and m[1] >= glim}
            top = -1
            for name in order:
                new = glim
                while new in taken:
                    if new in reserved:
                        raise Refused("family %s: no free index at or above the limit %s = %d "
                                      "for %s; the next one is the reserved member %s = %d "
                                      "(bead inc-cjos0)" % (fam, ",".join(sorted(grows)),
                                                            glim, name, reserved[new], new))
                    new += 1
                if new in reserved:
                    raise Refused("family %s: the next free index %d for %s is the reserved "
                                  "member %s above the limit %s = %d (bead inc-cjos0)"
                                  % (fam, new, name, reserved[new], ",".join(sorted(grows)),
                                     glim))
                if not csv.fits(new, shape, width):
                    raise Refused("family %s: %s would take %d, which does not fit %s "
                                  "(bead inc-xm3nq)" % (fam, name, new, width))
                taken.add(new)
                top = max(top, new)
                moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                                  file=names[name][2], line=names[name][3],
                                  shape=shape, sentinel=False))
            for g in sorted(grows):
                m = tvals.get(g)
                if m is not None and m[1] < top + 1:
                    if not csv.fits(top + 1, shape, width):
                        raise Refused("family %s: the limit %s would take %d, which does not "
                                      "fit %s (bead inc-xm3nq)" % (fam, g, top + 1, width))
                    moves.append(dict(fam=fam, name=g, old=m[1], new=top + 1, file=m[2],
                                      line=m[3], shape=shape, sentinel=True, grows=True))
            continue
        bounds = [tvals[b][1] for b in t.get("bounds", []) if b in tvals and b not in grows]
        lim = min(bounds) if bounds else None
        below = [v for v in merged if lim is None or v < lim]
        taken = set(merged)
        mx = max(below, default=-1)
        for name in order:
            new = mx + 1
            if lim is not None and new >= lim:
                free = [v for v in range(lim - 1, min(below, default=0) - 1, -1)
                        if v not in taken]
                if not free:
                    raise Refused("family %s: no free value below the bound %s = %d for %s "
                                  "(bead inc-xm3nq)" % (fam, ",".join(t["bounds"]), lim, name))
                new = free[0]
            else:
                mx = new
            if not csv.fits(new, shape, width):
                raise Refused("family %s: %s would take %d, which does not fit %s "
                              "(bead inc-xm3nq)" % (fam, name, new, width))
            taken.add(new)
            moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                              file=names[name][2], line=names[name][3],
                              shape=shape, sentinel=False))
        for s in t["sentinels"]:
            m = tvals.get(s)
            if m is not None and alias_note(root, m) is not None:
                continue    # an alias of the last member: alias_moves() sets it
            if m is not None and m[1] != mx + 1:
                moves.append(dict(fam=fam, name=s, old=m[1], new=mx + 1, file=m[2],
                                  line=m[3], shape=shape, sentinel=True))
        for g in sorted(grows):
            m = tvals.get(g)
            if m is not None and m[1] < mx + 1:
                if not csv.fits(mx + 1, shape, width):
                    raise Refused("family %s: the limit %s would take %d, which does not fit "
                                  "%s (bead inc-xm3nq)" % (fam, g, mx + 1, width))
                moves.append(dict(fam=fam, name=g, old=m[1], new=mx + 1, file=m[2],
                                  line=m[3], shape=shape, sentinel=True, grows=True))
    moves += alias_moves(tree, moves, root)
    moves += repair_moves(base, tree, retired, root, {mv["fam"] for mv in moves})
    bound_guard(tree, moves, root)
    return moves


# ---------------------------------------------------------------- editing

def split_comment(line):
    """Return (code, gap, comment) of a line without its newline."""
    idx = [i for i in (line.find("//"), line.find("/*")) if i >= 0]
    cut = min(idx) if idx else len(line)
    code = line[:cut].rstrip()
    return code, line[len(code):cut], line[cut:]


def edit_define(lines, mv):
    """Rewrite the value of a #define in lines (a list, edited in place).
    Return the old expression text when it was not a plain literal, else None."""
    ln = lines[mv["line"] - 1]
    eol = "\r" if ln.endswith("\r") else ""
    core = ln[:-1] if eol else ln
    m = re.match(r"^(\s*#\s*define\s+%s\s+)(.*)$" % re.escape(mv["name"]), core)
    if not m:
        raise Refused("%s:%d: %s is not a plain `#define %s <value>` line"
                      % (mv["file"], mv["line"], mv["name"], mv["name"]))
    if core.rstrip().endswith("\\"):
        raise Refused("%s:%d: %s continues on the next line; edit it by hand"
                      % (mv["file"], mv["line"], mv["name"]))
    code, gap, comment = split_comment(m.group(2))
    body = code.strip()
    fmt = "0x%X" if mv["shape"] == "bits" else "%d"
    if mv.get("alias") and mv["alias_off"] == 0:
        comment = ALIAS_NAME.sub(r"\g<1>" + mv["alias"], comment)
    lines[mv["line"] - 1] = m.group(1) + (fmt % mv["new"]) + gap + comment + eol
    if mv.get("alias") and mv["alias_off"] == -1:
        lines[mv["line"] - 2] = ALIAS_NAME.sub(r"\g<1>" + mv["alias"], lines[mv["line"] - 2])
    return None if LITERAL.fullmatch(body) else body


def parse_enum_line(text, no, name, path):
    eol = "\r" if text.endswith("\r") else ""
    core = text[:-1] if eol else text
    code, gap, comment = split_comment(core)
    m = ENUM_LINE.match(code)
    if not m or m.group(2) != name:
        raise Refused("%s:%d: the enumerator %s does not sit alone on its line; edit "
                      "the enum by hand" % (path, no, name))
    return dict(indent=m.group(1), name=name, expr=m.group(3), comma=bool(m.group(4)),
                gap=gap, comment=comment, eol=eol)


def build_enum_line(p):
    return (p["indent"] + p["name"] + (" = %s" % p["expr"] if p["expr"] is not None else "")
            + ("," if p["comma"] else "") + p["gap"] + p["comment"] + p["eol"])


def edit_enum(text, path, name, newv, vals, mode, sent_want, alias_want=None):
    """Edit the enum that holds name. mode 'move': take the line to the end of the
    enum (before trailing sentinel names) with `= newv`. mode 'set': give name the
    value newv in place. vals: {enumerator: value}, updated. sent_want: {sentinel
    name: wanted value}. Return (new text, [(follower, value)])."""
    if mode == "set" and vals.get(name) == newv:
        return text, []
    lines = text.split("\n")
    hit = None
    for _first, _last, members in cdd.find_enums(cdd.strip_comments(text)):
        if any(m[1] == name for m in members):
            hit = members
            break
    if hit is None:
        raise Refused("%s: cannot find the enum that holds %s" % (path, name))
    if len({m[0] for m in hit}) != len(hit):
        raise Refused("%s: two enumerators of the enum holding %s share a line; edit it "
                      "by hand" % (path, name))
    line_of = {m[1]: m[0] for m in hit}
    parsed = {m[1]: parse_enum_line(lines[m[0] - 1], m[0], m[1], path) for m in hit}
    order = [m[1] for m in hit]
    last_comma = parsed[order[-1]]["comma"]
    new_order = list(order)
    anchor, after = None, True
    if mode == "move":
        new_order.remove(name)
        pos = len(new_order)
        while pos > 0 and new_order[pos - 1] in sent_want:
            pos -= 1
        if pos > 0:
            anchor = line_of[new_order[pos - 1]]
        elif new_order:
            anchor, after = line_of[new_order[0]], False
        new_order.insert(pos, name)
    followers = []
    prev = -1
    for i, nm in enumerate(new_order):
        p = parsed[nm]
        if nm == name:
            want = newv
            p["expr"] = str(newv) if (mode == "move" or p["expr"] is not None
                                      or prev + 1 != newv) else None
        elif nm in sent_want:
            want = sent_want[nm]
            cur = prev + 1 if p["expr"] is None else vals[nm]
            if cur != want:
                p["expr"] = str(want)
            if alias_want and nm in alias_want:
                p["comment"] = ALIAS_NAME.sub(r"\g<1>" + alias_want[nm], p["comment"])
        else:
            want = vals[nm]
            if p["expr"] is None and prev + 1 != want:
                p["expr"] = str(want)
                followers.append((nm, want))
        p["comma"] = (i < len(new_order) - 1) or last_comma
        prev = want
        vals[nm] = want
    for nm in order:
        lines[line_of[nm] - 1] = build_enum_line(parsed[nm])
    if mode == "move" and anchor is not None:
        moved = lines[line_of[name] - 1]
        del lines[line_of[name] - 1]
        ai = anchor - 1 - (1 if anchor > line_of[name] else 0)
        lines.insert(ai + 1 if after else ai, moved)
    return "\n".join(lines), followers


def locate(text, name, shape):
    pat = (r"^\s*%s\b" % re.escape(name) if shape == "enum"
           else r"^\s*#\s*define\s+%s\b" % re.escape(name))
    for no, ln in enumerate(text.split("\n"), 1):
        if re.match(pat, ln):
            return no
    return 0


def apply_moves(root, moves, vals):
    """Edit the files in memory, write them all only when every edit worked.
    Return the report lines."""
    texts = {}

    def get(path):
        if path not in texts:
            with open(os.path.join(root, path), encoding="latin-1", newline="") as f:
                texts[path] = f.read()
        return texts[path]
    report, notes = [], {}
    by_fam = {}
    for mv in moves:
        by_fam.setdefault(mv["fam"], []).append(mv)
    for fam, ms in sorted(by_fam.items()):
        sent_want = {m["name"]: m["new"] for m in ms if m["sentinel"]}
        alias_want = {m["name"]: m["alias"] for m in ms if m.get("alias")}
        for mv in sorted(ms, key=lambda m: (m["sentinel"], m["file"], m["line"])):
            text = get(mv["file"])
            if mv["shape"] == "enum":
                mode = "set" if mv["sentinel"] else "move"
                text, fol = edit_enum(text, mv["file"], mv["name"], mv["new"], vals, mode,
                                      sent_want, alias_want)
                texts[mv["file"]] = text
                for nm, v in fol:
                    notes[(fam, nm)] = (v, mv["file"])
            else:
                lines = text.split("\n")
                expr = edit_define(lines, mv)
                texts[mv["file"]] = "\n".join(lines)
                vals[mv["name"]] = mv["new"]
                if expr:
                    notes[(fam, mv["name"])] = expr
    for path, text in texts.items():
        with open(os.path.join(root, path), "w", encoding="latin-1", newline="") as f:
            f.write(text)
    for mv in sorted(moves, key=lambda m: (m["fam"], m["file"], m["line"])):
        line = locate(texts[mv["file"]], mv["name"], mv["shape"])
        s = "%s %s %d -> %d %s:%d" % (mv["fam"], mv["name"], mv["old"], mv["new"],
                                      mv["file"], line)
        n = notes.get((mv["fam"], mv["name"]))
        if isinstance(n, str):
            s += "  [the expression `%s` is now a literal]" % n
        if mv["sentinel"]:
            s += "  [grows]" if mv.get("grows") else "  [sentinel]"
        report.append(s)
    for (fam, nm), val in sorted(notes.items(), key=lambda kv: str(kv[0])):
        if isinstance(val, tuple):
            file = val[1]
            report.append("%s %s %d -> %d %s:%d  [explicit value, because a move shifted it]"
                          % (fam, nm, val[0], val[0], file, locate(texts[file], nm, "enum")))
    return report


# ---------------------------------------------------------------- the run

def git(root, *args):
    r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise csv.Unmeasured("git %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout.strip()


def run_move(root, ref, dry, use_compiler=True, out=print):
    branch = git(root, "rev-parse", "--abbrev-ref", "HEAD")
    head = git(root, "rev-parse", "HEAD")
    base_commit = git(root, "rev-parse", "--verify", ref + "^{commit}")
    if branch == ref or head == base_commit:
        out("move_branch_values: no-op on %s" % ref)
        return 0
    base, tree, problems, retired, _kept = csv.measure(ref, root, use_compiler)
    moves = plan(base, tree, retired, root)
    vals = {m[0]: m[1] for d in tree.values() for m in d["members"]}
    if dry:
        for mv in sorted(moves, key=lambda m: (m["fam"], m["file"], m["line"])):
            out("%s %s %d -> %d %s:%d%s" % (mv["fam"], mv["name"], mv["old"], mv["new"],
                                            mv["file"], mv["line"],
                                            "  [%s]" % ("grows" if mv.get("grows") else "sentinel")
                                            if mv["sentinel"] else ""))
        out("move_branch_values: dry run, would move %d value(s)" % len(moves))
        return 0
    for line in apply_moves(root, moves, vals):
        out(line)
    out("move_branch_values: moved %d value(s)" % len(moves))
    if not moves:
        return 0
    base, tree, problems, retired, _kept = csv.measure(ref, root, use_compiler)
    msgs, _n = csv.compare(base, tree, problems, retired)
    if msgs:
        out("move_branch_values: check_stored_values still fails after the moves:")
        for m in msgs:
            out("  " + m)
        return 1
    return 0


# ---------------------------------------------------------------- selftest

def selftest():
    tmp = tempfile.mkdtemp(prefix="move_selftest.")

    def fam(name, body, cls="stored ordinal u8"):
        return "// family: %s %s\n%s// end family: %s\n" % (name, cls, body, name)

    def g(d, *args):
        subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t",
                        "-c", "core.hooksPath=/dev/null"] + list(args),
                       check=True, capture_output=True)

    def mkrepo(base, tree, retired=""):
        d = tempfile.mkdtemp(dir=tmp)
        os.makedirs(os.path.join(d, "inc"))
        os.makedirs(os.path.join(d, "tools"))
        defs, ret = os.path.join(d, "inc", "Defines.h"), os.path.join(d, "tools",
                                                                      "retired_values.txt")
        with open(defs, "w") as f:
            f.write(base)
        with open(ret, "w") as f:
            f.write(retired)
        g(d, "init", "-q", "-b", "master")
        g(d, "add", "-A")
        g(d, "commit", "-q", "-m", "base")
        g(d, "checkout", "-q", "-b", "feat")
        with open(defs, "w") as f:
            f.write(tree)
        g(d, "commit", "-qam", "tree")
        return d, defs

    def read(p):
        with open(p) as f:
            return f.read()

    def check(d, ref="master"):
        base, tree, problems, retired, _k = csv.measure(ref, d, False)
        return csv.compare(base, tree, problems, retired)[0]

    def case(label, base, tree, retired="", want=None, code=0, grep=(), dry=False, dups=False):
        print("case: " + label)
        d, defs = mkrepo(base, tree, retired)
        before = check(d)
        assert before, "case must start RED"
        print("  RED   " + before[0][:110])
        out = []
        try:
            c = run_move(d, "master", dry, False, out.append)
        except Refused as e:
            c = 1
            out.append("REFUSED: %s" % e)
        text = "\n".join(out)
        assert c == code, (label, c, text)
        for s in grep:
            assert s in text, (label, s, text)
        if code == 0 and not dry:
            assert check(d) == [], (label, check(d))
            if dups:
                c2, m2 = cdd.check(defs)
                assert c2 == 0, (label, m2)
            print("  GREEN " + out[0])
        elif code == 0:
            assert read(defs) == tree, label
            print("  GREEN dry run wrote nothing: " + out[0])
        else:
            assert read(defs) == tree, label
            print("  GREEN refused, file untouched: " + out[0][:100])
        if want is not None:
            assert read(defs) == want, (label, read(defs))
        return d

    try:
        b = fam("stati", "#define A_X 1\n#define A_Y 2\n")
        case("ordinal collision cleared, base untouched", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2 /* x */\n"),
             want=fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 3 /* x */\n"),
             grep=["stati A_Z 2 -> 3 inc/Defines.h:4"])
        bits = "stored bits u16"
        case("bit collision cleared, expression becomes a literal",
             fam("f", "#define F_A 1\n#define F_B 4\n", bits),
             fam("f", "#define F_A 1\n#define F_B 4\n#define F_C (1 << 2)\n", bits),
             want=fam("f", "#define F_A 1\n#define F_B 4\n#define F_C 0x2\n", bits),
             grep=["f F_C 4 -> 2", "(1 << 2)"])
        en = "stored enum i32"
        eb = fam("e", "enum {\n    E_A,\n    E_B,\n    E_C\n};\n", en)
        case("enum collision cleared, follower made explicit, base values kept", eb,
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 8,    // new\n"
                      "    E_F\n};\n", en),
             retired="e E_R 8\n",
             want=fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_F = 9,\n"
                           "    E_D = 10    // new\n};\n", en),
             grep=["e E_D 8 -> 10", "e E_F 9 -> 9", "explicit value"])
        es = "stored enum i32 sentinel E_LAST"
        case("enum collision stops before the sentinel, sentinel at max+1",
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_LAST\n};\n", es),
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 1,\n    E_LAST\n};\n",
                 es),
             want=fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 3,\n"
                           "    E_LAST\n};\n", es),
             grep=["e E_D 1 -> 3"])
        sca = "".join("#define S_%d 0x%X\n" % (k, 1 << k) for k in range(2))
        scb = "".join("#define S_%d 0x%X\n" % (k, 1 << k) for k in range(2, 8))
        sct = "// family: s_all internal\n" + scb + "// end family: s_all\n"
        scf = "// family: s stored bits u8, s_all internal\n" + sca + "// end family: s, s_all\n"
        case("an overlapping internal family holds the free bits: the mover refuses",
             scf + sct,
             scf.replace(sca, sca + "#define S_GA 0x2\n") + sct,
             code=1, grep=["family s", "inc-xm3nq"])
        full = "".join("#define F_%d 0x%X\n" % (k, 1 << k) for k in range(8))
        case("a full bit word refuses",
             fam("f", full, "stored bits u8"),
             fam("f", full + "#define F_N 0x80\n", "stored bits u8"),
             code=1, grep=["word is full", "family f"])
        case("a value past the storage width refuses and names inc-xm3nq",
             fam("a", "#define A_X 255\n"), fam("a", "#define A_X 255\n#define A_Z 255\n"),
             code=1, grep=["family a", "inc-xm3nq"])
        ss = "stored ordinal u8 sentinel T_LAST"
        case("the sentinel is rewritten to max+1",
             fam("t", "#define T_X 1\n#define T_Y 2\n#define T_LAST 3\n", ss),
             fam("t", "#define T_X 1\n#define T_Y 2\n#define T_Z 2\n#define T_LAST 3\n", ss),
             want=fam("t", "#define T_X 1\n#define T_Y 2\n#define T_Z 3\n#define T_LAST 4\n",
                      ss),
             grep=["t T_LAST 3 -> 4", "[sentinel]"])
        sa = "stored ordinal i8 sentinel X_TRUELAST"
        case("an alias sentinel equals the new top and names the moved member",
             fam("x", "#define X_A 1\n#define X_TOP 2\n#define X_TRUELAST 2 /* alias of X_TOP */\n",
                 sa),
             fam("x", "#define X_A 1\n#define X_TOP 2\n#define X_N 2\n"
                      "#define X_TRUELAST 2 /* alias of X_TOP */\n", sa),
             want=fam("x", "#define X_A 1\n#define X_TOP 2\n#define X_N 3\n"
                           "#define X_TRUELAST 3 /* alias of X_N */\n", sa),
             grep=["x X_TRUELAST 2 -> 3", "[sentinel]"], dups=True)
        def two(body):
            return ("// family: x stored ordinal i8 sentinel X_TRUELAST sentinel Y_TRUELAST, "
                    "y stored ordinal i8 sentinel Y_TRUELAST sentinel X_TRUELAST\n" + body
                    + "// end family: x, y\n")
        al = ("#define X_TRUELAST 2 /* alias of X_TOP */\n"
              "#define Y_TRUELAST 2 /* alias of X_TOP */\n")
        al2 = ("#define X_TRUELAST 3 /* alias of X_N */\n"
               "#define Y_TRUELAST 3 /* alias of X_N */\n")
        case("an alias sentinel named by two families moves once, to the top",
             two("#define X_A 1\n#define X_TOP 2\n" + al),
             two("#define X_A 1\n#define X_TOP 2\n#define X_N 2\n" + al),
             want=two("#define X_A 1\n#define X_TOP 2\n#define X_N 3\n" + al2),
             grep=["X_TRUELAST 2 -> 3", "Y_TRUELAST 2 -> 3"], dups=True)
        case("two colliding tree names get two distinct values", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n#define A_W 2\n"),
             want=fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 3\n"
                               "#define A_W 4\n"))
        case("a retired value is not reused", fam("stati", "#define A_X 1\n"),
             fam("stati", "#define A_X 1\n#define A_Z 1\n"), retired="stati A_OLD 2\n",
             want=fam("stati", "#define A_X 1\n#define A_Z 3\n"))
        case("--dry-run writes nothing", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"), dry=True,
             grep=["stati A_Z 2 -> 3", "would move 1"])
        bd = "stored ordinal u16 bound O_LAST"
        case("a bound: the next value is taken while it is below the bound",
             fam("o", "#define O_X 1\n#define O_Y 3\n#define O_LAST 5\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 3\n#define O_Z 3\n#define O_LAST 5\n", bd),
             want=fam("o", "#define O_X 1\n#define O_Y 3\n#define O_Z 4\n#define O_LAST 5\n",
                      bd))
        case("a bound: no value at or above it, the highest free one below it",
             fam("o", "#define O_X 1\n#define O_Y 4\n#define O_LAST 5\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 4\n#define O_Z 4\n#define O_LAST 5\n", bd),
             want=fam("o", "#define O_X 1\n#define O_Y 4\n#define O_Z 3\n#define O_LAST 5\n",
                      bd),
             grep=["o O_Z 4 -> 3"])
        case("a bound with no free value below it refuses naming the family",
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_LAST 3\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_Z 2\n#define O_LAST 3\n", bd),
             code=1, grep=["family o", "no free value below the bound O_LAST = 3"])
        gw = "stored ordinal u8 grows G_LAST"
        case("a grows limit: a moved value takes the old limit value, the limit rises",
             fam("g", "#define G_X 1\n#define G_Y 2\n#define G_LAST 3\n", gw),
             fam("g", "#define G_X 1\n#define G_Y 2\n#define G_Z 2\n#define G_LAST 3\n", gw),
             want=fam("g", "#define G_X 1\n#define G_Y 2\n#define G_Z 3\n#define G_LAST 4\n",
                      gw),
             grep=["g G_Z 2 -> 3", "g G_LAST 3 -> 4", "[grows]"])
        case("a grows limit already above the moved value is left alone",
             fam("g", "#define G_X 1\n#define G_Y 2\n#define G_LAST 3\n", gw),
             fam("g", "#define G_X 1\n#define G_Y 2\n#define G_Z 2\n#define G_LAST 9\n", gw),
             want=fam("g", "#define G_X 1\n#define G_Y 2\n#define G_Z 3\n#define G_LAST 9\n",
                      gw))
        gbd = "stored ordinal u16 bound O_LAST grows O_LAST"
        case("a bound that also grows rises instead of refusing",
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_LAST 3\n", gbd),
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_Z 2\n#define O_LAST 3\n", gbd),
             want=fam("o", "#define O_X 1\n#define O_Y 2\n#define O_Z 3\n#define O_LAST 4\n",
                      gbd),
             grep=["o O_Z 2 -> 3", "o O_LAST 3 -> 4"])
        sk = "stored ordinal i16 grows SK_HIGH_END"
        hf = fam("sk_high_first", "#define SK_HIGH_FIRST 800\n",
                 "stored ordinal i16 sentinel SK_HIGH_FIRST")
        case("the skill shape: a colliding high skill moves, SK_HIGH_END rises, SK_LASTSKILL stays",
             fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n#define SK_GRWA 800\n"
                       "#define SK_HIGH_END 801\n", sk) + hf,
             fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n#define SK_GRWA 800\n"
                       "#define SK_GRWB 800\n#define SK_HIGH_END 801\n", sk) + hf,
             want=fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n#define SK_GRWA 800\n"
                            "#define SK_GRWB 801\n#define SK_HIGH_END 802\n", sk) + hf,
             grep=["sk SK_GRWB 800 -> 801", "sk SK_HIGH_END 801 -> 802"])
        at = "stored ordinal i8 grows T_LAST"
        case("gap 6: a grows family takes the first free index, not past a reserved member",
             fam("at", "#define T_X 1\n#define T_Y 2\n#define T_LAST 3\n#define T_HIT 50\n"
                       "#define T_MAG 55\n", at),
             fam("at", "#define T_X 1\n#define T_Y 2\n#define T_Z 2\n#define T_LAST 3\n"
                       "#define T_HIT 50\n#define T_MAG 55\n", at),
             want=fam("at", "#define T_X 1\n#define T_Y 2\n#define T_Z 3\n#define T_LAST 4\n"
                            "#define T_HIT 50\n#define T_MAG 55\n", at),
             grep=["at T_Z 2 -> 3", "at T_LAST 3 -> 4"])
        bk = "stored ordinal u8 bound X_LAST grows X_LAST block 10"
        case("block <N>: a moved value takes the lowest free value of its own block, the limit stays",
             fam("x", "#define X_A 10\n#define X_E 12\n#define X_D 20\n#define X_LAST 30\n", bk),
             fam("x", "#define X_A 10\n#define X_E 12\n#define X_Z 12\n#define X_D 20\n"
                      "#define X_LAST 30\n", bk),
             want=fam("x", "#define X_A 10\n#define X_E 12\n#define X_Z 11\n#define X_D 20\n"
                           "#define X_LAST 30\n", bk),
             grep=["x X_Z 12 -> 11"])
        full = "".join("#define X_M%d %d\n" % (v, v) for v in range(10, 20))
        case("block <N>: a full block refuses, naming the family and the block",
             fam("x", full + "#define X_LAST 30\n", bk),
             fam("x", full + "#define X_Z 12\n#define X_LAST 30\n", bk),
             code=1, grep=["family x", "block 10", "is full", "X_Z"])
        case("gap 6: a move that reaches a reserved member refuses",
             fam("at", "#define T_X 1\n#define T_Y 2\n#define T_LAST 3\n#define T_HIT 4\n", at),
             fam("at", "#define T_X 1\n#define T_Y 2\n#define T_Z 2\n#define T_W 2\n"
                       "#define T_LAST 3\n#define T_HIT 4\n", at),
             code=1, grep=["family at", "T_LAST = 3", "reserved member T_HIT = 4"])
        # inc-pu6v.478.7: master's end marker B_LAST 2 is no taken value. The old tool moved
        # B_S to 4, past the tree's own marker B_LAST 3 (the BONUS_SSIGHT 41 incident).
        um = "stored ordinal i32"
        case("an unmarked end marker that holds a collision refuses and names the marker",
             fam("u", "#define B_X 1\n#define B_LAST 2\n", um),
             fam("u", "#define B_X 1\n#define B_S 2\n#define B_LAST 3\n", um),
             code=1, grep=["family u", "held by B_LAST", "end-of-table marker"])
        ms = "stored ordinal i32 sentinel B_LAST"
        d, defs = mkrepo(fam("u", "#define B_X 1\n#define B_LAST 2\n", um),
                         fam("u", "#define B_X 1\n#define B_S 2\n#define B_LAST 3\n", ms))
        assert check(d) == [], "marked, the base marker is no taken value"
        print("  GREEN a marked marker raises no collision: " + um)
        rp = "stored ordinal i32 sentinel B_LAST"
        case("a member past its marker with no collision is moved back below it",
             fam("u", "#define B_X 1\n#define B_LAST 2\n", rp),
             fam("u", "#define B_X 1\n#define B_S 3\n#define B_LAST 3\n", rp),
             want=fam("u", "#define B_X 1\n#define B_S 2\n#define B_LAST 3\n", rp),
             grep=["u B_S 3 -> 2"])
        case("a member past its marker with no free value below it refuses",
             fam("u", "#define B_X 1\n#define B_LAST 2\n", rp),
             fam("u", "#define B_X 1\n#define B_S 2\n#define B_T 2\n#define B_LAST 2\n", rp),
             code=1, grep=["family u", "end marker"])
        mv_in = [dict(fam="u", name="B_S", old=2, new=3, file="inc/Defines.h", line=1,
                      shape="ordinal", sentinel=False)]
        bf = {"u": dict(class_="x", sentinels=["B_LAST"], bounds=[],
                        members=[("B_S", 2, "inc/Defines.h", 1), ("B_LAST", 3, "inc/Defines.h", 2)])}
        bf["u"]["class"] = "stored"
        try:
            bound_guard(bf, mv_in, None)
            raise AssertionError("bound_guard let a value reach its end marker")
        except Refused as e:
            assert "end marker B_LAST = 3" in str(e), e
        print("  GREEN bound_guard refuses a moved value at its end marker")
        print("case: no-op on master")
        d, defs = mkrepo(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"))
        g(d, "checkout", "-q", "master")
        with open(defs, "w") as f:
            f.write(fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"))
        before = read(defs)
        out = []
        assert run_move(d, "master", False, False, out.append) == 0 and "no-op on master" in out[0]
        assert read(defs) == before
        print("  GREEN " + out[0])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("move_branch_values: selftest PASS")
    return 0


def main(argv):
    ref, dry, st = "master", False, False
    it = iter(argv)
    for a in it:
        if a == "--base":
            ref = next(it, None)
            if ref is None:
                print("--base needs a ref", file=sys.stderr)
                return 2
        elif a == "--dry-run":
            dry = True
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    if st:
        return selftest()
    try:
        return run_move(ROOT, ref, dry)
    except Refused as e:
        print("move_branch_values: REFUSED: %s" % e, file=sys.stderr)
        return 1
    except (csv.Unmeasured, cdd.Unmeasurable) as e:
        print("move_branch_values: UNMEASURED: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
