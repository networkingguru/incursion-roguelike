#!/bin/bash
# gate: cheap
# inc-ep4y. The order guard after the module compile must read the module with
# the binary that just wrote it, not a stray incursion-headless. build_macos.sh
# compiles the module in an unbuilt tree with the freshly built "$ROOT/$OUT",
# so order_guard.sh must be handed that binary via INCURSION_ORDER_BIN.
#
# This has two cases, neither needing a build:
#   A  resource_order_check.py must read INCURSION_ORDER_BIN and still fail
#      closed: with the env pointing at a nonexistent binary it exits 2 and its
#      output names that binary. On the old code it names incursion-headless
#      (or exits 0 when that binary happens to exist).
#   B  build_macos.sh's order_guard call must carry
#      INCURSION_ORDER_BIN="$ROOT/$OUT".
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
fail=0

# Case A: the env names a binary that is not there; the check must look for it.
out="$(INCURSION_ORDER_BIN=/nonexistent/incursion-x python3 \
    tools/resource_order_check.py 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && grep -q "incursion-x" <<< "$out"; then
    echo "case A: PASS -- env read, exit 2, message names incursion-x"
else
    echo "case A: FAIL -- exit $rc, output does not name incursion-x: $out"
    fail=1
fi

# Case B: the build must pass the binary it just built to the guard.
if grep -q 'INCURSION_ORDER_BIN="\$ROOT/\$OUT" "\$ROOT/tools/order_guard.sh"' \
        build_macos.sh; then
    echo "case B: PASS -- build_macos.sh guards with INCURSION_ORDER_BIN=\"\$ROOT/\$OUT\""
else
    echo "case B: FAIL -- build_macos.sh's order_guard call lacks INCURSION_ORDER_BIN=\"\$ROOT/\$OUT\""
    fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
