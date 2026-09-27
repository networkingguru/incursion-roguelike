#!/usr/bin/env python3
"""Generate the 391e353 recovery table using the headless compiler/driver.
Historical sources and every build/run specimen stay in logs/.
"""
import json, os, pathlib, re, subprocess, tempfile
from script_vars_save_diff import records
ROOT=pathlib.Path(__file__).resolve().parents[1]
work=pathlib.Path(tempfile.mkdtemp(prefix='prefix-vars.',dir=ROOT/'logs'))
subprocess.run(['git','archive','391e353','lib','inc'],cwd=ROOT,stdout=(work/'source.tar').open('wb'),check=True)
subprocess.run(['tar','-xf',str(work/'source.tar'),'-C',str(work)],check=True)
for d in ['mod','save','logs']: (work/d).mkdir(exist_ok=True)
env=dict(os.environ,INCURSIONPATH=str(work)+'/',INCURSION_SEED='1',INCURSION_V1_RAW='1')
binary=ROOT/'incursion-headless'
def run(args,log):
    with (work/log).open('w') as out:
        subprocess.run([str(binary),*args],cwd=work,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,check=True)
run(['-compile','main.irc'],'compile.log')
run(['-scriptvars'],'variables.tsv')
import shutil
shutil.copyfile(ROOT/'tools/fixtures/options-2026-08-22.dat',work/'Options.Dat')
run(['-keys',str(ROOT/'tools/keys/smoke.keys')],'session.log')
import struct
fields=next(fs for (typ,h),fs in records(next((work/'save').glob('*.sav'))).items() if typ==1)
lengths=struct.unpack('<21I',fields['816.1.4'][1][8:])
types={'int32':2,'hObj':3,'hText':4,'rID':5,'bool':7,'Rect':8,'int16':9,'int8':10,'uint8':11,'uint16':12}
rows=[]
for line in (work/'variables.tsv').read_text().splitlines():
    cols=line.split('\t')
    if len(cols)!=7 or not re.fullmatch('-?\\d+',cols[0]):continue
    array,pos,owner,ordinal,name,typ,address=cols
    assert int(address)==len(rows)
    rows.append((int(array),int(pos),owner,name,types[typ]))
assert len(rows)==97,len(rows)
output='// Generated from commit 391e353 by tools/generate_v1_prefix_vars.py.\n'
output+='static const uint32 v1PrefixLengths[21] = {'+', '.join(map(str,lengths))+'};\n'
output+='struct V1PrefixVariable { int array; uint32 position; const char *owner; const char *name; uint8 type; };\n'
output+='static const V1PrefixVariable v1PrefixVariables[97] = {\n'
for array,pos,owner,name,typ in rows:
    output+=f'    {{{array}, {pos}, {json.dumps(owner)}, {json.dumps(name)}, {typ}}},\n'
output+='};\n'
(ROOT/'src/SaveV1PrefixVars.inc').write_text(output)
print(f'97 rows; 21 lengths={lengths}; source=391e353; specimens={work}')
