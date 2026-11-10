#!/usr/bin/env python3
"""Search the values of the rolls a dump shows only through their results
(bead inc-10v7f, phase 11g; the owner's ruling of 2026-11-09; phase 11h).

ponytail: with tools/char_convert.sh this stays only until the epic conversion
lands (inc-pu6v.369). The ceiling: it tries every combination of the recorded
unseen rolls and refuses a space of more than --max tries; it prunes nothing.

A script's draw and an effect's damage roll are decisions whose value an old
dump shows only through what they made (an item's quality, a stat, a stati).
The walk that recorded the skeleton wrote, beside the .char, a `.rolls` file:
for each such roll, in the order made, the key, context, ordinal in that
(key, context) queue, and the inclusive range the game's own code fixes (the
UNSEEN column of CREATION_KEY_LIST, inc/CreationSource.h). This tool holds no
key name and no range: both come from that file and that column.

Usage: tools/char_roll_search.py selftest   (the verdict rules and the multiset difference; exit 0 all hold)
       tools/char_roll_search.py <skeleton.char> <rolls> <old.canon> <prefix>
           <keys> <seed> <options> <skip|-> <tick|-> <stream|-> [--max N]
  A roll's value can change which decisions the game asks next (an item the
  script now makes), so each combination is a whole conversion: the skeleton
  with those values, the lines the build then misses added with their table
  default (placed by ask number) and the lines it no longer asks for removed,
  built and replayed (tools/char_arrive.sh),
  converted from the old dump (tools/char_convert_map.py), built and replayed
  again, and compared with <old.canon> outside the allowlist of
  tools/canon_compare.py. Every combination is tried, the first roll in the file
  the most significant digit and each digit from its lowest value. D(c) is the
  multiset of differing lines of combination c (a collections.Counter of the
  lines of each filtered dump; no alignment of the two dumps). A line that
  differs in EVERY completed combination is a difference no roll explains (a
  rule that changed): the common core of all D(c). A combination MATCHES when
  its D(c) is that core and nothing more, so every line that any roll can change
  agrees with the old dump. The lowest matching combination is kept; every other
  match is listed. A combination that does not build or does not convert is
  listed and never matches.
  The search claims a result only when it can. Fewer than two completed
  combinations is "not searched": one combination has no core to compare
  against. A build that added the line of an UNSEEN key with its table default
  (a roll the walk never made, so it has no range) leaves that value unsearched,
  and the fixture is named "not searched".
Writes <prefix>.char (the converted .char of the kept combination; on a match
only), <prefix>.txt (the record), <prefix>-values.txt and <prefix>-unset.txt
(the values the kept conversion set and left unset; on a match only), and
<prefix>-unresolved.txt (when nothing was resolved: one line per searched roll,
the walk's value kept as recorded, with the reason and the tied candidates).
Prints a one-line result.
Exit: 0 a combination matched; 1 none matched (the walk's values are kept and
named unresolved); 2 none built, or it could not run; 3 the space exceeds --max
(default 500; nothing is tried); 4 nothing to search; 5 not searched (fewer than
two combinations completed, or a build added an UNSEEN key's line with its
default).
"""
import collections
import itertools
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import canon_compare   # noqa: E402  (the one allowlist)

CHAR_LINE = re.compile(r"^([a-z][a-z0-9_]*)(?: \[([^\]]*)\])?: ?(.*)$")


def fail(msg, code=2):
    print("char_roll_search: %s" % msg, file=sys.stderr)
    sys.exit(code)


def unseen_keys():
    """The lower-case names of the keys whose UNSEEN column is set in CREATION_KEY_LIST."""
    text = open(os.path.join(ROOT, "inc", "CreationSource.h"), errors="replace").read()
    return {m.group(1).lower() for m in re.finditer(r"X\((\w+),\s*(?:ROLL|PICK|ITEM),[^\n]*,\s*UNSEEN\)", text)}


def read_rolls(path, lines):
    """[(key, ctx, ordinal, lo, hi, line index)] in the order made."""
    where, count = {}, {}
    for i, l in enumerate(lines):
        m = CHAR_LINE.match(l)
        if m:
            k, c = m.group(1), m.group(2) or ""
            n = count.get((k, c), 0)
            count[(k, c)] = n + 1
            where[(k, c, n)] = i
    out = []
    for raw in open(path).read().split("\n"):
        if not raw.strip():
            continue
        f = raw.split("\t")
        if len(f) != 5:
            fail("%s: not a rolls line: %r" % (path, raw))
        key, ctx, ordinal, lo, hi = f[0], f[1], int(f[2]), int(f[3]), int(f[4])
        label = "%s%s #%d" % (key, " [%s]" % ctx if ctx else "", ordinal)
        if lo > hi:
            fail("%s: the game gave the roll no range, so it cannot be searched" % label, 1)
        i = where.get((key, ctx, ordinal))
        if i is None:
            fail("%s: the skeleton has no such line" % label)
        out.append((key, ctx, ordinal, lo, hi, i))
    return out


def diff_lines(built_canon, old_canon):
    """D(c): the multiset of lines on one side of the filtered dumps and not on the other
    (a line only in the build is prefixed "-", a line only in the old dump "+", as canon_compare prints them)."""
    a = collections.Counter(canon_compare.filtered(built_canon))
    b = collections.Counter(canon_compare.filtered(old_canon))
    out = collections.Counter()
    for l, n in (a - b).items():
        out["-" + l] = n
    for l, n in (b - a).items():
        out["+" + l] = n
    return out


def ctx_of(line):
    m = CHAR_LINE.match(line)
    return (m.group(2) or "") if m else ""


def key_of(line):
    m = CHAR_LINE.match(line)
    return m.group(1) if m else None


def insert_line(lines, new):
    """Put a line the build asked for next to its kin: before the first line of
    the same key and resource with a higher ask number (a<N>), else after the
    last line of that key and resource, else after the last line of the key."""
    m = CHAR_LINE.match(new)
    key, ctx = m.group(1), m.group(2) or ""
    res, _, rest = ctx.partition(";")
    am = re.match(r"^a(\d+)$", rest)
    same = [i for i, l in enumerate(lines) if key_of(l) == key and ctx_of(l).partition(";")[0] == res]
    if am:
        for i in same:
            bm = re.match(r"^a(\d+)$", ctx_of(lines[i]).partition(";")[2])
            if bm and int(bm.group(1)) > int(am.group(1)):
                lines.insert(i, new)
                return
    if same:
        lines.insert(same[-1] + 1, new)
        return
    kin = [i for i, l in enumerate(lines) if key_of(l) == key]
    lines.insert(kin[-1] + 1 if kin else len(lines), new)


def build_filled(lines, tc, added, limit=64):
    """Build `tc` (written from `lines`), adding each line the build misses
    with its table default; each added line is appended to `added`.
    Returns "" when it builds, else the reason."""
    seen = collections.Counter()
    while True:
        open(tc, "w").write("\n".join(lines))
        p = subprocess.run([os.path.join(ROOT, "tools", "build_fixture.sh"), tc, tc[:-5] + "-fill"],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if p.returncode == 0:
            return ""
        sm = re.search(r"BUILD FAILED: .*:(\d+): surplus: this stated value was never used: (.*)", p.stderr)
        if sm:   # a roll made the game stop asking for this decision: the stated line goes
            at = int(sm.group(1)) - 1
            if at < len(lines) and lines[at].strip() == sm.group(2).strip():
                del lines[at]
                continue
            return "the build calls line %d surplus, but it is not \"%s\"" % (at + 1, sm.group(2))[:300]
        mm = re.search(r"BUILD FAILED: missing line in .*; add: (.*)", p.stderr)
        if not mm:
            return (re.search(r"BUILD FAILED.*", p.stderr) or re.search(r".+", p.stderr + "build failed")).group(0)[:300]
        new = mm.group(1).rstrip("\n")
        seen[new] += 1
        if seen[new] > limit:
            return "the build asks for \"%s\" more than %d times" % (new, limit)
        added.append(new)
        insert_line(lines, new)


def decide(done, defaulted):
    """The verdict on the completed combinations `done` [(values, conv, D(c))] and the combinations whose build
    added an UNSEEN key's line with a default `defaulted`. Returns (kind, why, matches, ties, core):
    kind is "notsearched" (a build defaulted an unseen roll, or fewer than two combinations completed),
    "nomatch" (none equals the core; `ties` are the combinations that differ least) or "match"."""
    if defaulted:
        return ("notsearched", "not searched: %d combination(s) made the build add the line(s) of an unseen key with its table "
                "default (first: %s), a roll the walk never made and so with no range" % (len(defaulted), defaulted[0][1][0]),
                [], [], None)
    if len(done) < 2:
        return ("notsearched", "not searched: only %d combination(s) completed, and one combination has nothing to be compared with"
                % len(done), [], [], None)
    core = done[0][2].copy()
    for _v, _c, d in done[1:]:
        core &= d
    matches = [(v, c) for v, c, d in done if d == core]
    if matches:
        return ("match", "", matches, [], core)
    least = min(sum(d.values()) for _v, _c, d in done)
    ties = [list(v) for v, _c, d in done if sum(d.values()) == least]
    return ("nomatch", "no combination of the %d completed matched: each leaves a difference line a roll moves "
            "(fewest differing lines %d, core %d)" % (len(done), least, sum(core.values())), [], ties, core)


def selftest():
    """Phase 11h: the verdict rules and the multiset difference. Prints a line per case; exit 0 all hold."""
    import tempfile
    bad = []

    def want(label, cond, detail=""):
        print("%s %s%s" % ("ok  " if cond else "FAIL", label, (": " + detail) if detail and not cond else ""))
        if not cond:
            bad.append(label)
    C = collections.Counter
    a, b = C({"-x": 1}), C({"-x": 1, "-y": 1})
    want("one completed combination is not a match", decide([([1], "c", a)], [])[0] == "notsearched")
    want("no completed combination is not searched", decide([], [])[0] == "notsearched")
    k = decide([([1], "c1", a), ([2], "c2", a)], [])
    want("two combinations with the same lines both match", k[0] == "match" and len(k[2]) == 2, str(k[:2]))
    k = decide([([1], "c1", b), ([2], "c2", a)], [])
    want("the combination with fewer lines than the other matches (the core)", k[0] == "match" and k[2][0][0] == [2], str(k[:2]))
    k = decide([([1], "c1", C({"-x": 1, "-p": 1})), ([2], "c2", C({"-x": 1, "-q": 1}))], [])
    want("no combination at the core: no match, the tied candidates are named",
         k[0] == "nomatch" and k[3] == [[1], [2]], str(k[:4]))
    k = decide([([1], "c1", a), ([2], "c2", a)], [([3], ["script_roll [X]: 1"])])
    want("a build that added an unseen key's line with a default is not searched", k[0] == "notsearched" and "script_roll" in k[1], str(k[:2]))
    want("the unseen keys are read from the UNSEEN column", unseen_keys() == {"script_roll", "effect_roll"}, str(unseen_keys()))
    d = tempfile.mkdtemp()
    body = ["=== Identity ===", "Name: x", "Race: Orc", "Class[0]: Barbarian", "=== Kit ===", "  - Item A", "  - Item B", "  - Item B"]
    open(os.path.join(d, "p"), "w").write("\n".join(body))
    open(os.path.join(d, "q"), "w").write("\n".join(body[:5] + ["  - Item B", "  - Item A", "  - Item B"]))
    want("the difference is a multiset: the same lines in another order differ by nothing",
         sum(diff_lines(os.path.join(d, "p"), os.path.join(d, "q")).values()) == 0)
    open(os.path.join(d, "r"), "w").write("\n".join(body[:5] + ["  - Item A", "  - Item B"]))
    want("a line the build has once more than the old dump is one difference",
         sum(diff_lines(os.path.join(d, "p"), os.path.join(d, "r")).values()) == 1)
    return 1 if bad else 0


def sh(argv):
    return subprocess.run(argv, capture_output=True, text=True, stdin=subprocess.DEVNULL)


def main(argv):
    args = argv[1:]
    if args == ["selftest"]:
        return selftest()
    cap = 500
    if "--max" in args:
        i = args.index("--max")
        cap = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 10:
        print(__doc__, file=sys.stderr)
        return 2
    in_char, rolls_p, old_canon, prefix, keys, seed, opts, skip, tick, stream = args
    lines = open(in_char).read().split("\n")
    rolls = read_rolls(rolls_p, lines) if os.path.exists(rolls_p) else []
    if not rolls:
        print("char_roll_search: no unseen roll was recorded; nothing to search")
        return 4
    names = ["%s%s #%d" % (k, " [%s]" % c if c else "", n) for k, c, n, _lo, _hi, _i in rolls]
    ranges = [range(lo, hi + 1) for _k, _c, _n, lo, hi, _i in rolls]
    size = 1
    for r in ranges:
        size *= len(r)
    recorded = [int(CHAR_LINE.match(lines[i]).group(3)) for *_x, i in rolls]
    rec = open(prefix + ".txt", "w")

    def say(text):
        rec.write(text + "\n")

    def unresolved(reason, ties=None):
        """One line per searched roll: the walk's value kept, and why it is not resolved."""
        with open(prefix + "-unresolved.txt", "w") as uf:
            for nm, v in zip(names, recorded):
                uf.write("roll: %s: UNRESOLVED, kept as the walk recorded it (%d); %s%s\n"
                         % (nm, v, reason, ("; tied candidates (in the order of the rolls above): %s" % ties) if ties else ""))

    say("rolls searched (%d), recorded value, range:" % len(rolls))
    for nm, r, v in zip(names, ranges, recorded):
        say("  %s: recorded %d, range %d..%d" % (nm, v, r[0], r[-1]))
    say("space: %d combination(s)" % size)
    if size > cap:
        say("STOPPED: the space exceeds %d tries; nothing was tried" % cap)
        rec.close()
        unresolved("not searched: the space of %d combinations exceeds %d" % (size, cap))
        print("SIZE: %d combinations of %d roll(s) (%s) exceed %d; not searched"
              % (size, len(rolls), ", ".join(sorted({k for k, *_x in rolls})), cap))
        return 3

    unseen = unseen_keys()
    results = []   # (values, converted .char path or None, D(c) or None, why)
    defaulted = []   # (values, the unseen-key lines the build added with a default)
    t0 = time.time()
    for n, values in enumerate(itertools.product(*ranges)):
        pre = "%s-try%d" % (prefix, n)
        trial = list(lines)
        for (key, ctx, _o, _lo, _hi, i), v in zip(rolls, values):
            trial[i] = "%s%s: %d" % (key, " [%s]" % ctx if ctx else "", v)
        skel = pre + "-skel.char"
        added = []
        why = build_filled(trial, skel, added)
        defaulted_here = [a for a in added if key_of(a) in unseen]
        if defaulted_here:
            defaulted.append((values, defaulted_here))
        d = None
        conv = pre + "-conv.char"
        if not why:
            p = sh([os.path.join(ROOT, "tools", "char_arrive.sh"), skel, pre + "-s", keys, seed, opts, skip, tick, stream])
            why = p.stderr.strip()
            if p.returncode == 0:
                q = sh([os.path.join(ROOT, "tools", "char_convert_map.py"), "convert", old_canon, pre + "-s.canon",
                        skel, conv, "--rolls", rolls_p, "--report", pre + "-values.txt", "--unset", pre + "-unset.txt"])
                why = ("cannot convert: " + q.stderr.strip()) if q.returncode != 0 else ""
                if q.returncode == 0:
                    p = sh([os.path.join(ROOT, "tools", "char_arrive.sh"), conv, pre + "-c", keys, seed, opts, skip, tick, stream])
                    why = p.stderr.strip() if p.returncode != 0 else ""
                    if p.returncode == 0:
                        d = diff_lines(pre + "-c.canon", old_canon)
        results.append((values, conv if d is not None else None, d, why))
        # keep the converted .char of a completed try; drop the rest of its files
        for suffix in ("-fill", "-s-out", "-s-replay", "-c-out", "-c-replay"):
            subprocess.run(["rm", "-rf", pre + suffix])
        for suffix in ("-s-load.sav", "-s-build.log", "-s-replay.log", "-s.canon", "-c-load.sav", "-c-build.log",
                       "-c-replay.log", "-c.canon", "-s-arrive.err"):
            try:
                os.remove(pre + suffix)
            except OSError:
                pass
    secs = time.time() - t0
    done = [(v, c, d) for v, c, d, _w in results if d is not None]
    say("tries: %d in %.1f s (%.2f s per try)" % (len(results), secs, secs / len(results)))
    for v, c, d, w in results:
        if d is None:
            say("  %s : no result : %s" % (list(v), w))
    timing = "%d tries in %.1f s (%.2f s per try); record %s.txt" % (len(results), secs, secs / len(results), prefix)
    if not done:
        say("RESULT: no combination built and converted")
        rec.close()
        print("NO MATCH: no combination of %s built and converted (%s)" % (", ".join(names), timing))
        return 2
    kind, why, matches, ties, core = decide(done, defaulted)
    if kind == "notsearched":
        for v, ls in defaulted:
            say("  %s : the build added the unseen key line(s) %s with the table default; their values are not searched"
                % (list(v), "; ".join(ls)))
        say("RESULT: NOT SEARCHED; " + why)
        rec.close()
        unresolved(why)
        print("NOT SEARCHED: %s = recorded values kept (%s); %s" % (", ".join(names), why, timing))
        return 5
    say("difference lines no roll explains (the core common to every combination): %d" % sum(core.values()))
    say("values (in the order above) : difference lines : match:")
    for v, c, d in done:
        say("  %s : %d : %s" % (list(v), sum(d.values()), "MATCH" if d == core else "-"))
    if kind == "nomatch":
        # No combination agrees on every roll-dependent line (a rule that changed also moves lines a roll moves,
        # such as the derived attributes of a strength roll). Nothing is written as a fact: the walk's values stay
        # and each searched key is named unresolved, with the combinations that differ least.
        say("RESULT: NO MATCH; " + why + "; ties: %s" % ties)
        rec.close()
        unresolved(why, ties)
        print("NO MATCH: %s = recorded values kept, UNRESOLVED (recorded %s; %s; ties %s); %s"
              % (", ".join(names), recorded, why, ties, timing))
        return 1
    keep_v, keep_c = matches[0]
    subprocess.run(["cp", keep_c, prefix + ".char"])
    # the values the kept conversion set, and the rolls that moved from their recorded value
    with open(prefix + "-values.txt", "w") as vf:
        for (key, ctx, _o, _lo, _hi, _i), was, now in zip(rolls, recorded, keep_v):
            if was != now:
                vf.write("roll: %s%s: %d -> %d (searched)\n" % (key, " [%s]" % ctx if ctx else "", was, now))
        vf.write(open(keep_c[:-len("-conv.char")] + "-values.txt").read())
    subprocess.run(["cp", keep_c[:-len("-conv.char")] + "-unset.txt", prefix + "-unset.txt"])
    others = [list(m[0]) for m in matches[1:]] or "none"
    say("RESULT: kept %s; other matches: %s" % (list(keep_v), others))
    rec.close()
    print("MATCH: %s = %s (recorded %s); other matches %s; %s"
          % (", ".join(names), list(keep_v), recorded, others, timing))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
