#!/bin/bash
# witness for S05 (both sides add a stati value 251; B writes it as (250 + 1)): in the landed tree A's status keeps
# 251 (it is on master, so its saved files hold 251); when both exist B holds a different value below LAST_STATI.
# `#define NAME <expression of integers, + and ->` is read from inc/Defines.h and evaluated. $1 = the worktree.
# fact: stati values -- inc/Defines.h of the landed tree; no game run, no seed
set -uo pipefail
python3 - "$1/inc/Defines.h" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="latin-1").read()
def val(n):
    m = re.search(r"^#define %s[ \t]+([0-9+\-*() \t]+?)[ \t]*(?:/\*.*)?$" % n, t, re.M)
    return eval(m.group(1)) if m and re.fullmatch(r"[0-9+\-*() \t]+", m.group(1)) else None
a, b, last = val("AC8_EXPR_A"), val("AC8_EXPR_B"), val("LAST_STATI")
print("AC8_EXPR_A=%s AC8_EXPR_B=%s LAST_STATI=%s" % (a, b, last))
bad = lambda m: (print("FAIL: " + m), sys.exit(1))
if last is None: bad("no LAST_STATI")
if a is None and b is None: bad("the tree declares neither case status")
if a is not None and a != 251: bad("A's status changed from 251 to %s" % a)
if a is not None and not a < last: bad("A is not below LAST_STATI")
if b is not None and not b < last: bad("B is not below LAST_STATI")
if a is not None and b is not None and a == b: bad("A and B hold one value, %s" % a)
print("witness: statuses hold distinct values below LAST_STATI, A at 251")
PY
