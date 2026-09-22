#!/bin/bash
# gate: cheap
#
# Structural check for inc-30ps Phase 5, "the effect declarations": asserts
# the EF_ATTACK flag and the save (sval) field of all 15 bolt/ray effects
# that gained an attack roll, plus the negative cases the brief names --
# Call Companions must gain neither EF_ATTACK nor a changed aval, and Magic
# Missile, Force Missiles and Acid;wand must still carry no EF_ATTACK.
#
# See "Phase 5 -- the effect declarations" in
# docs/specs/2026-09-21-line-of-fire-spec.md and the file:line list in
# docs/specs/2026-09-21-line-of-fire-brief-phase56.md.
#
# Pure text over lib/*.irh -- no build needed. tools/line_of_fire_effects.py
# does the work; this is the gate-shaped wrapper.
#
# Usage: tools/check_line_of_fire_effects.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec python3 tools/line_of_fire_effects.py
