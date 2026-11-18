#!/bin/bash
# gate: live
# Does every Conditions-screen text say the same words as its help entry? (bd inc-9m0e)
#
#   tools/check_condition_texts.sh
#   exit 0 every ConditionText entry matches lib/help.irh, 1 a text differs, 2 could not measure
#
# fact: ConditionText table -- read from src/Managers.cpp, no game run
# fact: States of Being section -- read from lib/help.irh, no game run
# fact: seed, options, map, RNG -- none read; the check parses two files
#
# THE ORACLE. src/Managers.cpp holds a ConditionText table (name, text). The
# "States of Being" section of lib/help.irh holds one "__<9>Name:<1> text"
# entry per condition. Both must state the same words. Only format is
# normalized: help "~" is C++ "%", help markup (__ <9> <1> \n), line wraps,
# indentation, and the splitting of a C++ string literal.
# IT CANNOT PASS BY DEFAULT: exit 2 when the table or the section is missing,
# or when the section lacks an entry for a table name.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 -I - "$ROOT/src/Managers.cpp" "$ROOT/lib/help.irh" <<'PY'
import re, sys
cpp_path, help_path = sys.argv[1], sys.argv[2]
try:
    cpp = open(cpp_path).read(); hlp = open(help_path).read()
except OSError as e:
    print("INCONCLUSIVE: %s" % e); sys.exit(2)

a = cpp.find("struct ConditionText")
b = cpp.find("static String ConditionEntry")
if a < 0 or b < a:
    print("INCONCLUSIVE: ConditionText table not found in src/Managers.cpp"); sys.exit(2)
table = cpp[a:b]
lit = r'"(?:[^"\\]|\\.)*"'
ents = []
for m in re.finditer(r'\{\s*"(\w+)",\s*((?:%s\s*)+)\}' % lit, table):
    text = ''.join(s[1:-1] for s in re.findall(lit, m.group(2)))
    ents.append((m.group(1), text))
if len(ents) < 18:
    print("INCONCLUSIVE: only %d ConditionText entries found" % len(ents)); sys.exit(2)

s = hlp.find("<9>States of Being<1>")
e = hlp.find("<9>Vaults and Complexes<1>")
if s < 0 or e < s:
    print("INCONCLUSIVE: States of Being section not found in lib/help.irh"); sys.exit(2)
sec = hlp[s:e]
helpents = {}
parts = re.split(r'__<9>(\w+):<1>', sec)
for i in range(1, len(parts) - 1, 2):
    helpents[parts[i]] = parts[i + 1]

def norm(t, tokens=False):
    if tokens:
        for k, v in (('{he}', 'she'), ('{He}', 'She'), ('{his}', 'her'),
                     ('{His}', 'Her'), ('{him}', 'her')):
            t = t.replace(k, v)
    t = t.replace('\\n', ' ').replace('__', ' ').replace('~', '%')
    t = re.sub(r'<\d+>', '', t)
    return ' '.join(t.split())

bad = []
for name, text in ents:
    if name not in helpents:
        print("INCONCLUSIVE: no help entry for %s" % name); sys.exit(2)
    if norm(text, True) != norm(helpents[name]):
        bad.append(name)
if bad:
    print("FAIL: Conditions text differs from its help entry: " + ", ".join(bad))
    sys.exit(1)
print("PASS: %d Conditions texts match their help entries" % len(ents))
