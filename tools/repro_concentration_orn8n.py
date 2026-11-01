#!/usr/bin/env python3
"""inc-orn8n: historical measurement, NOT a new regression check or repair.

Prepare /tmp/inc-orn8n-a with git archive e8102f0c^1, and -b with
git archive e8102f0c. Build each with BACKEND=posix ./build_macos.sh.
Before building/running, symlink each archive's logs/ into this worktree's
logs/inc-orn8n/archive-{a,b}; redirect build output into logs/inc-orn8n/.
Then: python3 tools/repro_concentration_orn8n.py

The existing check's seed-dependent verdicts are reported, never converted
into new assertions. Cross the two executables with the two unchanged modules.
No source, module, fixture or existing check is edited by this driver.

Fact inventory of the existing check (including its five key scripts):
# fact: mage race/class/stats/kit/name/skills/innate spells/HP/world/options --
#       INCURSION_LOAD=elf-mage-illusions-seed1.sav (same bytes on both sides)
# fact: settings -- options-2026-08-22.dat; loaded settings also come from save
# fact: seed -- original seed 1; historical comparison only, not a control
#       that makes a new check independent of random monster selection
# fact: scripts -- concentration-{core,block,damage,tail,monster}.keys unchanged
# fact: spell choice -- Select Spell, Phantasmal Force, Improved Phantasmal Fo
#       selected by name; c/i illusion arm, Target Illusion, ENTER placement
# fact: cancel -- lowercase x, Stop concentrating on Phan/Improved menu text
# fact: prompt clearing -- more -- matched literally and cleared with SPACE
# fact: illusion species/glyph -- UNCONTROLLED; original check assumes R
#       illusory (monitor); catalog says read random text from the run instead
# fact: core presence/absence -- started/cancel-menu/cancelled screen labels;
#       Concentrating, R illusory, Stop concentrating on literal screen text
# fact: cast/attack refusal -- You cannot do that while concentrating on text
# fact: goblin identity/location -- wizard Monster Summoning, Goblinkin,
#       goblin, RIGHT ENTER; no Genocide in original damage script
# fact: freeze setting -- Wizard Mode Switches DOWN*10 SPACE (positional row)
# fact: goblin gear, hit/damage rolls, AI -- UNCONTROLLED; eight waits;
#       catalog offers SUMMON_NO_GEAR, LOF_FORCE_ROLL, FORCE_DAMAGE_ROLL,
#       but no monster-AI control (no new check is written around that hole)
# fact: damage -- first adjacent screen HP drop, HP:(digits)/(digits), paired
#       with first CONCENT check; assumes one damage event between snapshots
# fact: spell level -- Phantasmal Force level 1 hardcoded in damage oracle
# fact: tail -- cancelled/w01..w12 headers: label, key, mode, turn; R illusory
#       present at cancel and first wait, absent by 80 ticks after cancel
# fact: concentration logs -- INCURSION_CONCENT_PROBE=1, logs/errors.log;
#       start Phantasmal Force cap>0 tail=0; stop reason=cancel tail=0;
#       block event=cast|invoke|attack; check spell/dc/result parsed;
#       Improved Phantasmal Force start cap>0/stop reason=cancel tail=1
# fact: monster state -- INCURSION_CONCENT_MONSTER_PROBE=1 only last session;
#       ConcentMonsterProbe gives giant rats Telekinesis, range 10,
#       CONCENTRATING, HP 100/100 and 40/100, places near fixture player,
#       removes sleep and calls actual ChooseAction
# fact: monster decisions -- literal probe fields giant rat/Telekinesis,
#       keep/stop, affects=1, HP 100/100 or 40/100; cancel tail=0
# fact: source guards -- three check_mutation literals in Concentration.cpp
#       and Skills.cpp must occur once; ordinary invocation does not mutate
# fact: harness -- check_lib/headless, session exit, gameplay log, known
#       asserts, dump availability; MAP_AUDIT/SAVE_PROBE default to 1;
#       no inherited INCURSION_* variables or launcher in this comparison

No forced-roll variable is set: preserve original inputs to reproduce L1.
The proposed repair is to observe the illusion independently of species/glyph,
not to pin another seed or replace R with B. See the accompanying specimens.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import time

root = Path(__file__).resolve().parent.parent
base = root / 'logs/inc-orn8n' / ('comparison-' + time.strftime('%Y%m%d-%H%M%S'))
base.mkdir(parents=True, exist_ok=False)
archives = {s: Path('/tmp/inc-orn8n-' + s).resolve() for s in ('a', 'b')}
inputs = ['tools/check_concentration.sh', 'tools/check_lib.sh',
          'tools/headless.sh', 'tools/known_asserts.txt', 'tools/gametime.awk',
          'tools/fixtures/options-2026-08-22.dat',
          'tools/fixtures/chars/elf-mage-illusions-seed1.sav']
inputs += ['tools/keys/concentration-' + s + '.keys'
           for s in ('core', 'block', 'damage', 'tail', 'monster')]
manifest = []
for name in inputs:
    hashes = [hashlib.sha256((archives[s] / name).read_bytes()).hexdigest()
              for s in ('a', 'b')]
    if hashes[0] != hashes[1]:
        raise SystemExit('Comparison input differs: ' + name)
    manifest.append(hashes[0] + '  ' + name)
for label, archive in archives.items():
    if not (archive / 'logs').resolve().is_relative_to(root / 'logs'):
        raise SystemExit('Archive logs must point inside worktree logs/: ' + label)
    for name in ('incursion-headless', 'mod/Incursion.Mod'):
        manifest.append(hashlib.sha256((archive / name).read_bytes()).hexdigest()
                        + '  ' + str(archive / name))
(base / 'inputs.sha256').write_text('\n'.join(manifest) + '\n')
env = {k: v for k, v in os.environ.items() if not k.startswith('INCURSION')}
summary = []
for data, binary in (('a', 'a'), ('b', 'b'), ('a', 'b'), ('b', 'a')):
    tag = 'module-' + data + '-binary-' + binary
    runenv = dict(env, INCURSION_BIN=str(archives[binary] / 'incursion-headless'))
    result = subprocess.run(['bash', 'tools/check_concentration.sh'],
                            cwd=archives[data], env=runenv,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True)
    (base / (tag + '.log')).write_text(result.stdout)
    summary.append(tag + ' exit=' + str(result.returncode))
    for line in result.stdout.splitlines():
        if 'FAIL' in line or 'ok    TAIL:' in line:
            summary.append(line)
    for run in re.findall(r'^  session: (\S+)', result.stdout, re.M):
        if run.endswith(('-concentration-core', '-concentration-tail')):
            for screen in sorted((Path(run) / 'logs/screens').glob('*.txt')):
                text = screen.read_text()
                sidebar = [line.split('|', 1)[1].strip()
                           for line in text.splitlines()
                           if '|' in line and 'illusory' in line.split('|', 1)[1]]
                summary.append(str(screen.resolve()) + ': ' +
                               text.splitlines()[0] + ' sidebar=' + repr(sidebar))
output = '\n'.join(summary) + '\n'
(base / 'summary.txt').write_text(output)
print(output, end='')
print('Specimens:', base)
