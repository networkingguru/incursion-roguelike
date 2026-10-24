#!/usr/bin/env bash
# gate: cheap
# Static check (no build, no seed): the phase plane names the game prints must
# match the PHASE_ constants, and every CA_PHASE grant in lib/ must name a
# PHASE_ constant rather than a bare number.
#
# FAILS when it cannot see its own target: a missing constant in inc/Defines.h
# or a missing PhasePlaneName switch in src/Skills.cpp is a failure, not a pass.
#
# fact: the PHASE_ values -- inc/Defines.h (source constants, not a roll)
# fact: the plane names -- the PhasePlaneName switch in src/Skills.cpp (source, not a roll)
# fact: the grants -- CA_PHASE grant lines in lib/*.irh (resource data, not a roll)
# fact: no seed is read -- the check opens no session and no save
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 - "$ROOT" <<'PY'
import glob, pathlib, re, sys
root = pathlib.Path(sys.argv[1])

expected = {
    'PHASE_MATERIAL': 'material plane',
    'PHASE_ASTRAL':   'astral plane',
    'PHASE_ETHEREAL': 'ethereal plane',
    'PHASE_SHADOW':   'plane of shadow',
    'PHASE_NEGATIVE': 'negative energy plane',
}

# 1. Constants must exist in inc/Defines.h.
defines = (root / 'inc' / 'Defines.h').read_text(errors='replace')
for name in expected:
    if not re.search(r'#\s*define\s+' + name + r'\b', defines):
        print(f"RED: {name} not defined in inc/Defines.h")
        sys.exit(1)

# 2. The switch must exist in src/Skills.cpp.
skills = (root / 'src' / 'Skills.cpp').read_text(errors='replace')
m = re.search(r'PhasePlaneName\s*\([^)]*\)\s*\{', skills)
if not m:
    print("RED: no PhasePlaneName function in src/Skills.cpp")
    sys.exit(1)
body = skills[m.end():]
depth = 1
i = 0
while i < len(body) and depth:
    if body[i] == '{':
        depth += 1
    elif body[i] == '}':
        depth -= 1
    i += 1
switch = body[:i]
if 'switch' not in switch:
    print("RED: PhasePlaneName has no switch in src/Skills.cpp")
    sys.exit(1)

# 3. Every constant must map to its expected literal string.
cases = dict(re.findall(
    r'case\s+(PHASE_[A-Z_]+)\s*:\s*return\s*"([^"]*)"', switch))
bad = False
for name, want in expected.items():
    got = cases.get(name)
    if got != want:
        print(f'RED: {name} -> {got!r}, expected {want!r}')
        bad = True
if bad:
    sys.exit(1)

# 4. No CA_PHASE grant in lib/*.irh may use a bare number.
#    Forms: ABILITY(CA_PHASE,<arg>) and Ability[CA_PHASE,<arg>].
grant = re.compile(r'(?:ABILITY\s*\(\s*CA_PHASE\s*,\s*([^)]*)\)'
                   r'|Ability\s*\[\s*CA_PHASE\s*,\s*([^\]]*)\])')
for path in sorted(glob.glob(str(root / 'lib' / '*.irh'))):
    for n, line in enumerate(pathlib.Path(path).read_text(errors='replace').splitlines(), 1):
        mm = grant.search(line)
        if not mm:
            continue
        arg = (mm.group(1) or mm.group(2)).strip()
        if not re.match(r'PHASE_[A-Z_]+\s*$', arg):
            print(f"RED: {path}:{n}: CA_PHASE grant uses {arg!r}, not a PHASE_ constant")
            bad = True
if bad:
    sys.exit(1)

print("GREEN: PHASE_ constants, PhasePlaneName switch and lib/ CA_PHASE grants all agree")
PY
