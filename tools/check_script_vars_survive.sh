#!/bin/bash
# gate: live
# inc-glnx revision-4 sandbox-module persistence oracle.
# fact: base character -- Point Buy attributes, race/class/alignment named by @choose (tools/keys/script-vars-base.keys)
# fact: base save written with no turns passed -- the base script quits on arrival
# fact: case 30 character -- the base save is copied in and restored, not generated
# fact: no monster acts in case 30 -- wizard "Genocide Everything"
# fact: Command cast succeeds -- wizard switch "Ignore Spell Failure" YES
# fact: Command's Will save resists -- INCURSION_FORCE_SAVE_ROLL=20 (case 30 session only)
# fact: case 31 rename row -- INCURSION_RENAMED_EXTRA, a DEBUG-build hook in src/SaveV1.cpp that adds one Game.ScriptVariable rename row for the -dump run; no seed
# fact: module edits -- the check's own sandbox edits in tools/script_vars_survive.py
# fact: the rat is present beside the player -- Monster Summoning onto the square made floor by Change terrain type
# fact: the rat cannot act -- wizard switch "Freeze Monsters" YES
# Note: INCURSION_SVS_SEED overrides the run seed, to prove seed independence.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/script_vars_survive.py "$@"
