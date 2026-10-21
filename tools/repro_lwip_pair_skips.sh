#!/bin/sh
# Reproduction for the two silent-skip defects in tools/fidelity/build_pairs.py:
#   1. bd global flags between `bd` and `update` were not matched.
#   2. a single --append-notes carrying several rulings yielded one pair and
#      lost the text after the first shell-splice apostrophe ('"'"').
#
# Run from the repo root:  sh tools/repro_lwip_pair_skips.sh
set -eu
python3 -I - <<'PY'
import sys
sys.path.insert(0, "tools/fidelity")
import build_pairs as b

bead = "inc-pu6v.9"
rx = b.bead_update_re(bead)

print("defect 1: global flags between bd and update")
for cmd in [
    "bd -q update inc-pu6v.9 --append-notes 'R1 x'",
    "bd --quiet --db /some/db update inc-pu6v.9 --append-notes 'R1 x'",
    "bd -C /some/path update inc-pu6v.9 --append-notes 'R1 x'",
]:
    assert rx.search(cmd), "not matched: %r" % cmd
    print("  matched:", cmd)

print("boundary: inc-pu6v.91 must NOT match bead inc-pu6v.9")
assert not rx.search("bd update inc-pu6v.91 --append-notes 'R1 x'")
print("  ok")

print("defect 2: one write carrying two rulings with shell-splice apostrophes")
splice = "'\"'\"'"
cmd = ("bd update inc-pu6v.9 --append-notes "
       "'R40 (Brian" + splice + "s words: \"forty\"): first ruling"
       "\nR41 (Brian" + splice + "s words: \"forty one\"): second ruling'")
text, ok, src = b.extract_notes(cmd)
assert ok and src == "command", (ok, src)
assert "first ruling" in text and "second ruling" in text, "text truncated: %r" % text
parts = b.split_ruling_parts(text)
assert len(parts) == 2, "expected 2 parts, got %r" % parts
assert b._extract_rulings(parts[0]) == [40], parts[0]
assert b._extract_rulings(parts[1]) == [41], parts[1]
print("  two parts, numbers [40] and [41]")
print("REPRO OK")
PY
