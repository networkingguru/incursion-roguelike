#!/usr/bin/env python3
"""Read-only field comparison for the script-variable round-trip evidence."""
import pathlib, struct, sys, zlib
FIXED={1:1,2:1,3:2,4:2,5:4,6:4,9:4,10:4}
def fields(stream,prefix=''):
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
        key=f'{prefix}{tag}'
        if kind==12:out.update(fields(pay,key+'.'))
        else:out[key]=(kind,pay)
def records(path):
    data=pathlib.Path(path).read_bytes()
    comp,=struct.unpack_from('<h',data,90)
    size,packed,count=struct.unpack_from('<iii',data,104)
    payload=data[124:124+packed]
    if comp==1:payload=zlib.decompress(payload)
    assert len(payload)==size
    pos=0;out={}
    for _ in range(count):
        typ=payload[pos];handle,n=struct.unpack_from('<II',payload,pos+1);pos+=9
        out[(typ,handle)]=fields(payload[pos:pos+n]);pos+=n
    return out
ALLOW = {(1,str(t)) for t in range(800,808)} | {(1,'811'),(1,'812'),(1,'814'),(7,'527.1'),(7,'527.2'),(7,'527.5')}
def compare(a,b):
    first,second=records(a),records(b)
    assert first.keys()==second.keys(), 'record sets differ'
    for key in first:
        for tag in first[key].keys()|second[key].keys():
            if first[key].get(tag)==second[key].get(tag): continue
            assert any(key[0]==typ and (tag==path or tag.startswith(path+'.')) for typ,path in ALLOW), (key,tag)
def variables(path):
    return {tag: value for (typ,h),fs in records(path).items() if typ==1
            for tag,value in fs.items() if tag.startswith('816.') and tag.endswith('.7')}
if __name__=='__main__':
    compare(*sys.argv[1:3])
    assert variables(sys.argv[1])==variables(sys.argv[2])
    print('PASS fixpoint outside documented volatile fields; variable records byte-identical')
