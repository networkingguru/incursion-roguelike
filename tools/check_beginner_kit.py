#!/usr/bin/env python3
# gate: none helper of check_beginner_kit.sh (the gate runs that); --selftest needs no build
"""Oracle for tools/check_beginner_kit.sh (bd inc-rt8l).

Derives the expected Beginner's Kit from Roark's NECESSITIES rows in
lib/dungeon.irh and the type rules, then compares it with what creation
granted. The granted kit is the per-(item, effect) quantity difference between
a run with OPT_BEGINKIT on and the same build and seed with it off, read from
the KIT_STACK / KIT_FACTS lines of INCURSION_KIT_PROBE (src/Create.cpp). No
item list is hard-coded here.

  check_beginner_kit.py ON_LOG OFF_LOG BUILD TAGS [--no-dark-gate]
  check_beginner_kit.py --selftest
Exit 0 pass, 1 a rule failed, 2 could not measure or build did not exercise TAGS.
--no-dark-gate drops the darkvision rule from the oracle (the --prove-red
mutation); it is the oracle-side twin of removing the gate from the source.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def consts():
    c = {}
    for line in open(ROOT + "/inc/Defines.h", errors="replace"):
        m = re.match(r"\s*#define\s+(\w+)\s+(\d+)\b", line)
        if m:
            c[m.group(1)] = int(m.group(2))
    return c


C = consts()


def necessities():
    text = open(ROOT + "/lib/dungeon.irh", errors="replace").read()
    a = text.index("* NECESSITIES")
    i, q = a + len("* NECESSITIES"), False
    while q or text[i] != ";":              # a ';' inside quotes is part of a name
        q ^= text[i] == '"'
        i += 1
    body = text[a + len("* NECESSITIES"):i]
    rows = []
    for m in re.finditer(r'\$"([^"]+)"\s+(\$"[^"]+"|0)\s+(\d+)\s+(\w+)', body):
        eff = "" if m.group(2) == "0" else m.group(2).strip('$"')
        kit = m.group(4)
        kit = int(kit) if kit.isdigit() else C[kit]
        rows.append((m.group(1), eff, int(m.group(3)), kit))
    return rows


def item_info():
    """name -> (type constant name, set of skill ids named by SKILL_KIT_FOR)"""
    info = {}
    for f in glob.glob(ROOT + "/lib/*.irh"):
        cur = None
        for line in open(f, errors="replace"):
            m = re.match(r'\s*Item\s+"([^"]+)"\s*:\s*(T_\w+)', line)
            if m:
                cur = m.group(1)
                info[cur] = (m.group(2), set())
                continue
            if cur and "SKILL_KIT_FOR" in line:
                for sk in re.findall(r"SK_\w+", line):
                    info[cur][1].add(C[sk])
    return info


def norm(eff):
    return eff.split(";")[0].strip().lower()


def read(path):
    stacks, dark, ranks = {}, None, set()
    text = open(path, errors="replace").read()
    if "KIT_PROBE end" not in text or "KIT_FACTS" not in text:
        return None
    for line in text.splitlines():
        m = re.search(r"KIT_FACTS dark=(\d) ranks=([\d,]*)", line)
        if m:
            dark = int(m.group(1))
            ranks = {int(x) for x in m.group(2).split(",") if x}
        m = re.search(r'KIT_STACK item="(.*?)" eff="(.*?)" qty=(\d+)', line)
        if m:
            k = (m.group(1).lower(), norm(m.group(2)))
            stacks[k] = stacks.get(k, 0) + int(m.group(3))
    return stacks, dark, ranks


def expected(dark, ranks, off, dark_gate=True):
    """key -> (lo, hi) quantity the kit must add, from the rows and the rules"""
    info = item_info()
    exp = {}
    for item, eff, tier, kit in necessities():
        typ, skills = info[item]
        key = (item.lower(), norm(eff))
        if kit == 0 or typ == "T_FOOD":
            continue
        if kit != C["KIT_BY_TYPE"]:
            n = kit
        elif typ in ("T_POTION", "T_SCROLL"):
            n = (tier + 1) // 2
        elif typ == "T_LIGHT":
            if dark and dark_gate:
                continue
            n = (tier + 1) // 2
        elif skills:
            if not (skills & ranks) or off.get(key, 0) > 0:
                continue
            n = 1
        else:
            n = (tier + 1) // 2
        exp[key] = (n, n)
    exp[("food ration", "")] = (7, 10)          # 3d2+4
    return exp


def evaluate(on, off, dark, ranks, dark_gate=True):
    exp = expected(dark, ranks, off, dark_gate)
    bad = []
    keys = set(exp) | set(on) | set(off)
    for k in sorted(keys):
        got = on.get(k, 0) - off.get(k, 0)
        lo, hi = exp.get(k, (0, 0))
        if not lo <= got <= hi:
            bad.append("%s/%s: kit added %d, expected %s" % (
                k[0], k[1] or "-", got,
                lo if lo == hi else "%d..%d" % (lo, hi)))
    n_id = on.get(("scroll", "identify"), 0) - off.get(("scroll", "identify"), 0)
    if n_id != 24:
        bad.append("scroll/identify: kit added %d, expected 24" % n_id)
    for item in ("brass lantern", "hemp rope"):
        d = on.get((item, ""), 0) - off.get((item, ""), 0)
        if d:
            bad.append("%s: kit added %d, expected 0" % (item, d))
    d = on.get(("potion", "flask of oil"), 0) - off.get(("potion", "flask of oil"), 0)
    if d:
        bad.append("flask of oil: kit added %d, expected 0" % d)
    return bad, exp


def exercised(dark, ranks, off):
    seen = {"dark1" if dark else "dark0",
            "climb" if C["SK_CLIMB"] in ranks else "noclimb"}
    if C["SK_HEAL"] in ranks and off.get(("healing kit", ""), 0) > 0:
        seen.add("heal-base")
    return seen


def one(on_path, off_path, build, tags, dark_gate=True):
    a, b = read(on_path), read(off_path)
    if not a or not b:
        print("%s: UNMEASURED no complete KIT_PROBE/KIT_FACTS block" % build)
        return 2
    (on, dark, ranks), (off, dark2, ranks2) = a, b
    if (dark, ranks) != (dark2, ranks2):
        print("%s: UNMEASURED on/off runs made different characters" % build)
        return 2
    bad, exp = evaluate(on, off, dark, ranks, dark_gate)
    seen = exercised(dark, ranks, off)
    print("%s: dark=%d climb=%d, %d kit rows expected" % (
        build, dark, int(C["SK_CLIMB"] in ranks), len(exp)))
    for m in bad:
        print("      - FAIL %s" % m)
    missing = [t for t in tags if t and t not in seen]
    if missing:
        print("  NOT EXERCISED (wanted %s)" % ",".join(missing))
        return 1 if bad else 2
    print("  %s" % ("FAIL" if bad else "ok"))
    return 1 if bad else 0


def selftest():
    ok = {("scroll", "identify"): 24, ("food ration", ""): 9}
    off = {("food ration", ""): 0}
    exp = expected(1, set(), off)
    on = {k: v[0] for k, v in exp.items()}
    bad, _ = evaluate(on, off, 1, set())
    assert not bad, bad
    on[("torch", "")] = 6                     # a dark-sighted character got torches
    bad, _ = evaluate(on, off, 1, set())
    assert any("torch" in m for m in bad), bad
    exp = expected(0, {C["SK_CLIMB"]}, {("climbing rig", ""): 1})
    assert ("climbing rig", "") not in exp    # already held: no duplicate
    exp = expected(0, {C["SK_CLIMB"]}, {})
    assert exp[("climbing rig", "")] == (1, 1)
    assert ("healing kit", "") not in expected(0, set(), {})
    print("selftest ok")
    return 0


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    on, off, build, tags = sys.argv[1:5]
    gate = "--no-dark-gate" not in sys.argv[5:]
    return one(on, off, build, tags.split(","), gate)


if __name__ == "__main__":
    sys.exit(main())
