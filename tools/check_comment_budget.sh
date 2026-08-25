#!/usr/bin/env bash
#
# Is any comment block or _PROBE block in src/ or inc/ over the 30-line ceiling,
# and is it one this change made?
#
#   tools/check_comment_budget.sh              compare against the baseline
#   tools/check_comment_budget.sh --record     re-freeze the baseline
#   tools/check_comment_budget.sh --selftest   prove this script still bites
#
# THE RULE is in AGENTS.md, "The comment budget". A comment at a fix site states
# the invariant, the tier, the id and the sent status. The reproduction and the
# argument go in the bead.
#
# WHY. tools/check_doc_freshness.sh records the cost: a 102-line probe block at
# the top of src/Event.cpp moved 92 of that page's 131 line citations, and
# nothing noticed for days. Bulk in a source file breaks every citation below it.
#
# A RATCHET, NOT A SWEEP. On 2026-08-25 src/ and inc/ held 41 _PROBE blocks over
# 1,238 lines, plus long-form upstream: markers. Cutting them is judgement work,
# one bead at a time. This check fails on a block that is NEW over the ceiling,
# or one that GREW past what the baseline recorded. It stays quiet about the rest.
#
# Exit: 0 nothing new is over the ceiling
#       1 a block is new over it, or grew past its recorded size
#       2 could not measure

exec python3 "$(dirname "$0")/comment_budget.py" "$@"
