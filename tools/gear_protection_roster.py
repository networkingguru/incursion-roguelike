"""The whole EF_PROTECTS_ITEMS ruling table, as a static oracle over lib/.

Not an .irh interpreter. It reads declarative `xval:`/`yval:` grants and the
`Stati[...]`, `Resists:` and `Immune:` grant lists, on the clause evals that
inc/Defines.h:3300-3301 document as stati-bearing (EA_GRANT, EA_INFLICT). A
grant made by a script block inside `On Event` is invisible to it, and so is any
new grant channel: a structural change needs this file reviewed, not patched
around. `#if 0` regions are dead code and are skipped. Comments and strings
supply no evidence. --root permits isolated mutation tests.

Usage: tools/gear_protection_roster.py [A|B|C1|C2|all] [--root DIR]
Exit:  0 every part passed, 1 a part failed, 2 could not measure.
"""
import argparse
import re
import sys
from pathlib import Path

M_ITEMS = 'lib/m_items.irh'
WSPELLS = 'lib/wspells.irh'
PSPELLS = 'lib/pspells.irh'
DOMAINS = 'lib/domains.irh'
RELIGION = 'lib/religion.irh'
RACES = 'lib/races.irh'
SUBRACES = 'lib/subraces.irh'

# ---------------------------------------------------------------------------
# PART A. The effects the owner ruled protect the bearer's carried gear. The
# name is the EFFECT's own name, which is not the name a player reads: the
# source token in front of the declaration supplies the noun, so
# `AI_BOOTS Effect "the Winterlands"` is the Boots of the Winterlands.

PROTECTS = [
    (M_ITEMS, 'the Winterlands', 'Boots of the Winterlands'),
    (M_ITEMS, 'the Inferno', 'Bracers of the Inferno'),
    (M_ITEMS, 'Fire Resistance', 'Ring of Fire Resistance'),
    (M_ITEMS, 'the Stormlord', 'Girdle of the Stormlord'),
    (M_ITEMS, 'Musical Defense', 'Instrument of Musical Defense'),
    (M_ITEMS, 'the Endless Wave', 'Bracers of the Endless Wave'),
    (M_ITEMS, 'Stone;eyes', 'Eyes of Stone'),
    (M_ITEMS, 'Neutralization', 'Bracers of Neutralization'),
    (M_ITEMS, 'Grounding', 'Bracers of Grounding'),
    (M_ITEMS, 'Rust;gauntlet', 'Gauntlets of Rust'),
    (M_ITEMS, 'Cowl of Warding', 'Cowl of Warding'),
    (M_ITEMS, 'Sunblade', 'Sunblade'),
    (WSPELLS, 'Endure Fire', 'Endure Fire'),
    (WSPELLS, 'Endure Cold', 'Endure Cold'),
    (WSPELLS, 'Endure Lightning', 'Endure Lightning'),
    (WSPELLS, 'Endure Acid', 'Endure Acid'),
    (WSPELLS, 'Endure Sound', 'Endure Sound'),
    (WSPELLS, 'Resist Water', 'Resist Water'),
    (WSPELLS, 'Resist Fire', 'Resist Fire'),
    (WSPELLS, 'Resist Cold', 'Resist Cold'),
    (WSPELLS, 'Resist Lightning', 'Resist Lightning'),
    (WSPELLS, 'Resist Acid', 'Resist Acid'),
    (WSPELLS, 'Resist Sound', 'Resist Sound'),
    (WSPELLS, 'Protection from Fire', 'Protection from Fire'),
    (WSPELLS, 'Protection from Cold', 'Protection from Cold'),
    (WSPELLS, 'Protection from Lightning', 'Protection from Lightning'),
    (WSPELLS, 'Protection from Acid', 'Protection from Acid'),
    (WSPELLS, 'Protection from Sound', 'Protection from Sound'),
    (WSPELLS, 'Endure the Elements', 'Endure the Elements'),
    (WSPELLS, 'Fire Shield', 'Fire Shield'),
    (WSPELLS, 'Chill Shield', 'Chill Shield'),
    (WSPELLS, 'Mooncloak', 'Mooncloak'),
    (WSPELLS, 'Resist the Elements', 'Resist the Elements'),
    (WSPELLS, 'Protection from Elements', 'Protection from Elements'),
    (PSPELLS, 'Death Ward', 'Death Ward'),
    (PSPELLS, 'Lesser Aspect of Divinity', 'Lesser Aspect of Divinity'),
]

# ---------------------------------------------------------------------------
# PART B. The grants the owner ruled wearer-only. A flag on any of these is a
# defect, not a matter of taste. The first table is effects; the second is the
# declarations that are not effects at all, and therefore carry no effect id
# for src/Values.cpp to read a flag from -- they are asserted so that turning
# one into a flagged effect cannot pass unnoticed.

WEARER_ONLY = [
    (M_ITEMS, 'Ice', 'Amulet of Ice'),
    (M_ITEMS, 'Surtur', 'Girdle of Surtur'),
    (M_ITEMS, 'Bile', 'Amulet of Bile'),
    (M_ITEMS, 'Acid Warding', 'Ring of Acid Warding'),
    (M_ITEMS, 'Brass and Glass', 'Ring of Brass and Glass'),
    (M_ITEMS, 'Clear Sound', 'Helm of Clear Sound'),
    (M_ITEMS, 'the Fiery Citadel', 'Staff of the Fiery Citadel'),
    (M_ITEMS, 'Elemental Command (Fire)', 'Ring of Elemental Command (Fire)'),
    (M_ITEMS, 'Life Protection', 'Amulet of Life Protection'),
    (M_ITEMS, 'the Lizardfolk', 'Girdle of the Lizardfolk'),
    (M_ITEMS, 'Lesser Divine Aspect', 'Girdle of Lesser Divine Aspect'),
    (RELIGION, 'Hesani;symbol', "Hesani's holy symbol"),
]

WEARER_ONLY_DECLS = [
    (DOMAINS, 'Domain', 'Slime', ['Stati[RESIST,AD_ACID]'], 'the Slime domain'),
    (DOMAINS, 'Domain', 'Fire', ['Stati[RESIST,AD_FIRE,+1]'], 'the Fire domain'),
    (DOMAINS, 'Domain', 'Death', ['Stati[RESIST,AD_NECR,+1]'], 'the Death domain'),
    (RELIGION, 'God', 'Immotian',
     ['Stati[RESIST,AD_FIRE,+5]', 'Stati[IMMUNITY,AD_FIRE]'], 'the god Immotian'),
    (RELIGION, 'God', 'Mara', ['Stati[RESIST,AD_NECR,+2]'], 'the god Mara'),
    (RACES, 'Monster', 'lizardman;temp', ['Resists:DF_FIRE'], 'the Lizardfolk race'),
    (SUBRACES, 'Monster', 'Dragonkin;temp', ['Immune:DF_FIRE'], 'the Dragonkin subrace'),
    (RACES, 'Monster', 'elf;temp', ['Stati[RESIST,AD_COLD,2]'], 'the Elf race'),
    (SUBRACES, 'Monster', 'Grey Elf;temp', ['Stati[RESIST,AD_COLD,2]'], 'the Grey Elf subrace'),
    (SUBRACES, 'Monster', 'Wood Elf;temp', ['Stati[RESIST,AD_COLD,2]'], 'the Wood Elf subrace'),
]

# Part C2's files: domains, gods, races and subraces are `n` by rule, so no
# effect declared in any of them may carry the flag.
NEVER_FLAGGED_FILES = [DOMAINS, RELIGION, RACES, SUBRACES]

# Every .irh the roster speaks for. Part A's "and nothing else does" is asked
# of all of them, so a flag appearing in a file nobody thought about fails.
ALL_LIB = 'lib/*.irh'

# Part C1 holds these two back from the verdict until Brian rules on inc-taoa.
# Both grant immunity to a damage type MaterialHardness never exempts -- trip,
# critical, paralysis, stuck and stoning -- so MAT_BONE returns 6 and an item
# can technically take one. Either his "spells are y" rule reaches these two,
# or those five types belong beside AD_SLEE and AD_STUN in the exempt list and
# the finding retires without touching either spell. He decides which.
# The check still reports them by name every run, and still fails if the list
# and the tree stop agreeing in EITHER direction: a third bare spell fails C1,
# and a name here that is no longer bare fails it too, so this cannot rot into
# a permanent excuse.
PENDING_RULING = ['Rooting', 'Free Action;spell']

# The two clause evals that read xval as a stati nature; inc/Defines.h:3300-3301.
GRANTING_EVALS = ('EA_GRANT', 'EA_INFLICT')


class Unmeasurable(Exception):
    pass


def measure(ok, part, message):
    print('%s [%s] %s' % ('PASS:' if ok else 'FAIL:', part, message))
    return not ok


def compact(s):
    return re.sub(r'\s+', '', s)


def mask(src):
    """Blank comment, string and character-literal interiors, offsets intact.

    Newlines survive everywhere, so a line-anchored pattern still sees lines,
    and no brace, quote or directive inside prose can be mistaken for code.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
        elif c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            for k in range(i + 1, j - 1):
                if out[k] != '\n':
                    out[k] = '_'
            i = j
            continue
        else:
            i += 1
            continue
        for k in range(i, j):
            if out[k] != '\n':
                out[k] = ' '
        i = j
    return ''.join(out)


COND = re.compile(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|endif)\b', re.M)
IF0 = re.compile(r'^[ \t]*#[ \t]*if[ \t]+0[ \t]*$', re.M)


def strip_if0(masked):
    """Blank every `#if 0` region. Dead code states no rule."""
    out = list(masked)
    depth, start = 0, None
    for mo in COND.finditer(masked):
        if mo.group(1) == 'endif':
            depth -= 1
            if start is not None and depth == 0:
                stop = masked.find('\n', mo.end())
                stop = len(masked) if stop < 0 else stop
                for k in range(start, stop):
                    if out[k] != '\n':
                        out[k] = ' '
                start = None
        else:
            if depth == 0 and IF0.match(masked, mo.start()):
                start = mo.start()
            depth += 1
    if depth:
        raise Unmeasurable('unbalanced #if/#endif nesting')
    return ''.join(out)


def close_brace(masked, open_at):
    depth = 0
    for i in range(open_at, len(masked)):
        depth += (masked[i] == '{') - (masked[i] == '}')
        if depth == 0:
            return i
    raise Unmeasurable('unclosed block at offset %d' % open_at)


def close_paren(s, open_at):
    depth = 0
    for i in range(open_at, len(s)):
        depth += (s[i] == '(') - (s[i] == ')')
        if depth == 0:
            return i
    raise Unmeasurable('unclosed parenthesis at offset %d' % open_at)


def body(s, pattern):
    mo = re.search(pattern + r'\s*\{', s)
    if not mo:
        raise Unmeasurable('missing function or block: ' + pattern)
    return s[mo.end():close_brace(s, mo.end() - 1)]


# lang/Grammar.acc:642-681: sources, then the keyword, the name, the eval, one
# braced clause, and any number of `and <eval> { }` continuations. One TEffect
# holds the lot, so a flag in any clause covers the whole effect.
EFFECT = re.compile(r'(?<![A-Za-z0-9_])(?:Spell|Effect|Poison|Disease)\s+"([^"\n]*)"\s*:')
SOURCES = re.compile(r'([A-Za-z_]\w*(?:\s*/\s*[A-Za-z_]\w*)*)\s*$')
EVAL = re.compile(r'\s*([A-Za-z_]\w*)')
VALUE = re.compile(r'\b(xval|yval)\s*:\s*([A-Za-z_]\w*)')
DECL_HEAD = re.compile(r'([A-Za-z_]\w*)\s+"(_*)"[^"{}]*$')
FLAG = 'EF_PROTECTS_ITEMS'


class Effect(object):
    def __init__(self, path, src, masked, mo):
        self.path = path
        self.name = src[mo.start(1):mo.end(1)]
        self.line = src.count('\n', 0, mo.start()) + 1
        pre = SOURCES.search(masked[max(0, mo.start() - 160):mo.start()])
        self.sources = re.sub(r'\s+', '', pre.group(1)) if pre else ''
        self.clauses = []
        at = mo.end()
        ev = EVAL.match(masked, at)
        eval_name = ev.group(1) if ev else ''
        while True:
            opened = masked.find('{', at)
            if opened < 0:
                raise Unmeasurable('%s: effect "%s" has no body' % (path, self.name))
            closed = close_brace(masked, opened)
            self.clauses.append((eval_name, opened + 1, closed))
            nxt = re.match(r'\s*and\b([^{}]*)\{', masked[closed + 1:])
            if not nxt:
                break
            ev = EVAL.match(nxt.group(1))
            eval_name = ev.group(1) if ev else ''
            at = closed + 1 + nxt.start(1)
        self.start, self.end = mo.start(), self.clauses[-1][2]
        self.text = masked[self.start:self.end]
        self.src = src

    @property
    def flagged(self):
        return 'EF_PROTECTS_ITEMS' in self.text

    def grants(self):
        """(nature, damage type) for every clause whose eval reads a stati.

        Values carry forward: the grammar snapshots the running EffectValues
        into each new annotation, so a clause that names only one of the pair
        inherits the other.
        """
        out, xval, yval = [], None, None
        for eval_name, a, b in self.clauses:
            for mo in VALUE.finditer(self.text, a - self.start, b - self.start):
                token = self.src[self.start + mo.start(2):self.start + mo.end(2)]
                if mo.group(1) == 'xval':
                    xval = token
                else:
                    yval = token
            if eval_name in GRANTING_EVALS and xval in ('RESIST', 'IMMUNITY'):
                out.append((xval, yval))
        return out


def read(root, path):
    try:
        return (root / path).read_text(errors='surrogateescape')
    except (OSError, UnicodeError) as e:
        raise Unmeasurable(str(e))


class Lib(object):
    """One .irh, parsed once."""

    def __init__(self, root, path):
        self.path = path
        self.src = read(root, path)
        self.masked = strip_if0(mask(self.src))
        if self.masked.count('{') != self.masked.count('}'):
            raise Unmeasurable('%s: braces do not balance after masking' % path)
        self.effects = [Effect(path, self.src, self.masked, mo)
                        for mo in EFFECT.finditer(self.masked)]

    def effect(self, name):
        hits = [e for e in self.effects if e.name == name]
        if len(hits) != 1:
            raise Unmeasurable('%s: %d effects named "%s", want exactly 1'
                               % (self.path, len(hits), name))
        return hits[0]

    def effect_at(self, offset):
        for e in self.effects:
            if e.start <= offset < e.end:
                return e
        return None

    def owner_of(self, offset):
        """Name the declaration an offset sits in, for a message a reader can act on."""
        e = self.effect_at(offset)
        if e:
            return 'Effect "%s"' % e.name
        depth, opened = 0, None
        for i, ch in enumerate(self.masked):
            if ch == '{':
                if depth == 0:
                    opened = i
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and opened is not None and opened < offset < i:
                    head = DECL_HEAD.search(self.masked[max(0, opened - 200):opened])
                    if head:
                        base = max(0, opened - 200)
                        return '%s "%s"' % (head.group(1),
                                            self.src[base + head.start(2):base + head.end(2)])
                    break
        return 'no declaration'

    def line_of(self, offset):
        return self.src.count('\n', 0, offset) + 1

    def declaration(self, keyword, name):
        """The extent of a Monster, Domain or God declaration, by name."""
        pattern = r'(?<![A-Za-z0-9_])%s\s+"%s"' % (keyword, re.escape('_' * len(name)))
        hits = [mo for mo in re.finditer(pattern, self.masked)
                if self.src[mo.start():mo.end()].endswith('"%s"' % name)]
        if len(hits) != 1:
            raise Unmeasurable('%s: %d declarations of %s "%s", want exactly 1'
                               % (self.path, len(hits), keyword, name))
        opened = self.masked.find('{', hits[0].end())
        if opened < 0:
            raise Unmeasurable('%s: %s "%s" has no body' % (self.path, keyword, name))
        return self.masked[hits[0].start():close_brace(self.masked, opened) + 1]


# ---------------------------------------------------------------------------
# Which damage types can hurt an item, read out of MaterialHardness rather than
# assumed. Two guards return -1 for a whole type regardless of material: the
# leading `else if` list, and any `case AD_x: return -1;` in the type switch. A
# type that passes both reaches the material switch, where MAT_BONE returns 6
# unconditionally, so it can hurt at least one item.

def damage_types(root):
    values = {}
    for mo in re.finditer(r'^#define\s+(AD_[A-Z0-9_]+)\s+(\d+)',
                          read(root, 'inc/Defines.h'), re.M):
        values[mo.group(1)] = int(mo.group(2))
    if not values:
        raise Unmeasurable('inc/Defines.h declares no AD_ damage types')
    return values


def never_hurts_an_item(root, values):
    s = mask(read(root, 'src/Item.cpp'))
    sig = re.search(r'\bMaterialHardness\s*\(\s*\w+\s+(\w+)\s*,\s*\w+\s+(\w+)\s*\)', s)
    if not sig:
        raise Unmeasurable('MaterialHardness signature missing or reshaped')
    mat, dtype = sig.groups()
    f = body(s, r'\bMaterialHardness\s*\([^)]*\)')
    if not re.match(r'\s*if\s*\(\s*%s\s*==\s*MAT_\w+\s*\)\s*return\s*-\s*1\s*;\s*else\s+if\s*\('
                    % mat, f):
        raise Unmeasurable('MaterialHardness no longer opens with a material '
                           'guard followed by a damage-type guard')
    opened = f.index('(', f.index('else'))
    shut = close_paren(f, opened)
    if not re.match(r'\s*return\s*-\s*1\s*;\s*else\s+switch\s*\(\s*%s\s*\)' % dtype,
                    f[shut + 1:]):
        raise Unmeasurable('the damage-type guard no longer returns -1 before '
                           'the type switch')
    never = set()
    for term in f[opened + 1:shut].split('||'):
        rng = re.fullmatch(r'\s*\(\s*%s\s*>=\s*(AD_\w+)\s*&&\s*%s\s*<=\s*(AD_\w+)\s*\)\s*'
                           % (dtype, dtype), term)
        one = re.fullmatch(r'\s*%s\s*==\s*(AD_\w+)\s*' % dtype, term)
        if rng:
            lo, hi = values.get(rng.group(1)), values.get(rng.group(2))
            if lo is None or hi is None:
                raise Unmeasurable('unknown damage type in ' + term.strip())
            never.update(range(lo, hi + 1))
        elif one:
            if one.group(1) not in values:
                raise Unmeasurable('unknown damage type ' + one.group(1))
            never.add(values[one.group(1)])
        else:
            raise Unmeasurable('unreadable term in the damage-type guard: '
                               + term.strip())
    # A `case AD_x:` that returns -1 whatever the material joins the guard.
    switch = body(f[shut:], r'switch\s*\(\s*%s\s*\)' % dtype)
    cases = list(re.finditer(r'\bcase\s+(AD_\w+)\s*:', switch))
    pending = []
    for i, mo in enumerate(cases):
        stop = cases[i + 1].start() if i + 1 < len(cases) else len(switch)
        pending.append(mo.group(1))
        arm = compact(switch[mo.end():stop])
        if not arm:
            continue
        if arm == 'return-1;':
            for name in pending:
                if name not in values:
                    raise Unmeasurable('unknown damage type ' + name)
                never.add(values[name])
        pending = []
    return never


# ---------------------------------------------------------------------------

def run(part, root):
    libs = {}

    def lib(path):
        if path not in libs:
            libs[path] = Lib(root, path)
        return libs[path]

    failed = False
    every = sorted(p.as_posix()[len(root.as_posix()) + 1:]
                   for p in sorted(root.glob(ALL_LIB)))
    if not every:
        raise Unmeasurable('no lib/*.irh under ' + str(root))

    if part in ('A', 'all'):
        want = {(f, n) for f, n, _ in PROTECTS}
        got, stray = set(), []
        for p in every:
            for mo in re.finditer(FLAG, lib(p).masked):
                e = lib(p).effect_at(mo.start())
                if e is None:
                    stray.append('%s:%d %s' % (p, lib(p).line_of(mo.start()),
                                               lib(p).owner_of(mo.start())))
                else:
                    got.add((p, e.name))
        extra = sorted('%s "%s"' % (f, n) for f, n in got - want)
        missing = sorted('%s "%s"' % (f, n) for f, n in want - got)
        failed |= measure(not extra and not missing and not stray
                          and len(got) == len(PROTECTS), 'A',
                          'EF_PROTECTS_ITEMS effects=%d/%d; wrongly flagged=%s; '
                          'lost the flag=%s; outside any effect=%s'
                          % (len(got), len(PROTECTS), ', '.join(extra) or 'none',
                             ', '.join(missing) or 'none', ', '.join(stray) or 'none'))

    if part in ('B', 'all'):
        wrong = []
        for path, name, reads_as in WEARER_ONLY:
            e = lib(path).effect(name)
            if e.flagged:
                wrong.append(reads_as)
            elif not e.grants():
                raise Unmeasurable('%s: "%s" (%s) no longer grants a resistance '
                                   'or an immunity' % (path, name, reads_as))
        for path, keyword, name, fragments, reads_as in WEARER_ONLY_DECLS:
            text = lib(path).declaration(keyword, name)
            if FLAG in text:
                wrong.append(reads_as)
                continue
            flat = compact(text)
            for fragment in fragments:
                if fragment not in flat:
                    raise Unmeasurable('%s: %s no longer grants %s'
                                       % (path, reads_as, fragment))
        total = len(WEARER_ONLY) + len(WEARER_ONLY_DECLS)
        failed |= measure(not wrong, 'B',
                          'wearer-only grants unflagged=%d/%d; wrongly flagged=%s'
                          % (total - len(wrong), total, ', '.join(wrong) or 'none'))

    if part in ('C1', 'all'):
        values = damage_types(root)
        never = never_hurts_an_item(root, values)
        # One name per value: AD_MIND and AD_CHRM are the same number, and
        # printing both would overstate how many types there are.
        canonical = {}
        for name in sorted(values):
            canonical.setdefault(values[name], name)
        hurts = [canonical[v] for v in sorted(canonical) if v not in never]
        print('      [C1] gear-relevant damage types=%d of %d: %s'
              % (len(hurts), len(canonical), ' '.join(hurts)))
        bare = []
        for path in (WSPELLS, PSPELLS):
            for e in lib(path).effects:
                if e.flagged:
                    continue
                exposed = []
                for nature, dtype in e.grants():
                    if dtype not in values:
                        raise Unmeasurable('%s: "%s" grants %s against %s, which '
                                           'inc/Defines.h does not declare'
                                           % (path, e.name, nature, dtype))
                    if values[dtype] not in never and dtype not in exposed:
                        exposed.append(dtype)
                if exposed:
                    bare.append((e.name, '%s:%d "%s" (%s)'
                                 % (path, e.line, e.name, ' '.join(exposed))))
        held = [text for name, text in bare if name in PENDING_RULING]
        unruled = [text for name, text in bare if name not in PENDING_RULING]
        stale = [name for name in PENDING_RULING
                 if name not in [n for n, _ in bare]]
        print('      [C1] held for Brian (bd inc-taoa)=%d of %d: %s'
              % (len(held), len(PENDING_RULING), '; '.join(held) or 'none'))
        failed |= measure(not unruled and not stale, 'C1',
                          'unflagged spell grants against a damage type that '
                          'hurts gear=%d; %s; PENDING_RULING names no longer '
                          'bare=%s' % (len(unruled), '; '.join(unruled) or 'none',
                                       ', '.join(stale) or 'none'))

    if part in ('C2', 'all'):
        wrong = []
        for path in NEVER_FLAGGED_FILES:
            for mo in re.finditer(FLAG, lib(path).masked):
                wrong.append('%s:%d %s' % (path, lib(path).line_of(mo.start()),
                                           lib(path).owner_of(mo.start())))
        failed |= measure(not wrong, 'C2',
                          'flags in domains, gods, races and subraces=%d/0; %s'
                          % (len(wrong), ', '.join(wrong) or 'none'))

    return failed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('part', nargs='?', default='all',
                        choices=['A', 'B', 'C1', 'C2', 'all'])
    parser.add_argument('--root', type=Path, default=Path('.'))
    args = parser.parse_args()
    try:
        sys.exit(int(run(args.part, args.root.resolve())))
    except Unmeasurable as e:
        print('COULD NOT MEASURE: ' + str(e))
        sys.exit(2)
