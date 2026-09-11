"""Function-scoped static oracles for inc-m2zi AC8 and inc-w26h.

Not a C++ interpreter: structural changes require reviewing these oracles.
Comments and strings cannot supply positive evidence. Locals are captured rather
than pinned to their current names. --root permits isolated mutation tests.
"""
import argparse
import re
import sys
from pathlib import Path


class Unmeasurable(Exception):
    pass


def clean(s, strings=True):
    pattern = r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, lambda m: ' ' if strings or m[0].startswith(('/', "'")) else m[0], s)


def body(s, pattern):
    m = re.search(pattern + r'\s*\{', s)
    if not m:
        raise Unmeasurable('missing function or block: ' + pattern)
    start = m.end()
    depth = 1
    for i in range(start, len(s)):
        depth += (s[i] == '{') - (s[i] == '}')
        if depth == 0:
            return s[start:i]
    raise Unmeasurable('unclosed function or block: ' + pattern)


def compact(s):
    return re.sub(r'\s+', '', s)


def measure(ok, message):
    print(('PASS: ' if ok else 'FAIL: ') + message)
    return not ok


def run(rule, root):
    def read(path):
        try:
            return (root / path).read_text()
        except (OSError, UnicodeError) as e:
            raise Unmeasurable(str(e))

    if rule == 'dequ_dice':
        s = body(clean(read('src/Fight.cpp')), r'\bCreature\s*::\s*SAttack\s*\([^)]*\)')
        s = body(s, r'\bcase\s+A_DEQU\s*:')
        # Both naked-striker and equipment branches must load and immediately
        # roll the declared dice; this excludes any intervening rescaling.
        pairs = re.findall(r'(\w+)\s*\.\s*Dmg\s*=\s*\w+\s*->\s*u\s*\.\s*a\s*\.\s*Dmg\s*;\s*\1\s*\.\s*vDmg\s*=\s*\1\s*\.\s*Dmg\s*\.\s*Roll\s*\(\s*\)\s*;', s)
        writes = re.findall(r'\.\s*Dmg(?:\s*\.\s*\w+)?\s*(?:[+*/%-]=|=(?!=)|\+\+|--)', s)
        return measure(len(pairs) == 2 and len(writes) == 2,
                       f'A_DEQU declared-dice immediate rolls={len(pairs)}/2; dice writes={len(writes)}/2')

    if rule == 'dequ_dc':
        allowed = {'remorhaz', 'rust monster', 'grey ooze', 'babau'}
        ordinary = {'shattering ur-dragon', 'firebat', 'caryatid column', 'caustic fungus', 'acid blob', 'brown pudding', 'magma creeper', 'small mud elemental', 'vaporighu'}
        found = []
        for n in range(1, 5):
            s = clean(read(f'lib/mon{n}.irh'), strings=False)
            monsters = list(re.finditer(r'\bMonster\s+"([^"]+)"', s))
            if not monsters:
                raise Unmeasurable(f'no Monster declarations in lib/mon{n}.irh')
            for i, m in enumerate(monsters):
                section = s[m.end():monsters[i+1].start() if i+1 < len(monsters) else len(s)]
                for attack in re.finditer(r'\bA_DEQU\b([^,;]*)[,;]', clean(section)):
                    found.append((m[1], len(re.findall(r'\(\s*DC\s+\d+\s*\)', attack[1]))))
        names = [name for name, _ in found]
        bad = sorted(name for name, dc in found if dc != int(name in allowed))
        ok = len(found) == 13 and set(names) == allowed | ordinary and not bad
        return measure(ok, f'A_DEQU monsters={len(found)}/13; DC tokens={sum(dc for _, dc in found)}/4; incorrect DC owners={",".join(bad) or "none"}; roster={"expected" if set(names) == allowed | ordinary else "changed"}')

    s = clean(read('src/Item.cpp'))
    if rule == 'fire_hardness':
        f = body(s, r'\bMaterialHardness\s*\([^)]*\)')
        # Isolate the material switch, excluding earlier damage-type switches.
        param = re.search(r'MaterialHardness\s*\(\s*\w+\s+(\w+)\s*,\s*\w+\s+(\w+)', s)
        if not param:
            raise Unmeasurable('MaterialHardness parameters missing')
        mat, dtype = param.groups()
        # The last switch on mat is the base hardness table.
        starts = list(re.finditer(r'\bswitch\s*\(\s*' + mat + r'\s*\)', f))
        if not starts:
            raise Unmeasurable('material switch missing')
        f = body(f[starts[-1].start():], r'switch\s*\([^)]*\)')
        failed = False
        for material, fire, other in [('WOOD',0,5), ('LEATHER',0,10), ('CLOTH',0,5), ('IRONWOOD',10,None), ('DARKWOOD',20,15), ('DRAGON_HIDE',15,None)]:
            m = re.search(r'case\s+MAT_' + material + r'\s*:(.*?)(?=\bcase\b|\bdefault\b|\Z)', f, re.S)
            actual = compact(m[1]) if m else 'missing'
            expected = f'return{fire};' if other is None else f'return({dtype}==AD_FIRE)?{fire}:{other};'
            failed |= measure(actual == expected, f'MAT_{material} fire hardness expected={fire}; rule={actual}')
        return failed

    if rule == 'item_hardness':
        f = body(s, r'\bItem\s*::\s*Hardness\s*\([^)]*\)')
        q = body(s, r'\bQItem\s*::\s*Hardness\s*\([^)]*\)')
        m = re.search(r'\bint16\s+(\w+)\s*=\s*MaterialHardness\s*\(\s*Material\s*\(\s*\)\s*,\s*(\w+)\s*\)\s*;', f)
        if not m:
            return measure(False, 'Item::Hardness material initialization missing')
        hd, dtype = m.groups()
        f = compact(re.sub(r'\b' + hd + r'\b', 'H', f))
        # Exact statement structure deliberately rejects new paths that could
        # bypass the sentinel guard or apply the arithmetic twice.
        # inc-to9x's quality immunity is pinned as the FIRST statement, ahead of
        # the material lookup and therefore ahead of both returns below. It
        # returns the sentinel rather than adding to anything, so it cannot be
        # rewritten into the arithmetic without failing here.
        prefix = (f'if(QualityImmune({dtype}))return-1;'
                  f'int16H=MaterialHardness(Material(),{dtype});if(H<0)returnH;')
        zero = 'if(H==0){if(GetPlus()>=0)H+=GetPlus()*5;elseH+=50;returnH;}'
        arithmetic = 'if(HasQuality(IQ_DWARVEN))H+=10;if(HasQuality(IQ_ORCISH)||HasQuality(IQ_SILVER))H/=2;if(HasQuality(IQ_ADAMANT)||HasQuality(IQ_DARKWOOD))H*=2;if(HasQuality(IQ_MITHRIL))H=(H*150)/100;if(GetPlus()>=0)H+=GetPlus()*5;elseH+=50;returnH;'
        delegated = bool(re.fullmatch(r'returnItem::Hardness\(\w+\);', compact(q)))
        return measure(f == prefix + zero + arithmetic and delegated,
                       f'Item arithmetic and preceding immunity guard={"intact" if f == prefix + zero + arithmetic else "changed"}; QItem single delegation={int(delegated)}/1')

    f = body(s, r'\bItem\s*::\s*Damage\s*\([^)]*\)')
    init = re.search(r'\b(\w+)\s*=\s*Hardness\s*\(\s*(\w+)\s*\.\s*DType\s*\)\s*;', f)
    calls = len(re.findall(r'\bResistLevel\s*\(', f))
    gear_calls = len(re.findall(r'\bGearResistLevel\s*\(', f))
    grant = re.search(r'\b(\w+)\s*=\s*\w+\s*->\s*GearResistLevel\s*\(\s*(\w+)\s*\.\s*DType\s*\)\s*;', f)
    guarded = False
    if init and grant and init[2] == grant[2]:
        hard, gear, ev = init[1], grant[1], init[2]
        decl = re.search(r'\bint16\s+' + re.escape(gear) + r'\s*=\s*0\s*;', f)
        tail = compact(f[grant.end():])
        # The whole order is pinned, because inc-kapn is a statement ABOUT the
        # order: the immunity return still precedes every piece of arithmetic;
        # the two bypass flags then act on what Hardness() returned and on
        # nothing else, because each speaks about the MATERIAL rather than
        # about the owner's spell; and only then is the grant added, under the
        # same nonnegative guard that keeps the -1 sentinel out of arithmetic.
        # An addition that moves back above the bypass fails here.
        guarded = tail.startswith(
            f'if({gear}==-1)returnDONE;}}'
            f'if({hard}>=0){{if({ev}.ignoreHardness==true){hard}=0;'
            f'elseif({ev}.halfHardness==true){hard}/=2;}}'
            f'if({hard}>=0){hard}+={gear};')
        # Declared and zeroed before the call, so an item with no owner adds
        # nothing rather than whatever the slot happened to hold.
        guarded &= bool(decl) and decl.start() < grant.start()
        guarded &= init.end() < grant.start()
        guarded &= len(re.findall(r'\b' + re.escape(hard) + r'\s*\+=\s*' + re.escape(gear) + r'\s*;', f)) == 1
    failed = measure(bool(init) and calls == 0 and gear_calls == 1 and guarded,
                     f'Item::Damage hardness initialization={int(bool(init))}/1; ResistLevel calls={calls}/0; GearResistLevel calls={gear_calls}/1; immunity return, bypass order and guarded addition={int(guarded)}/1')
    v = clean(read('src/Values.cpp'))
    g = body(v, r'\bCreature\s*::\s*GearResistLevel\s*\([^)]*\)')
    # Match the entire blanket condition, so an extra damage type cannot hide
    # behind the expected tokens. Other structures need oracle review.
    # The four gear-only types: none of them ever costs a creature hit points,
    # so a wearer-only grant against one would be a no-op (inc-w26h).
    BLANKET = ['AD_DCAY', 'AD_RUST', 'AD_SHAT', 'AD_SOAK']
    blanket = re.findall(r'\bif\s*\(([^()]*)\)\s*return\s+ResistLevel\s*\(\s*(\w+)\s*\)\s*;', g)
    types = []
    if len(blanket) == 1:
        condition, dtype = blanket[0]
        terms = condition.split('||')
        for term in terms:
            m = re.fullmatch(r'\s*' + re.escape(dtype) + r'\s*==\s*(AD_\w+)\s*', term)
            types.append(m[1] if m else '?')
    blanket_ok = sorted(types) == BLANKET
    blanket_ok &= len(re.findall(r'\bResistLevel\s*\(', g)) == 1
    failed |= measure(blanket_ok, f'GearResistLevel blanket types={",".join(sorted(types)) or "none"}; expected={",".join(BLANKET)}')
    loops = re.findall(r'\bStatiIterNature\s*\(\s*this\s*,\s*(\w+)\s*\)(.*?)\bStatiIterEnd\s*\(\s*this\s*\)', g, re.S)
    if not loops:
        raise Unmeasurable('GearResistLevel status loops missing')
    expected = {
        'IMMUNITY': r'if\(S->Val==\w+&&S->eID&&RES\(S->eID\)->Type==T_TEFFECT&&TEFF\(S->eID\)->HasFlag\(EF_PROTECTS_ITEMS\)\)\w+=true;',
        'RESIST': r'if\(!S->Dis&&S->Val==\w+&&S->eID&&RES\(S->eID\)->Type==T_TEFFECT&&TEFF\(S->eID\)->HasFlag\(EF_PROTECTS_ITEMS\)\)\w+=max\(\w+,\(int16\)S->Mag\);',
    }
    guarded_loops = sum(bool(re.fullmatch(expected.get(nature, r'(?!)'), compact(code))) for nature, code in loops)
    failed |= measure(sorted(n for n, _ in loops) == ['IMMUNITY', 'RESIST'] and guarded_loops == 2,
                      f'GearResistLevel flag-guarded status loops={guarded_loops}/2')

    # The two divine feats have no effect id, so no flag can reach them and the
    # loops above can never see them. One helper serves both readers; pin its
    # whole body, so dropping a damage type, the CHANNELING condition or the
    # Charisma scaling is a failure, and pin each reader's single use of it.
    sig = re.search(r'\bbool\s+DivineFeatResist\s*\(\s*Creature\s*\*\s*(\w+)\s*,'
                    r'\s*int16\s+(\w+)\s*,\s*int16\s*&\s*(\w+)\s*\)', v)
    if not sig:
        raise Unmeasurable('DivineFeatResist signature missing or reshaped')
    c, dtype, mag = sig.groups()
    def arm(types, feat, scale):
        condition = '||'.join(f'{dtype}=={t}' for t in types)
        return (f'if(({condition})&&{c}->HasFeat({feat})&&{c}->HasStati(CHANNELING))'
                f'{{{mag}={c}->Mod(A_CHA){scale};returntrue;}}')
    want = (arm(['AD_NECR', 'AD_HOLY', 'AD_LAWF', 'AD_CHAO', 'AD_EVIL'], 'FT_DIVINE_ARMOUR', '*2')
            + arm(['AD_FIRE', 'AD_COLD', 'AD_ELEC'], 'FT_DIVINE_RESISTANCE', '')
            + 'returnfalse;')
    got = compact(body(v, r'\bbool\s+DivineFeatResist\s*\([^)]*\)'))
    # The creature keeps its own grant unchanged: the value still enters
    # Resists[] so it stacks, and a zero or negative modifier still counts.
    r = compact(body(v, r'\bCreature\s*::\s*ResistLevel\s*\([^)]*\)'))
    creature = re.search(r'if\(DivineFeatResist\(this,(\w+),(\w+)\)\)Resists\[ResistCount\+\+\]=\2;', r)
    creature_uses = len(re.findall(r'\bDivineFeatResist\s*\(', r))
    # Gear takes the same grant, as the best of the sources rather than stacked.
    gear = re.search(r'if\(DivineFeatResist\(this,(\w+),(\w+)\)\)(\w+)=max\(\3,\2\);', compact(g))
    gear_uses = len(re.findall(r'\bDivineFeatResist\s*\(', g))
    failed |= measure(got == want and bool(creature) and creature_uses == 1
                                  and bool(gear) and gear_uses == 1,
                      f'DivineFeatResist grants={"intact" if got == want else "changed"}; '
                      f'ResistLevel stacks it={int(bool(creature)) if creature_uses == 1 else 0}/1; '
                      f'GearResistLevel takes its max={int(bool(gear)) if gear_uses == 1 else 0}/1')
    return failed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rule', choices=['dequ_dice','dequ_dc','fire_hardness','item_hardness','item_owner_resist'])
    parser.add_argument('--root', type=Path, default=Path('.'))
    args = parser.parse_args()
    try:
        sys.exit(int(run(args.rule, args.root)))
    except Unmeasurable as e:
        print('COULD NOT MEASURE: ' + str(e))
        sys.exit(2)
