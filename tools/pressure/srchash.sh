#!/bin/bash
# The hash of every input of the C++ compile of a tree: src/, inc/, compat/, build_macos.sh, lib/dispatch.h (included
# by src/VMachine.cpp) and the two generators build_macos.sh runs. Two trees with one hash build the same binary
# (inc-cjos0 phase 8, D5); lib/*.irh and the rest are the module, which tools/pressure/oracle.sh recompiles.
#
#   tools/pressure/srchash.sh <tree>      prints the hash; exit 2 when it cannot
#
# fact: the tree's files -- read from <tree> as they are on disk; no seed, no options file, no clock
set -uo pipefail
[ $# -eq 1 ] && [ -d "$1/src" ] || { echo "usage: $0 <tree>" >&2; exit 2; }
cd "$1" || exit 2
git ls-files -co --exclude-standard -z -- src inc compat build_macos.sh lib/dispatch.h \
    tools/gen_record_layout.py tools/gen_family_names.py > "${TMPDIR:-/tmp}/srchash.$$" || exit 2
h="$(xargs -0 shasum < "${TMPDIR:-/tmp}/srchash.$$" | shasum | cut -c1-16)"
rc=$?; rm -f "${TMPDIR:-/tmp}/srchash.$$"
[ -n "$h" ] || exit 2
echo "$h"
