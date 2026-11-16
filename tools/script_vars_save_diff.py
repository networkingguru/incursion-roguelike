#!/usr/bin/env python3
"""Read-only field comparison for the script-variable round-trip evidence.

Fields are keyed by NAME (inc-cjos0): a revision 7 save numbers its fields by
row of its own name table (the group's type-200 record), so the walk reads
that table and spells each field as a dotted path of names. A revision 3-6
file has no table (the recovery tools read such files from the frozen 391e353
build and from tools/fixtures/chars/); its fields keep their tag numbers, as
the dotted path of numbers they have always been, e.g. '816.1.4'."""
import pathlib, struct, sys, zlib
FIXED={1:1,2:1,3:2,4:2,5:4,6:4,9:4,10:4}
REC_NAMES=200
def fields(stream,names,prefix=''):
    pos=0; out={}
    while True:
        tag,=struct.unpack_from('<H',stream,pos);pos+=2
        if not tag:return out
        kind=stream[pos];pos+=1
        if kind in FIXED:n=FIXED[kind]
        elif kind in (7,8,12):n,=struct.unpack_from('<I',stream,pos);pos+=4
        elif kind==11:
            count,width=struct.unpack_from('<II',stream,pos);n=8+count*width
        else:raise ValueError(kind)
        pay=stream[pos:pos+n];pos+=n
        key=f'{prefix}{names[tag] if names else tag}'
        if kind==12:out.update(fields(pay,names,key+'.'))
        else:out[key]=(kind,pay)
def table(body):
    names={};q=0
    while q!=len(body):
        nid,sl=struct.unpack_from('<HH',body,q);q+=4+sl
        nl,=struct.unpack_from('<H',body,q);q+=2
        names[nid]=body[q:q+nl].decode();q+=nl
    return names
def records(path):
    data=pathlib.Path(path).read_bytes()
    comp,=struct.unpack_from('<h',data,90)
    size,packed,count=struct.unpack_from('<iii',data,104)
    payload=data[124:124+packed]
    if comp==1:payload=zlib.decompress(payload)
    assert len(payload)==size
    pos=0;raw=[];names={}
    for _ in range(count):
        typ=payload[pos];handle,n=struct.unpack_from('<II',payload,pos+1);pos+=9
        body=payload[pos:pos+n];pos+=n
        if typ==REC_NAMES:names=table(body)
        else:raw.append((typ,handle,body))
    return {(typ,handle):fields(body,names) for typ,handle,body in raw}
ALLOW = ({(1,n) for n in ('ccHasEffStati','ccHasValStati','ccHasNatStati','ccHasStatiTrue',
                           'ccHasStatiFalse','ccHSPerceive','ccHSMonAI','ccHSCalcVal',
                           'ccStatiNat','ccStatiVal','Turn')}
         | {(7,'GameTimeInfo.GameTimeInfo_LTI'),(7,'GameTimeInfo.GameTimeInfo_start_turn'),
            (7,'GameTimeInfo.GameTimeInfo_start_second')})
def compare(a,b):
    first,second=records(a),records(b)
    assert first.keys()==second.keys(), 'record sets differ'
    for key in first:
        for tag in first[key].keys()|second[key].keys():
            if first[key].get(tag)==second[key].get(tag): continue
            assert any(key[0]==typ and (tag==path or tag.startswith(path+'.')) for typ,path in ALLOW), (key,tag)
def variables(path):
    """The script-variable blob of every module slot: Game.MDataSeg.Segment#k.Variables
    (revision 3-6 files: tag path 816.<1+k>.7)."""
    def is_var(tag):
        return ((tag.startswith('MDataSeg.') and tag.endswith('.Variables'))
                or (tag.startswith('816.') and tag.endswith('.7')))
    return {tag: value for (typ,h),fs in records(path).items() if typ==1
            for tag,value in fs.items() if is_var(tag)}
if __name__=='__main__':
    compare(*sys.argv[1:3])
    vars_a=variables(sys.argv[1])
    assert vars_a, 'no MDataSeg.*.Variables field in the save: the variable records were not compared'
    assert vars_a==variables(sys.argv[2])
    print('PASS fixpoint outside documented volatile fields; variable records byte-identical')
