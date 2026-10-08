#!/usr/bin/env python3
# gate: none -- analyser for check_door_pick_kick.sh and check_door_axe_wizlock.sh, which are the gated checks
"""Analyser for the inc-h22n door probe log (src/DoorPickProbe.cpp).

  check_door_probe.py pick     LOG   lock-picking and kicking assertions
  check_door_probe.py axe      LOG   weapon-damage and wizard-lock assertions
  check_door_probe.py selftest       prove both analysers fail on the pre-design
                                     log shape and pass on a design-conformant one

Exit 0 pass, 1 fail, 2 inconclusive. Called by tools/check_door_pick_kick.sh and
tools/check_door_axe_wizlock.sh, which run the session. Each assertion line
names the settled-design point it covers (the numbered points in bd inc-h22n).
"""
import os
import re
import sys

# Design point 3: Break DC per door feature (lib/dungeon.irh).
BREAK_DC = {"oak door": 15, "warded oak door": 15, "ice door": 18,
            "iron door": 28, "darkwood door": 28, "vault door": 35}
STR_MOD = lambda s: (s - 10) // 2
SIZE_MOD = {3: -4, 4: 0, 5: 4}          # SZ_SMALL, SZ_MEDIUM, SZ_LARGE
RATE_TOL = 8.0                          # percentage points; N=400 gives sd<=2.5


def parse(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        head, _, rest = line.partition(" ")
        kv = {}
        for m in re.finditer(r'(\w+)=("[^"]*"|\S+)', rest):
            kv[m.group(1)] = m.group(2).strip('"')
        rows.append((head, kv, line))
    return rows


class Report:
    def __init__(self):
        self.fail = 0
        self.inc = 0

    passed = 0

    def ok(self, point, text, good, detail=""):
        # Quiet by default: a failure prints, a pass is only counted.
        # DOOR_PROBE_VERBOSE=1 prints every assertion.
        if good:
            self.passed += 1
        else:
            self.fail += 1
        if not good or os.environ.get("DOOR_PROBE_VERBOSE"):
            print("  %-4s [point %s] %s%s" % ("ok" if good else "FAIL", point, text,
                                              "" if good else "   <- " + detail))

    def inconclusive(self, text):
        print("  INCONCLUSIVE  %s" % text)
        self.inc += 1

    def rc(self):
        print("  %d assertions held, %d failed" % (self.passed, self.fail))
        return 2 if self.inc else (1 if self.fail else 0)


def want_rate(dc, mod):
    # d20 + mod >= dc, no automatic success or failure.
    return 100.0 * max(0, min(20, 21 - (dc - mod))) / 20.0


def load(path, r):
    rows = parse(path)
    by = {}
    for head, kv, raw in rows:
        key = head + ":" + kv.get("case", kv.get("label", ""))
        by.setdefault(head, []).append(kv)
    heads = [h for h, _, _ in rows]
    if "INCONCLUSIVE" in heads or "DONE" not in heads or "RIG" not in heads:
        r.inconclusive("the probe did not finish (no RIG/DONE line, or it said "
                       "INCONCLUSIVE). Is DoorPickProbe still called from "
                       "Game::Play?")
        return None, None
    return rows, by


def pick_named(rows, name):
    for head, kv, raw in rows:
        if head == "PICK" and raw.split()[1] == name:
            return kv
    return None


def kick_rows(rows):
    return [kv for head, kv, raw in rows if head == "KICK"]


def analyse_pick(path):
    r = Report()
    rows, by = load(path, r)
    if rows is None:
        return r.rc()
    rig = by["RIG"][0]
    d = int(rig["depth"])
    if int(rig["size"]) != 4:
        r.inconclusive("the probe character is not Medium (size %s)" % rig["size"])
    door_dc, chest_dc = 20 + 2 * d, 25 + 2 * d
    print("probe character: depth %d, Str %s, size %s" % (d, rig["str"], rig["size"]))
    print("--- lock-picking (design point 2) ---")

    def need(name):
        kv = pick_named(rows, name)
        if kv is None:
            r.inconclusive("probe line PICK %s is missing" % name)
        return kv

    for nm in ("door-untrained", "chest-untrained"):
        kv = need(nm)
        if kv:
            r.ok("2", "%s: an untrained creature cannot try (checks=%s, still locked=%s)"
                 % (nm, kv["checks"], kv["locked"]),
                 kv["checks"] == "0" and kv["locked"] == "1",
                 "a Lockpicking check was rolled with 0 ranks")
    for nm, dc in (("door-trained", door_dc), ("chest-trained", chest_dc)):
        kv = need(nm)
        if kv:
            r.ok("2", "%s: one attempt at DC %d" % (nm, dc),
                 kv["checks"] == "1" and kv["dcs"] == str(dc),
                 "checks=%s dcs=%s" % (kv["checks"], kv["dcs"]))
            r.ok("2", "%s: no retry bonus passed to the check" % nm,
                 kv["modbad"] == "0", "modbad=%s" % kv["modbad"])
            r.ok("2", "%s: an attempt costs a full round (Timeout 30)" % nm,
                 kv["timeout"] == "30", "timeout=%s" % kv["timeout"])
    for nm, dc in (("door-retry", door_dc + 10), ("chest-retry", chest_dc + 10)):
        kv = need(nm)
        if kv:
            if kv["locked"] != "1":
                r.inconclusive("%s: the lock opened, so the attempts did not all fail" % nm)
            r.ok("2", "%s: three attempts in a row, no resting, all at DC %d "
                 "(wizard lock +10)" % (nm, dc),
                 kv["checks"] == "3" and kv["dcs"] == ",".join([str(dc)] * 3),
                 "checks=%s dcs=%s" % (kv["checks"], kv["dcs"]))
            r.ok("2", "%s: no retry bonus on any attempt" % nm,
                 kv["modbad"] == "0", "modbad=%s" % kv["modbad"])
    kv = need("door-repeat")
    if kv:
        if kv["threatened"] != "0":
            r.inconclusive("door-repeat: the player was threatened, so the out-of-combat case did not run")
        r.ok("2", "out of combat a failed pick repeats by itself (ACTING set after one command)",
             kv["acting"] == "1", "acting=%s" % kv["acting"])
        r.ok("2", "...for at least 15 attempts from that one command (total=%s)" % kv["total"],
             int(kv["total"]) >= 15, "total=%s" % kv["total"])
    kv = need("door-combat")
    if kv:
        if kv["threatened"] != "1":
            r.inconclusive("door-combat: the player was not threatened")
        r.ok("2", "in combat one attempt per command, no auto-repeat",
             kv["first"] == "1" and kv["acting"] == "0",
             "first=%s acting=%s" % (kv["first"], kv["acting"]))
        r.ok("2", "in combat the next command may try again at once (after2=%s)" % kv["after2"],
             kv["after2"] == "2", "after2=%s" % kv["after2"])
    for nm in ("door-skilled", "chest-skilled"):
        kv = need(nm)
        if kv:
            r.ok("2", "%s: a skilled picker opens the lock in one attempt (control)" % nm,
                 kv["checks"] == "1" and kv["locked"] == "0",
                 "checks=%s locked=%s" % (kv["checks"], kv["locked"]))

    print("--- kicking a door (design point 3) ---")
    seen = set()
    for kv in kick_rows(rows):
        label, feat = kv["label"], kv["feat"]
        str_, size = int(kv["str"]), int(kv["size"])
        n, broke, fails = int(kv["n"]), int(kv["broke"]), int(kv["fails"])
        if feat not in BREAK_DC:
            r.ok("3", "door feature '%s' has a Break DC" % feat, False,
                 "no Break DC in the table of design point 3")
            continue
        seen.add(feat)
        dc = BREAK_DC[feat] + (10 if kv["wiz"] == "1" else 0)
        if kv["hp"] != "0" and int(kv["hp"]) * 2 <= 20:   # HP <= half of max (max 10 or 20)
            dc -= 2
        mod = STR_MOD(str_) + SIZE_MOD.get(size, 0)
        want = want_rate(dc, mod)
        got = 100.0 * broke / n
        tag = "%s %s Str %d size %d%s%s" % (label, feat, str_, size,
                                            " wizlock" if kv["wiz"] == "1" else "",
                                            " hp<=half" if kv["hp"] != "0" else "")
        r.ok("3", "%s: kick breaks it %.0f%% of the time (want %.0f%% +/- %.0f, DC %d, mod %+d)"
             % (tag, got, want, RATE_TOL, dc, mod),
             abs(got - want) <= RATE_TOL, "got %.1f%%" % got)
        if label in ("base", "str18", "large", "small", "wizlock", "halfhp", "table20"):
            r.ok("3", "%s: a failed kick does no damage to the door (%s of %d lost HP)"
                 % (tag, kv["hplost"], fails), kv["hplost"] == "0",
                 "%s failed kicks reduced the door's HP" % kv["hplost"])
            r.ok("3", "%s: a kick costs a standard action (Timeout %s, formula %s)"
                 % (tag, kv["timeout"], kv["std"]), kv["timeout"] == kv["std"],
                 "Timeout %s, standard action %s" % (kv["timeout"], kv["std"]))
            r.ok("3", "%s: OPT_REPEAT_KICK still repeats after every failure (control)" % tag,
                 kv["acting"] == kv["fails"], "acting=%s fails=%s" % (kv["acting"], kv["fails"]))
    missing = sorted(set(BREAK_DC) - seen)
    if missing:
        r.inconclusive("door features never kicked: %s" % ", ".join(missing))
    kv = [x for h, x, raw in rows if h == "KICKRETRY"]
    if kv:
        r.ok("3", "kick retries are unlimited: %s of 60 kicks on one door ran, no resting"
             % kv[0]["executed"], kv[0]["executed"] == "60", "executed=%s" % kv[0]["executed"])
    else:
        r.inconclusive("KICKRETRY line missing")
    return r.rc()


def analyse_axe(path):
    r = Report()
    rows, by = load(path, r)
    if rows is None:
        return r.rc()
    print("--- weapon damage to an oak door (design point 4) ---")
    got = {kv["label"]: kv for kv in by.get("AXE", [])}
    for need_ in ("axe", "sword", "blunt", "blunt-wiz", "axe-wiz"):
        if need_ not in got:
            r.inconclusive("AXE %s line missing" % need_)
    if r.inc:
        return r.rc()
    hard = int(got["axe"]["hard"])
    dmg = int(got["axe"]["vdmg"])
    loss = lambda k: int(got[k]["loss"])
    if dmg - hard <= 0 or dmg // 3 - hard <= 0:
        r.inconclusive("the probe damage %d does not exceed hardness %d once divided by 3" % (dmg, hard))
        return r.rc()
    full = dmg - hard
    r.ok("4", "an axe (WG_AXES) deals full damage minus hardness: %d (want %d)" % (loss("axe"), full),
         loss("axe") == full, "lost %d" % loss("axe"))
    r.ok("4", "a non-blunt, non-axe sword still deals one third minus hardness: %d (want %d)"
         % (loss("sword"), dmg // 3 - hard), loss("sword") == dmg // 3 - hard,
         "lost %d" % loss("sword"))
    r.ok("4", "a blunt weapon still deals full damage minus hardness: %d (want %d)"
         % (loss("blunt"), full), loss("blunt") == full, "lost %d" % loss("blunt"))
    r.ok("4", "a wizard lock no longer doubles hardness (blunt: %d, want %d)"
         % (loss("blunt-wiz"), full), loss("blunt-wiz") == full,
         "lost %d; hardness doubled gives %d" % (loss("blunt-wiz"), dmg - 2 * hard))
    r.ok("4", "...and an axe on a wizard-locked door deals %d (want %d)"
         % (loss("axe-wiz"), full), loss("axe-wiz") == full, "lost %d" % loss("axe-wiz"))
    return r.rc()


# ---------------------------------------------------------------------------
def synth(design):
    """A probe log as the unmodified code would write it (design=False, taken
    from a real run) or as a build of the settled design should (design=True)."""
    d = 1
    out = ["RIG depth=%d str=18 size=4 std=21" % d]
    P = out.append
    P("PICK door-untrained sr=0 checks=%d locked=1" % (0 if design else 1))
    P("PICK door-trained sr=1 depth=1 checks=1 dcs=%d modbad=0 timeout=30" % (22 if design else 15))
    P("PICK door-retry sr=1 depth=1 checks=%d dcs=%s modbad=%d locked=1"
      % (3, "32,32,32", 0) if design else "PICK door-retry sr=1 depth=1 checks=1 dcs=25 modbad=0 locked=1")
    P("PICK door-repeat threatened=0 first=1 acting=%d total=%d" % ((1, 15) if design else (0, 1)))
    P("PICK door-skilled checks=1 locked=0 open=1")
    P("PICK chest-untrained checks=%d locked=1" % (0 if design else 1))
    P("PICK chest-trained depth=1 checks=1 dcs=%d modbad=%d timeout=30"
      % ((27, 0) if design else (20, 1)))
    P("PICK chest-retry depth=1 checks=%d dcs=%s modbad=%d locked=1"
      % ((3, "37,37,37", 0) if design else (1, "30", 1)))
    P("PICK chest-skilled checks=1 locked=0")

    def kick(label, feat, s, size, wiz, hp):
        dc = BREAK_DC[feat] + (10 if wiz else 0) - (2 if hp else 0)
        rate = want_rate(dc, STR_MOD(s) + SIZE_MOD.get(size, 0)) / 100.0 if design else 0.0
        broke = int(round(400 * rate))
        fails = 400 - broke
        out.append('KICK label=%s feat="%s" str=%d size=%d wiz=%d hp=%d n=400 broke=%d fails=%d '
                   'hplost=%d acting=%d timeout=%d std=21'
                   % (label, feat, s, size, wiz, hp, broke, fails,
                      0 if design else fails, fails, 21 if design else 10))
    kick("base", "oak door", 10, 4, 0, 0)
    kick("str18", "oak door", 18, 4, 0, 0)
    kick("large", "oak door", 10, 5, 0, 0)
    kick("small", "oak door", 20, 3, 0, 0)
    kick("wizlock", "oak door", 30, 4, 1, 0)
    kick("halfhp", "oak door", 10, 4, 0, 4)
    for f in BREAK_DC:
        kick("table20", f, 20, 4, 0, 0)
        kick("table40", f, 40, 4, 0, 0)
    P("KICKRETRY n=60 executed=60")
    full = 25
    P("AXE label=axe item=\"battleaxe\" vdmg=30 hard=5 loss=%d" % (full if design else 5))
    P("AXE label=sword item=\"long sword\" vdmg=30 hard=5 loss=5")
    P("AXE label=blunt item=\"light mace\" vdmg=30 hard=5 loss=%d" % full)
    P("AXE label=blunt-wiz item=\"light mace\" vdmg=30 hard=5 loss=%d" % (full if design else 20))
    P("AXE label=axe-wiz item=\"battleaxe\" vdmg=30 hard=5 loss=%d" % (full if design else 0))
    P("PICK door-combat threatened=1 first=1 acting=0 after2=%d" % (2 if design else 1))
    P("DONE")
    return "\n".join(out) + "\n"


def selftest():
    import contextlib
    import io
    import os
    import tempfile
    bad = 0
    for design, want_pick, want_axe in ((False, 1, 1), (True, 0, 0)):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write(synth(design))
            p = f.name
        for name, fn, want in (("pick", analyse_pick, want_pick), ("axe", analyse_axe, want_axe)):
            with contextlib.redirect_stdout(io.StringIO()):
                got = fn(p)
            ok = got == want
            print("selftest %-5s %-7s log -> exit %d (want %d)  %s"
                  % ("ok" if ok else "FAIL", name, got, want,
                     "pre-design" if not design else "design-conformant"))
            bad += 0 if ok else 1
        os.unlink(p)
    print("selftest: %s" % ("pass" if not bad else "FAIL"))
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3 or sys.argv[1] not in ("pick", "axe"):
        print(__doc__)
        sys.exit(2)
    sys.exit((analyse_pick if sys.argv[1] == "pick" else analyse_axe)(sys.argv[2]))
