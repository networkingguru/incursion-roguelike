#!/bin/bash
# gate: none explicitly rebuilds a deliberately broken loader
# fact: the save under test -- the base save of the tools/check_script_vars_survive.sh run named by the argument, made under that check's own fact lines
# fact: oracle values 12345, 67890, 13579 -- assigned by the sandbox script edits in tools/script_vars_survive.py, read by -dump with no session
# fact: the sandbox modules -- copied from that run's case directories, not recompiled here
# Usage: tools/check_script_var_loader_mutation.sh logs/script-vars-survive.<id>
set -euo pipefail
cd "$(dirname "$0")/.."
work="$PWD/$1"
evidence="$PWD/logs/inc-glnx-phase2"
cp -f src/SaveV1.cpp "$evidence/SaveV1.before-loader-mutation.cpp"
restore() {
    cp -f "$evidence/SaveV1.before-loader-mutation.cpp" src/SaveV1.cpp
    BACKEND=posix ./build_macos.sh > "$evidence/restored-build.log" 2>&1
}
trap restore EXIT
python3 - <<'PY'
p='src/SaveV1.cpp';s=open(p).read()
old='static long v1PlaceVariables(V1SegPending *sp, Module *mod, char *seg)\n  {'
assert s.count(old)==1
open(p,'w').write(s.replace(old,old+'\n    return 0; /* deliberate loader mutation */'))
PY
BACKEND=posix ./build_macos.sh > "$evidence/broken-loader-build.log" 2>&1
python3 - "$work" <<'PY'
import os,pathlib,re,subprocess,sys
work=pathlib.Path(sys.argv[1]); root=pathlib.Path.cwd()
save=next((work/'base/save').glob('*.sav'))
for case in [16,17,18,19,22,23,24,29]:
 sb=work/str(case)
 env=dict(os.environ,INCURSIONPATH=str(sb)+'/')
 result=subprocess.run([str(root/'incursion-headless'),'-dump',str(save)],env=env,capture_output=True,text=True)
 text=result.stdout+result.stderr
 (sb/'logs/red-loader.log').write_text(text)
 if case in [19,22,23,24]:
  # by-name placement: the mutated loader leaves oracleB (case 24 removed oracleB, so it reads oracleA) at 0, the real one holds 67890
  values=re.findall(r'ident=oracle%s type=int32 value=(-?\d+)'%('A' if case==24 else 'B'),text)
  red=result.returncode==0 and values==['0']
 else:
  pattern=r'ident=oracleGod type=int32 value=(-?\d+)' if case==16 else r'ident=oracleA type=int32 value=(-?\d+)'
  values=re.findall(pattern,text)
  red=result.returncode==0 and values==['0']
 print(f'case {case}: {"RED detected" if red else "MUTATION NOT DETECTED"} exit={result.returncode}',flush=True)
 assert red
PY
