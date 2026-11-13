#!/bin/bash
# AC9 merge-1 substep (inc-cjos0 E2): the epic's character fixtures become `.char` files, by tool output only.
#
#   tools/pressure/ac9_fixtures.sh <merge-worktree> <state-dir> [<names-file>]
#
# Spec: ~/Scripts/Incursion-inc-10v7f/docs/specs/2026-11-06-fixture-builder-spec.md, amendment A11 and section 10 step 3:
# one .char per fixture name per branch. For every fixture name the pre-merge epic (HEAD of <merge-worktree> mid-merge; AC9_FIXTURES_BASE names another ref for a test run)
# holds as a `.sav` AND the oracle dumps hold (docs/evidence/inc-10v7f/epic-d71c1823/<name>.canon), the epic's .char is
# converted from the epic's own `.sav` by tools/char_convert.sh against that oracle dump. It REPLACES master's .char when
# master has one. The god line comes from the character itself (the conversion records the walk and sets what the dump
# states); nothing is taken from an `add: god: <X>` hint. A name with no epic `.sav` or no oracle dump is left alone.
# Then the epic's old `.sav`, `.keys` and sheet of each converted name leave the tree, and every check that loaded
# `<name>.sav` loads `<name>.char`.
#
# Needs the merged tree built (BACKEND=posix ./build_macos.sh). Writes <state-dir>/fixtures/{MANIFEST,names.txt,log/,result.tsv}
# and <state-dir>/fixtures/added.diff (the lines this substep adds: ac9.sh attributes them as tool output).
# Exit: 0 every name converted (result.tsv: name TAB rc TAB computed-diff-lines TAB choices-diff-lines TAB excused),
#       1 a name did not convert (listed in <state-dir>/fixtures/failures.txt; nothing is committed here), 2 could not run.
#
# fact: the character -- the epic's own d71c1823 .sav of each name, with its oracle dump; no seed beyond the one in its sheet
# fact: the oracle -- $AC9_ORACLE (default ~/Scripts/Incursion/docs/evidence/inc-10v7f/epic-d71c1823), read only
# fact: the binary -- the merged tree's incursion-headless
set -uo pipefail
W="$(cd "${1:?usage: ac9_fixtures.sh <worktree> <state-dir> [names]}" && pwd -P)"
SD="${2:?state dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export AC9_STANDINS="${AC9_STANDINS:-$HERE/ac9/standins.txt}"
ORACLE="${AC9_ORACLE:-$HOME/Scripts/Incursion/docs/evidence/inc-10v7f/epic-d71c1823}"
JOBS="${AC9_FIXTURE_JOBS:-3}"
BASE_REF="${AC9_FIXTURES_BASE:-HEAD}"
F="$SD/fixtures"; OLD="$F/old"; OUT="$F/out"; LG="$F/log"
rm -rf "$F"; mkdir -p "$OLD" "$OUT" "$LG" || exit 2
[ -d "$ORACLE" ] || { echo "ac9_fixtures: no oracle directory $ORACLE" >&2; exit 2; }
[ -x "$W/incursion-headless" ] || { echo "ac9_fixtures: $W is not built" >&2; exit 2; }
cd "$W" || exit 2

# 1. names, MANIFEST rows (from each epic sheet), the epic's files, the key scripts the merge removed
python3 - "$W" "$ORACLE" "$F" "${3:-}" <<'PY' || exit 2
import os, re, subprocess, sys
w, oracle, f, only = sys.argv[1:5]
BASE = os.environ.get("AC9_FIXTURES_BASE", "HEAD")   # the pre-merge epic (a test run names it)
def git(*a):
    return subprocess.run(["git", "-C", w] + list(a), capture_output=True)
ls = git("ls-tree", "--name-only", BASE, "tools/fixtures/chars/").stdout.decode().split("\n")
names = sorted(os.path.basename(p)[:-4] for p in ls if p.endswith(".sav"))
names = [n for n in names if os.path.exists("%s/%s.canon" % (oracle, n))]
# A name takes part when master holds its .char (both branches: the epic's replaces master's), or when the epic's .sav is
# still in the merged tree (epic only). Master's own `.sav` fixtures (the README table "Old fixtures that have no .char")
# and every name master keeps only as a specimen stay as they are.
readme = open(os.path.join(w, "tools/fixtures/README.md"), errors="replace").read()
keep_sav = set(re.findall(r"^\| `([^`]+)` \| `tools/keys/", readme, re.M))
names = [n for n in names if n not in keep_sav and (os.path.exists("%s/tools/fixtures/chars/%s.char" % (w, n))
                                                    or os.path.exists("%s/tools/fixtures/chars/%s.sav" % (w, n)))]
if only:
    keep = set(open(only).read().split())
    names = [n for n in names if n in keep]
standins = set(l.split("\t")[0] for l in open(os.environ["AC9_STANDINS"]) if l.strip() and not l.startswith("#"))
open(f + "/standins.txt", "w").write("\n".join(sorted(standins)) + "\n")
names = [n for n in names if n not in standins]
rows, added = [], []
for n in names:
    for ext in ("sav", "sheet.txt"):
        open("%s/old/%s.%s" % (f, n, ext), "wb").write(git("show", BASE + ":tools/fixtures/chars/%s.%s" % (n, ext)).stdout)
    t = open("%s/old/%s.sheet.txt" % (f, n), errors="replace").read()
    seed, st, ks = (re.search(r"^%s\s+(\S+)" % k, t, re.M).group(1) for k in ("seed", "settings", "key script"))
    rows.append((n, ks, seed, st))
    if not os.path.exists(os.path.join(w, ks)):
        r = git("show", BASE + ":" + ks)
        if r.returncode != 0:
            print("ac9_fixtures: %s: key script %s is in neither the tree nor the epic" % (n, ks)); sys.exit(2)
        open(os.path.join(w, ks), "wb").write(r.stdout)
        added.append(ks)
open(f + "/MANIFEST", "w").write("".join("\t".join(r) + "\n" for r in rows))
open(f + "/names.txt", "w").write("\n".join(names) + "\n")
open(f + "/tempkeys.txt", "w").write("\n".join(added) + ("\n" if added else ""))
print("ac9_fixtures: %d name(s), %d key script(s) restored for the walks" % (len(names), len(added)))
PY

# 2. convert, JOBS at a time
export CHAR_CONVERT_MANIFEST="$F/MANIFEST" CHAR_CONVERT_DIR="$OLD" CHAR_CONVERT_OLD_CANON_DIR="$ORACLE" CHAR_CONVERT_LOGS="logs/ac9-fixtures"
export OUT_DIR="$OUT" LOG_DIR="$LG"
one() {
    local n="$1"
    tools/char_convert.sh "$n" "$OUT_DIR/$n.char" > "$LOG_DIR/$n.txt" 2>&1 < /dev/null
    echo "$n $?" >> "$LOG_DIR/rc.txt"
}
export -f one
: > "$LG/rc.txt"
xargs -n1 -P "$JOBS" bash -c 'one "$0"' < "$F/names.txt"

# 3. result table; install the converted files
: > "$F/result.tsv"; : > "$F/failures.txt"
while read -r n rc; do
    d="logs/ac9-fixtures/$n"
    nd="$(grep -cE '^[-+][^-+]' "$d/diff.txt" 2>/dev/null || echo -)"
    cd_="$(grep -vc '^$' "$d/choices-diff.txt" 2>/dev/null || echo -)"
    ex="$(grep -c '^excused' "$d/excused.txt" 2>/dev/null || echo 0)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$rc" "$nd" "$cd_" "$ex" >> "$F/result.tsv"
    if [ "$rc" -eq 0 ] && [ -n "${AC9_FIXTURES_CONVERT_ONLY:-}" ]; then :
    elif [ "$rc" -eq 0 ]; then
        cp "$OUT/$n.char" "tools/fixtures/chars/$n.char" && git add -- "tools/fixtures/chars/$n.char"
    else
        echo "$n rc=$rc: $(grep -v 'roll:' "$LG/$n.txt" | tail -2 | tr '\n' ' ' | cut -c1-300)" >> "$F/failures.txt"
    fi
done < <(sort "$LG/rc.txt")

# 4. the restored key scripts go again (AC9_FIXTURES_CONVERT_ONLY=1: convert and report, install nothing) (they are not part of the merge)
while read -r k; do [ -n "$k" ] && rm -f "$k"; done < "$F/tempkeys.txt"

[ -z "${AC9_FIXTURES_CONVERT_ONLY:-}" ] || { echo "ac9_fixtures: convert-only run: $(wc -l < "$F/result.tsv" | tr -d ' ') name(s), $(wc -l < "$F/failures.txt" | tr -d ' ') failure(s)"; exit 0; }
if [ -s "$F/failures.txt" ]; then echo "ac9_fixtures: $(wc -l < "$F/failures.txt" | tr -d ' ') name(s) did not convert: see $F/failures.txt"; exit 1; fi

# 5. retire the old files of each converted name, and point every check at the .char
while read -r n; do
    for ext in sav keys sheet.txt; do
        [ -e "tools/fixtures/chars/$n.$ext" ] && git rm -q -f -- "tools/fixtures/chars/$n.$ext"
    done
done < "$F/names.txt"
python3 - "$W" "$F" <<'PY'
import os, re, subprocess, sys
w, f = sys.argv[1:3]
names = open(f + "/names.txt").read().split()
man = os.path.join(w, "tools/fixtures/chars/MANIFEST")
if os.path.exists(man):
    keep = [l for l in open(man).read().split("\n") if not (l.split() and l.split()[0] in names)]
    open(man, "w").write("\n".join(keep))
files = subprocess.run(["git", "-C", w, "ls-files", "tools"], capture_output=True, text=True).stdout.split()
pat = re.compile(r"chars/(%s)\.sav\b" % "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True)))
n_files = 0
for p in files:
    if p.startswith("tools/fixtures/") or p.endswith((".sav", ".char")):
        continue
    fp = os.path.join(w, p)
    try:
        t = open(fp, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    t2 = pat.sub(lambda m: "chars/" + m.group(1) + ".char", t)
    if t2 != t:
        open(fp, "w", encoding="utf-8").write(t2)
        n_files += 1
print("ac9_fixtures: %d check file(s) now name the .char" % n_files)
PY
# 5b. stand-ins (rehearsal only, tools/pressure/ac9/standins.txt): the merged tree keeps the epic's own pre-merge files
while IFS=$'\t' read -r n bead why; do
    case "$n" in ''|'#'*) continue ;; esac
    git cat-file -e "$BASE_REF:tools/fixtures/chars/$n.sav" 2> /dev/null || continue   # no epic save: nothing to keep
    for ext in sav keys sheet.txt; do
        git show "$BASE_REF:tools/fixtures/chars/$n.$ext" > "tools/fixtures/chars/$n.$ext" 2> /dev/null && git add -- "tools/fixtures/chars/$n.$ext"
    done
    [ -e "tools/fixtures/chars/$n.char" ] && git rm -q -f -- "tools/fixtures/chars/$n.char"
    echo "ac9_fixtures: stand-in $n ($bead): the epic's .sav stays"
done < "$AC9_STANDINS"

# 6. owner rulings 2026-11-13 for the master-only names: epic-side edits to the merged tree, never to master's files
python3 - "$W" <<'PY'
import os, re, sys
w = sys.argv[1]
c = os.path.join(w, "tools/fixtures/chars")
for n in ("elf-rogue-bluff-seed1-opt0822", "orc-barbarian-ce-opt0822", "wood-elf-rogue-seed7-opt0818", "orc-paladin-cannibal"):
    p = os.path.join(c, n + ".char")
    if not os.path.exists(p):
        print("ac9_fixtures: %s: master's tree has no such fixture; no edit" % n)
        continue
    t = open(p).read()
    if re.search(r"^god:", t, re.M):
        print("ac9_fixtures: %s already has a god line; no edit" % n)
        continue
    t = re.sub(r"^(class:[^\n]*\n)", r"\1god: No god\n", t, count=1, flags=re.M)
    if n == "orc-barbarian-ce-opt0822":
        # with no god the Orc script never asks this yes/no: the build refuses the stated answer as surplus
        t = t.replace("script_yn [Orc;EV_150]: yes\n", "", 1)
    open(p, "w").write(t)
    print("ac9_fixtures: %s: god: No god" % n)
p = os.path.join(c, "orc-priest-seed1-opt0822.char")
t = open(p).read()
if "domain: Fate\n" in t:
    t = t.replace("domain: Fate\n", "", 1)
    t = re.sub(r"^(domain: Night\n)", r"\1domain: Planning\n", t, count=1, flags=re.M)
    open(p, "w").write(t)
    print("ac9_fixtures: orc-priest-seed1-opt0822: domain Planning replaces Fate (god: Aiswin kept)")
PY
# 7. the damage-class freeze (inc-kx693's rule): the god case may move, nothing else
if ! tools/check_damage_class.sh --freeze > "$F/freeze.log" 2>&1; then echo "ac9_fixtures: check_damage_class.sh --freeze failed: $(tail -2 "$F/freeze.log")"; exit 1; fi
moved="$(git diff -U0 -- tools/fixtures/damage-class.expected | grep -E '^[-+]DC ' | grep -vc 'case=god type=13 ')"
if [ "$moved" -ne 0 ]; then echo "ac9_fixtures: the freeze moved $moved line(s) besides DC case=god type=13"; git diff -- tools/fixtures/damage-class.expected | grep '^[-+]'; exit 1; fi
git diff -- tools/fixtures/damage-class.expected | grep -E '^[-+]DC ' > "$F/freeze-moved.txt"
git add -A -- tools >/dev/null 2>&1
git diff --cached -- tools > "$F/added.diff"
exit 0
