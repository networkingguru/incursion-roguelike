#!/usr/bin/env python3
"""Exercise real saves and sandbox modules; keep every specimen under logs/."""
import os, pathlib, re, shutil, subprocess, tempfile, struct
from script_vars_save_diff import compare, variables
ROOT = pathlib.Path(__file__).resolve().parents[1]
WORK = pathlib.Path(tempfile.mkdtemp(prefix='script-vars-survive.', dir=ROOT/'logs'))
BIN = ROOT/'incursion-headless'
print(f'Specimens: {WORK}', flush=True)

def run(sb, args, label):
    env = dict(os.environ, INCURSIONPATH=str(sb)+'/', INCURSION_SEED='1')
    with (sb/'logs'/label).open('w') as out:
        return subprocess.run([str(BIN), *map(str,args)], cwd=ROOT, env=env,
                              stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT).returncode

def sandbox(name, source=None):
    sb=WORK/name
    for d in ['mod','save','logs']: (sb/d).mkdir(parents=True,exist_ok=True)
    shutil.copytree((source or ROOT)/'lib',sb/'lib')
    (sb/'inc').symlink_to(ROOT/'inc')
    shutil.copyfile(ROOT/'tools/fixtures/options-2026-08-22.dat',sb/'Options.Dat')
    return sb

def edit(sb,file,old,new):
    p=sb/'lib'/file
    text=p.read_text(); assert old in text, (file,old)
    p.write_text(text.replace(old,new,1))

def compile(sb):
    assert run(sb,['-compile','main.irc'],'compile.log')==0, sb/'logs/compile.log'
    assert (sb/'mod/Incursion.Mod').exists()

def dump(sb,save):
    rc=run(sb,['-dump',save],'dump.log')
    text=(sb/'logs/dump.log').read_text(errors='replace')
    rows={}
    for m in re.finditer(r'  slot=(\d+) owner=(.*?) ordinal=(\d+) ident=(\S+) type=(.*?) value=(-?\d+)',text):
        slot,owner,ordinal,name,typ,value=m.groups()
        rows[(owner,int(ordinal))]=(name,typ,int(value),int(slot))
    return rc,rows,text

base=sandbox('base')
edit(base,'main.irc','Slot 0;','Slot 0;\nint32 oracleScratch, oracleGlobal;')
edit(base,'races.irh','Race "Orc;race"\n  {','Race "Orc;race"\n  {\nint32 oracleA, oracleB;')
p=base/'lib/races.irh'; text=p.read_text(); start=text.index('Race "Orc;race"')
a=text.index('hObj h;',start)+len('hObj h;')
text=text[:a]+'\noracleA = 12345; oracleB = 67890; oracleGlobal = 24680; RedirectEff(e,$"Khasrach",EV_BIRTH);'+text[a:]; p.write_text(text)
edit(base,'religion.irh','God "Khasrach"\n  {','God "Khasrach"\n  {\nint32 oracleGod;\nOn Event EV_BIRTH { oracleGod = 13579; };')
compile(base)
assert run(base,['-keys',ROOT/'tools/keys/smoke.keys'],'session.log')==0
save=next((base/'save').glob('*.sav'))
rc,original,_=dump(base,save); assert rc==0
assert original[('Orc;race',0)][2]==12345, original
assert original[('Orc;race',1)][2]==67890
assert original[('Khasrach',0)][2]==13579
assert any(v[0]=='oracleGlobal' and v[2]==24680 for v in original.values())
print(f'baseline variables={len(original)} nonzero={sum(v[2]!=0 for v in original.values())}',flush=True)
failed=0
for case in [16,17,18,19,22,23,24,29]:
    sb=sandbox(str(case),base)
    if case==16: edit(sb,'religion.irh','int32 oracleGod;','int32 oracleGod, oracleNew;')
    if case==17:
        with (sb/'lib/main.irc').open('a') as out: out.write('\nint32 oracleNewGlobal;\n')
    if case==29:
        with (sb/'lib/main.irc').open('a') as out: out.write('\nEffect "Variable Append Oracle" : EA_NOTIMP { int32 oracleNew; }\n')
    if case==18:
        # Resource-kind lists keep their order. Move the entire Race list
        # behind the appended Effect; preserve all within-pool resource order.
        source=(base/'lib/program.i').read_text()
        blocks=[]; spans=[]
        token=re.compile(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*|[{}]',re.S)
        for match in re.finditer(r'^Race "[^"]+"',source,re.M):
            depth=0; opened=False
            for t in token.finditer(source,match.end()):
                if t.group()=='{': depth+=1; opened=True
                elif t.group()=='}':
                    depth-=1
                    if opened and depth==0:
                        spans.append((match.start(),t.end()))
                        blocks.append(source[match.start():t.end()]); break
        assert blocks
        for a,b in reversed(spans): source=source[:a]+source[b:]
        declaration='int32 oracleScratch, oracleGlobal;'
        assert source.count(declaration)==1
        # Global declarations stay before their uses and keep owner order.
        effect_kind=re.search(r'^#define EA_NOTIMP\s+(\d+)',(ROOT/'inc/Defines.h').read_text(),re.M).group(1)
        source+='\nEffect "Variable Append Oracle" : '+effect_kind+' { int32 oracleNew; }\n'
        source+='\n'.join(blocks)+'\n'
        (sb/'lib/main.irc').write_text(source)
    if case==19:
        p=sb/'lib/races.irh';p.write_text(p.read_text().replace('oracleA','oracleRenamed'))
    if case==22: edit(sb,'races.irh','int32 oracleA, oracleB;','int32 oracleInserted, oracleA, oracleB;')
    if case==23: edit(sb,'races.irh','int32 oracleA, oracleB;','int32 oracleB, oracleA;')
    if case==24:
        edit(sb,'races.irh','int32 oracleA, oracleB;','int32 oracleA;')
        edit(sb,'races.irh','oracleB = 67890;','')
    compile(sb)
    rc,rows,text=dump(sb,save)
    if case in [22,23,24]:
        good=rc!=0 and all(word in text for word in ['owner','ordinal','recorded','found'])
    else:
        good=rc==0 and all(k in rows and rows[k][1:3]==v[1:3] for k,v in original.items())
        good=good and all(v[2]==0 for k,v in rows.items() if k not in original)
    if case==18:
        moved=sum(k in rows and v[3]!=rows[k][3] for k,v in original.items())
        print(f'case 18 old slots moved={moved}',flush=True)
        good=good and moved>=len(original)-2
    print(f'case {case}: {"PASS" if good else "FAIL"} exit={rc} variables={len(rows)}',flush=True)
    failed+=not good
def fixpoint(source,save,label):
    previous=save
    generations=[]
    for n in [2,3]:
        sb=sandbox(f'{label}-{n}',source)
        shutil.copyfile(source/'mod/Incursion.Mod',sb/'mod/Incursion.Mod')
        output=sb/'save'/save.name
        shutil.copyfile(previous,output)
        assert run(sb,['-keys',ROOT/'tools/keys/loadsave.keys'],'session.log')==0
        generations.append(output);previous=output
    compare(*generations)
    assert variables(save)==variables(generations[0])==variables(generations[1])
    print(f'case {label}: PASS save2/save3 fixpoint; all three variable blobs identical',flush=True)
fixpoint(base,save,'15')
command=sandbox('30',base)
edit(command,'pspells.irh','        TPrint(e, "You point at the <EVictim>',
     '        EActor->IPrint(Format("COMMAND_HTEXT=%d",str));\n        TPrint(e, "You point at the <EVictim>')
compile(command)
rc=run(command,['-keys',ROOT/'tools/keys/script-vars-command.keys'],'session.log')
command_saves=list((command/'save').glob('*.sav'))
if rc==0 and command_saves:
    first=command_saves[0]
    dump_rc,command_rows,_=dump(command,first)
    text_value=[v[2] for (owner,ordinal),v in command_rows.items() if owner=='Command' and v[0]=='str']
    blob=next(iter(variables(first).values()))[1]
    values=[];offset=0
    while offset<len(blob):
        owner,typ,n=struct.unpack_from('<IBB',blob,offset);offset+=6
        name=blob[offset:offset+n].decode();offset+=n
        value,=struct.unpack_from('<i',blob,offset);offset+=4
        if typ==4: values.append((name,value))
    assert ('str',0) in values, values
    print(f'case 30 first SAVE text records={values}',flush=True)
    fixpoint(command,first,'30')
    screens=''.join(p.read_text(errors='replace') for p in (command/'logs/screens').glob('*.txt'))
    htext=[int(v) for v in re.findall(r'COMMAND HTEXT=(\d+)',screens)]
    print(f'case 30 observed live hText={htext}',flush=True)
    failed+=not (text_value==[0] and any(htext))
else:
    print(f'case 30: FAIL Command session exit={rc} saves={len(command_saves)}',flush=True)
    failed+=1
raise SystemExit(1 if failed else 0)
