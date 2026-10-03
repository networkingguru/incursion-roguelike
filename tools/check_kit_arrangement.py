#!/usr/bin/env python3
# gate: none helper of check_kit_arrangement.sh (the gate runs that); --selftest needs no build
"""Judge one creation run's KIT_PROBE lines against the starting-kit design.

Usage: check_kit_arrangement.py <errors.log> <build-name> <exercise-tags>

The probe (INCURSION_KIT_PROBE, src/Create.cpp KitProbe) logs facts, not a
verdict: per item, where it sits, its type and group, the wearer's weapon
skill with it (WepSkill), its small/large damage dice, and whether the engine
would need both hands for it. This script derives the arrangement the design
asks for FROM those facts, so the check never hard-codes a class's kit. A kit
that a build did not get (seed, rolled gear) is reported as "not exercised",
never as a pass.

The five rules (inc-zzwm settled design):
  R1 basic    proficient worn gear is worn; non-proficient armour/shield is in
              the pack
  R2 weapon   the melee weapon in hand has the highest WepSkill; tie -> higher
              average damage
  R3 offhand  no Two-Weapon Style: a proficient shield in the ready slot unless
              a two-handed weapon or a two-handed shield blocks it; with the
              feat: the second-best melee weapon in the ready slot
  R4 other    bows on a shoulder; thrown weapons in a pouch; every other
              weapon in the pack
  R5 pouches  belt pouches hold only quick-use items; quick-use beyond five
              pouches goes to the pack

Exit 0 all rules hold, 1 a rule failed, 2 the run proved nothing.
"""
import re
import sys

ROOT = __file__.rsplit("/tools/", 1)[0]

# Slot numbers: inc/Defines.h SL_*. -2 is "inside the pack", -1 "loose".
SL_READY, SL_WEAPON, SL_LSHOULDER, SL_RSHOULDER = 1, 2, 4, 5
POUCHES = range(18, 23)
PACK = -2

# Natural worn slot(s) per item type; a type is worn only if a slot is free.
WORN_SLOTS = {}


def load_consts():
    t = {}
    for line in open(ROOT + "/inc/Defines.h"):
        m = re.match(r"#define\s+(T_[A-Z]+)\s+(\d+)\b", line)
        if m:
            t[m.group(1)] = int(m.group(2))
    return t


T = load_consts()
WG_THROWN, WG_DAGGERS = 0x100, 0x1000
WORN_SLOTS = {
    T["T_ARMOUR"]: [9], T["T_BRACERS"]: [17], T["T_RING"]: [12, 13],
    T["T_AMULET"]: [14], T["T_SYMBOL"]: [14], T["T_BOOTS"]: [10],
    T["T_HELMET"]: [16], T["T_CLOTHES"]: [8], T["T_CLOAK"]: [11],
    T["T_EYES"]: [7], T["T_GAUNTLETS"]: [15],
}
QUICK = {T["T_POTION"], T["T_MISSILE"], T["T_WAND"], T["T_HERB"],
         T["T_DUST"], T["T_MUSH"]}

ITEM_RE = re.compile(
    r'KIT_ITEM sl=(-?\d+) slot=(.*?)\s+name="(.*?)" type=(\d+) group=(\d+) '
    r'qty=(\d+) eid=(-?\d+) skill=(-?\d+) size=(-?\d+) grip2=(\d) '
    r'sd=(-?\d+),(-?\d+),(-?\d+) ld=(-?\d+),(-?\d+),(-?\d+)')


class Item:
    def __init__(self, m):
        g = m.groups()
        self.sl, self.name, self.type = int(g[0]), g[2], int(g[3])
        self.group, self.qty, self.eid = int(g[4]), int(g[5]), int(g[6])
        self.skill, self.size, self.grip2 = int(g[7]), int(g[8]), int(g[9])
        n, s, b = int(g[10]), int(g[11]), int(g[12])
        # twice the average, so the comparison stays in integers
        self.dmg2 = n * (s + 1) + 2 * b if self.type == T["T_WEAPON"] else 0

    def key(self):
        return (self.skill, self.dmg2)

    def __repr__(self):
        return "%s(skill=%d,avg=%.1f,sl=%d)" % (self.name, self.skill,
                                                self.dmg2 / 2.0, self.sl)

    @property
    def thrown_only(self):
        return (self.type == T["T_WEAPON"] and self.group & WG_THROWN
                and not self.group & WG_DAGGERS)

    @property
    def melee_candidate(self):
        return (self.type == T["T_WEAPON"] and not self.thrown_only
                and self.name != "pickaxe" and self.eid == 0)

    @property
    def quick(self):
        return self.type in QUICK or self.thrown_only


def parse(path, siz_limit):
    head, items = None, []
    for line in open(path, errors="replace"):
        m = re.search(r"KIT_PROBE race=(.*?) class=(.*?) siz=(\d+) twf=(\d)", line)
        if m:
            head = (m.group(1), m.group(2), int(m.group(3)), int(m.group(4)))
        m = ITEM_RE.search(line)
        if m:
            items.append(Item(m))
    return head, items


def best_of(units):
    top = max((u.key() for u in units), default=None)
    return top, [u for u in units if u.key() == top]


def evaluate(head, items):
    race, cls, siz, twf = head
    res = {r: [] for r in ("R1", "R2", "R3", "R4", "R5")}
    seen = set()  # rules the build actually exercised

    def fail(rule, msg):
        res[rule].append(msg)

    at = lambda sl: [i for i in items if i.sl == sl]

    # ---- R1: worn gear ------------------------------------------------
    for i in items:
        if i.type in (T["T_ARMOUR"], T["T_SHIELD"]) and i.skill <= 0:
            seen.add("R1-nonprof")
            if i.sl != PACK:
                fail("R1", "non-proficient %s is at slot %d, not in the pack" % (i.name, i.sl))
    by_type = {}
    for i in items:
        if i.type in WORN_SLOTS and not (i.type == T["T_ARMOUR"] and i.skill <= 0):
            by_type.setdefault(tuple(WORN_SLOTS[i.type]), []).append(i)
    for slots, group in by_type.items():
        if len(group) <= len(slots):
            seen.add("R1-worn")
            for i in group:
                if i.sl not in slots:
                    fail("R1", "%s should be worn (slot %s) but sits at slot %d" % (i.name, list(slots), i.sl))

    # ---- R2: weapon in hand -------------------------------------------
    cands = [i for i in items if i.melee_candidate and i.size <= siz + 1]
    units = [u for i in cands for u in [i] * max(i.qty, 1)]
    top, tied = best_of(units)
    inhand = at(SL_WEAPON)
    main = None
    if top is not None:
        seen.add("R2")
        if not inhand:
            fail("R2", "no weapon in hand; expected one of %s" % sorted({t.name for t in tied}))
        else:
            main = inhand[0]
            if main.key() != top:
                fail("R2", "in hand %r; expected %s with skill/avg %s" %
                     (main, sorted({t.name for t in tied}), (top[0], top[1] / 2.0)))
    if len(cands) >= 2 and len({u.key() for u in units}) > 1:
        seen.add("R2-choice")

    # ---- R3: off hand --------------------------------------------------
    ready = [i for i in at(SL_READY) if i is not main]
    main_two = bool(main and main.grip2)
    if twf:
        pool = list(units)
        if main is not None:
            for k, u in enumerate(pool):
                if u.name == main.name:
                    del pool[k]
                    break
        stop, stied = best_of(pool)
        if stop is not None and not main_two:
            seen.add("R3-twf")
            if not ready or ready[0].key() != stop:
                fail("R3", "off hand holds %r; expected %s skill/avg %s" %
                     (ready, sorted({t.name for t in stied}), (stop[0], stop[1] / 2.0)))
        for s in ready:
            if s.type == T["T_SHIELD"]:
                fail("R3", "shield %s worn with Two-Weapon Style" % s.name)
    else:
        shields = [i for i in items if i.type == T["T_SHIELD"] and i.skill > 0]
        usable = [s for s in shields if not s.grip2]
        if shields:
            seen.add("R3-shield")
        if usable and not main_two:
            seen.add("R3-worn")
            if not any(s.sl == SL_READY for s in usable):
                fail("R3", "proficient shield %s not in the ready slot (slot %s)" %
                     (usable[0].name, [s.sl for s in usable]))
        elif shields:
            seen.add("R3-blocked")
            for s in shields:
                if s.sl == SL_READY:
                    fail("R3", "shield %s worn although %s blocks it" %
                         (s.name, "a two-handed weapon" if main_two else "its own grip"))

    # ---- R4: other weapons ---------------------------------------------
    for i in items:
        if i.type == T["T_BOW"]:
            seen.add("R4-bow")
            if i.sl not in (SL_LSHOULDER, SL_RSHOULDER):
                fail("R4", "bow %s at slot %d, not on a shoulder" % (i.name, i.sl))
        elif i.type == T["T_WEAPON"]:
            if i.thrown_only:
                seen.add("R4-thrown")
                if i.sl not in POUCHES and i.sl != PACK:
                    fail("R4", "thrown weapon %s at slot %d, not in a pouch" % (i.name, i.sl))
            elif i is main or (twf and ready and i is ready[0]):
                pass
            elif i.sl != PACK:
                fail("R4", "spare weapon %s at slot %d, not in the pack" % (i.name, i.sl))
            else:
                seen.add("R4-spare")
    for i in items:
        if i.sl in (SL_LSHOULDER, SL_RSHOULDER) and i.type != T["T_BOW"]:
            fail("R4", "%s on a shoulder; only a bow belongs there" % i.name)

    # ---- R5: belt pouches -----------------------------------------------
    occupied = [i for i in items if i.sl in POUCHES]
    quick = [i for i in items if i.quick]
    for i in occupied:
        if not i.quick:
            fail("R5", "%s (type %d) in pouch slot %d is not quick-use" % (i.name, i.type, i.sl))
    for i in quick:
        if i.sl not in POUCHES and i.sl != PACK:
            fail("R5", "quick-use %s at slot %d, not in a pouch or the pack" % (i.name, i.sl))
    want = min(5, len(quick))
    got = len([i for i in occupied if i.quick])
    if quick:
        seen.add("R5")
    if got != want:
        fail("R5", "%d quick-use stacks, %d pouches full of them; expected %d" % (len(quick), got, want))
    if len(quick) > 5:
        seen.add("R5-overflow")
    return res, seen


def _line(sl, name, typ, skill, grip2=0, group=0, qty=1, eid=0, size=3, sd=(0, 0, 0)):
    return ("KIT_ITEM sl=%d slot=x  name=\"%s\" type=%d group=%d qty=%d eid=%d "
            "skill=%d size=%d grip2=%d sd=%d,%d,%d ld=0,0,0" %
            ((sl, name, typ, group, qty, eid, skill, size, grip2) + sd))


def selftest():
    """Hand-written arrangements, one right and several each wrong in one
    rule. Proves the rules can go green and go red without a game run."""
    import tempfile
    W, SH, AR = T["T_WEAPON"], T["T_SHIELD"], T["T_ARMOUR"]
    PO, CO, SC = T["T_POTION"], T["T_COIN"], T["T_SCROLL"]
    DAG = WG_THROWN | WG_DAGGERS

    def kit(sword=2, shield=1, dagger=-2, gold=-2, arm_sl=9, arm_skill=1,
            axe=None, extra=()):
        rows = [
            _line(sword, "long sword", W, 2, sd=(1, 8, 0)),
            _line(shield, "kite shield", SH, 1),
            _line(arm_sl, "banded mail", AR, arm_skill),
            _line(dagger, "dagger", W, 1, group=DAG, sd=(1, 4, 0)),
            _line(gold, "gold piece", CO, 0),
            _line(18, "potion", PO, 0), _line(19, "potion", PO, 0),
            _line(20, "potion", PO, 0), _line(21, "potion", PO, 0),
            _line(22, "potion", PO, 0), _line(PACK, "potion", PO, 0),
            _line(PACK, "scroll", SC, 0),
        ]
        if axe is not None:
            rows.append(_line(axe, "glaive", W, 2, grip2=1, sd=(1, 10, 0)))
        return rows + list(extra)

    def run(rows, twf=0):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write("KIT_PROBE race=Human class=Warrior siz=4 twf=%d\n" % twf)
            f.write("\n".join(rows) + "\nKIT_PROBE end\n")
        head, items = parse(f.name, 0)
        return evaluate(head, items)

    cases = [
        ("right arrangement", kit(), 0, None),
        ("shield on a shoulder", kit(shield=4), 0, "R3,R4"),
        ("dagger wielded over a focused long sword", kit(sword=-2, dagger=2), 0, "R2"),
        ("gold in a pouch", kit(gold=22, extra=[]), 0, "R5"),
        ("non-proficient armour worn", kit(arm_skill=0), 0, "R1"),
        ("non-proficient armour packed", kit(arm_skill=0, arm_sl=PACK), 0, None),
        ("spare dagger left on a belt", kit(dagger=19), 0, "R4,R5"),
        ("two-handed glaive in hand, shield packed",
         kit(sword=-2, shield=PACK, axe=2), 0, None),
        ("two-handed glaive in hand, shield worn",
         kit(sword=-2, shield=1, axe=2), 0, "R3"),
        ("feat: dagger in the off hand", kit(shield=PACK, dagger=1), 1, None),
        ("feat: nothing in the off hand", kit(shield=PACK, dagger=-2), 1, "R3"),
        ("feat: shield worn", kit(shield=1, dagger=1), 1, "R3,R4"),
    ]
    bad = 0
    for label, rows, twf, want in cases:
        res, _ = run(rows, twf)
        failed = sorted(r for r in res if res[r])
        ok = failed == ([] if want is None else want.split(","))
        print("selftest %-52s %s" % (label, "ok" if ok else "WRONG (red: %s)" % failed))
        bad += not ok
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    path, build, tags = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    try:
        text = open(path, errors="replace").read()
    except OSError:
        print("%s: UNMEASURED no errors.log (probe never ran)" % build)
        return 2
    if "KIT_PROBE end" not in text:
        print("%s: UNMEASURED no complete KIT_PROBE block" % build)
        return 2
    head, items = parse(path, 0)
    res, seen = evaluate(head, items)
    bad = 0
    print("%s: %s %s siz=%d twf=%d, %d stacks" % (build, head[0], head[1], head[2], head[3], len(items)))
    for r in sorted(res):
        status = "FAIL" if res[r] else "ok"
        bad += bool(res[r])
        print("  %s %s" % (r, status))
        for msg in res[r]:
            print("      - %s" % msg)
    missing = [t for t in tags
               if t and not any(a in seen for a in t.split("|"))]
    print("  exercised: %s" % ",".join(sorted(seen)))
    if missing:
        print("  NOT EXERCISED (wanted %s): this build's kit did not hold them" % ",".join(missing))
        return 2 if not bad else 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
