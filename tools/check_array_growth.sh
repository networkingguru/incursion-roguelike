#!/bin/bash
# gate: none heavy; builds scratch trees with larger limits (a few minutes); run by hand (inc-cjos0 phase 7f)
# fact: save content -- the file `incursion-headless -schematest` writes (a fixed set of populated objects built in code); no seed, no key script, no options file, no module data enters
# fact: the larger limits -- this script raises EVERY limit that a family mark of inc/Defines.h calls `grows` (read from the marks, 19 names today, MA_COUNT and SK_COUNT through the limits they are made of) by 3 (MAX_SAC_CATS by 2) in a scratch copy of the tree under test and drops that copy's struct-size pins and the SkillInfo row-count pin (the pins only say the layout or the table did not grow)
# fact: the dumped arrays -- both scratch trees (the reference and the grown one) get the same extra printf lines for the arrays of the limits in the -schemaload Player, Game and Map dump; the table of arrays (label, limits, printf line) is the AGTABLE heredoc below; the tree under test is not edited
# fact: the Game and Map record -- the file `incursion-headless -schematest` writes as game.sav (theGame with its MDataSeg slot 0, three dungeons and a Map with its overlay glyphs, all built in code with nonzero values); no seed, no key script, no options file
# fact: the arrays the file leaves empty -- the reference tree's dump must hold at least one nonzero entry of every array of the table, else the check exits 2 (UNMEASURED) naming the array
# fact: the limit-to-array tie -- every limit a family mark calls `grows` must name an array of the table or an entry of the allow list (AGTABLE heredoc, with its reason), else the check exits 2 naming the limit
# fact: the saved values the larger build must find -- read from the tree under test loading its own file (the same dump lines), then moved by the rule of spec 6.1 (a row keeps its columns; the last two SacVals columns stay last)
# fact: the build flags -- BACKEND=posix, EXTRA_CXXFLAGS=-O0 for speed; the same source and defines in every scratch tree but the one planted change
#
# What it guards (spec docs/superpowers/specs/2026-11-07-names-in-the-file-design.md 6.1): a limit that
# sizes a saved array may grow. A save written by this tree must load in a tree whose `grows` limits
# (every one in inc/Defines.h) are larger, and every value must land where it belongs:
# hpRolls, manaRolls and SacVals keep their rows, and the SacVals total and maximum stay in the last
# two columns of a row. A save that needs a smaller limit must refuse.
#
# Usage: tools/check_array_growth.sh              (exit 0 pass, 1 fail)
#        tools/check_array_growth.sh --selftest   (proves red: the grown reader reverted, the row copy
#                                                  reverted, and a smaller limit)
#        GROW_ONLY=NAME[,NAME] grows only those limits (to find which limit fails)
#        builds two scratch copies of the tree under test (a reference and a grown one), a few minutes at most
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE=check
[ "${1:-}" = "--selftest" ] && MODE=selftest
command -v python3 >/dev/null 2>&1 || { echo "UNMEASURED: no python3"; exit 2; }

W="$(mktemp -d "$ROOT/logs/array-growth.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/incursion-arraygrowth.XXXXXX")"
trap '[ -n "${ARRAY_GROWTH_KEEP:-}" ] && echo "kept: $W" || rm -rf "$W"' EXIT
START=$SECONDS
GROW_SAC=2   # MAX_SAC_CATS grows by this much; the other limits grow by 3 (make_tree)
[ -n "${GROW_ONLY:-}" ] && case ",$GROW_ONLY," in *,MAX_SAC_CATS,*) ;; *) GROW_SAC=0 ;; esac
export GROW_SAC

# The table of arrays: (label in the dump, the grows limits that size it, class, the printf line injected into
# the scratch trees or None when the tree under test already prints it). Written once; make_tree, the
# nonzero check, the tie check and per_limit all read it.
cat > "$W/agtable.py" <<'PY'
import os
def _p(arr, cnt, lims):
    lab = "Character." + arr.replace(".", "_")
    return (lab, lims, "player",
            'for (long gi = 0; gi != (long)(%s); gi++) if (pl->%s[gi]) printf("field %s[%%ld]=%%ld\\n", gi, (long)pl->%s[gi]);' % (cnt, arr, lab, arr))
def _g(arr, lims, body):
    return ("Game." + arr, lims, "game", body)
def _m(arr, lims, cnt):
    return ("Map." + arr, lims, "map",
            'for (long gi = 0; gi != (long)(%s); gi++) if (mp->ov.%s[gi]) printf("field Map.%s[%%ld]=%%ld\\n", gi, (long)mp->ov.%s[gi]);' % (cnt, arr[3:], arr, arr[3:]))
ARRAYS = [
    ("Character.KAttr", ["ATTR_LAST"], "player", None),
    ("Character.hpRolls", ["MAX_CHAR_LEVEL"], "player", None),
    ("Character.manaRolls", ["MAX_CHAR_LEVEL"], "player", None),
    ("Character.GainAttr", [], "player", None),
    ("Character.SacVals", ["MAX_SAC_CATS", "MAX_GODS"], "player", None),
    ("Player.Options", ["OPT_LAST"], "player", None),
    _p("Attr", "ATTR_LAST", ["ATTR_LAST"]),
    _p("Inv", "NUM_SLOTS", ["SL_LAST", "NUM_SLOTS"]),
    _p("SkillRanks", "SK_COUNT", ["SK_HIGH_END", "SK_COUNT"]),
    _p("Feats", "(FEATBITS_LAST/8)+1", ["FEATBITS_LAST"]),
    _p("Abilities", "CA_LAST", ["CA_LAST"]),
    _p("IntStudy", "STUDY_LAST", ["STUDY_LAST"]),
    _p("Spells", "MAX_SPELLS+1", ["MAX_SPELLS"]),
    _p("MMArray", "MAX_SPELLS", ["MAX_SPELLS"]),
    _p("MaxDepths", "MAX_DUNGEONS", ["MAX_DUNGEONS"]),
    _p("JournalInfo.numMonOfType", "MA_COUNT", ["MA_HIGH_END", "MA_COUNT"]),
    _p("FavourLev", "MAX_GODS", ["MAX_GODS"]),
    _p("TempFavour", "MAX_GODS", ["MAX_GODS"]),
    _p("Anger", "MAX_GODS", ["MAX_GODS"]),
    _p("FavPenalty", "MAX_GODS", ["MAX_GODS"]),
    _p("PrayerTimeout", "MAX_GODS", ["MAX_GODS"]),
    _p("AngerThisTurn", "MAX_GODS", ["MAX_GODS"]),
    _p("lastPulse", "MAX_GODS", ["MAX_GODS"]),
    _p("godFlags", "MAX_GODS", ["MAX_GODS"]),
    _g("MDataSegSize", ["MAX_MODULES"],
       'for (long gi = 0; gi != (long)(MAX_MODULES); gi++) if (gp->MDataSegSize[gi]) printf("field Game.MDataSegSize[%ld]=%lu\\n", gi, (unsigned long)gp->MDataSegSize[gi]);'),
    _g("MDataSeg", ["MAX_MODULES"],
       'for (long gi = 0; gi != (long)(MAX_MODULES); gi++) if (gp->MDataSeg[gi]) for (unsigned long gb = 0; gb != (unsigned long)gp->MDataSegSize[gi]; gb++) if (gp->MDataSeg[gi][gb]) printf("field Game.MDataSeg[%ld][%lu]=%d\\n", gi, gb, (int)(unsigned char)gp->MDataSeg[gi][gb]);'),
    _g("DungeonID", ["MAX_DUNGEONS"],
       'for (long gi = 0; gi != (long)(MAX_DUNGEONS); gi++) if (gp->DungeonID[gi]) printf("field Game.DungeonID[%ld]=%lu\\n", gi, (unsigned long)gp->DungeonID[gi]);'),
    _g("DungeonSize", ["MAX_DUNGEONS"],
       'for (long gi = 0; gi != (long)(MAX_DUNGEONS); gi++) if (gp->DungeonSize[gi]) printf("field Game.DungeonSize[%ld]=%ld\\n", gi, (long)gp->DungeonSize[gi]);'),
    _g("DungeonLevels", ["MAX_DUNGEONS"],
       'for (long gi = 0; gi != (long)(MAX_DUNGEONS); gi++) if (gp->DungeonLevels[gi]) for (long gb = 0; gb <= (long)gp->DungeonSize[gi]; gb++) if (gp->DungeonLevels[gi][gb]) printf("field Game.DungeonLevels[%ld][%ld]=%ld\\n", gi, gb, (long)gp->DungeonLevels[gi][gb]);'),
    _m("ov_GlyphX", ["MAX_OVERLAY_GLYPHS"], "MAX_OVERLAY_GLYPHS"),
    _m("ov_GlyphY", ["MAX_OVERLAY_GLYPHS"], "MAX_OVERLAY_GLYPHS"),
    _m("ov_GlyphImage", ["MAX_OVERLAY_GLYPHS"], "MAX_OVERLAY_GLYPHS"),
]
# Limits marked `grows` that size no saved array. Each carries its reason.
ALLOW = {
    "FT_LAST": "a feat number is a stored VALUE (the bit it sets in Character.Feats, sized by FEATBITS_LAST); FT_LAST sizes no array, so a larger FT_LAST changes no saved byte",
}
_drop = [x for x in os.environ.get("ARRAY_GROWTH_DROP", "").split(",") if x]
ARRAYS = [a for a in ARRAYS if a[0] not in _drop]
PY
export PYTHONPATH="$W"

# make_tree <dir> <mutation>   mutation: none | ref (no larger limits) | exact (the old exact-count V1Array) | flat (a flat copy of rows) | glyph (ov_GlyphX read from the ov_GlyphY values)
# Copies the tracked source of the tree under test (working-tree text, so an uncommitted edit counts),
# raises the limits, drops the struct-size pins, applies the one planted change.
make_tree() {
    python3 - "$ROOT" "$1" "$2" <<'PY'
import os, re, shutil, subprocess, sys
root, dest, mut = sys.argv[1:4]
# Every limit the family marks of inc/Defines.h call `grows`, read from the marks of the tree under test.
# A limit written as an expression (MA_COUNT, SK_COUNT) grows through the plain limit it is made of.
src = open(os.path.join(root, "inc", "Defines.h"), encoding="latin-1").read()
names = []
for ln in src.split("\n"):
    if re.match(r"//\s*family:", ln):
        names += re.findall(r"\bgrows\s+(\w+)", ln)
only = [x for x in os.environ.get("GROW_ONLY", "").split(",") if x]
GROW = {}
for n in names:
    if (only and n not in only) or mut == "ref":
        continue
    GROW[n] = int(os.environ["GROW_SAC"]) if n == "MAX_SAC_CATS" else 3
files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", "inc", "src", "lib", "compat", "build_macos.sh"],
                       capture_output=True, check=True).stdout.decode().split("\0")
for f in files:
    if not f:
        continue
    s, d = os.path.join(root, f), os.path.join(dest, f)
    if not os.path.lexists(s):
        continue
    os.makedirs(os.path.dirname(d), exist_ok=True)
    if os.path.islink(s):
        os.symlink(os.readlink(s), d)
    else:
        shutil.copy2(s, d)
def rw(path, fn):
    t = open(path, encoding="latin-1", newline="").read()
    n = fn(t)
    if n != t:
        open(path, "w", encoding="latin-1", newline="").write(n)
    return n != t
dfn = os.path.join(dest, "inc", "Defines.h")
t = open(dfn, encoding="latin-1", newline="").read()
report = []
for name, inc in GROW.items():
    m = re.search(r"^(#define\s+%s\s+)(\d+)\s*(?:/\*.*\*/\s*)?$" % name, t, re.M)
    if not m:
        report.append("%s derived (an expression of other limits)" % name)
        continue
    t = t[:m.start(2)] + str(int(m.group(2)) + inc) + t[m.end(2):]
    report.append("%s %s -> %d" % (name, m.group(2), int(m.group(2)) + inc))
open(dfn, "w", encoding="latin-1", newline="").write(t)
open(os.path.join(dest, "grown.txt"), "w").write("\n".join(report) + "\n")
pin = re.compile(r"(static_assert\(\s*sizeof\(\w+\)\s*)==\s*\d+")
for dp, _dn, fns in os.walk(dest):
    for fn in fns:
        if fn.endswith((".h", ".cpp")):
            rw(os.path.join(dp, fn), lambda x: pin.sub(r"\1> 0", x))
# The build runs the resource-order guard after it compiles the module. The scratch tree has no
# ledger and no git, and its module is not the one the order rule protects, so the guard is a stub.
os.makedirs(os.path.join(dest, "tools"), exist_ok=True)
stub = os.path.join(dest, "tools", "order_guard.sh")
open(stub, "w").write("#!/bin/bash\nexit 0\n")
os.chmod(stub, 0o755)
# The DEBUG build measures the record layout and the family names with these generators; without them
# SaveV1.cpp does not compile. They read the scratch tree's own headers, so a grown layout is measured, not pinned.
for gen in ("gen_record_layout.py", "save_pad_rows.py", "gen_family_names.py", "check_define_dups.py"):
    shutil.copy2(os.path.join(root, "tools", gen), os.path.join(dest, "tools", gen))
# SkillInfo[] has one row per skill: a grown SK_HIGH_END adds a skill number and no table row. The scratch
# tree never runs a skill, so the row-count pin only says the table did not grow.
tab = os.path.join(dest, "src", "Tables.cpp")
rw(tab, lambda x: x.replace("sizeof(SkillInfo[0]) == SK_COUNT + 1", "sizeof(SkillInfo[0]) <= SK_COUNT + 1", 1))
sv = os.path.join(dest, "src", "SaveV1.cpp")
# Extra dump lines (nonzero entries only, like the lines above them) for the arrays of the table that the tree
# under test does not print itself: the Player ones before the Player anchor, the Game and Map ones before the
# Game and Map anchor.
import agtable
anchor = '              printf("field Player.cAutoBuff=%d\\n", (int)pl->cAutoBuff);'
extra = "".join("              " + cpp + "\n" for _l, _x, cls, cpp in agtable.ARRAYS if cls == "player" and cpp)
assert rw(sv, lambda x: x.replace(anchor, extra + anchor, 1)), "dump anchor gone"
ganchor = '              printf("field %s.present=1\\n", o->Type == T_GAME ? "Game" : "Map");'
gblock = "".join("                  " + cpp + "\n" for _l, _x, cls, cpp in agtable.ARRAYS if cls == "game" and cpp)
mblock = "".join("                  " + cpp + "\n" for _l, _x, cls, cpp in agtable.ARRAYS if cls == "map" and cpp)
inject = ("              if (o->Type == T_GAME)\n                {\n                  Game *gp = (Game*)o;\n" + gblock +
          "                }\n              else\n                {\n                  Map *mp = (Map*)o;\n" + mblock + "                }\n")
assert rw(sv, lambda x: x.replace(ganchor, inject + ganchor, 1)), "game/map dump anchor gone"
# The DEBUG coverage map pins padding offsets that the larger arrays move; like the size pins, they
# only say the layout changed on purpose. Without this the larger tree cannot WRITE a save (red 3).
cov = "if (v1CovFindings != covBefore)"
assert rw(sv, lambda x: x.replace(cov, "if (0 && v1CovFindings != covBefore)", 1)), "coverage site gone"
if mut == "exact":
    old = "if (c > count || es != (uint32)elemSize)"
    assert rw(sv, lambda x: x.replace(old, "if (c != count || es != (uint32)elemSize)", 1)), "mutation site gone"
elif mut == "glyph":
    # the reader puts the saved ov_GlyphY values into GlyphX: a new array lands in the wrong place
    mp = os.path.join(dest, "inc", "Map.h")
    old = 'FIELD_ARRAY("ov_GlyphX", ov.GlyphX,'
    assert rw(mp, lambda x: x.replace(old, 'FIELD_ARRAY("ov_GlyphX", ov.GlyphY,', 1)), "mutation site gone"
elif mut == "flat":
    a = "uint8 *d = dst + (size_t)r * rowLen * es;"
    b = "memcpy(d + (size_t)(rowLen - tail) * es,"
    def flat(x):
        assert a in x and b in x, "mutation site gone"
        return x.replace(a, "uint8 *d = dst + (size_t)r * savedRowLen * es;", 1).replace(
            b, "memcpy(d + (size_t)(savedRowLen - tail) * es,", 1)
    rw(sv, flat)
PY
}

# build <dir> <log>   (the scratch tree builds itself; -O0 after -O2 wins)
build() {
    ( cd "$1" && BACKEND=posix EXTRA_CXXFLAGS=-O0 ./build_macos.sh > "$2" 2>&1 ) && [ -x "$1/incursion-headless" ]
}

# dump <binary-dir> <file>  -> the array lines of -schemaload for the character file and the game file next to it, sorted
dump() {
    for f in "$2" "$(dirname "$2")/game.sav"; do
        ( cd "$1" && ./incursion-headless -schemaload "$f" -timeout 120 < /dev/null 2> "$W/load.err" ) | grep -E '^field (Character\.[A-Za-z_]+|Player\.Options|Game\.[A-Za-z]+|Map\.[A-Za-z_]+)\['
    done | LC_ALL=C sort
}

# expect <A dump file> <A SacVals row length> <B SacVals row length>
# Move A's lines the way spec 6.1 says: only SacVals changes (columns >= A.row-2 shift by the growth).
expect() {
    python3 - "$1" "$2" "$3" <<'PY'
import re, sys
src, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
out = []
for ln in open(src):
    m = re.match(r"field Character\.SacVals\[(\d+)\]\[(\d+)\]=(-?\d+)$", ln.strip())
    if m:
        g, j, v = int(m.group(1)), int(m.group(2)), m.group(3)
        if j >= a - 2:
            j += b - a
        out.append("field Character.SacVals[%d][%d]=%s" % (g, j, v))
    else:
        out.append(ln.strip())
print("\n".join(out))
PY
}

# tie_check: every limit a family mark calls `grows` names an array of the table or the allow list (exit 2 if not)
tie_check() {
    python3 - "$ROOT" <<'PY'
import os, re, sys
import agtable
src = open(os.path.join(sys.argv[1], "inc", "Defines.h"), encoding="latin-1").read()
names = []
for ln in src.split("\n"):
    if re.match(r"//\s*family:", ln):
        names += re.findall(r"\bgrows\s+(\w+)", ln)
mapped = set(l for a in agtable.ARRAYS for l in a[1])
bad = [n for n in names if n not in mapped and n not in agtable.ALLOW]
if not names:
    print("UNMEASURED: no `grows` mark found in inc/Defines.h"); sys.exit(2)
for n in bad:
    print("UNMEASURED: the limit %s is marked `grows` and names no dumped array and no allow-list entry (tools/check_array_growth.sh, AGTABLE)" % n)
sys.exit(2 if bad else 0)
PY
}

# need_nonzero <dump>: every array of the table holds a nonzero entry in the reference dump (exit 2 naming the first that does not)
need_nonzero() {
    python3 - "$1" <<'PY'
import sys
import agtable
lines = open(sys.argv[1]).read().split("\n")
bad = []
for lab, lims, _c, _x in agtable.ARRAYS:
    n = sum(1 for x in lines if x.startswith("field %s[" % lab))
    print("  %s: %d nonzero" % (lab, n))
    if not n:
        bad.append(lab)
for lab in bad:
    print("UNMEASURED: the array %s holds no nonzero entry in the file the reference tree wrote; the schematest leaves it empty, so a wrong placement would not show" % lab)
sys.exit(2 if bad else 0)
PY
}

tie_check || exit 2
[ "${1:-}" = "--tie" ] && { echo "tie ok"; exit 0; }
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
ok() { echo "ok: $1"; }

# The reference (a scratch copy of the tree under test, extra dump lines, no larger limit) and the grown copy.
mkdir -p "$W/ref" "$W/grown"
make_tree "$W/ref" ref && make_tree "$W/grown" none || { fail "could not make the scratch trees"; exit 1; }
build "$W/ref" "$W/ref.log" & PR=$!
build "$W/grown" "$W/grown.log" & PG=$!
wait $PR || { tail -20 "$W/ref.log"; fail "the reference tree did not build"; exit 1; }
wait $PG || { tail -20 "$W/grown.log"; fail "the grown tree did not build"; exit 1; }

# The file written by the reference tree, and what that tree reads back from it.
mkdir -p "$W/a"
"$W/ref/incursion-headless" -schematest "$W/a" -timeout 120 < /dev/null > "$W/a/schematest.log" 2> "$W/a/schematest.err" \
    || { cat "$W/a/schematest.err"; fail "-schematest did not run clean on the reference tree"; exit 1; }
SAV="$W/a/e.sav"
dump "$W/ref" "$SAV" > "$W/a.dump"
NA="$(wc -l < "$W/a.dump" | tr -d ' ')"
[ "$NA" -gt 100 ] || { fail "the reference tree printed only $NA array lines for its own file"; exit 1; }
need_nonzero "$W/a.dump" > "$W/nonzero.txt"; NZ=$?
if [ "$NZ" != 0 ]; then grep UNMEASURED "$W/nonzero.txt"; exit 2; fi
ROWLEN_A="$(sed -n 's/^#define MAX_SAC_CATS *\([0-9]*\).*/\1/p' inc/Defines.h | head -1)"
ROWLEN_A=$((ROWLEN_A + 2))
ROWLEN_B=$((ROWLEN_A + GROW_SAC))
expect "$W/a.dump" "$ROWLEN_A" "$ROWLEN_B" | LC_ALL=C sort > "$W/want.dump"

# loads <tree> <file> -> 0 and the dump in $W/got.dump when the load worked
loads() {
    for f in "$2" "$(dirname "$2")/game.sav"; do
        ( cd "$1" && ./incursion-headless -schemaload "$f" -timeout 120 < /dev/null > /dev/null 2> "$W/load.err" ) || return 1
    done
    dump "$1" "$2" > "$W/got.dump"
}
refused() { # <tree> <file> <label>   0 when the load failed with a corrupt-file error
    ( cd "$1" && ./incursion-headless -schemaload "$2" -timeout 120 < /dev/null > /dev/null 2> "$W/load.err" )
    [ $? != 0 ] && grep -q -i "corrupt" "$W/load.err"
}

# per_limit: one line per grown limit, from the list make_tree wrote, the table and the lines the reference dump holds
per_limit() {
    python3 - "$W/grown/grown.txt" "$W/a.dump" <<'PY'
import re, sys
import agtable
lines = open(sys.argv[2]).read().split("\n")
for ln in open(sys.argv[1]):
    name = ln.split()[0]
    names = [a[0] for a in agtable.ARRAYS if name in a[1]]
    n = {a: sum(1 for x in lines if x.startswith("field %s[" % a)) for a in names}
    seen = ", ".join("%s %d" % (a, c) for a, c in n.items() if c)
    how = ("values compared in " + seen) if seen else ("allowed, sizes no saved array: " + agtable.ALLOW[name] if name in agtable.ALLOW else "NO ARRAY")
    print("ok: %s: %s" % (ln.strip(), how))
PY
}

if [ "$MODE" = check ]; then
    if loads "$W/grown" "$SAV"; then
        ok "a save from the tree under test loads in a tree with larger limits"
        if diff -q "$W/want.dump" "$W/got.dump" > /dev/null; then
            ok "every saved value landed where it belongs ($NA lines; SacVals total and maximum in the last two columns)"
            echo "nonzero entries per dumped array in the reference:"; cat "$W/nonzero.txt"
            per_limit
        else
            diff "$W/want.dump" "$W/got.dump" | head -10
            fail "a saved value landed in the wrong place"
        fi
    else
        cat "$W/load.err" | tail -3
        fail "the grown tree refused the save"
    fi
    echo "elapsed: $((SECONDS - START)) s"
    [ "$FAILED" = 0 ] && echo "PASS" || echo "FAILED"
    exit "$FAILED"
fi

# --selftest: build the grown tree and the two planted changes at once.
mkdir -p "$W/exact" "$W/flat" "$W/glyph"
make_tree "$W/exact" exact && make_tree "$W/flat" flat && make_tree "$W/glyph" glyph || { echo "SELFTEST FAIL: could not make the planted trees"; exit 1; }
build "$W/exact" "$W/exact.log" & P2=$!
build "$W/flat" "$W/flat.log" & P3=$!
build "$W/glyph" "$W/glyph.log" & P4=$!
wait $P4 || { tail -20 "$W/glyph.log"; echo "SELFTEST FAIL: glyph tree"; exit 1; }
wait $P2 || { tail -20 "$W/exact.log"; echo "SELFTEST FAIL: exact tree"; exit 1; }
wait $P3 || { tail -20 "$W/flat.log"; echo "SELFTEST FAIL: flat tree"; exit 1; }
ST=0
st_ok() { echo "ok: $1"; }
st_fail() { echo "SELFTEST FAIL: $1"; ST=1; }

# green first: the good tree passes
if loads "$W/grown" "$SAV" && diff -q "$W/want.dump" "$W/got.dump" > /dev/null; then
    st_ok "green: the grown tree loads the save and every value lands"
else
    st_fail "green: the grown tree did not pass"
fi
# red 1: the old exact-count reader refuses a shorter saved array
if loads "$W/exact" "$SAV"; then st_fail "red 1: the exact-count reader loaded a shorter array"
else st_ok "red 1: the reverted reader (exact count) refuses the save"; fi
# red 2: a flat copy of rows loads and puts values in the wrong place
if loads "$W/flat" "$SAV"; then
    if diff -q "$W/want.dump" "$W/got.dump" > /dev/null; then st_fail "red 2: the flat copy put every value in place"
    else st_ok "red 2: the reverted row copy loads and misplaces values ($(diff "$W/want.dump" "$W/got.dump" | grep -c '^<') lines differ)"; fi
else st_fail "red 2: the flat-copy tree refused the save instead of misplacing values"; fi
# red 3: a smaller limit refuses. The grown tree writes a file; the reference tree (smaller limits) reads it.
mkdir -p "$W/b"
( cd "$W/grown" && ./incursion-headless -schematest "$W/b" -timeout 120 < /dev/null > /dev/null 2> "$W/b/schematest.err" )
if [ -s "$W/b/e.sav" ]; then
    if refused "$W/ref" "$W/b/e.sav" small; then st_ok "red 3: a save that needs a larger limit is refused by the smaller tree"
    else st_fail "red 3: the smaller tree did not refuse: $(tail -1 "$W/load.err")"; fi
else
    st_fail "red 3: the grown tree wrote no file"
fi
# red 4: a reader that puts a new array's values in the wrong place (ov_GlyphX read from the ov_GlyphY values) is caught, with the array named
if loads "$W/glyph" "$SAV"; then
    if diff -q "$W/want.dump" "$W/got.dump" > /dev/null; then st_fail "red 4: the misplaced Map array was not noticed"
    else st_ok "red 4: a misplaced Map array differs ($(diff "$W/want.dump" "$W/got.dump" | grep -o 'field Map\.[A-Za-z_]*' | sort -u | tr '\n' ' '))"; fi
else st_fail "red 4: the glyph tree refused the save instead of misplacing values"; fi
# red 5: a table that lacks the arrays of a grows limit exits 2 naming the limit
OUT5="$(ARRAY_GROWTH_DROP=Game.MDataSeg,Game.MDataSegSize "$0" --tie 2>&1)"; RC5=$?
if [ "$RC5" = 2 ] && [[ "$OUT5" == *MAX_MODULES* ]]; then st_ok "red 5: a limit with no array in the table exits 2 naming MAX_MODULES"
else st_fail "red 5: exit $RC5: $OUT5"; fi
# red 6: a dump with no entry of one array exits 2 naming the array
grep -v '^field Game\.DungeonSize\[' "$W/a.dump" > "$W/empty.dump"
OUT6="$(need_nonzero "$W/empty.dump" 2>&1)"; RC6=$?
if [ "$RC6" = 2 ] && [[ "$OUT6" == *"UNMEASURED: the array Game.DungeonSize"* ]]; then st_ok "red 6: an array the file leaves empty exits 2 naming Game.DungeonSize"
else st_fail "red 6: exit $RC6"; fi
echo "elapsed: $((SECONDS - START)) s"
[ "$ST" = 0 ] && echo "SELFTEST PASS" || echo "SELFTEST FAILED"
exit "$ST"
