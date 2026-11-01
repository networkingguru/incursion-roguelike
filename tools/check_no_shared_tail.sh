#!/bin/bash
# gate: live
# It builds a scratch clone with the posix backend and merges two branches in it; it runs when the bead changes this file, and in the nightly.
# Do two branches that each add one effect merge with no conflict, and do both
# effects land after every position the base ledger records?
#
# Authority: docs/superpowers/specs/2026-10-31-no-shared-tail-design.md, 4.1,
# 4.2 and 8 (AC1); plan phase 5 (bead inc-mhn1w).
#
# GREEN. In a scratch clone of this tree's HEAD (under logs/), branch inc-testa
# adds one effect in lib/landed-inc-testa.irh plus its include line in
# lib/landed.irc; branch inc-testb does the same with another effect. Both merge
# into the base branch. The check then requires: both merges finish with no
# conflict; lib/landed.irc holds both include lines; the module built in the
# clone holds both effects at positions past the last Effect position in the
# base ledger (tools/resource_order.ledger); tools/check_resource_order.sh
# passes on the clone.
#
# RED (--prove-red). The same two branches append their effects to
# lib/mundane.irh instead. The second merge MUST conflict (no build). The
# check then exits 1. A red that does not conflict exits 2: the check cannot
# prove the old layout was a problem.
#
# Usage:
#   tools/check_no_shared_tail.sh               green scenario
#   tools/check_no_shared_tail.sh --prove-red   red scenario
#   --keep                                      keep the clone under logs/
#
# Exit 0 green; 1 the property fails (or, with --prove-red, the expected red);
# 2 cannot establish (no clone, no build, a merge that failed another way).
# Reads HEAD, not the working tree: commit a change to a driver or to
# lib/landed.irc before running.
#
# fact: git merge outcome -- no random input; the scratch clone's own two branches, merged by the driver in tools/merge_landed.py
# fact: the built module's effect positions -- the module compiled by BACKEND=posix ./build_macos.sh in the clone; the compiler is deterministic and no game is played
# fact: the base ledger's last Effect position -- tools/resource_order.ledger at HEAD, read from the clone
# fact: character, world, rolls, text matched -- none read; no game is run, so no seed is involved
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEEP=0
RED=0
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        --prove-red) RED=1 ;;
        *) echo "usage: $0 [--prove-red] [--keep]" >&2; exit 2 ;;
    esac
done

mkdir -p "$ROOT/logs" || exit 2
WORK="$(mktemp -d "$ROOT/logs/no-shared-tail.XXXXXX")" || { echo "UNMEASURED: cannot make a scratch directory" >&2; exit 2; }
case "$WORK" in "$ROOT"/logs/no-shared-tail.?*) ;; *) echo "UNMEASURED: odd scratch path $WORK" >&2; exit 2 ;; esac
cleanup() {
    if [ "$KEEP" = 1 ]; then
        echo "kept: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

CL="$WORK/repo"
unmeasured() { echo "UNMEASURED: $*" >&2; exit 2; }
g() { git -C "$CL" "$@"; }

git clone -q --no-hardlinks "$ROOT" "$CL" 2>"$WORK/clone.err" \
    || { cat "$WORK/clone.err" >&2; unmeasured "clone of $ROOT failed"; }
g config user.name "no-shared-tail" || unmeasured "git config failed"
g config user.email "no-shared-tail@example.invalid"
g config commit.gpgsign false
g config core.hooksPath /dev/null
# The driver config is the one tools/worktree.sh sets.
g config merge.landed.name "lib/landed.irc include order (tools/merge_landed.py)"
g config merge.landed.driver "python3 tools/merge_landed.py landed %O %A %B"
g config merge.landed-ledger.name "tools/resource_order.ledger is master's (tools/merge_landed.py)"
g config merge.landed-ledger.driver "python3 tools/merge_landed.py landed-ledger %O %A %B"
g checkout -q -B master || unmeasured "cannot make the master branch"

effect_text() {
    printf 'Effect "%s" : EA_GENERIC\n  {\n    aval: AR_TOUCH;\n  }\n' "$1"
}

# add_branch <bead> <effect name>
add_branch() {
    local bead="$1" name="$2"
    g checkout -q master && g checkout -q -b "$bead" || unmeasured "cannot branch $bead"
    if [ "$RED" = 1 ]; then
        { printf '\n'; effect_text "$name"; } >> "$CL/lib/mundane.irh"
    else
        effect_text "$name" > "$CL/lib/landed-$bead.irh"
        printf '#include "landed-%s.irh"\n' "$bead" >> "$CL/lib/landed.irc"
    fi
    g add -A && g commit -q -m "add $name" || unmeasured "cannot commit $bead"
    g checkout -q master
}

add_branch inc-testa "nst test effect alpha"
add_branch inc-testb "nst test effect beta"

g merge -q --no-ff -m "merge inc-testa" inc-testa >"$WORK/merge-a.out" 2>&1 \
    || { cat "$WORK/merge-a.out" >&2; unmeasured "the first merge failed; the scenario cannot start"; }

if g merge -q --no-ff -m "merge inc-testb" inc-testb >"$WORK/merge-b.out" 2>&1; then
    B_CLEAN=1
else
    B_CLEAN=0
fi

if [ "$RED" = 1 ]; then
    if [ "$B_CLEAN" = 1 ]; then
        unmeasured "red scenario: the second merge did not conflict; the old layout is not shown to fail"
    fi
    if ! grep -qx 'lib/mundane.irh' <<< "$(g diff --name-only --diff-filter=U)"; then
        cat "$WORK/merge-b.out" >&2
        unmeasured "red scenario: the second merge failed, but not as a conflict in lib/mundane.irh"
    fi
    echo "RED (expected): the second merge conflicts in lib/mundane.irh when both effects are appended there"
    exit 1
fi

if [ "$B_CLEAN" != 1 ]; then
    cat "$WORK/merge-b.out" >&2
    echo "FAIL: the second merge conflicted; two landed files must merge with no conflict"
    exit 1
fi

for n in a b; do
    if ! grep -qx "#include \"landed-inc-test$n.irh\"" "$CL/lib/landed.irc"; then
        echo "FAIL: lib/landed.irc lacks the include line for inc-test$n"
        exit 1
    fi
done

( cd "$CL" && env -u INCURSION_RECORD_LEDGER BACKEND=posix OUT=incursion-ntail EXTRA_CXXFLAGS=-DNO_SHARED_TAIL_CLONE ./build_macos.sh ) >"$WORK/build.log" 2>&1 \
    || { tail -n 25 "$WORK/build.log" >&2; unmeasured "build in the clone failed (log kept only with --keep)"; }
[ -x "$CL/incursion-ntail" ] && [ -f "$CL/mod/Incursion.Mod" ] \
    || unmeasured "the build left no incursion-ntail or no mod/Incursion.Mod"

if [ -n "$(g diff --name-only -- tools/resource_order.ledger)" ]; then
    echo "FAIL: the build rewrote tools/resource_order.ledger; only finish_bead.sh may record it"
    exit 1
fi

( cd "$CL" && ./incursion-ntail -resorder ) >"$WORK/module.txt" 2>"$WORK/module.err" \
    || { cat "$WORK/module.err" >&2; unmeasured "incursion-ntail -resorder failed"; }

python3 - "$WORK/module.txt" "$CL/tools/resource_order.ledger" <<'PY'
import sys

def effects(path):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "E" and len(f) == 5 and f[1] == "0" and f[2] == "3":
            out.append(f[4])
    return out

mod, led = effects(sys.argv[1]), effects(sys.argv[2])
if not led or not mod:
    print("UNMEASURED: no Effect records in the module dump or the ledger", file=sys.stderr)
    sys.exit(2)
last = len(led) - 1
bad = 0
for name in ("nst test effect alpha", "nst test effect beta"):
    pos = [i for i, n in enumerate(mod) if n == name]
    if len(pos) != 1:
        print("FAIL: effect %r appears %d times in the module" % (name, len(pos)))
        bad = 1
    elif pos[0] <= last:
        print("FAIL: effect %r at position %d; the base ledger runs to %d" % (name, pos[0], last))
        bad = 1
    else:
        print("ok: effect %r at position %d, past the base ledger's last (%d)" % (name, pos[0], last))
sys.exit(bad)
PY
rc=$?
[ "$rc" = 2 ] && exit 2
[ "$rc" = 0 ] || exit 1

( cd "$CL" && INCURSION_ORDER_BIN="$CL/incursion-ntail" tools/check_resource_order.sh ) >"$WORK/order.out" 2>&1
rc=$?
tail -n 3 "$WORK/order.out"
if [ "$rc" = 2 ]; then unmeasured "check_resource_order.sh could not establish"; fi
if [ "$rc" != 0 ]; then echo "FAIL: tools/check_resource_order.sh exited $rc on the merged clone"; exit 1; fi

echo "PASS: two landed files merged with no conflict; both effects follow every base position; the order check is green"
exit 0
