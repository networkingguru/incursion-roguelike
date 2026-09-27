#!/bin/bash
# gate: live
# The build-time order check (docs/SAVE-SCHEMA-SPEC.md, "The build-time order
# check", test-plan case 26, amended 2026-09-26). It reads the compiled module
# and the committed ledger and fails when the module's list is shorter than the
# ledger's (a removal), or when a name the ledger records at position P appears
# in the module at a position other than P (an insertion, a removal or a
# reorder); a repeated ledger name is exempt from that test. A name the ledger
# records and the module lacks is a rename or replacement and passes. It needs
# a built module, so it is a live gate check.
#
# Usage:
#   tools/check_resource_order.sh                 check, exit 0/1 (2 unbuilt)
#   tools/check_resource_order.sh --record        re-record after a legal append
#                                                 or an in-place rename
#   tools/check_resource_order.sh --selftest      prove the check bites, no build
#
# tools/check_resource_order_mutations.sh is the committed reproduction: six
# illegal edits, each proved red and refused by --record, plus two legal appends
# and two legal in-place renames proved green and accepted by --record.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/resource_order_check.py "$@"
