#!/bin/bash
# gate: cheap
#
# Does every SchemaPad array in src/SaveV1.cpp still match what the
# compiler actually lays out (tools/save_pad_rows.py), rather than what
# was hand-measured last time a member moved?
#
#   tools/check_save_pad_rows.sh              compare against src/SaveV1.cpp
#   tools/check_save_pad_rows.sh --selftest   prove this script still bites
#
# WHY: inc-30ps moved two archived members (ShadowRange, NatureSight) into
# what CreaturePads used to call padding, without growing sizeof(Creature)
# -- the one case a build alone cannot catch. See tools/save_pad_rows.py's
# own module docstring for the full mechanism.
#
# Exit: 0 every array agrees; 1 a mismatch (printed, class/declared/measured);
#       2 could not measure (clang missing, a class absent from the dump).
set -uo pipefail
# -B: save_pad_rows_check.py imports save_pad_rows.py as a module, which
# would otherwise leave tools/__pycache__/ behind on every run and dirty
# the tree on every gate pass.
exec python3 -B "$(dirname "$0")/save_pad_rows_check.py" "$@"
