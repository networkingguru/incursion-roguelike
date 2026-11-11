#!/usr/bin/env python3
"""The value mapping of tools/char_convert.sh (bead inc-10v7f, spec section 8).

ponytail: this helper and tools/char_convert.sh stay only until the epic
conversion lands (inc-pu6v.369); then both are deleted. The ceiling: the
tables below map what a canonical dump states as a DECISION: names, base
attributes, hit and mana rolls, the creation seeds (MAP); the starting perks,
the feat queue, the skill ranks, the kit and two item quantities (LISTS).
Abilities, derived attributes and the equipment arrangement are RESULTS of
those decisions under the current rules; nothing here sets them, and a
difference left in them is the conversion's finding (a rule changed since the
old save was made). A fact the dump does not state (an ability perk's value,
the item of an item perk) stops the conversion and is named.

Usage:
  tools/char_convert_map.py selftest
      Prove, on synthetic input, that the perk charges follow their item and that
      merged stacks keep their sources. Exit 0 all hold.
  tools/char_convert_map.py excuse <choices-diff.txt>
      Read the output of `canon_compare.py --choices-diff` (lines `- old` and
      `+ built`). Pass it through KNOWN_DIFFERENCES: print `excused: <old> -> <built> --
      <cause>` for each pair a row covers, then `remainder:` lines for the rest.
      Exit 0 the remainder is empty; 1 it is not.
  tools/char_convert_map.py causes
      Prove each KNOWN_DIFFERENCES row's cause is live: `commit <sha>` resolves
      with git; `bead <id>` is not closed: `bd show <id> --json`, or the JSONL (one object per
      line) that CHAR_CONVERT_BEADS names. Exit 0 all live; 1 a row is stale (delete it);
      2 COULD NOT MEASURE (no bd, no JSON).
  tools/char_convert_map.py options <old.canon> <walk.canon> <manifest-settings> <dir>
      Print the settings file in <dir> (options-*.dat) whose options equal the
      old save's. <walk.canon> is the dump of the save a walk wrote under the
      MANIFEST settings; an option that differs from the file there is one the
      engine sets on its own, and is not compared. Exit 0 printed; 1 none
      matches (the differing options are printed).
  tools/char_convert_map.py convert <old.canon> <built.canon> <in.char> <out.char>
           [--withhold <key>] [--report <file>] [--unset <file>] [--rolls <file>]
      Read the two canonical dumps (tools/char_dump.sh) and the skeleton
      .char. Set each scalar the MAP table names, then replace each list the
      LISTS table names, where the old dump states another value than the
      dump of the build. Prints one line per value set; --report writes them,
      each led by its kind (scalar, perk, feat, skill, kit, quantity). Also
      prints one `unset <kind>:` line for each value it could not set from the
      dump and the dump shows only as a result (--unset writes them; --rolls
      names the .rolls file of the walk, whose keys char_roll_search.py sets).
      Exit: 0 done; 2 bad usage, or a fact the dump does not state.
"""
import functools
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_LINE = re.compile(r"^([a-z][a-z0-9_]*)(?: \[([^\]]*)\])?: ?(.*)$")


class Stop(Exception):
    """A fact the dump does not state, or a list the table cannot place."""


# Values the converter does not set from the old dump and that the dump shows
# only through a result (phase 11g, A5): each is named in the output, never
# left as a difference that reads as a rule change. Entries are (kind, text).
UNSET = []


# ---------------------------------------------------------------- the tables

# SCALARS. dump line pattern -> the .char lines it states.
# Each target is (key, context, value); \1, \2 are the pattern's groups, and
# {lower}(\1) is the group in lower case. The context is the text between the
# brackets, or "" for a line without one.
MAP = [
    (r"^Name: (\S+) (.+)$",
        [("name", "", r"\1"), ("surname", "", r"\2"), ("character_name", "", r"\1 \2")]),
    (r"^HitRolls\[\d+:([^-][^\]]*)\]: (-?\d+)(?: -?\d+)*$", [("hp_roll", r"\1", r"\2")]),
    (r"^ManaRolls\[\d+:([^-][^\]]*)\]: (-?\d+)(?: -?\d+)*$", [("mana_roll", r"\1", r"\2")]),
    (r"^BaseAttr A_([A-Z]+): (-?\d+)$", [("attr_{lower}(\\1)", "", r"\2")]),
    (r"^storeSeed: (-?\d+)$", [("store_seed", "", r"\1")]),
    (r"^formulaSeed: (-?\d+)$", [("formula_seed", "", r"\1")]),
    (r"^statMethod: (-?\d+)$", [("stat_method", "", r"\1")]),
    (r"^rerollCount: (-?\d+)$", [("rerolls", "", r"\1")]),
    (r"^rerolledPerks: (-?\d+)$", [("rerolled_perks", "", r"\1")]),
    (r"^Flags: .*Wizard=(-?\d+) Explore=(-?\d+)\s*$", [("wizard_mode", "", r"\1"), ("explore_mode", "", r"\2")]),
]

# KEYS THE DUMP SHOWS DIRECTLY (phase 11h). A key kept as the walk recorded it is named in the output
# unless the dump states its value on a line the comparison reads, so that a wrong value is a visible
# difference. The prefix form (`attr_`) covers a family. `seed` and `options` are data lines, not decisions.
# Each entry says where the dump shows it.
SHOWN = {
    "name": "Identity Name", "surname": "Identity Name", "character_name": "Identity Name",
    "race": "Identity Race", "subrace": "Identity mID", "class": "Identity Class[0]", "god": "Identity God",
    "alignment": "Player Stati ALIGNMENT", "personality": "Perk Block Personality",
    "hp_roll": "Level Rolls HitRolls", "mana_roll": "Level Rolls ManaRolls", "skill_ranks": "Skill Ranks",
    "formula_seed": "Perk Block formulaSeed", "store_seed": "Perk Block storeSeed",
    "stat_method": "Perk Block statMethod", "rerolls": "Perk Block rerollCount",
    "rerolled_perks": "Perk Block rerolledPerks", "wizard_mode": "Player State Flags",
    "explore_mode": "Player State Flags", "feat": "Feats", "natural_aptitude": "Feats SkillFlag",
    "feat_weapon": "Feats", "spell_learn": "Spells", "attr_": "Attributes BaseAttr",
}
DATA_LINES = ("seed", "options")

# PERKS. The dump keeps no perk block; the journal lists the granted perks
# ("Starting Perks:", src/Create.cpp NamePerk). One row per journal label:
# (label, PerkType, the .char key, the journal text pattern, the value, the
# kind of name the value is: "" none, "effect" resolve in program.i).
# A row with no PerkType is a perk the journal does not state fully; its
# fourth field says what is missing.
PERK_LABELS = [
    ("Bonus Feat",     "PERK_FEAT",   "perk_feat",   r"^(.+)$", r"\1", ""),
    ("Wild Talent",    "PERK_TALENT", "perk_spell",  r"^(.+)$", r"\1", "effect"),
    ("Innate Spell",   "PERK_SPELL",  "perk_spell",  r"^(.+)$", r"\1", "effect"),
    ("Resistance",     "PERK_RESIST", "perk_resist", r"^(.+) \+10$", r"\1", ""),
    ("Save Bonus",     "PERK_RESIST", "perk_resist", r"^\+4 vs\. (.+)$", r"save {lower}(\1)", ""),
    ("Immunity",       "PERK_IMMUNE", "perk_immune", r"^(.+)$", r"\1", ""),
    ("Extra Ability",  None, "perk_ability",
        "the journal omits the ability value when it is 1 or less"),
    ("Favoured Enemy", None, "perk_ability",
        "the journal names the enemy type, not the ability value"),
    ("Starting Item",  None, "perk_item",
        "the journal names the item as a player reads it, not its item, effect, plus and qualities"),
]

# QUANTITIES. A carried item no kit ask made, and the roll key that sets its
# quantity (src/Create.cpp: the thrown weapons, the Beginner's Kit food, the
# ammunition of a bow). The item is named by its item name or by its type.
OTHER_QUANTITY = [(("name", "shotput"), "thrown_quantity"),
                  (("name", "food ration"), "beginkit_food"),
                  (("type", "T_MISSILE"), "ammo_quantity")]

# LISTS. name, the keys the list owns (what --withhold names).
LISTS = [
    ("perks",  ("perk_type", "perk_feat", "perk_ability", "perk_spell", "perk_resist",
                "perk_immune", "perk_item", "perk_charges")),
    ("feats",  ("feat",)),
    ("skills", ("skill_ranks",)),
    ("kit",    ("kit_item", "beginkit_item")),
    ("quantities", tuple(k for _, k in OTHER_QUANTITY)),
]

# Item flags the writer spells as words (inc/Defines.h IF_*).
ITEM_FLAGS = [(0x0001, "blessed"), (0x0002, "cursed"), (0x0008, "masterwork"), (0x0080, "runic")]


# --------------------------------------------------------------- the readers

@functools.lru_cache(maxsize=None)
def read_defines(prefix):
    """{name: value} of the `#define <prefix>...` lines of inc/Defines.h."""
    out = {}
    for line in open(os.path.join(ROOT, "inc", "Defines.h"), errors="replace"):
        m = re.match(r"^#define\s+(%s\w*)\s+(-?\d+)\b" % prefix, line)
        if m:
            out.setdefault(m.group(1), int(m.group(2)))
    return out


class Names:
    """Item and effect names with their tags, from lib/program.i (the
    preprocessed module: the engine's FindResource reads the same names)."""

    def __init__(self):
        self.full = {"item": {}, "effect": {}}
        path = os.path.join(ROOT, "lib", "program.i")
        if not os.path.exists(path):
            raise Stop("lib/program.i is missing; build the module first")
        for line in open(path, errors="replace"):
            m = re.search(r'\b(Item|Effect|Spell)\s+"([^"]+)"\s*:', line)
            if not m:
                continue
            kind = "item" if m.group(1) == "Item" else "effect"
            name = m.group(2)
            lst = self.full[kind].setdefault(name.split(";")[0], [])
            if name not in lst:
                lst.append(name)

    def resolve(self, kind, base, hint=""):
        cands = self.full[kind].get(base)
        if not cands:
            raise Stop("no %s named \"%s\" in lib/program.i" % (kind, base))
        if len(cands) == 1:
            return cands[0]
        tagged = [c for c in cands if c.endswith(";" + hint)] if hint else []
        if len(tagged) == 1:
            return tagged[0]
        raise Stop("\"%s\" names %d %ss (%s); the dump keeps the name without its tag"
                   % (base, len(cands), kind, ", ".join(cands)))


def sections(path):
    secs, cur = {}, None
    for line in open(path, errors="replace").read().split("\n"):
        m = re.match(r"^=== (.*) ===$", line)
        if m:
            cur = m.group(1)
            secs.setdefault(cur, [])
            continue
        if cur is not None:
            secs[cur].append(line)
    return secs


def sect(secs, prefix):
    for k, v in secs.items():
        if k.startswith(prefix):
            return v
    return []


def parse_items(secs):
    """The Kit section as a list of dicts, in the dump's order. The dump lists
    every carried item as an Inv# entry, the contents of a container too, and
    nests the contents again under the container: only the Inv# entries
    (two spaces of indent) are read."""
    items, cur = [], None
    for line in sect(secs, "Kit"):
        m = re.match(r"^( *)- Item iID=(.*?) eID=(.*?) Type=(\S+)$", line)
        if m and len(m.group(1)) != 2:
            cur = None
            continue
        if m:
            cur = {"iid": m.group(2), "eid": m.group(3), "type": m.group(4), "quals": [],
                   "bane": "#0", "stati": [], "gen": 10 ** 9, "plus": 0, "charges": 0,
                   "qty": 1, "iflags": 0}
            items.append(cur)
            continue
        if cur is None:
            continue
        m = re.match(r"^\s+Known=\S+ Plus=(-?\d+) Charges=(-?\d+) DmgType=-?\d+ "
                     r"(?:GenNum=(-?\d+) )?Flavor=\S+ homeID=.* HP=-?\d+ (?:Age=-?\d+ )?"
                     r"Swing=\d+ Quantity=(\d+) IFlags=0x([0-9a-f]+)$", line)
        if m:
            cur["plus"], cur["charges"] = int(m.group(1)), int(m.group(2))
            if m.group(3) is not None:
                cur["gen"] = int(m.group(3))
            cur["qty"], cur["iflags"] = int(m.group(4)), int(m.group(5), 16)
            continue
        m = re.match(r"^\s+Qualities: (.*) Known=0x[0-9a-f]+$", line)
        if m:
            cur["quals"] = re.findall(r"\[\d+\]=(\S+)", m.group(1))
            continue
        m = re.match(r"^\s+Bane: (\S+)$", line)
        if m:
            cur["bane"] = m.group(1)
            continue
        m = re.match(r"^\s+Stati: Nature=(\S+) Val=(-?\d+) Mag=(-?\d+) Duration=(-?\d+) "
                     r"Source=\S+ CLev=\d+ Dis=\d+ Once=\d+ eID=(.*)$", line)
        if m:
            cur["stati"].append(m.groups())
    return items


def base_name(n):
    return n.split(";")[0]


def split_item_text(text):
    """The writer's item text -> pieces: [name, 'effect X', 'plus 1', ...]."""
    words = ("effect", "plus", "bane", "flag", "quality", "quantity", "charges", "stati")
    pieces, start, pos = [], 0, 0
    while True:
        pos = text.find(", ", pos)
        if pos < 0:
            break
        if any(text.startswith(w + " ", pos + 2) for w in words):
            pieces.append(text[start:pos])
            start = pos + 2
        pos += 2
    pieces.append(text[start:])
    return pieces


def parse_item_text(text):
    """A kit_item value -> {name, effect, plus, quantity, charges, quals}."""
    p = split_item_text(text.strip())
    d = {"name": p[0], "effect": "", "plus": 0, "quantity": 0, "charges": 0, "quals": []}
    for f in p[1:]:
        w, _, rest = f.partition(" ")
        if w == "effect":
            d["effect"] = rest
        elif w in ("plus", "quantity", "charges"):
            try:
                d[w] = int(rest)
            except ValueError:
                pass
        elif w == "quality":
            d["quals"].append(rest)
    return d


# ------------------------------------------------------------ scalar mapping

def expand(tmpl, m):
    out = re.sub(r"\{lower\}\(\\(\d)\)", lambda g: m.group(int(g.group(1))).lower(), tmpl)
    return m.expand(out)


def targets(dump_path):
    """Ordered list of (key, ctx, value) the dump states, by MAP."""
    out = []
    for line in open(dump_path, errors="replace").read().split("\n"):
        for pat, tgts in MAP:
            m = re.match(pat, line)
            if m:
                for key, ctx, val in tgts:
                    out.append((expand(key, m), expand(ctx, m), expand(val, m)))
    return out


def fmt(key, ctx):
    return "%s%s" % (key, " [%s]" % ctx if ctx else "")


def key_of(line):
    m = CHAR_LINE.match(line)
    return m.group(1) if m else None


def set_scalars(lines, old_p, built_p, withhold, done):
    old, built = targets(old_p), targets(built_p)
    built_by, seen = {}, {}
    for key, ctx, val in built:
        n = seen.get((key, ctx), 0)
        seen[(key, ctx)] = n + 1
        built_by[(key, ctx, n)] = val
    where, count = {}, {}
    for i, l in enumerate(lines):
        m = CHAR_LINE.match(l)
        if m:
            k, c = m.group(1), m.group(2) or ""
            n = count.get((k, c), 0)
            count[(k, c)] = n + 1
            where[(k, c, n)] = i
    seen = {}
    for key, ctx, val in old:
        n = seen.get((key, ctx), 0)
        seen[(key, ctx)] = n + 1
        if built_by.get((key, ctx, n)) == val or key == withhold:
            continue
        i = where.get((key, ctx, n))
        if i is None:
            raise Stop("the dump states %s = %s but the skeleton has no such line" % (fmt(key, ctx), val))
        old_val = CHAR_LINE.match(lines[i]).group(3)
        lines[i] = "%s: %s" % (fmt(key, ctx), val)
        done.append(("scalar", "%s: %s -> %s" % (fmt(key, ctx), old_val, val)))


# -------------------------------------------------------------------- lists

def journal_perks(secs):
    """The granted perks a journal lists: [(label, text)]."""
    out, on = [], False
    for line in sect(secs, "Derived Sheet"):
        if re.match(r"^\s*Starting Perks:\s*$", line):
            on = True
            continue
        if not on:
            continue
        m = re.match(r"^\s+([A-Za-z ]+): (.*?)\.?\s*$", line)
        if not m:
            break
        out.append((m.group(1).strip(), m.group(2)))
    return out


def old_perks(old_secs, built_secs, names):
    """The granted perks the old journal lists: [(type, key, value)], or None
    where the old journal says what the build's says (the skeleton's line
    stands, whatever the journal leaves out of it)."""
    built = journal_perks(built_secs)
    out = []
    for n, (label, val) in enumerate(journal_perks(old_secs)):
        if n < len(built) and built[n] == (label, val):
            out.append(None)
            continue
        row = next((r for r in PERK_LABELS if r[0] == label), None)
        if row is None:
            raise Stop("the journal lists a perk labelled \"%s\" that the table does not know" % label)
        if row[1] is None:
            raise Stop("perk \"%s: %s\" cannot be set from the dump: %s (key %s)"
                       % (label, val, row[3], row[2]))
        pm = re.match(row[3], val)
        if not pm:
            raise Stop("perk \"%s: %s\" does not read as %s" % (label, val, row[3]))
        v = expand(row[4], pm)
        if row[5]:
            v = names.resolve("effect", v)
        out.append((row[1], row[2], v))
    return out


def perk_slots(lines):
    """{slot: {"type": (line, value), "field": (line, key, value)}}."""
    slots = {}
    for i, l in enumerate(lines):
        m = CHAR_LINE.match(l)
        if not m or not m.group(1).startswith("perk_") or m.group(1) == "perk_charges":
            continue
        rec = slots.setdefault(int(m.group(2)), {"type": None, "field": None})
        if m.group(1) == "perk_type":
            rec["type"] = (i, m.group(3))
        else:
            rec["field"] = (i, m.group(1), m.group(3))
    return slots


def replace_perks(lines, perks, done):
    """Edits {line index: replacement lines} that make the skeleton's perk
    slots, in order, the old granted perks. Slots past them stay."""
    slots = perk_slots(lines)
    order = sorted(slots)
    if len(perks) > len(order):
        raise Stop("the old character was granted %d perks; the skeleton asks for %d (perk_type)"
                   % (len(perks), len(order)))
    edits, charge_drop = {}, []
    item_slots = [s for s in order if slots[s]["type"] and slots[s]["type"][1] == "PERK_ITEM"]

    def item_name(slot):   # the item a PERK_ITEM slot makes, named as perk_charges [<item>] names it
        f = slots[slot]["field"]
        return base_name(parse_item_text(f[2])["name"]) if f and f[1] == "perk_item" else None
    for k, perk in enumerate(perks):
        if perk is None:
            continue
        ptype, key, val = perk
        s = order[k]
        rec = slots[s]
        cur = (rec["type"][1], rec["field"][1], rec["field"][2]) if rec["type"] and rec["field"] else None
        if cur == (ptype, key, val):
            continue
        edits[rec["type"][0]] = ["perk_type [%d]: %s" % (s, ptype), "%s [%d]: %s" % (key, s, val)]
        if rec["field"]:
            edits[rec["field"][0]] = []
        done.append(("perk", "perk [%d]: %s -> %s %s" % (
            s, "%s %s" % (cur[0], cur[2]) if cur else "(none)", ptype, val)))
        if s in item_slots:
            # the charges line of that item: the nth line of its context, n counting the item slots of that name before this one
            name = item_name(s)
            nth = len([t for t in item_slots if t < s and item_name(t) == name])
            charge_drop.append((name, nth))
    for name, nth in charge_drop:
        same = [i for i, l in enumerate(lines)
                if key_of(l) == "perk_charges" and (CHAR_LINE.match(l).group(2) or "") == name]
        if nth < len(same):
            edits[same[nth]] = []
            done.append(("perk", "%s dropped (its perk is no longer an item)" % lines[same[nth]]))
        # no line: an item that is no wand or staff draws no charges
    return edits


def feat_names(path):
    return [m.group(1) for l in sect(sections(path), "Feats")
            for m in [re.match(r"^Feat (?!\(unnamed)(.+)$", l)] if m]


def replace_feats(lines, old_p, built_p, skel_perk_feats, old_perk_feats, done):
    """The feats the screens asked for: what the old character has, less the
    build's own grants (race, class) and its perk feats."""
    old_f, built_f = feat_names(old_p), feat_names(built_p)
    chosen_s = [CHAR_LINE.match(l).group(3) for l in lines if key_of(l) == "feat"]
    auto = [f for f in built_f if f not in chosen_s and f not in skel_perk_feats]
    chosen_o = [f for f in old_f if f not in auto and f not in old_perk_feats]
    if sorted(chosen_o) == sorted(chosen_s):
        return {}
    idx = [i for i, l in enumerate(lines) if key_of(l) == "feat"]
    edits = {}
    if idx:
        edits[idx[0]] = ["feat: %s" % f for f in chosen_o]
        for i in idx[1:]:
            edits[i] = []
    else:
        edits[len(lines)] = ["feat: %s" % f for f in chosen_o]
    done.append(("feat", "feat queue: %s -> %s" % (", ".join(chosen_s) or "(none)", ", ".join(chosen_o) or "(none)")))
    if len(chosen_o) != len(chosen_s):
        done.append(("feat", "NOTE the old queue has %d feats, the skeleton asked for %d: the build decides"
                     % (len(chosen_o), len(chosen_s))))
    return edits


def replace_skills(lines, old_p, built_p, done):
    nums = read_defines("SK_")
    last = nums["SK_LASTSKILL"]
    idx = [i for i, l in enumerate(lines) if key_of(l) == "skill_ranks"]
    if not idx:
        return {}
    if len(idx) != last:
        raise Stop("the skeleton has %d skill_ranks lines, the module has %d skills (skill_ranks)"
                   % (len(idx), last))

    def ranks(path):
        r = {}
        for l in sect(sections(path), "Skill Ranks"):
            m = re.match(r"^Skill (SK_\w+): (\d+)$", l)
            if m:
                if m.group(1) not in nums:
                    raise Stop("the dump names skill %s, which inc/Defines.h does not define" % m.group(1))
                r[nums[m.group(1)]] = int(m.group(2))
        return r
    old_r, built_r = ranks(old_p), ranks(built_p)
    skel_r = {}
    for j, i in enumerate(idx):
        v = int(CHAR_LINE.match(lines[i]).group(3))
        if v:
            skel_r[j] = v
    if skel_r != built_r:
        raise Stop("the skeleton's skill_ranks lines are not in skill-number order: the build's ranks "
                   "differ from them (skill_ranks)")
    edits = {}
    for j, i in enumerate(idx):
        want, have = old_r.get(j, 0), skel_r.get(j, 0)
        if want != have:
            m = CHAR_LINE.match(lines[i])
            edits[i] = ["skill_ranks [%s]: %d" % (m.group(2), want)]
            done.append(("skill", "skill_ranks [%s]: %d -> %d" % (m.group(2), have, want)))
    return edits


def merge_stacks(items):
    """One logical item per kind: the engine splits a stack across the hand,
    the belt and the pack, and the split is an arrangement, not a decision."""
    out, seen = [], {}
    for it in items:
        k = (base_name(it["iid"]), base_name(it["eid"]), it["plus"], it["charges"],
             tuple(it["quals"]), it["iflags"] & 0x8b, it["bane"], tuple(it["stati"]))
        if k in seen:
            seen[k]["qty"] += it["qty"]
            seen[k]["gen"] = min(seen[k]["gen"], it["gen"])
        else:
            seen[k] = dict(it)
            out.append(seen[k])
    return out


def item_sig(it):
    return (base_name(it["iid"]), base_name(it["eid"]), it["plus"], it["charges"], it["qty"],
            tuple(it["quals"]), it["iflags"] & 0x8b, it["bane"])


def quality_names(quals):
    """The writer's names for a list of dump qualities (`#<n>` becomes its IQ_ name)."""
    out = []
    for q in quals:
        m = re.match(r"^#(\d+)$", q)
        if m:
            nm = next((k for k, v in read_defines("IQ_").items() if v == int(m.group(1))), None)
            if nm is None:
                raise Stop("a quality number %s has no IQ_ name (kit_item)" % m.group(1))
            q = nm
        out.append(q)
    return out


def item_text(it, plus, quals, names):
    """The writer's text (ItemText, src/CreationSource.cpp) for a dump item."""
    hint = base_name(it["iid"])
    s = names.resolve("item", base_name(it["iid"]))
    if it["eid"] != "-":
        s += ", effect " + names.resolve("effect", base_name(it["eid"]), hint)
    if plus:
        s += ", plus %d" % plus
    if it["bane"] != "#0":
        ma = read_defines("MA_")
        if it["bane"] not in ma:
            raise Stop("an item's bane %s has no number (kit_item)" % it["bane"])
        s += ", bane %d" % ma[it["bane"]]
    for bit, word in ITEM_FLAGS:
        if it["iflags"] & bit:
            s += ", flag " + word
    for q in quals:
        m = re.match(r"^#(\d+)$", q)
        if m:
            nm = next((k for k, v in read_defines("IQ_").items() if v == int(m.group(1))), None)
            if nm is None:
                raise Stop("a quality number %s has no IQ_ name (kit_item)" % m.group(1))
            q = nm
        s += ", quality " + q
    s += ", quantity %d" % it["qty"]
    if it["charges"]:
        s += ", charges %d" % it["charges"]
    for nat, val, mag, dur, eid in it["stati"]:
        s += ", stati %s val %s mag %s duration %s" % (nat, val, mag, dur)
        if eid != "-":
            s += " effect " + names.resolve("effect", base_name(eid))
    return s


def other_match(b, spec):
    """Is the built item `b` the one an OTHER_QUANTITY spec names?"""
    kind, val = spec
    return base_name(b["iid"]) == val if kind == "name" else b["type"] == val


def kit_line_text(o, i, lines, ask_item, built_items, names, qty):
    """The kit_item text that makes the old item `o` at the ask on line i, with
    `qty` as its quantity."""
    m = CHAR_LINE.match(lines[i])
    quals, plus = list(o["quals"]), o["plus"]
    if i in ask_item:   # what the build adds to this item itself is not stated
        b = built_items[ask_item[i]]
        stated = parse_item_text(m.group(3))
        plus = stated["plus"]
        rest = list(b["quals"])
        for q in stated["quals"]:
            if q in rest:
                rest.remove(q)
        for q in rest:
            if q in quals:
                quals.remove(q)
        if sorted(o["quals"]) == sorted(b["quals"]):
            # The same qualities. The skeleton's stated plus builds b["plus"] (the script of the ask may add a
            # plus that depends on the stated one, such as the Warrior's +1 only below 1), so the stated plus
            # is kept: exact when the old plus is the built one, and named when it is not.
            if o["plus"] != b["plus"]:
                UNSET.append(("kit", "%s: plus stays %d (the build makes plus %d from it); the old %s has plus %d, and the "
                              "birth script of the ask may add a plus that depends on the stated one, which the dump does not say"
                              % (fmt(m.group(1), m.group(2) or ""), plus, b["plus"], base_name(o["iid"]), o["plus"])))
        elif plus != o["plus"]:
            UNSET.append(("kit", "%s: plus stays %d; the old %s has plus %d and qualities [%s], the build's has [%s], "
                          "and the dump does not say how much of a plus a quality adds"
                          % (fmt(m.group(1), m.group(2) or ""), plus, base_name(o["iid"]), o["plus"],
                             " ".join(o["quals"]), " ".join(b["quals"]))))
    return item_text(dict(o, qty=qty), plus, quals, names)


def replace_kit(lines, old_p, built_p, names, done, other_out):
    """The kit asks (kit_item, beginkit_item) take the items the old character
    holds. A kit ask takes the old item of its own name (the same item first,
    then the same name); the rest go in the order of asking against the order
    the old game made them (GenNum). The Beginner's Kit is the old run made
    between the last paired class kit item and the first paired Universal Gear
    item (or the kit's food ration). The engine merges equal stacks: asks whose
    quantities add up to one built stack are one group (a kit_item and a beginkit_item ask alike), and the old stack's
    quantity is shared out over them; a quantity key that feeds the same stack
    keeps its value."""
    old_items = merge_stacks(parse_items(sections(old_p)))
    built_items = merge_stacks(parse_items(sections(built_p)))
    if sorted(map(item_sig, old_items)) == sorted(map(item_sig, built_items)):
        return {}   # the same items already: nothing in the kit to set
    ask_lines = {k: [i for i, l in enumerate(lines) if key_of(l) == k]
                 for k in ("kit_item", "beginkit_item")}
    asks = ask_lines["kit_item"] + ask_lines["beginkit_item"]
    # 1. each skeleton ask -> the item of the build it made (the same
    # quantity first, then any of that name). A kit_item ask also joins a stack
    # the engine merged: the asks' quantities add up to the stack's.
    used, ask_item, left = set(), {}, {}
    for exact in (True, False):
        for i in asks:
            text = CHAR_LINE.match(lines[i]).group(3).strip()
            if text == "none" or i in ask_item:
                continue
            d = parse_item_text(text)
            for bi, b in enumerate(built_items):
                if (base_name(b["iid"]) != base_name(d["name"])
                        or base_name(b["eid"]) != (base_name(d["effect"]) or "-")):
                    continue
                if bi in used:
                    if (not exact and d["quantity"]
                            and left.get(bi, 0) >= d["quantity"]):
                        left[bi] -= d["quantity"]
                        ask_item[i] = bi
                        break
                    continue
                if exact and d["quantity"] and b["qty"] != d["quantity"]:
                    continue
                used.add(bi)
                ask_item[i] = bi
                left[bi] = b["qty"] - d["quantity"] if d["quantity"] else 0
                break
    group = {}   # built item -> its asks, in the order of asking
    for i in sorted(ask_item):
        group.setdefault(ask_item[i], []).append(i)
    # 2. the items no ask made (holy symbol, thrown weapons, food ...) and the
    # old character's counterpart of each, by item and effect name.
    pool = sorted(range(len(old_items)), key=lambda k: old_items[k]["gen"])
    for b in [b for bi, b in enumerate(built_items) if bi not in used]:
        match = None
        for k in pool:
            o = old_items[k]
            if base_name(o["iid"]) == base_name(b["iid"]) and base_name(o["eid"]) == base_name(b["eid"]):
                match = k
                pool.remove(k)
                break
        other_out.append((b, old_items[match] if match is not None else None))
    # 3. a kit ask takes the old item that is its own built item, else the
    # old item of its name. The asks of one group take one old item.
    paired, group_old = {}, {}
    for same in (lambda o, b: item_sig(o) == item_sig(b),
                 lambda o, b: base_name(o["iid"]) == base_name(b["iid"])
                 and base_name(o["eid"]) == base_name(b["eid"])):
        for i in ask_lines["kit_item"]:
            if i in paired or i not in ask_item:
                continue
            bi = ask_item[i]
            if bi in group_old:
                paired[i] = group_old[bi]
                continue
            b = built_items[bi]
            hit = next((k for k in pool if same(old_items[k], b)), None)
            if hit is not None:
                pool.remove(hit)
                paired[i] = group_old[bi] = hit
    pending_kit = [i for i in ask_lines["kit_item"] if i not in paired]
    # 4. the Beginner's Kit run among the rest of the old items.
    def resource(i):
        return (CHAR_LINE.match(lines[i]).group(2) or "").split(";")[0]
    # a stack the engine merged keeps the generation number of its first ask: only that ask places it in time
    placed = {i: k for i, k in paired.items() if group[ask_item[i]][0] == i}
    lo = max([old_items[k]["gen"] for i, k in placed.items() if resource(i) != "Universal Gear"], default=-1)
    hi = min([old_items[k]["gen"] for i, k in placed.items() if resource(i) == "Universal Gear"], default=10 ** 9)
    food = next((o for b, o in other_out if base_name(b["iid"]) == "food ration" and o), None)
    if food is not None and lo < food["gen"] < hi:
        hi = food["gen"]
    # The run is found whether or not the skeleton asks for it: a kit-off skeleton has no beginkit_item
    # ask, and the old (kit-on) character's Beginner's Kit items are then left out, not set (an item is not a choice).
    bk = [k for k in pool if lo < old_items[k]["gen"] < hi]
    groups = {"kit_item": [k for k in pool if k not in bk], "beginkit_item": bk}
    # a beginkit_item ask that joined the stack of a paired kit_item ask is set with that group, not by the Beginner's Kit run
    slots = {"kit_item": pending_kit,
             "beginkit_item": [i for i in ask_lines["beginkit_item"] if ask_item.get(i) not in group_old]}
    edits = {}

    def own_qty(i):
        return parse_item_text(CHAR_LINE.match(lines[i]).group(3)).get("quantity") or 0

    def put(i, o, qty=None):
        if qty is None and i in ask_item and item_sig(o) == item_sig(built_items[ask_item[i]]):
            return   # the ask already makes this item
        m = CHAR_LINE.match(lines[i])
        label = fmt(m.group(1), m.group(2) or "")
        new = kit_line_text(o, i, lines, ask_item, built_items, names, o["qty"] if qty is None else qty)
        if new != m.group(3):
            edits[i] = ["%s: %s" % (label, new)]
            done.append(("kit", "%s: %s -> %s" % (label, m.group(3), new)))
    def label_of(i):
        m = CHAR_LINE.match(lines[i])
        return fmt(m.group(1), m.group(2) or "")
    shared = {}   # built item -> handled once for all its asks
    for i, k in paired.items():
        bi = ask_item[i]
        o, b = old_items[k], built_items[bi]
        members = group[bi]
        # the quantity keys that feed the same stack (food rations: the race's ask and the kit's food)
        feeders = [key for spec, key in OTHER_QUANTITY if other_match(b, spec)
                   and any(key_of(l) == key for l in lines)]
        if len(members) == 1 and not feeders:
            put(i, o)
            continue
        if bi in shared:
            continue
        shared[bi] = True
        if item_sig(o) == item_sig(b):
            continue   # the stack is already the old one
        delta = o["qty"] - b["qty"]
        target = members[-1]   # the share the dump cannot place goes on the last ask
        # A surplus comes off the last ask first, then the one before it: an ask left with nothing is set to none.
        # A shortfall goes on the last ask.
        share, excess = {j: own_qty(j) for j in members}, -delta
        for j in reversed(members):
            take = min(share[j], max(excess, 0))
            share[j] -= take
            excess -= take
        share[target] -= min(excess, 0)
        if excess > 0 or sum(share.values()) + (b["qty"] - sum(own_qty(j) for j in members)) != o["qty"]:
            raise Stop("the old %s stack holds %d and the skeleton's other sources of it make %d (%s)"
                       % (base_name(o["iid"]), o["qty"], b["qty"] - sum(own_qty(j) for j in members), label_of(target)))
        for j in members:
            if share[j] >= 1:
                put(j, o, share[j])
            elif own_qty(j):
                m = CHAR_LINE.match(lines[j])
                edits[j] = ["%s: none" % label_of(j)]
                done.append(("kit", "%s: %s -> none (the old %s stack of %d is made by the other asks)"
                             % (label_of(j), m.group(3), base_name(o["iid"]), o["qty"])))
        if delta:
            UNSET.append(("kit", "%s: the dump shows one stack of %d where the build merged %d (%s); the split is "
                          "not in the dump, so the difference %+d went on %s"
                          % (base_name(o["iid"]), o["qty"], b["qty"],
                             ", ".join(["%s %d" % (label_of(j), own_qty(j)) for j in members]
                                       + ["%s %s" % (key, CHAR_LINE.match(next(l for l in lines if key_of(l) == key)).group(3)) for key in feeders]),
                             delta, label_of(target))))
    for key in ("kit_item", "beginkit_item"):
        have, mine = sorted(groups[key], key=lambda k: old_items[k]["gen"]), slots[key]
        if key == "beginkit_item":
            have = have[:len(mine)]   # the old kit items beyond the skeleton's asks are not choices
        if len(have) > len(mine):
            raise Stop("the old character holds %d %s item(s) the skeleton has no ask for, first: %s (%s)"
                       % (len(have) - len(mine), key, base_name(old_items[have[len(mine)]]["iid"]), key))
        if key == "kit_item":   # asks that made an item come first, the ones that made none after
            mine = [i for i in mine if i in ask_item] + [i for i in mine if i not in ask_item]
        for n, i in enumerate(mine):
            if n < len(have):
                put(i, old_items[have[n]])
            else:
                m = CHAR_LINE.match(lines[i])
                if m.group(3).strip() != "none":
                    label = fmt(m.group(1), m.group(2) or "")
                    edits[i] = ["%s: none" % label]
                    done.append(("kit", "%s: %s -> none (the old character has no item for this ask)"
                                 % (label, m.group(3))))
    return edits


def replace_quantities(lines, other, done):
    """The roll keys that set the quantity of an item no ask made (OTHER_QUANTITY):
    each takes the quantity of the old character's counterpart item."""
    edits = {}
    for spec, key in OTHER_QUANTITY:
        idx = [i for i, l in enumerate(lines) if key_of(l) == key]
        items = [(b, o) for b, o in other if other_match(b, spec)]
        if not idx:
            continue
        if len(idx) != len(items):
            if items:
                UNSET.append(("quantity", "%s: the skeleton has %d line(s) and the build %d item(s) it feeds; "
                              "no line is set from the dump" % (key, len(idx), len(items))))
            continue
        for i, (b, o) in zip(idx, items):
            if o is None:
                continue
            m = CHAR_LINE.match(lines[i])
            if int(m.group(3)) != o["qty"]:
                edits[i] = ["%s: %d" % (key, o["qty"])]
                done.append(("quantity", "%s: %s -> %d" % (key, m.group(3), o["qty"])))
    return edits


def apply_edits(lines, edits):
    out = []
    for i in range(len(lines) + 1):
        if i in edits:
            out.extend(edits[i])
        elif i < len(lines):
            out.append(lines[i])
    return out


def key_kinds():
    """{key name: ROLL, PICK or ITEM} from the CREATION_KEY_LIST table of inc/CreationSource.h."""
    text = open(os.path.join(ROOT, "inc", "CreationSource.h"), errors="replace").read()
    return {m.group(1).lower(): m.group(2) for m in re.finditer(r"X\((\w+),\s*(ROLL|PICK|ITEM),", text)}


def owned_keys():
    """The keys this tool can set from a dump: the MAP targets and the LISTS."""
    owned = set()
    for _pat, tgts in MAP:
        for key, _ctx, _val in tgts:
            owned.add(key.split("{")[0])   # "attr_{lower}(\1)" -> the prefix "attr_"
    for _name, ks in LISTS:
        owned.update(ks)
    return owned


def carry_perk_items(lines, old_p, built_p, done):
    """Each PERK_ITEM slot's item as the old dump holds it, also when the old and the built journals agree
    (the journal names the item as a player reads it): the qualities, the plus and the charges.
    The old counterpart of a slot is the n-th item of its item and effect name, oldest first (a perk item
    is made before the kit). The qualities are stated, so they are set. The stated plus is kept when the build
    already makes the old plus, and named unresolved when it does not (a quality may add a plus the dump
    does not split out). perk_charges [<item>] takes the old item's charges."""
    slots = perk_slots(lines)
    old_items = merge_stacks(parse_items(sections(old_p)))
    built_items = merge_stacks(parse_items(sections(built_p)))
    edits, seen = {}, {}
    for s_ in sorted(slots):
        rec = slots[s_]
        if not (rec["type"] and rec["type"][1] == "PERK_ITEM" and rec["field"] and rec["field"][1] == "perk_item"):
            continue
        li, _k, text = rec["field"]
        d = parse_item_text(text)
        nm, ef = base_name(d["name"]), base_name(d["effect"]) or "-"
        n = seen.get((nm, ef), 0)
        seen[(nm, ef)] = n + 1

        def pick(items):
            c = sorted([it for it in items if base_name(it["iid"]) == nm and base_name(it["eid"]) == ef],
                       key=lambda it: it["gen"])
            return c[n] if n < len(c) else None
        o, b = pick(old_items), pick(built_items)
        label = "perk_item [%d]" % s_
        if o is None or b is None:
            UNSET.append(("perk", "%s: %s; its plus, qualities and charges are kept as the walk recorded them"
                          % (label, "the old dump holds no %s" % nm if o is None else "the build holds no %s" % nm)))
            continue
        pieces = split_item_text(text.strip())
        keep = [p_ for p_ in pieces if p_.split(" ", 1)[0] not in ("quality",)]
        quals = quality_names(o["quals"])
        new_quals = ["quality " + q for q in quals]
        if sorted(o["quals"]) != sorted(b["quals"]):
            UNSET.append(("perk", "%s: plus stays %d; the old %s has plus %d and qualities [%s], the build's has [%s], "
                          "and the dump does not say how much of a plus a quality adds"
                          % (label, d["plus"], nm, o["plus"], " ".join(o["quals"]), " ".join(b["quals"]))))
        elif o["plus"] != b["plus"]:
            UNSET.append(("perk", "%s: plus stays %d (the build makes plus %d from it); the old %s has plus %d, "
                          "which the dump does not say how to state" % (label, d["plus"], b["plus"], nm, o["plus"])))
        # the qualities come after the flags and before the quantity, as item_text writes them
        out = [p_ for p_ in keep]
        at = len(out)
        for j, p_ in enumerate(out):
            if p_.split(" ", 1)[0] in ("quantity", "charges", "stati"):
                at = j
                break
        out[at:at] = new_quals
        new_text = ", ".join(out)
        if new_text != text.strip():
            edits[li] = ["perk_item [%d]: %s" % (s_, new_text)]
            done.append(("perk", "perk_item [%d]: %s -> %s" % (s_, text.strip(), new_text)))
        idx = [i for i, l in enumerate(lines) if key_of(l) == "perk_charges" and (CHAR_LINE.match(l).group(2) or "") == nm]
        if n < len(idx):
            cm = CHAR_LINE.match(lines[idx[n]])
            if int(cm.group(3)) != o["charges"]:
                edits[idx[n]] = ["perk_charges [%s]: %d" % (nm, o["charges"])]
                done.append(("perk", "perk_charges [%s]: %s -> %d" % (nm, cm.group(3), o["charges"])))
    return edits


def gear_chance_report(lines):
    """A gear_chance roll decides whether an annotation of a kit resource grants anything (its roll must
    be within the annotation's chance). The grant is derived from the old dump: the kit_item line of the
    same annotation holds the old item, or `none` when the old character holds none, or is absent. The
    roll is then kept, and each kept roll is named with what the dump says about its annotation."""
    kit = {}
    for l in lines:
        m = CHAR_LINE.match(l)
        if m and m.group(1) == "kit_item":
            kit[m.group(2) or ""] = m.group(3).strip()
    for l in lines:
        m = CHAR_LINE.match(l)
        if not (m and m.group(1) == "gear_chance"):
            continue
        ctx = m.group(2) or ""
        item = kit.get(ctx)
        if item is None:
            what = ("no kit_item line for this annotation: it grants nothing in the old character, so its roll is above its chance "
                    "or its condition is false; any value above the chance gives the same character")
        elif item == "none":
            what = ("the old character holds no item for this annotation (kit_item is none); the dump does not say whether the old roll "
                    "failed the chance, which lets an else-annotation grant, or the item pick gave nothing")
        else:
            what = "the old character holds this annotation's item (%s), so its roll is within the annotation's chance" % item
        UNSET.append(("roll", "gear_chance [%s]: %s kept as the walk recorded it; %s" % (ctx, m.group(3), what)))


def unset_kept(lines, searched):
    """Name every key of the skeleton that nothing here set from the dump, that the dump does not show
    directly (SHOWN) and that is not searched: PICK, ROLL and ITEM keys alike. gear_chance is named per
    line (gear_chance_report)."""
    kinds, owned, count = key_kinds(), owned_keys(), {}
    for l in lines:
        k = key_of(l)
        if not k or k in DATA_LINES or k in searched or k == "gear_chance":
            continue
        if any(k.startswith(o) if o.endswith("_") else k == o for o in owned):
            continue
        if any(k.startswith(o) if o.endswith("_") else k == o for o in SHOWN):
            continue
        count[k] = count.get(k, 0) + 1
    for k in sorted(count):
        UNSET.append((kinds.get(k, "?").lower(), "%s: %d line(s) kept as the walk recorded them; the dump does not show this decision directly" % (k, count[k])))
    gear_chance_report(lines)


def searched_keys(rolls):
    """The keys named in the .rolls file of the walk (tab-separated key, context, ordinal, lo, hi)."""
    if not rolls or not os.path.exists(rolls):
        return set()
    return {l.split("\t")[0] for l in open(rolls).read().split("\n") if l.strip()}


def convert(old_p, built_p, in_p, out_p, withhold, report, unset=None, rolls=None):
    lines = open(in_p).read().split("\n")
    skel_feats = [r["field"][2] for r in perk_slots(lines).values()
                  if r["type"] and r["type"][1] == "PERK_FEAT" and r["field"]]
    done, other = [], []
    del UNSET[:]
    names = Names()
    perks = old_perks(sections(old_p), sections(built_p), names)
    set_scalars(lines, old_p, built_p, withhold, done)

    def on(name):   # --withhold <key> skips the one list that owns the key
        return withhold not in next(r for r in LISTS if r[0] == name)[1]
    if on("perks"):
        lines = apply_edits(lines, replace_perks(lines, perks, done))
        lines = apply_edits(lines, carry_perk_items(lines, old_p, built_p, done))
    if on("feats"):
        lines = apply_edits(lines, replace_feats(lines, old_p, built_p, skel_feats,
                                                 [v for lab, v in journal_perks(sections(old_p)) if lab == "Bonus Feat"], done))
    if on("skills"):
        lines = apply_edits(lines, replace_skills(lines, old_p, built_p, done))
    if on("kit"):
        lines = apply_edits(lines, replace_kit(lines, old_p, built_p, names, done, other))
    if on("quantities") and other:
        lines = apply_edits(lines, replace_quantities(lines, other, done))
    unset_kept(lines, searched_keys(rolls))
    open(out_p, "w").write("\n".join(lines))
    for kind, text in done:
        print("set %s: %s" % (kind, text))
    for kind, text in UNSET:
        print("unset %s: %s" % (kind, text))
    if report:
        open(report, "w").write("".join("%s: %s\n" % (k, t) for k, t in done))
    if unset:
        open(unset, "w").write("".join("%s: %s\n" % (k, t) for k, t in UNSET))
    return 0


# ------------------------------------------------------------ the settings

def option_bytes(path):
    d = open(path, "rb").read()
    return {i: (b if b < 128 else b - 256) for i, b in enumerate(d) if b}


def dump_options(path):
    for l in open(path, errors="replace"):
        if l.startswith("Options:"):
            return {int(a): int(b) for a, b in (x.split("=") for x in l[8:].split())}
    raise Stop("%s has no Options line" % path)


KIT_OPTION = 101   # OPT_BEGINKIT, inc/Defines.h


def choose_options(old_p, walk_p, manifest, d):
    old, walk = dump_options(old_p), dump_options(walk_p)
    base = option_bytes(manifest)
    noise = {k for k in set(walk) | set(base) if walk.get(k, 0) != base.get(k, 0)}
    noise.add(KIT_OPTION)   # an item is not a choice (Brian, 2026-11-11): the kit byte is never compared
    fits, closest = [], None
    cands = sorted(glob.glob(os.path.join(d, "options-*.dat")))
    if not any(os.path.normpath(c) == os.path.normpath(manifest) for c in cands):
        cands.append(manifest)
    for c in cands:
        cb = option_bytes(c)
        diff = {k: (old.get(k, 0), cb.get(k, 0)) for k in set(old) | set(cb)
                if k not in noise and old.get(k, 0) != cb.get(k, 0)}
        if not diff:
            fits.append(c)
        elif closest is None or len(diff) < len(closest[1]):
            closest = (c, diff)
    if not fits:
        if closest is None:
            raise Stop("no options-*.dat in %s" % d)
        c, diff = closest
        print("no settings file matches the old save; closest %s differs in option(s): %s"
              % (c, ", ".join("%d (old %d, file %d)" % (k, a, b) for k, (a, b) in sorted(diff.items()))))
        return 1
    pick = next((c for c in fits if os.path.normpath(c) == os.path.normpath(manifest)), None)
    if pick is None:   # never a kit-on file unless the MANIFEST names one
        pick = next((c for c in fits if not option_bytes(c).get(KIT_OPTION, 0)), fits[0])
    if len(fits) > 1:
        print("char_convert_map: %d settings files match (%s); chose %s"
              % (len(fits), ", ".join(fits), pick), file=sys.stderr)
    print(pick)
    return 0


def selftest():
    """Phase 11g: the perk charges follow their item's context, merged stacks keep their sources, and
    a quantity key that feeds a merged stack keeps its value. Prints one line per case; exit 0 all hold."""
    import tempfile

    def canon(items):
        out = ["=== Identity ===", "=== Kit ==="]
        for n, (iid, qty, gen, plus, *quals) in enumerate(items):
            out.append("  - Item iID=%s eID=- Type=T_COIN" % iid)
            out.append("    Known=0xff Plus=%d Charges=0 DmgType=0 GenNum=%d Flavor=0 homeID=- HP=1 Age=0 Swing=0 "
                       "Quantity=%d IFlags=0x0" % (plus, gen, qty))
            if quals:
                out.append("    Qualities: %s Known=0xff" % " ".join("[%d]=%s" % (i, q) for i, q in enumerate(quals[0])))
        return "\n".join(out) + "\n"
    bad = []

    def want(label, cond, detail=""):
        print("%s %s%s" % ("ok  " if cond else "FAIL", label, (": " + detail) if detail and not cond else ""))
        if not cond:
            bad.append(label)
    # 1. perk_charges by the item's context
    base = ["perk_type [0]: PERK_ITEM", "perk_item [0]: ring, effect Channeling, plus 2",
            "perk_type [1]: PERK_ITEM", "perk_item [1]: wand, effect cracked, plus 3", "perk_charges [wand]: 36"]
    for label, perks, kept in (("the wand's perk is replaced: its charges line goes", [None, ("PERK_FEAT", "perk_feat", "Alertness")], False),
                               ("the ring's perk is replaced: the wand keeps its charges line", [("PERK_FEAT", "perk_feat", "Alertness"), None], True)):
        lines = list(base)
        done = []
        lines = apply_edits(lines, replace_perks(lines, perks, done))
        want(label, ("perk_charges [wand]: 36" in lines) == kept, "\n".join(lines))
    # 2. merged stacks (a 5-line skeleton, two dumps)
    d = tempfile.mkdtemp()
    names = Names()

    def run(skel, built, old):
        for n, items in (("built", built), ("old", old)):
            open(os.path.join(d, n), "w").write(canon(items))
        lines = list(skel)
        del UNSET[:]
        other, done = [], []
        edits = replace_kit(lines, os.path.join(d, "old"), os.path.join(d, "built"), names, done, other)
        return apply_edits(lines, edits), [t for k, t in UNSET]
    knife = ("knife", 1, 5, 0)
    # gold: two kit asks made one stack of 156; the old character has the same stack and a better knife
    out, _ = run(["kit_item [Orc;a2]: knife, quantity 1", "kit_item [Mage;a2]: gold piece, quantity 155",
                  "kit_item [Universal Gear;a9]: gold piece, quantity 1"],
                 [knife, ("gold piece", 156, 7, 0)], [("knife", 1, 5, 2), ("gold piece", 156, 15, 0)])
    want("gold: both asks keep their quantity (no ask is set to none)", out[1] == "kit_item [Mage;a2]: gold piece, quantity 155"
         and out[2] == "kit_item [Universal Gear;a9]: gold piece, quantity 1", " | ".join(out))
    # food: a race ask (6) and the kit's food key (9) made 15; the old stack is 14
    out, unset = run(["kit_item [Orc;a2]: knife, quantity 1", "kit_item [Human;a1]: food ration, quantity 6", "beginkit_food: 9"],
                     [knife, ("food ration", 15, 3, 0)], [("knife", 1, 5, 2), ("food ration", 14, 5, 0)])
    want("food: the key keeps its value, the ask takes the difference, the split is named",
         out[1] == "kit_item [Human;a1]: food ration, quantity 5" and out[2] == "beginkit_food: 9"
         and any("the split is not in the dump" in u for u in unset), " | ".join(out) + " / " + " ; ".join(unset))
    # inc-10v7f: a kit_item ask and a beginkit_item ask for the same item made one stack; the old stack is shared out
    pot = ("potion", 10, 5, 0)
    for label, skel_q, built_q, want_q in (("7+3, old 10: both keep the walk's quantity", (7, 3), 10, (7, 3)),
                                           ("7+5, old 10: the last ask takes the remainder", (7, 5), 12, (7, 3)),
                                           ("7+3, old 12: the last ask takes the extra", (7, 3), 10, None)):
        old_q = 12 if want_q is None else 10
        want_q = want_q or (7, 5)
        out, _ = run(["kit_item [Orc;a2]: knife, quantity 1", "kit_item [Dragonkin;a0]: potion, quantity %d" % skel_q[0],
                      "beginkit_item: potion, quantity %d" % skel_q[1]],
                     [knife, ("potion", built_q, 6, 0)], [("knife", 1, 5, 2), ("potion", old_q, 6, 0)])
        want("stack of two asks, " + label, out[1] == "kit_item [Dragonkin;a0]: potion, quantity %d" % want_q[0]
             and out[2] == "beginkit_item: potion, quantity %d" % want_q[1], " | ".join(out))
    out, _ = run(["kit_item [Orc;a2]: knife, quantity 1", "kit_item [Human;a2]: potion, quantity 5", "beginkit_item: potion, quantity 6"],
                 [knife, ("potion", 11, 6, 0)], [("knife", 1, 5, 2), ("potion", 5, 6, 0)])
    want("stack of two asks, old 5 against walk 5+6: the surplus takes the last ask to none",
         out[1] == "kit_item [Human;a2]: potion, quantity 5" and out[2] == "beginkit_item: none", " | ".join(out))
    out, _ = run(["kit_item [Orc;a2]: knife, quantity 1", "kit_item [Dragonkin;a0]: potion, quantity 7", "beginkit_item: none"],
                 [knife, ("potion", 7, 6, 0)], [("knife", 1, 5, 2), pot])
    want("stack of one ask (and an ask the walk gave nothing): the ask takes the old total",
         out[1] == "kit_item [Dragonkin;a0]: potion, quantity 10" and out[2] == "beginkit_item: none", " | ".join(out))
    # a quality that adds to the plus: the dump cannot say how much, so the plus stays and the output names it
    out, unset = run(["kit_item [Universal Gear;a20]: banded mail, quantity 1"],
                     [("banded mail", 1, 5, 0)], [("banded mail", 1, 5, 1, ["AQ_LIGHT_FOR"])])
    want("quality: the plus stays at the stated value and the output names it",
         any("plus stays 0" in u for u in unset) and "plus" not in out[0], " | ".join(out) + " / " + " ; ".join(unset))
    # the Warrior birth script adds +1 only below 1: a stated plus 1 builds plus 1, the old holds plus 0; the stated plus
    # is kept and the output names the item, not a guessed plus
    out, unset = run(["kit_item [Warrior;a0]: knife, plus 1, quantity 1"], [("knife", 1, 5, 1)], [("knife", 1, 5, 0)])
    want("plus: a plus the build does not reproduce is kept and named (no constant delta is assumed)",
         any("plus stays 1 (the build makes plus 1 from it)" in u for u in unset) and out == ["kit_item [Warrior;a0]: knife, plus 1, quantity 1"],
         " | ".join(out) + " / " + " ; ".join(unset))
    # 3. a perk item is carried from the dump also when the journals agree: its charges
    def item_canon(charges):
        return ("=== Identity ===\n=== Kit ===\n  - Item iID=wand eID=cracked Type=T_WAND\n    Known=0xff Plus=3 Charges=%d "
                "DmgType=0 GenNum=11 Flavor=0 homeID=- HP=1 Age=0 Swing=0 Quantity=1 IFlags=0x0\n" % charges)
    open(os.path.join(d, "old"), "w").write(item_canon(40))
    open(os.path.join(d, "built"), "w").write(item_canon(36))
    lines = ["perk_type [1]: PERK_ITEM", "perk_item [1]: wand, effect cracked, plus 3", "perk_charges [wand]: 36"]
    del UNSET[:]
    out = apply_edits(lines, carry_perk_items(lines, os.path.join(d, "old"), os.path.join(d, "built"), []))
    want("perk item: perk_charges takes the old item's charges", out[2] == "perk_charges [wand]: 40" and out[1] == lines[1],
         " | ".join(out))
    # 4. the unset report names a PICK key and each gear_chance line, and the wizard and explore flags are mapped
    del UNSET[:]
    unset_kept(["alter_options: no", "gear_chance [Universal Gear;a3]: 54", "kit_item [Universal Gear;a16]: hide armour, quantity 1",
                "gear_chance [Universal Gear;a16]: 3"], set())
    want("unset report: a PICK key and each gear_chance line are named",
         any(u.startswith("alter_options: 1 line") for k, u in UNSET) and len([1 for k, u in UNSET if u.startswith("gear_chance")]) == 2
         and any("holds this annotation's item" in u for k, u in UNSET) and any("no kit_item line" in u for k, u in UNSET),
         " ; ".join(u for k, u in UNSET))
    open(os.path.join(d, "flags"), "w").write("Flags: statiChanged=0 shownFF=1 Victory=0 Quit=0 UpdateMap=0 Dig=0 Wizard=1 Explore=0\n")
    want("scalars: the Flags line states wizard_mode and explore_mode",
         ("wizard_mode", "", "1") in targets(os.path.join(d, "flags")) and ("explore_mode", "", "0") in targets(os.path.join(d, "flags")))
    return 1 if bad else 0


# The conversion passes when the CHOICES of the build equal the choices of the old
# save (canon_compare.py --choices). A row here names one difference that a rule
# change since the old save was made causes, so a reader sees what was excused and
# why. A row covers EXACT lines; a line no row covers fails the conversion.
# A row whose cause is fixed MUST be deleted (tools/check_char_convert.sh).
KNOWN_DIFFERENCES = [
    {"name": "devouring-to-cannibalism", "cause": "commit 4e1fc266",
     "kinds": ["Special Abilities: Devouring -> Feats: Cannibalism"],
     "old_to_built": lambda old: "Feats: Cannibalism" if old == "Special Abilities: Devouring" else None},
]


def excuse(old_only, built_only):
    """(excused, old_rest, built_rest): excused is [(old, built, row)]. Each excused
    pair consumes one old-only and one built-only line; nothing else is dropped."""
    old_rest, built_rest, excused = list(old_only), list(built_only), []
    for row in KNOWN_DIFFERENCES:
        for old in list(old_rest):
            want = row["old_to_built"](old)
            if want is not None and want in built_rest:
                old_rest.remove(old)
                built_rest.remove(want)
                excused.append((old, want, row))
    return excused, old_rest, built_rest


def read_choices_diff(path):
    old, built = [], []
    for l in open(path, errors="replace").read().split("\n"):
        if l.startswith("- "):
            old.append(l[2:])
        elif l.startswith("+ "):
            built.append(l[2:])
    return old, built


def bead_status(ref):
    """The status of bead <ref>: from the JSONL named by CHAR_CONVERT_BEADS (one object
    per line; the controls use it), else from `bd show <ref> --json`. Returns the status
    string, None when the bead is not found, and raises Stop when neither source works."""
    import json
    env = os.environ.get("CHAR_CONVERT_BEADS")
    if env:
        if not os.path.exists(env):
            raise Stop("COULD NOT MEASURE: CHAR_CONVERT_BEADS=%s does not exist" % env)
        status = None
        for l in open(env, errors="replace"):
            try:
                d = json.loads(l)
            except ValueError:
                continue
            if isinstance(d, dict) and d.get("id") == ref:
                status = d.get("status")
        return status
    cmd = "bd show %s --json" % ref
    try:
        r = subprocess.run(["bd", "show", ref, "--json"], capture_output=True, text=True, cwd=ROOT)
        d = json.loads(r.stdout)
    except (OSError, ValueError) as e:
        raise Stop("COULD NOT MEASURE: `%s` gave no JSON (%s)" % (cmd, e))
    if isinstance(d, list):
        d = d[0] if d else None
    if not isinstance(d, dict) or "status" not in d:
        raise Stop("COULD NOT MEASURE: `%s` printed no object with a status" % cmd)
    return d["status"]


def causes(rows=None):
    """0 all rows live, 1 a row is stale, 2 the bead status could not be measured."""
    rc = 0
    for row in (KNOWN_DIFFERENCES if rows is None else rows):
        kind, _, ref = row["cause"].partition(" ")
        if kind == "commit":
            ok = subprocess.run(["git", "-C", ROOT, "cat-file", "-e", ref + "^{commit}"],
                                capture_output=True).returncode == 0
            if not ok:
                print("stale: row %s names %s, which git does not resolve; delete the row" % (row["name"], row["cause"]))
                rc = max(rc, 1)
        elif kind == "bead":
            try:
                status = bead_status(ref)
            except Stop as e:
                print(e)
                return 2
            if status is None or status == "closed":
                print("stale: row %s names %s, which is %s; the row is stale and must be deleted" % (row["name"], row["cause"], status or "not found"))
                rc = max(rc, 1)
        else:
            print("stale: row %s has a cause that is neither commit nor bead: %s" % (row["name"], row["cause"]))
            rc = max(rc, 1)
    return rc


def cmd_excuse(path):
    old, built = read_choices_diff(path)
    excused, old_rest, built_rest = excuse(old, built)
    for o, b, row in excused:
        print("excused: %s -> %s -- %s (%s)" % (o, b, row["cause"], row["name"]))
    for l in old_rest:
        print("remainder: - %s" % l)
    for l in built_rest:
        print("remainder: + %s" % l)
    return 0 if not old_rest and not built_rest else 1


def main(argv):
    args = argv[1:]
    try:
        if len(args) == 2 and args[0] == "excuse":
            return cmd_excuse(args[1])
        if args == ["causes"]:
            return causes()
        if args == ["selftest"]:
            return selftest()
        if args and args[0] == "options" and len(args) == 5:
            return choose_options(*args[1:])
        if args and args[0] == "convert":
            args = args[1:]
            opt = {"--withhold": None, "--report": None, "--unset": None, "--rolls": None}
            for flag in opt:
                while flag in args:
                    i = args.index(flag)
                    opt[flag] = args[i + 1]
                    del args[i:i + 2]
            if len(args) == 4:
                return convert(args[0], args[1], args[2], args[3], opt["--withhold"], opt["--report"],
                               opt["--unset"], opt["--rolls"])
    except Stop as e:
        print("char_convert_map: %s" % e, file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
