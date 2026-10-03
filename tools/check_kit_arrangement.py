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
              average damage; a reach-only weapon (WT_REACH without
              WT_STRIKE_NEAR) is never a candidate -- it cannot strike an
              adjacent square -- and is a spare by R4
  R3 offhand  no Two-Weapon Style: a proficient shield in the ready slot unless
              a two-handed weapon or a two-handed shield blocks it; with the
              feat: the second-best melee weapon in the ready slot (also
              excluding reach-only weapons)
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
    r'weight=(-?\d+) sd=(-?\d+),(-?\d+),(-?\d+) ld=(-?\d+),(-?\d+),(-?\d+) '
    r'reach=(\d) near=(\d)')

PACK_RE = re.compile(
    r'KIT_PACK weight=(-?\d+) wlim=(-?\d+) cap=(-?\d+) count=(-?\d+) '
    r'maxsize=(-?\d+)')


class Pack:
    """The pack's normal limits, logged by the probe. weight/count are the live
    state (the same Weight() Container::Insert reads); wlim/cap/maxsize come
    from the pack template. `none` when the character has no pack container."""
    def __init__(self, m):
        g = m.groups()
        self.weight, self.wlim = int(g[0]), int(g[1])
        self.cap, self.count, self.maxsize = int(g[2]), int(g[3]), int(g[4])
        self.present = True

    def fits(self, item, packrat, packed=False):
        """Would Container::FitsNormal accept `item`? Mirrors src/Inv.cpp
        Container::FitsNormal, including the Faster-Than-The-Eye doubling. When
        `packed` the item is already one of the pack's children, so its weight
        and count are removed before the projection -- the same adjustment
        FitsNormal makes for a child."""
        dbl = 2 if packrat else 1
        w = self.weight - (item.weight if packed else 0)
        c = self.count - (1 if packed else 0)
        if self.wlim and w + item.weight > self.wlim * dbl:
            return False
        if self.cap * dbl and c >= self.cap * dbl:
            return False
        if item.size > self.maxsize + (1 if packrat else 0):
            return False
        return True

    def over_limit(self, item, packrat, packed=False):
        return not self.fits(item, packrat, packed)


class Item:
    def __init__(self, m):
        g = m.groups()
        self.sl, self.name, self.type = int(g[0]), g[2], int(g[3])
        self.group, self.qty, self.eid = int(g[4]), int(g[5]), int(g[6])
        self.skill, self.size, self.grip2 = int(g[7]), int(g[8]), int(g[9])
        self.weight = int(g[10])
        n, s, b = int(g[11]), int(g[12]), int(g[13])
        # twice the average, so the comparison stays in integers
        self.dmg2 = n * (s + 1) + 2 * b if self.type == T["T_WEAPON"] else 0
        self.reach, self.near = int(g[17]), int(g[18])

    def key(self):
        return (self.skill, self.dmg2)

    @property
    def reach_only(self):
        """WT_REACH without WT_STRIKE_NEAR: cannot strike an adjacent square,
        so it may never be the weapon in hand (src/Values.cpp MS_REACH_ONLY)."""
        return bool(self.reach) and not self.near

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
                and not self.reach_only
                and self.name != "pickaxe" and self.eid == 0)

    @property
    def quick(self):
        return self.type in QUICK or self.thrown_only


def parse(path, siz_limit):
    head, items, pack = None, [], None
    for line in open(path, errors="replace"):
        m = re.search(
            r"KIT_PROBE race=(.*?) class=(.*?) siz=(\d+) twf=(\d+) packrat=(\d)",
            line)
        if m:
            head = (m.group(1), m.group(2), int(m.group(3)), int(m.group(4)),
                    int(m.group(5)))
        if "KIT_PACK none" in line:
            pack = Pack.__new__(Pack)
            pack.weight = pack.wlim = pack.cap = pack.count = pack.maxsize = 0
            pack.present = False
        else:
            m = PACK_RE.search(line)
            if m:
                pack = Pack(m)
        m = ITEM_RE.search(line)
        if m:
            items.append(Item(m))
    return head, items, pack


def best_of(units):
    top = max((u.key() for u in units), default=None)
    return top, [u for u in units if u.key() == top]


def evaluate(head, items, pack=None):
    race, cls, siz, twf, packrat = head
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
    # The settled rule (inc-zzwm): a spare weapon goes to the pack only when the
    # pack can hold it within its NORMAL limits; otherwise a free shoulder; only
    # when both shoulders are taken does it go to the pack regardless.
    shoulders_free = not at(SL_LSHOULDER) or not at(SL_RSHOULDER)

    def spare_ok(i, shoulder):
        """R4 for one spare weapon. `shoulder` says whether i sits on one."""
        if not pack.present:
            # With no pack, the shoulder is the only home the rule allows; a
            # spare left loose is still wrong.
            if not shoulder:
                fail("R4", "spare weapon %s at slot %d and the character has no pack" % (i.name, i.sl))
            return
        if shoulder:
            if pack.fits(i, packrat):
                fail("R4", "spare weapon %s rides a shoulder although the pack "
                           "fits it (weight %d/%d, count %d/%d, size %d/%d)"
                     % (i.name, pack.weight, pack.wlim, pack.count, pack.cap,
                        i.size, pack.maxsize))
        else:
            if shoulders_free and pack.over_limit(i, packrat, packed=True):
                fail("R4", "spare weapon %s is in the pack although a shoulder "
                           "is free and the pack is over its limit "
                           "(weight %d/%d, count %d/%d, size %d/%d)"
                     % (i.name, pack.weight, pack.wlim, pack.count, pack.cap,
                        i.size, pack.maxsize))

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
            elif i.sl == PACK:
                seen.add("R4-spare")
                spare_ok(i, shoulder=False)
            elif i.sl in (SL_LSHOULDER, SL_RSHOULDER):
                seen.add("R4-shoulder")
                spare_ok(i, shoulder=True)
            else:
                fail("R4", "spare weapon %s at slot %d, not in the pack or on a shoulder" % (i.name, i.sl))
    for i in items:
        if i.sl in (SL_LSHOULDER, SL_RSHOULDER) and i.type == T["T_BOW"]:
            continue
        if i.sl in (SL_LSHOULDER, SL_RSHOULDER) and i.type == T["T_WEAPON"]:
            continue    # a spare weapon on a shoulder is judged by spare_ok
        if i.sl in (SL_LSHOULDER, SL_RSHOULDER):
            fail("R4", "%s on a shoulder; only a bow or an over-limit spare weapon belongs there" % i.name)

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


def _line(sl, name, typ, skill, grip2=0, group=0, qty=1, eid=0, size=3,
          weight=4, sd=(0, 0, 0), reach=0, near=0):
    return ("KIT_ITEM sl=%d slot=x  name=\"%s\" type=%d group=%d qty=%d eid=%d "
            "skill=%d size=%d grip2=%d weight=%d sd=%d,%d,%d ld=0,0,0 "
            "reach=%d near=%d" %
            ((sl, name, typ, group, qty, eid, skill, size, grip2, weight) + sd
             + (reach, near)))


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

    def run(rows, twf=0, packrat=0, pack=(20, 1000, 50, 5, 4)):
        """pack is (weight, wlim, cap, count, maxsize)."""
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write("KIT_PROBE race=Human class=Warrior siz=4 twf=%d packrat=%d\n"
                    % (twf, packrat))
            f.write("KIT_PACK weight=%d wlim=%d cap=%d count=%d maxsize=%d\n" % pack)
            f.write("\n".join(rows) + "\nKIT_PROBE end\n")
        head, items, pk = parse(f.name, 0)
        return evaluate(head, items, pk)

    # Inc-zzwm R4 fixtures. A spare weapon marked eid=1 is not a melee
    # candidate (see melee_candidate), so it only exercises R4. HEAVY is weight
    # 1200 against a 1000 pack limit; FIT_PACK can hold it.
    HEAVY_PACK = (0, 1000, 50, 5, 4)
    FIT_PACK = (0, 2000, 50, 5, 4)
    heavy = lambda sl: _line(sl, "glaive", W, 2, eid=1, size=4, weight=1200,
                             sd=(1, 10, 0))

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
        # inc-zzwm new R4: over-limit spare weapons ride a shoulder.
        ("over-limit spare on a shoulder is correct",
         kit(extra=[heavy(4)]), 0, None, 0, HEAVY_PACK),
        # The logged live pack weight includes the packed spare, as the real
        # probe's Weight() does.
        ("over-limit spare in the pack with a free shoulder",
         kit(extra=[heavy(PACK)]), 0, "R4", 0, (1200, 1000, 50, 6, 4)),
        ("two over-limit spares fill both shoulders",
         kit(extra=[heavy(4), heavy(5)]), 0, None, 0, HEAVY_PACK),
        ("third over-limit spare packed with both shoulders full",
         kit(extra=[heavy(4), heavy(5), heavy(PACK)]),
         0, None, 0, HEAVY_PACK),
        ("over-limit spare on a shoulder although the pack fits it",
         kit(extra=[heavy(4)]), 0, "R4", 0, FIT_PACK),
        ("packrat doubling lets an over-limit spare fit the pack",
         kit(extra=[heavy(PACK)]), 0, None, 1, (0, 1000, 50, 5, 4)),
        # inc-zzwm new R2: a reach-only weapon may not be the one in hand.
        # A longspear (WT_REACH, no WT_STRIKE_NEAR) with a higher skill than
        # the long sword is still a non-candidate, so the sword stays in hand
        # and the spear is a spare (R4). Skill 3 > sword's 2: if the spear were
        # counted it would win, so the case is red only when the exclusion works.
        ("reach-only weapon excluded from hand",
         kit(extra=[_line(PACK, "longspear", W, 3, reach=1, near=0,
                          sd=(1, 8, 0))]),
         0, None),
        # inc-zzwm control: a reach weapon that ALSO strikes near is an ordinary
        # candidate, so its higher skill wins the hand.
        ("reach weapon that strikes near may hold the hand",
         kit(sword=-2, extra=[_line(2, "preternatural longspear", W, 3, reach=1,
                                    near=1, sd=(1, 8, 0))]),
         0, None),
    ]
    bad = 0
    for case in cases:
        label, rows, twf, want = case[:4]
        packrat = case[4] if len(case) > 4 else 0
        pack = case[5] if len(case) > 5 else (20, 1000, 50, 5, 4)
        res, _ = run(rows, twf, packrat, pack)
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
    head, items, pack = parse(path, 0)
    res, seen = evaluate(head, items, pack)
    bad = 0
    print("%s: %s %s siz=%d twf=%d packrat=%d, %d stacks" %
          (build, head[0], head[1], head[2], head[3], head[4], len(items)))
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
