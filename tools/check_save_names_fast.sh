#!/bin/bash
# gate: none static; runs tools/check_save_names.py --fast, which reads C/C++ source text only; needs no build and no game run
# gate-fast: save-name checks 1-3 and 5 need no master snapshot, so a merge commit gets them too
# fact: field names, scope, retired names, migration names, revision owner -- the same facts as tools/check_save_names.py, read by its --fast mode
# fact: the base tree -- not read: --fast skips check 4, the only check that needs master's snapshot
# Fast-set entry point: fast_checks.sh passes no argument, so this wrapper adds --fast.
exec python3 "$(dirname "$0")/check_save_names.py" --fast "$@"
