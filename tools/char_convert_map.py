#!/usr/bin/env python3
"""The value mapping of tools/char_convert.sh (bead inc-10v7f, spec section 8).

ponytail: this helper and tools/char_convert.sh stay only until the epic
conversion lands (inc-pu6v.369); then both are deleted. The ceiling: the
tables below map what a canonical dump states as a DECISION: names, base
attributes, hit and mana rolls, the creation seeds (MAP); the feat queue, the
skill ranks, the kit and two item quantities (LISTS). A perk is not a choice
(owner's ruling 2026-11-11): the built character keeps the perks the walk rolled.
Abilities, derived attributes and the equipment arrangement are RESULTS of
those decisions under the current rules; nothing here sets them, and a
difference left in them is the conversion's finding (a rule changed since the
old save was made).

Usage:
  tools/char_convert_map.py selftest
      Prove, on synthetic input, that merged stacks keep their sources. Exit 0 all hold.
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
      each led by its kind (scalar, feat, spell, skill, kit, quantity). Also
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
    # a one-word Name is a monk's title (the Monk EV_150 script replaces the typed name): only character_name states it
    (r"^Name: (\S+)$", [("character_name", "", r"\1")]),
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

# QUANTITIES. A carried item no kit ask made, and the roll key that sets its
# quantity (src/Create.cpp: the thrown weapons, the Beginner's Kit food, the
# ammunition of a bow). The item is named by its item name or by its type.
OTHER_QUANTITY = [(("name", "shotput"), "thrown_quantity"),
                  (("name", "food ration"), "beginkit_food"),
                  (("type", "T_MISSILE"), "ammo_quantity")]

# LISTS. name, the keys the list owns (what --withhold names).
LISTS = [
    ("feats",  ("feat",)),
    ("spells", ("spell_learn",)),
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
        if kind == "effect" and hint:   # an item's effect with no tag of its own: the one ";item" candidate
            items = [c for c in cands if c.endswith(";item")]
            if len(items) == 1:
                return items[0]
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
    beyond = []
    if idx and len(chosen_o) > len(idx):
        # more feats than creation has slots: the extra are level-up picks of the arrival replay, and the dump cannot tell
        # them from creation's. The feats the skeleton states and the old also has come first.
        rest, first = list(chosen_o), []
        for f in chosen_s:
            if f in rest:
                rest.remove(f)
                first.append(f)
        ordered = first + rest
        chosen_o, beyond = ordered[:len(idx)], ordered[len(idx):]
    if idx:
        edits[idx[0]] = ["feat: %s" % f for f in chosen_o]
        for i in idx[1:]:
            edits[i] = []
    else:
        edits[len(lines)] = ["feat: %s" % f for f in chosen_o]
    done.append(("feat", "feat queue: %s -> %s" % (", ".join(chosen_s) or "(none)", ", ".join(chosen_o) or "(none)")))
    if beyond:
        UNSET.append(("feat", "feat: %s are the old character's beyond creation's %d slots: level-up picks of the arrival replay "
                      "(a leveled fixture); the replay decides them" % (", ".join(beyond), len(idx))))
    elif len(chosen_o) < len(chosen_s):
        done.append(("feat", "NOTE the old queue has %d feats, the skeleton asked for %d: the build decides"
                     % (len(chosen_o), len(chosen_s))))
    return edits


def known_spells(path):
    """The names of the dump's Known Spells section, in the dump's order, less the spells a perk granted
    (the journal's Wild Talent and Innate Spell lines: a perk is not a choice)."""
    secs = sections(path)
    perk = [t for lab, t in journal_perks(secs) if lab in ("Wild Talent", "Innate Spell")]
    out = []
    on = False
    for l in open(path, errors="replace").read().split("\n"):
        if re.match(r"^[A-Z][A-Za-z' ]+:$", l):
            on = l == "Known Spells:"
            continue
        m = on and re.match(r"^\s+(\S.*?)\s{2,}\d", l)
        if m:
            out.append(m.group(1))
    for t in perk:
        if t in out:
            out.remove(t)
    return out


def replace_spells(lines, old_p, built_p, done):
    """The spells the screens asked for (spell_learn): what the old character knows, less the build's own
    grants (the spells it knows that its spell_learn lines did not pick, perks aside)."""
    idx = [i for i, l in enumerate(lines) if key_of(l) == "spell_learn"]
    if not idx:
        return {}
    skel = [CHAR_LINE.match(lines[i]).group(3) for i in idx]
    skel_names = [re.sub(r" \[[^\]]*\]$", "", v) for v in skel]
    auto = known_spells(built_p)
    for n in skel_names:
        if n in auto:
            auto.remove(n)
    chosen_o = known_spells(old_p)
    for n in auto:
        if n in chosen_o:
            chosen_o.remove(n)
    if sorted(chosen_o) == sorted(skel_names):
        return {}
    src = re.search(r" (\[[^\]]*\])$", skel[0])   # the source of the skeleton's own pick; the dump does not name it
    new = ["spell_learn: %s%s" % (n, " " + src.group(1) if src else "") for n in chosen_o]
    edits = {idx[0]: new}
    for i in idx[1:]:
        edits[i] = []
    done.append(("spell", "spell queue: %s -> %s" % (", ".join(skel), ", ".join(n[13:] for n in new) or "(none)")))
    return edits


def skill_names():
    """{display name: SK_ constant} from the SkillInfo table of src/Tables.cpp (read at run time)."""
    text = open(os.path.join(ROOT, "src", "Tables.cpp"), errors="replace").read()
    a = text.find("SkillInfoStruct SkillInfo[]")
    names = dict((m.group(2), m.group(1)) for m in re.finditer(r'\{\s*(SK_\w+)\s*,\s*"([^"]+)"', text[a:])) if a >= 0 else {}
    if not names:
        raise Stop("src/Tables.cpp has no SkillInfo table")
    return names


def replace_skills(lines, old_p, built_p, done):
    """Each skeleton skill_ranks line is set to the old ranks less what the build adds on its own (race, class):
    the skeleton states what the player bought, the dump shows the sum."""
    nums = read_defines("SK_")
    idx = [i for i, l in enumerate(lines) if key_of(l) == "skill_ranks"]
    if not idx:
        return {}
    by_name = skill_names()

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
    edits = {}
    for pos, i in enumerate(idx):
        m = CHAR_LINE.match(lines[i])
        name = m.group(2) or ""
        nm = re.match(r"^skill (\d+)$", name)
        if nm:
            sk = int(nm.group(1))   # the unnamed number the writer uses for a skill with no name
        elif name in by_name and by_name[name] in nums:
            sk = nums[by_name[name]]
        else:
            # a skill with no SK_ constant (an unimplemented one, a generated Knowledge name): the writer lists
            # the skills in skill-number order, so its place in the list is its number
            if len(idx) != nums["SK_LASTSKILL"]:
                raise Stop("the skeleton's skill_ranks [%s] names no skill of the SkillInfo table, and its %d skill_ranks lines "
                           "are not the module's %d skills, so the position cannot stand for the number (skill_ranks)"
                           % (name, len(idx), nums["SK_LASTSKILL"]))
            sk = pos
        stated, built = int(m.group(3)), built_r.get(sk, 0)
        if built < stated:
            raise Stop("the build has %d rank(s) of skill_ranks [%s] where the skeleton states %d: nothing can take ranks away (skill_ranks)"
                       % (built, name, stated))
        auto = built - stated   # ranks the race or class adds on its own
        want = old_r.get(sk, 0) - auto
        if want < 0:
            raise Stop("the old character has %d rank(s) of skill_ranks [%s] but the build adds %d on its own (skill_ranks)"
                       % (old_r.get(sk, 0), name, auto))
        if want != stated:
            edits[i] = ["skill_ranks [%s]: %d" % (name, want)]
            done.append(("skill", "skill_ranks [%s]: %d -> %d%s" % (name, stated, want, " (the build adds %d on its own)" % auto if auto else "")))
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


SKILL_TOOLS = (("SK_HEAL", "healing kit"), ("SK_DISGUISE", "disguise kit"), ("SK_ALCHEMY", "alchemy set"),
               ("SK_MINING", "pickaxe"), ("SK_CRAFT", "craftsman's tools"), ("SK_HANDLE_DEV", "mechanical tools"))


def skill_rank_by_define(path):
    """{SK_ name: ranks} of the dump's Skill Ranks section."""
    out = {}
    for l in sect(sections(path), "Skill Ranks"):
        m = re.match(r"^Skill (SK_\w+): (\d+)$", l)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def set_aside_made_items(old_items, built_items, old_secs, built_secs, old_p, built_p):
    """Items no kit ask makes: a perk item (made before any kit item, so the oldest items by GenNum; the
    journal's "Starting Item" lines count them) and the tool a skill with ranks gives (src/Create.cpp
    SkillKits). Neither side counts them: the walk's own perk roll and the skill ranks make them."""
    out = []
    notes = []
    for secs, items, who in ((old_secs, old_items, "old"), (built_secs, built_items, "built")):
        items = list(items)
        lines = [t for lab, t in journal_perks(secs) if lab == "Starting Item"]
        oldest = sorted(items, key=lambda it: it["gen"])[:len(lines)]
        if len(oldest) < len(lines):
            raise Stop("the %s journal lists %d Starting Item perk(s) but the dump holds %d item(s)" % (who, len(lines), len(items)))
        perk_names = []
        for text, it in zip(lines, oldest):
            pm = re.search(r" \+(-?\d+)$", text)
            em = re.search(r" of (.+?)(?: \+-?\d+)?$", text)
            if pm and int(pm.group(1)) != it["plus"]:
                raise Stop("the %s journal line \"Starting Item: %s\" says plus %s but the oldest item (%s) has plus %d"
                           % (who, text, pm.group(1), base_name(it["iid"]), it["plus"]))
            if em and base_name(it["eid"]) != "-" and em.group(1) != base_name(it["eid"]):   # "of <x>" on an item with no effect is a quality
                raise Stop("the %s journal line \"Starting Item: %s\" says effect %s but the oldest item (%s) has effect %s"
                           % (who, text, em.group(1), base_name(it["iid"]), base_name(it["eid"])))
            items.remove(it)
            perk_names.append(base_name(it["iid"]))
        ranks = skill_rank_by_define(old_p if who == "old" else built_p)
        tools = []
        for sk, tool in SKILL_TOOLS:
            if ranks.get(sk, 0) > 0:
                hit = next((it for it in items if base_name(it["iid"]) == tool), None)
                if hit is not None:
                    items.remove(hit)
                    tools.append("%s, %s %d" % (tool, sk[3:].lower(), ranks[sk]))
        out.append(items)
        if perk_names or tools:
            notes.append("%s: %d perk item%s (%s) and %d skill tool%s (%s)" % (
                who, len(perk_names), "" if len(perk_names) == 1 else "s", ", ".join(perk_names) or "-",
                len(tools), "" if len(tools) == 1 else "s", "; ".join(tools) or "-"))
    if notes:
        UNSET.append(("kit", "set aside, made by the perk roll and the skill ranks, not by a kit ask -- " + " | ".join(notes)))
    return out[0], out[1]


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
    old_secs, built_secs = sections(old_p), sections(built_p)
    old_items = merge_stacks(parse_items(old_secs))
    built_items = merge_stacks(parse_items(built_secs))
    old_items, built_items = set_aside_made_items(old_items, built_items, old_secs, built_secs, old_p, built_p)
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
    perk_slots_n = 0
    for l in lines:
        k = key_of(l)
        if k and k.startswith("perk_"):   # a perk is not a choice (owner's ruling 2026-11-11): one line for all the slots
            perk_slots_n += k == "perk_type"
            continue
        if not k or k in DATA_LINES or k in searched or k == "gear_chance":
            continue
        if any(k.startswith(o) if o.endswith("_") else k == o for o in owned):
            continue
        if any(k.startswith(o) if o.endswith("_") else k == o for o in SHOWN):
            continue
        count[k] = count.get(k, 0) + 1
    for k in sorted(count):
        UNSET.append((kinds.get(k, "?").lower(), "%s: %d line(s) kept as the walk recorded them; the dump does not show this decision directly" % (k, count[k])))
    if perk_slots_n:
        UNSET.append(("perk", "perk slots: %d kept as the walk rolled them; a perk is not a choice (owner's ruling 2026-11-11)"
                      % perk_slots_n))
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
    set_scalars(lines, old_p, built_p, withhold, done)

    def on(name):   # --withhold <key> skips the one list that owns the key
        return withhold not in next(r for r in LISTS if r[0] == name)[1]
    if on("feats"):
        lines = apply_edits(lines, replace_feats(lines, old_p, built_p, skel_feats,
                                                 [v for lab, v in journal_perks(sections(old_p)) if lab == "Bonus Feat"], done))
    if on("spells"):
        lines = apply_edits(lines, replace_spells(lines, old_p, built_p, done))
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
    """Phase 11g: merged stacks keep their sources, and
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
    # 1. merged stacks (a 5-line skeleton, two dumps)
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
    # inc-10v7f: a perk item and a skill tool are made by the perk roll and the skill ranks, not by a kit ask
    def canon2(items, perks, ranks):
        out = ["=== Derived Sheet ===", "  Starting Perks:"] + ["  Starting Item: %s." % t for t in perks] + [""]
        out += ["=== Skill Ranks ==="] + ["Skill %s: %d" % kv for kv in ranks] + ["=== Kit ==="]
        for iid, qty, gen, plus in items:
            out.append("  - Item iID=%s eID=- Type=T_COIN" % iid)
            out.append("    Known=0xff Plus=%d Charges=0 DmgType=0 GenNum=%d Flavor=0 homeID=- HP=1 Age=0 Swing=0 "
                       "Quantity=%d IFlags=0x0" % (plus, gen, qty))
        return "\n".join(out) + "\n"

    def run2(skel, built, old):
        for n, (items, perks, ranks) in (("built", built), ("old", old)):
            open(os.path.join(d, n), "w").write(canon2(items, perks, ranks))
        del UNSET[:]
        lines = list(skel)
        edits = replace_kit(lines, os.path.join(d, "old"), os.path.join(d, "built"), names, [], [])
        return apply_edits(lines, edits), [t for k, t in UNSET]
    ask = ["kit_item [Orc;a2]: knife, quantity 1"]
    out, unset = run2(ask, ([knife], [], []), ([("buckler", 1, 2, 2), ("knife", 1, 5, 2)], ["uncursed buckler +2"], []))
    want("perk item: the oldest old item is set aside and paired to no ask",
         out == ask and any("1 perk item (buckler)" in u for u in unset), " | ".join(out) + " / " + " ; ".join(unset))
    out, unset = run2(ask, ([knife], [], []), ([("healing kit", 1, 37, 0), ("knife", 1, 5, 2)], [], [("SK_HEAL", 2)]))
    want("skill tool: the healing kit of a Healing 2 character is set aside",
         out == ask and any("healing kit, heal 2" in u for u in unset), " | ".join(out) + " / " + " ; ".join(unset))
    try:
        run2(ask, ([knife], [], []), ([("buckler", 1, 2, 1), ("knife", 1, 5, 2)], ["uncursed buckler +2"], []))
        want("perk item: a journal plus that disagrees with the oldest item stops", False, "no Stop")
    except Stop as e:
        want("perk item: a journal plus that disagrees with the oldest item stops", "plus 2" in str(e), str(e))
    # inc-10v7f: a one-word Name (a monk's title) states character_name only
    open(os.path.join(d, "nm"), "w").write("Name: Harmonious_Fox\n")
    want("scalars: a one-word Name states character_name only",
         targets(os.path.join(d, "nm")) == [("character_name", "", "Harmonious_Fox")], str(targets(os.path.join(d, "nm"))))
    # inc-10v7f: the spell queue takes the old character's picks, less the build's grants
    def spells_canon(names):
        return "Known Spells:\n" + "".join("  %s                     1   80%%    2 +10\n" % n for n in names) + "\nJournal:\n"
    open(os.path.join(d, "sold"), "w").write(spells_canon(["True Strike", "Bane", "Call Light", "Call Companions"]))
    open(os.path.join(d, "sbuilt"), "w").write(spells_canon(["True Strike", "Bane"]))
    done = []
    sl = ["spell_learn: Bane [Divine]", "feat: Alertness"]
    out = apply_edits(sl, replace_spells(sl, os.path.join(d, "sold"), os.path.join(d, "sbuilt"), done))
    want("spell queue: the old picks replace the skeleton's, with the skeleton's source",
         out == ["spell_learn: Bane [Divine]", "spell_learn: Call Light [Divine]", "spell_learn: Call Companions [Divine]", "feat: Alertness"],
         " | ".join(out))
    # inc-10v7f: an item's effect with an ";item" candidate, and the ambiguous case that stays a Stop
    fake = Names.__new__(Names)
    fake.full = {"item": {}, "effect": {"Nondetection": ["Nondetection;item", "Nondetection"], "Zap": ["Zap;item", "Zap;a;item", "Zap"]}}
    want("effect name: the one ;item candidate is taken for an item", fake.resolve("effect", "Nondetection", "cloak") == "Nondetection;item")
    try:
        fake.resolve("effect", "Zap", "wand")
        want("effect name: two ;item candidates stay a Stop", False, "no Stop")
    except Stop:
        want("effect name: two ;item candidates stay a Stop", True)
    # skill ranks by name, less what the build adds on its own
    sk = os.path.join(d, "skold"); sb = os.path.join(d, "skbuilt")
    open(sk, "w").write("=== Skill Ranks (x) ===\nSkill SK_CLIMB: 9\nSkill SK_CRAFT: 4\n")
    open(sb, "w").write("=== Skill Ranks (x) ===\nSkill SK_CLIMB: 9\nSkill SK_CRAFT: 2\n")
    sl = ["skill_ranks [skill 0]: 0", "skill_ranks [Climb]: 2", "skill_ranks [Craft]: 2"]
    out = apply_edits(sl, replace_skills(sl, sk, sb, []))
    want("skill ranks: set by name to the old ranks less the build's own", out == ["skill_ranks [skill 0]: 0", "skill_ranks [Climb]: 2", "skill_ranks [Craft]: 4"], " | ".join(out))
    # inc-10v7f: more old feats than creation slots keeps the stated feats first and names the rest
    fk = os.path.join(d, "fkold"); fb = os.path.join(d, "fkbuilt")
    open(fk, "w").write("=== Feats ===\nFeat Endurance\nFeat Great Fortitude\nFeat Hardiness\n")
    open(fb, "w").write("=== Feats ===\nFeat Endurance\nFeat Focus Spell\n")
    del UNSET[:]
    fl = ["feat: Endurance", "feat: Hardiness"]
    out = apply_edits(fl, replace_feats(fl, fk, fb, [], [], []))
    want("feats: more old feats than slots keeps the stated feats and names the rest in one unset line",
         out == ["feat: Endurance", "feat: Hardiness"] and any("Great Fortitude are the old character's beyond creation's 2 slots" in u for _k, u in UNSET),
         " | ".join(out) + " / " + str(UNSET))
    # 2. the unset report names a PICK key and each gear_chance line, and the wizard and explore flags are mapped
    del UNSET[:]
    unset_kept(["alter_options: no", "gear_chance [Universal Gear;a3]: 54", "kit_item [Universal Gear;a16]: hide armour, quantity 1",
                "gear_chance [Universal Gear;a16]: 3"], set())
    want("unset report: a PICK key and each gear_chance line are named",
         any(u.startswith("alter_options: 1 line") for k, u in UNSET) and len([1 for k, u in UNSET if u.startswith("gear_chance")]) == 2
         and any("holds this annotation's item" in u for k, u in UNSET) and any("no kit_item line" in u for k, u in UNSET),
         " ; ".join(u for k, u in UNSET))
    del UNSET[:]
    unset_kept(["perk_type [0]: PERK_ITEM", "perk_item [0]: ring", "perk_type [1]: PERK_FEAT", "perk_feat [1]: Alertness",
                "perk_charges [ring]: 3"], set())
    want("unset report: all perk slots are ONE line of kind perk",
         UNSET == [("perk", "perk slots: 2 kept as the walk rolled them; a perk is not a choice (owner's ruling 2026-11-11)")],
         str(UNSET))
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
    {"name": "level-up-first-feat-moved", "cause": "bead inc-10v7f.1",
     "kinds": ["Feats: Great Fortitude -> Feats: Focus Spell (level-up menu's first entry moved)"],
     "old_to_built": lambda old: "Feats: Focus Spell" if old == "Feats: Great Fortitude" else None},
    {"name": "devouring-to-cannibalism", "cause": "commit 4e1fc266",
     "kinds": ["ability CA_DEVOURING 1 -> Feats: Cannibalism"],
     "old_to_built": lambda old: "Feats: Cannibalism" if old == "ability CA_DEVOURING 1" else None},
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
