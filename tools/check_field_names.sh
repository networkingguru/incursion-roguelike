#!/bin/bash
# gate: none heavy; needs a posix DEBUG build (BACKEND=posix ./build_macos.sh); run by hand (inc-cjos0 phase 2)
# fact: save content -- the files `incursion-headless -schematest` writes (a fixed set of populated objects built in code, INCURSION_V1_RAW=1 so the records are readable); no seed, no key script, no options file, no module data enters
# fact: planted duplicate name -- INCURSION_NAMES_PLANT=dup, a DEBUG-build hook in src/SaveV1.cpp that makes the writer register its third name of a group twice through the real per-frame check (v1WSeenCheck); same on every run
# fact: planted unknown name -- this script flips the first letter of the first row of the file's own name table, in a scratch copy; the file is the schematest file above
# fact: retired name -- INCURSION_RETIRED_EXTRA=<scope>:<name>, a DEBUG-build hook in src/SaveV1.cpp that retires one more name for one run; the engine's real list is inc/SaveRetiredNames.h
# fact: retired list copies -- tools/retired_field_names.txt and inc/SaveRetiredNames.h, read as text
# fact: save revision -- the build under test (SCHEMA_REV in src/SaveV1.cpp)
#
# The three refusals of spec 5.3 of docs/superpowers/specs/2026-11-07-names-in-the-file-design.md:
#   1. the writer refuses one name written twice in one frame;
#   2. the reader refuses a name in a file that no field list asks for;
#   3. the reader ignores a name on the retired list;
# and that tools/retired_field_names.txt and inc/SaveRetiredNames.h list the same names.
#
# Usage: tools/check_field_names.sh              (exit 0 pass, 1 fail)
#        tools/check_field_names.sh --selftest   (proves each assertion goes red on a wrong input)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN=./incursion-headless
MODE=check
[ "${1:-}" = "--selftest" ] && MODE=selftest
[ -x "$BIN" ] || { echo "FAIL: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/incursion-fieldnames.XXXXXX")"
trap 'rm -rf "$W"' EXIT

# Write the schematest files into $1 (raw payload, so the records are readable).
make_files() { # <dir> [plant]
    mkdir -p "$1"
    INCURSION_NAMES_PLANT="${2:-}" INCURSION_V1_RAW=1 "$BIN" -schematest "$1" -timeout 120 \
        < /dev/null > "$1/schematest.log" 2> "$1/schematest.err"
}

# Flip the first letter of the first row of the file's name table.
# prints the new name, "scope:name" form, on stdout.
craft_unknown() { # <in.sav> <out.sav>
    python3 - "$1" "$2" <<'PY'
import struct, sys
d = bytearray(open(sys.argv[1], "rb").read())
comp, = struct.unpack_from("<h", d, 90)
gsize, csize, objc = struct.unpack_from("<iii", d, 104)
if comp != 0:
    sys.exit("not a raw save")
pos = 124
for _ in range(objc):
    typ = d[pos]
    reclen, = struct.unpack_from("<I", d, pos + 5)
    body = pos + 9
    pos = body + reclen
    if typ == 200:
        sl, = struct.unpack_from("<H", d, body + 2)
        nl, = struct.unpack_from("<H", d, body + 4 + sl)
        scope = bytes(d[body + 4:body + 4 + sl]).decode()
        at = body + 6 + sl
        name = bytes(d[at:at + nl]).decode()
        d[at] = ord("Z") if name[0] != "Z" else ord("Y")
        open(sys.argv[2], "wb").write(d)
        print("%s:%s" % (scope, bytes(d[at:at + nl]).decode()))
        sys.exit(0)
sys.exit("no name table record in the file")
PY
}

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
ok() { echo "ok: $1"; }

# 1. The writer refuses a duplicate.   args: planted?  -> returns 0 when the writer refused
writer_refuses() { # <dir> <plant|"">
    make_files "$1" "$2"; local rc=$?
    [ "$rc" != 0 ] && grep -q "is written twice in one frame" "$1/schematest.err"
}

# 2. The reader refuses an unknown name.   -> 0 when it refused
reader_refuses() { # <file> <extra-retired|"">
    INCURSION_RETIRED_EXTRA="${2:-}" "$BIN" -schemaload "$1" -timeout 60 < /dev/null > "$W/load.out" 2> "$W/load.err"
    local rc=$?
    [ "$rc" != 0 ] && grep -q "which is not one this binary reads" "$W/load.err"
}

# 3. The reader loads the file.   -> 0 when it loaded
reader_loads() { # <file> <extra-retired|"">
    INCURSION_RETIRED_EXTRA="${2:-}" "$BIN" -schemaload "$1" -timeout 60 < /dev/null > "$W/load.out" 2> "$W/load.err"
}

# 4. The two lists are the same.   -> 0 when equal
lists_agree() { # <txt> <header>
    python3 - "$1" "$2" <<'PY'
import re, sys
txt = set()
ren = set()
for ln in open(sys.argv[1]):
    ln = ln.split("#", 1)[0].split()
    if len(ln) == 2:
        txt.add(tuple(ln))
    elif len(ln) == 4 and ln[0] == "rename":
        ren.add(tuple(ln[1:]))
    elif ln:
        sys.exit("bad line in %s: %s" % (sys.argv[1], " ".join(ln)))
h = open(sys.argv[2]).read()
def block(name):
    m = re.search(name + r"\[\] = \{(.*?)\n\};", h, re.S)
    return m.group(1) if m else ""
hret = set(re.findall(r'\{ "([^"]+)", "([^"]+)" \}', block("RETIRED_FIELD_NAMES")))
hren = set(re.findall(r'\{ "([^"]+)", "([^"]+)", "([^"]+)" \}', block("RENAMED_FIELD_NAMES")))
if txt != hret or ren != hren:
    sys.exit("retired lists differ: txt %s %s, header %s %s" % (sorted(txt), sorted(ren), sorted(hret), sorted(hren)))
PY
}

if [ "$MODE" = check ]; then
    make_files "$W/good" "" || { cat "$W/good/schematest.err"; fail "-schematest without a plant did not run clean"; }
    writer_refuses "$W/plant" dup && ok "the writer refuses a name written twice in one frame" \
        || fail "the writer did not refuse a planted duplicate name"
    SAV="$W/good/e.sav"
    reader_loads "$SAV" "" && ok "an unplanted revision 7 file loads" || fail "the clean file was refused: $(tail -1 "$W/load.err")"
    NEW="$(craft_unknown "$SAV" "$W/unknown.sav")" || fail "could not craft the unknown-name file"
    reader_refuses "$W/unknown.sav" "" && ok "the reader refuses an unknown name ($NEW)" \
        || fail "the reader did not refuse the unknown name $NEW"
    reader_loads "$W/unknown.sav" "$NEW" && ok "the reader ignores the retired name $NEW" \
        || fail "the reader refused the retired name $NEW: $(tail -1 "$W/load.err")"
    lists_agree tools/retired_field_names.txt inc/SaveRetiredNames.h && ok "tools/retired_field_names.txt and inc/SaveRetiredNames.h agree" \
        || fail "the two retired lists differ"
    [ "$FAILED" = 0 ] && echo "PASS" || echo "FAILED"
    exit "$FAILED"
fi

# --selftest: each assertion must go red on an input that does not satisfy it.
ST=0
red() { # <label> <command...>   the command must FAIL
    local label="$1"; shift
    if "$@"; then echo "SELFTEST FAIL: $label did not go red"; ST=1; else echo "ok: $label goes red"; fi
}
make_files "$W/good" "" || { echo "SELFTEST FAIL: schematest"; exit 1; }
red "writer_refuses with no plant" writer_refuses "$W/noplant" ""
SAV="$W/good/e.sav"
NEW="$(craft_unknown "$SAV" "$W/unknown.sav")"
red "reader_refuses on the clean file" reader_refuses "$SAV" ""
red "reader_refuses when the name is retired" reader_refuses "$W/unknown.sav" "$NEW"
red "reader_loads on the unknown name" reader_loads "$W/unknown.sav" ""
sed 's/^Character SpellsU16$/Character SpellsU16x/' tools/retired_field_names.txt > "$W/wrong.txt"
red "lists_agree on a changed txt" lists_agree "$W/wrong.txt" inc/SaveRetiredNames.h
[ "$ST" = 0 ] && echo "SELFTEST PASS" || echo "SELFTEST FAILED"
exit "$ST"
