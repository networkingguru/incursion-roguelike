#!/bin/bash
# Does tools/sweep_ptr_order.sh actually find a pointer ordering?
#
# Usage: tools/check_ptr_sweep.sh
#
# A sweep that reports nothing looks exactly like a sweep that is broken, and
# on 2026-08-15 this one WAS broken and reported nothing: it filtered hits on an
# absolute path while clang was printing the relative one it had been given.
# The whole codebase came back clean and the known defect in TargetSort was sat
# in the file at the time. So the tool needs a case it must find and a case it
# must ignore, and this runs both in about a second.
#
# It checks four things, one per line of the fixture:
#   subtracting two pointers        MUST be reported
#   comparing two pointers with <   MUST be reported
#   comparing two pointers with >=  MUST be reported
#   comparing two pointers with ==  MUST NOT be reported -- equality is fine,
#                                   two objects either are the same or are not,
#                                   and that answer never moves
#   comparing two ints with <       MUST NOT be reported
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIX="$(mktemp -t ptrsweep).cpp"
OUT="$(mktemp)"
trap 'rm -f "$FIX" "$OUT"' EXIT

cat > "$FIX" <<'EOF'
struct Thing { int x; };
int sub(Thing *l, Thing *r) { return (int)(r - l); }
int lt(Thing *l, Thing *r)  { return l < r; }
int ge(Thing *l, Thing *r)  { return l >= r; }
int eq(Thing *l, Thing *r)  { return l == r; }
int ilt(int a, int b)       { return a < b; }
EOF

clang++ -std=c++17 -fsyntax-only -Xclang -ast-dump -w "$FIX" 2>/dev/null |
    python3 "$ROOT/tools/sweep_ptr_order.py" > "$OUT"

fail=0

want() {
    if grep -q ":$1	$2	" "$OUT"; then
        echo "  ok    line $1: the $3 is reported"
    else
        echo "  FAIL  line $1: the $3 was NOT reported"
        fail=1
    fi
}

reject() {
    if grep -q ":$1	" "$OUT"; then
        echo "  FAIL  line $1: the $2 was reported, and must not be"
        fail=1
    else
        echo "  ok    line $1: the $2 is ignored"
    fi
}

want   2 -  "subtraction of two pointers"
want   3 '<'  "less-than of two pointers"
want   4 '>=' "greater-or-equal of two pointers"
reject 5 "equality of two pointers"
reject 6 "less-than of two ints"

# --stored asks the other question: which pointers to objects are kept
# somewhere that outlives the object. The ordering sweep above could not have
# found the Falling defect in src/Move.cpp, because that comparison was an
# equality, which it ignores on purpose. This mode is what covers it.
echo
cat > "$FIX" <<'EOF'
struct Creature { int x; };
Creature *Falling = 0;
static Creature *Cache = 0;
char *Buffer = 0;
int Count = 0;
void f(Creature *local) {
  Creature *tmp = local;
  static Creature *sticky = 0;
  sticky = tmp;
}
EOF

clang++ -std=c++17 -fsyntax-only -Xclang -ast-dump -w "$FIX" 2>/dev/null |
    python3 "$ROOT/tools/sweep_ptr_order.py" --stored > "$OUT"

want   2 global "global pointer to an object"
want   3 static "file-scope static pointer to an object"
want   8 static "static pointer inside a function"
reject 4 "global char buffer, which is bytes and not an identity"
reject 5 "global int, which is not a pointer at all"
reject 7 "plain local, which cannot outlive anything"

echo
if [ "$fail" -ne 0 ]; then
    echo "FAIL: the sweep does not report what it claims to report."
    echo "      Its output for the fixture was:"
    sed 's/^/        /' "$OUT"
    exit 1
fi

echo "PASS: the sweep reports an ordering of two pointers and ignores an equality"
echo "      test and an ordering of two integers; and --stored reports a global, a"
echo "      file-scope static and a static inside a function, while ignoring a char"
echo "      buffer, a non-pointer and a plain local"
