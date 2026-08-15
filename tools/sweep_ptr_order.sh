#!/bin/bash
# Where does this codebase put two pointers in order?
#
# Usage: tools/sweep_ptr_order.sh            # every file in src/
#        tools/sweep_ptr_order.sh src/Target.cpp src/MakeLev.cpp
#
# inc-dhc is a class of defect, not one bug: the engine compares two addresses
# and lets the answer change a decision, and the allocator puts objects
# somewhere different on every launch. TargetSort was one site. Finding the
# next one by running a seed twenty times and hoping it splits costs about an
# hour. This lists every candidate in the codebase in a few seconds.
#
# It asks clang for the parse tree, because the question cannot be asked with
# grep. `a - b` is a subtraction of addresses or of two numbers depending on
# what a and b were declared to be, and only the compiler knows. clang-query
# and clang-tidy are not installed on this machine; `clang -Xclang -ast-dump`
# ships with the command line tools, and every operator in it carries the types
# of its operands.
#
# READ THE HEADER OF tools/sweep_ptr_order.py BEFORE ACTING ON THE OUTPUT. Two
# limits matter. Ordering two pointers into ONE array is legal and repeatable,
# and looks identical here, so every hit needs a person to say which kind it
# is. And a table walked in allocation order reads an address without ever
# comparing one, so a clean sweep does not mean the class is closed --
# tools/check_layout.sh is what says that.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The same flags build_macos.sh compiles the headless build with. They have to
# match: a different -D changes which code the parser even sees.
INCLUDES="-Iinc -Ilib -Icompat"
DEFINES="-DDEBUG -DPOSIX_TERM"

# --stored asks the other question. Instead of "where are two pointers put in
# order", it asks "where is a pointer to an object kept somewhere that outlives
# the object" -- a global or a static. That is the shape of the Falling defect
# in src/Move.cpp: the comparison there was an EQUALITY, which the ordering
# sweep ignores on purpose, and the fault was that one side had been dead for a
# while. Storage is what makes that possible, so storage is what this lists.
MODE=""
WHAT="pointer orderings"
if [ "${1:-}" = "--stored" ]; then
    MODE="--stored"
    WHAT="stored pointers to objects"
    shift
fi

if [ "$#" -gt 0 ]; then
    FILES="$*"
else
    FILES="$(ls src/*.cpp)"
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

for f in $FILES; do
    n="$(basename "$f" .cpp)"
    # Only one terminal backend compiles at a time, and the other two do not
    # parse without their own libraries.
    case "$n" in Wlibtcod|Wcurses) continue ;; esac
    # src/Tokens.cpp and src/Art.cpp are flex and ACCENT output and use the
    # `register` keyword, which C++17 removed.
    std="c++17"
    case "$n" in Tokens|Art) std="c++14" ;; esac
    # No filter argument, so the sweep keeps everything that is not a system
    # header. The paths clang prints are the ones it was given, and those are
    # relative to here, so filtering on an absolute path finds nothing at all.
    clang++ -std=$std -fsyntax-only -Xclang -ast-dump -w -fpermissive \
        $DEFINES $INCLUDES "$f" 2>/dev/null |
        python3 "$ROOT/tools/sweep_ptr_order.py" $MODE >> "$OUT"
done

# One header line is parsed once per file that includes it, so the same site
# arrives many times over.
sort -u "$OUT" | sed "s|^$ROOT/||" > "$OUT.u"

COUNT="$(wc -l < "$OUT.u" | tr -d ' ')"
echo "--- $WHAT in src/ and inc/: $COUNT ---"
echo
if [ "$COUNT" -eq 0 ]; then
    echo "  none. That does NOT mean the class is closed -- see the header."
    exit 0
fi

printf '%s\n' "  file:line, kind, type"
echo
sed 's/^/  /' "$OUT.u"

echo
echo "--- by type, since one type is one decision to make ---"
echo
cut -f3 "$OUT.u" | sort | uniq -c | sort -rn | sed 's/^/  /'

echo
if [ -n "$MODE" ]; then
  echo "Triage: a stored pointer is a defect only if the object can die while the"
  echo "pointer still points at it. Ask what clears it, and on which paths. If the"
  echo "answer is \"one path\", the other paths leak -- that was Falling in Move.cpp."
else
  echo "Triage: an ordering INSIDE one array is fine. An ordering of two objects"
  echo "the allocator placed separately is the defect. The types above say which"
  echo "is which faster than the line numbers do."
fi
