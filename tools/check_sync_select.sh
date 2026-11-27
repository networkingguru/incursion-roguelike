#!/bin/bash
# gate: cheap
# Check tools/sync_select.py: it picks only the beads whose issue is missing or
# differs in title or trimmed body, never a mirrored bead, never on labels alone.
# fact: the game, a seed, a character -- none read; the check feeds sync_select.py its own synthetic JSON written to a temp dir
# fact: bead database and GitHub issues -- none read; both files are synthetic
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
R=o/r
cat > "$tmp/beads.json" <<JSON
[
 {"id":"same","title":"T","description":"body","issue_type":"bug","priority":1,"external_ref":"https://github.com/$R/issues/1","labels":["public"]},
 {"id":"title","title":"T2","description":"body","issue_type":"bug","priority":1,"external_ref":"https://github.com/$R/issues/1","labels":["public"]},
 {"id":"body","title":"T","description":"body2","external_ref":"https://github.com/$R/issues/1","labels":["public"]},
 {"id":"noref","title":"T","description":"body","labels":["public"]},
 {"id":"otherrepo","title":"T","description":"body","external_ref":"https://github.com/x/y/issues/1","labels":["public"]},
 {"id":"missing","title":"T","description":"body","external_ref":"https://github.com/$R/issues/99","labels":["public"]},
 {"id":"mirror","title":"changed","description":"changed","external_ref":"https://github.com/$R/issues/1","labels":["mirrored"]},
 {"id":"mirrornoref","title":"x","labels":["mirrored"]},
 {"id":"labels","title":"T","description":"body","external_ref":"https://github.com/$R/issues/1","issue_type":"bug","priority":1,"labels":["public","upstream","extra"]},
 {"id":"prio","title":"T","description":"body","issue_type":"bug","priority":2,"external_ref":"https://github.com/$R/issues/1","labels":["public"]},
 {"id":"type","title":"T","description":"body","issue_type":"task","priority":1,"external_ref":"https://github.com/$R/issues/1","labels":["public"]}
]
JSON
cat > "$tmp/issues.json" <<'JSON'
[{"number":1,"title":"T","body":"body\n\n","state":"OPEN","labels":[{"name":"type::bug"},{"name":"priority::high"},{"name":"plain"}]}]
JSON
fail=0
check() { # name, expected, actual
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: want '$2' got '$3'"; fail=1; fi
}
full=$(python3 "$root/tools/sync_select.py" "$tmp/beads.json" "$tmp/issues.json" $R)
new=$(python3 "$root/tools/sync_select.py" "$tmp/beads.json" "$tmp/issues.json" $R --new-only)
has() { case ",$1," in *",$2,"*) echo yes;; *) echo no;; esac; }
check "matching text, trailing newline: not selected" no "$(has "$full" same)"
check "changed title: selected" yes "$(has "$full" title)"
check "changed body: selected" yes "$(has "$full" body)"
check "no external_ref: selected" yes "$(has "$full" noref)"
check "ref to another repo: selected" yes "$(has "$full" otherrepo)"
check "ref to number not in listing: selected" yes "$(has "$full" missing)"
check "mirrored with changed text: not selected" no "$(has "$full" mirror)"
check "mirrored with no ref: not selected" no "$(has "$full" mirrornoref)"
check "labels differ, text matches: not selected" no "$(has "$full" labels)"
check "priority label differs: selected" yes "$(has "$full" prio)"
check "type label differs: selected" yes "$(has "$full" type)"
check "--new-only selects only the no-ref bead" noref "$new"
exit $fail
