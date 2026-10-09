#!/bin/bash
# gate: cheap
# inc-u3dp phase 6: the four hide-check TRIED keys cannot collide with any other
# TRIED key. 0 GREEN, 1 RED, 2 INCONCLUSIVE.
#
# WHAT IT PROVES. Each hide key is an id + 100*EV_SPOT_CHECK and is stored in
# the Val field of a TRIED stati (signed 16 bits). If any other TRIED use
# evaluates its Val to one of the four, two kinds of state share one entry and
# overwrite each other. This check reads the four values from the headers by
# compiling a tiny program with the same flags build_macos.sh uses for one file,
# extracts the Val expression of every TRIED use in src/ and lib/, evaluates
# each compile-time-constant expression in that same tiny program, and fails if
# any value equals a hide key outside src/HideCheck.cpp and the hide probes.
#
# WHY A COMPILED EXPRESSION AND NOT A GREP. The keys are sums of macros
# (SK_* + 100*EV_*), so a textual match would miss a collision written a
# different way. Evaluating the same expression the compiler sees is the only
# way to be sure; it also catches a raw literal that happens to land on a key.
#
# RED PROOF. Add a scratch line 'HasStati(TRIED, 30000 + SK_SPOT);' to any
# probe file and run again: 30000+44 == HK_SPOT_RESULT, so it is a RED.
#
# Exit: 0 no collision, 1 a collision (or a key too big for Val), 2 no measure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CXX="${CXX:-clang++}"
command -v "$CXX" >/dev/null || { echo "INCONCLUSIVE: $CXX not on PATH"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tried-keys-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The same flags build_macos.sh gives a POSIX source file (build_macos.sh:324,
# 337). No linking against the game: the constants are compile-time.
CXXFLAGS="-std=c++17 -O2 -w -fpermissive -Wno-narrowing -DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat"

# --- 1. The four hide-key values, straight from the headers. ----------------
cat > "$TMP/keys.cpp" <<'EOF'
#include "Incursion.h"
#include "HideCheck.h"
#include <cstdio>
int main() {
    printf("HK_SPOT_RESULT %d\n", (int)HK_SPOT_RESULT);
    printf("HK_HIDE_BAND %d\n", (int)HK_HIDE_BAND);
    printf("HK_DISTRACT %d\n", (int)HK_DISTRACT);
    printf("HK_ROAR %d\n", (int)HK_ROAR);
    return 0;
}
EOF
"$CXX" $CXXFLAGS "$TMP/keys.cpp" -o "$TMP/keys" 2> "$TMP/keys.err" || {
    echo "INCONCLUSIVE: could not compile the key program"; cat "$TMP/keys.err"; exit 2;
}
"$TMP/keys" > "$TMP/keys.txt" || { echo "INCONCLUSIVE: key program failed"; exit 2; }

# A key too big for the signed 16-bit Val field is itself a RED.
while read -r n v; do
    if [ "$v" -ge 32767 ]; then
        echo "RED: $n = $v does not fit Status::Val (signed 16-bit)"
        exit 1
    fi
done < "$TMP/keys.txt"

# --- 2. Extract every TRIED use's Val expression from src/ and lib/. --------
# keypos: the argument position (1-based) of the Val/key in each call. The
# signatures are in inc/Api.h: HasStati(n, val, t); GainPermStati(n, h, cause,
# val, mag,...); GainTempStati(n, h, dur, cause, val,...); RemoveStati(n, cause,
# val,...); IncStatiMag(n, cause, val, t, inc).
python3 - "$TMP/exprs.txt" <<'PY'
import pathlib, re, sys
funcs = {'HasStati':2,'GetStatiMag':2,'SetStatiMag':2,'IncStatiMag':3,
         'GainPermStati':4,'GainTempStati':5,'RemoveStati':3}
pat = re.compile(r'\b(' + '|'.join(funcs) + r')\s*\(')
out = []
for root in ('src','lib'):
    for p in sorted(pathlib.Path(root).glob('*')):
        if p.is_dir():
            continue
        try:
            txt = p.read_text(errors='replace')
        except OSError:
            continue
        if 'TRIED' not in txt:
            continue
        for m in pat.finditer(txt):
            i = m.end(); depth = 1; start = i
            while i < len(txt) and depth:
                if txt[i] == '(': depth += 1
                elif txt[i] == ')': depth -= 1
                i += 1
            inner = txt[start:i-1]
            args = []; d = 0; cur = ''
            for ch in inner:
                if ch in '([': d += 1
                elif ch in ')]': d -= 1
                if ch == ',' and d == 0:
                    args.append(cur.strip()); cur = ''
                else:
                    cur += ch
            args.append(cur.strip())
            fn = m.group(1)
            if fn not in funcs:
                continue
            # The first argument must be exactly TRIED: an n argument.
            if not args or args[0] != 'TRIED':
                continue
            kp = funcs[fn] - 1
            if kp >= len(args):
                continue
            expr = args[kp]
            line = txt.count('\n', 0, m.start()) + 1
            out.append((str(p), line, fn, expr))
with open(sys.argv[1], 'w') as f:
    for p, line, fn, expr in out:
        f.write(f'{p}\t{line}\t{fn}\t{expr}\n')
PY

# --- 3. Keep only compile-time-constant expressions. ------------------------
# An expression made only of macros (upper-case), digits, casts to integer
# types, and operators can be evaluated in a throwaway program. Anything with a
# lower-case identifier (a runtime variable such as `key`) is not a compile-time
# constant and is skipped: it cannot collide with a fixed key unless a probe
# passes a hide key through it, and those sites are the hide probes. A name that
# is not a macro at all (a local enum such as HAS_DRUID_ANIMAL) fails the
# compile; the retry below drops it and reports what it dropped.
CC="$CXX" python3 - "$TMP/exprs.txt" "$TMP/const.txt" "$TMP/val.cpp" \
        "$TMP/val" "$TMP/val.txt" "$CXXFLAGS" <<'PY'
import os, re, subprocess, sys
exprs_file, const_file, cpp_file, bin_file, out_file, cxxflags = sys.argv[1:7]
cxx = os.environ.get('CC', 'clang++')

seen = {}
for ln in open(exprs_file):
    p, line, fn, expr = ln.rstrip('\n').split('\t', 3)
    e = expr.strip()
    # Drop a leading integer cast, e.g. (int8)HAS_DRUID_ANIMAL.
    e2 = re.sub(r'^\([a-zA-Z_][a-zA-Z0-9_ ]*\)\s*', '', e)
    # Constant iff every identifier is all-caps (a macro) and no lower-case var.
    ids = re.findall(r'[A-Za-z_][A-Za-z0-9_]*', e2)
    if any(i != i.upper() for i in ids):
        continue
    if not re.fullmatch(r'[A-Z0-9_+\-*/() \t]+', e2):
        continue
    seen.setdefault(e2, []).append((p, line, fn))

exprs = list(seen)

def emit(active):
    with open(cpp_file, 'w') as f:
        f.write('#include "Incursion.h"\n#include "HideCheck.h"\n#include <cstdio>\n')
        f.write('int main() {\n')
        for i, expr in enumerate(exprs):
            if i in active:
                f.write('  printf("E%d %%d\\n", (int)(%s));\n' % (i, expr))
        f.write('  return 0;\n}\n')

active = set(range(len(exprs)))
dropped = []
for _ in range(60):
    emit(active)
    r = subprocess.run([cxx] + cxxflags.split() + [cpp_file, '-o', bin_file],
                       capture_output=True, text=True)
    if r.returncode == 0:
        break
    # Drop every expression naming an undeclared identifier.
    bad = set(re.findall(r"undeclared identifier '([A-Za-z_][A-Za-z0-9_]*)'",
                         r.stderr))
    if not bad:
        sys.stderr.write('INCONCLUSIVE: constant TRIED Val program does not compile\n')
        sys.stderr.write(r.stderr)
        sys.exit(2)
    for i in list(active):
        ids = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', exprs[i]))
        if ids & bad:
            active.discard(i)
            dropped.append((exprs[i], ';'.join('%s:%s' % (p, l)
                                                for p, l, fn in seen[exprs[i]])))
else:
    sys.stderr.write('INCONCLUSIVE: expression narrowing did not converge\n')
    sys.exit(2)

subprocess.run([bin_file], stdout=open(out_file, 'w'), check=True)
with open(const_file, 'w') as f:
    for i in sorted(active):
        expr = exprs[i]
        f.write('E%d\t%s\t%s\n' % (i, expr, ';'.join('%s:%s' % (p, l)
                                                      for p, l, fn in seen[expr])))
for expr, sites in dropped:
    sys.stderr.write('NOTE: not a compile-time constant, skipped: '
                     'TRIED(%s) at %s\n' % (expr, sites))
PY
[ $? -eq 0 ] || exit 2

# --- 5. Compare. Any constant expression equal to a hide key, outside
#        src/HideCheck.cpp and the hide probes, is a RED. -------------------
python3 - "$TMP/const.txt" "$TMP/val.txt" "$TMP/keys.txt" <<'PY'
import os, re, sys
consts = {}
for ln in open(sys.argv[1]):
    ln = ln.rstrip('\n')
    if not ln: continue
    idx, expr, sites = ln.split('\t', 2)
    consts[int(idx[1:])] = (expr, sites)
val = {}
for ln in open(sys.argv[2]):
    m = re.match(r'E(\d+) (-?\d+)$', ln.strip())
    if m: val[int(m.group(1))] = int(m.group(2))
keyval = {}
for ln in open(sys.argv[3]):
    n, v = ln.split(); keyval[int(v)] = n

# Site is exempt if it is src/HideCheck.cpp or a hide probe.
def exempt(site):
    f = site.rsplit(':', 1)[0]
    if f == 'src/HideCheck.cpp': return True
    base = os.path.basename(f)
    return 'Hide' in base and 'Probe' in base

red = []
for idx, (expr, sites) in consts.items():
    v = val.get(idx)
    if v in keyval:
        if not all(exempt(s) for s in sites.split(';')):
            red.append((keyval[v], expr, v, sites))

if red:
    for name, expr, v, sites in red:
        print(f'RED: {name} = {v} collides with TRIED({expr}) at {sites}')
    sys.exit(1)
k = {n: int(v) for n, v in (l.split() for l in open(sys.argv[3]))}
print(f'GREEN: {len(val)} constant TRIED Val expressions, none collides with '
      f'HK_SPOT_RESULT={k["HK_SPOT_RESULT"]}, HK_HIDE_BAND={k["HK_HIDE_BAND"]}, '
      f'HK_DISTRACT={k["HK_DISTRACT"]}, HK_ROAR={k["HK_ROAR"]}; all < 32767')
PY
