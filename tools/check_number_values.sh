#!/bin/bash
# gate: none heavy; needs clang and a posix build (BACKEND=posix ./build_macos.sh); run by hand
# fact: source tree -- the working tree this script runs in; the dump and the compiler both read it, nothing else
# fact: compiler flags -- the posix flags of build_macos.sh (-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -std=c++17 -fpermissive), copied here, plus three alternate configs only to explain names
# fact: saved files scanned by part 4 -- the committed fixtures tools/fixtures/chars/*.sav (frozen bytes), docs/evidence/inc-upw.13 and inc-x1f3 (frozen bytes), plus fresh saves from the key scripts in SCAN_GEN at the seeds named there, all run with options tools/fixtures/options-2026-08-22.dat; the assertions are "every save of a format the reader reads loads" and "the log holds fields", which hold for any seed, while the coverage count (reported, never asserted) depends on them
# fact: the TerraRecord save -- tools/keys/terra-save.keys loads tools/fixtures/chars/elf-mage-illusions-seed1.sav (INCURSION_LOAD, frozen bytes; it fixes character and map) with the options above; its header lists the other facts (Freeze Monsters, Wall of Fire learned, Ignore Spell Failure, Infinite Mana); the assertion is "some scan holds scope TerraRecord", which holds at any seed
# fact: saves the v1 reader never reads -- the two paths in KNOWN_UNREAD, frozen bytes, each named with the stamp in its own header (0.6.9Y19, SF0F7B6EDC)
# fact: reader behavior on an unknown tag -- Registry::LoadGroupV1 refuses a tag no field list asks for (v1PopFrame, ECORRUPT); the planted-tag selftest proves it on this build
# fact: save revision -- the build under test (incursion-headless built from this tree)
# fact: legacy tag table -- inc/SaveLegacyTags.h, committed and frozen (generated once from master by tools/gen_legacy_tags.py); part 5 reads it and nothing else of the tag numbers; it matches a logged (owner, tag) by revision, not by the reading line, because the lines move with every edit of src/SaveV1.cpp
# fact: revision of a scanned file -- the IS1.<n> stamp in the file's own header bytes; fixtures and evidence are frozen bytes, generated saves carry this build's SCHEMA_REV
#
# Cross-checks tools/number_values.py (the "dump") by methods that share no
# parsing code with it (inc-cjos0):
#   1. NAMES   the real preprocessor (clang -E -dD) vs the dump's define names
#   2. VALUES  a generated C++ file, compiled and run, prints every dumped
#              define and enum member; compared with the dump
#   3. (retired: the source holds no tag numbers, so the dump holds no tag rows)
#   4. SAVES   every real save loads (two named formats the v1 reader never reads
#              excepted); the reader's scan log holds the fields it asked for; the
#              TerraRecord save shows that record's fields (inc-cjos0 phase 6)
#   5. LEGACY  every (owner, tag) in a revision 3-6 save has a row in the frozen
#              table inc/SaveLegacyTags.h for that revision (inc-cjos0 phase 1)
#
# Usage: tools/check_number_values.sh [--dump FILE] [--keep]   (exit 0 pass, 1 fail)
#        tools/check_number_values.sh --selftest                (proves each part goes red)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE=check
DUMP=""
KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) MODE=selftest ;;
        --dump) DUMP="$2"; shift ;;
        --keep) KEEP=1 ;;
        *) echo "unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

W="$(mktemp -d "${TMPDIR:-/tmp}/incursion-nvcheck.XXXXXX")"
[ "$KEEP" = 1 ] || trap 'rm -rf "$W"' EXIT
CXX="${CXX:-clang++}"
CC="${CC:-clang}"
command -v "$CXX" >/dev/null || { echo "FAIL: no $CXX" >&2; exit 1; }

# The flags build_macos.sh uses for BACKEND=posix with the developer compiler.
POSIX_FLAGS="-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -fpermissive -Wno-narrowing -w"

if [ -z "$DUMP" ]; then
    DUMP="$W/dump.txt"
    python3 tools/number_values.py "$ROOT" > "$DUMP" 2> "$W/dump.err" \
        || { echo "FAIL: tools/number_values.py failed"; exit 1; }
fi

# ------------------------------------------------------------------ configs
# One module shared by collect and compare: the compiler configurations and the
# way one translation unit is preprocessed. The "build" config is the one
# build_macos.sh uses for BACKEND=posix; the others exist only to explain names.
write_cfg() {
    cat > "$W/nvcfg.py" <<'PY'
import glob, os, subprocess
sdl = subprocess.run("pkg-config --cflags sdl2", shell=True, capture_output=True, text=True).stdout.split()
CONFIGS = {
    "build":          ["-DDEBUG", "-DPOSIX_TERM", "-Iinc", "-Ilib", "-Icompat"],
    "posix-release":  ["-DPOSIX_TERM", "-Iinc", "-Ilib", "-Icompat"],
    "sdl-debug":      ["-DDEBUG", "-DLIBTCOD_TERM", "-DTCODLIB_API=", "-Iinc", "-Ilib", "-Ilibtcod/include", "-Icompat"] + sdl,
    "sdl-release":    ["-DLIBTCOD_TERM", "-DTCODLIB_API=", "-Iinc", "-Ilib", "-Ilibtcod/include", "-Icompat"] + sdl,
}
def units(root):
    return (sorted(glob.glob(root + "/src/*.cpp")) + sorted(glob.glob(root + "/inc/*.h"))
            + sorted(glob.glob(root + "/src/*.c")))
def cmd(cfg, f, root):
    if f.endswith(".c"):
        return ["clang", "-x", "c", "-E", "-dD", "-w"] + CONFIGS[cfg] + [f]
    std = "c++14" if os.path.basename(f) in ("Tokens.cpp", "Art.cpp") else "c++17"
    return ["clang++", "-x", "c++", "-std=" + std, "-E", "-dD", "-w", "-fpermissive"] + CONFIGS[cfg] + [f]
PY
}

# ------------------------------------------------------------------ collect 1
collect_names() {
    write_cfg
    python3 - "$ROOT" "$W" <<'PY'
import os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
root, W = sys.argv[1:3]
sys.path.insert(0, W)
import nvcfg
jobs = [(c, f) for c in nvcfg.CONFIGS for f in nvcfg.units(root)]
DEF = re.compile(r"^#define\s+([A-Za-z_]\w*)(\(|\s|$)")
MARK = re.compile(r'^#\s+\d+\s+"([^"]*)"')
def run(job):
    cfg, f = job
    r = subprocess.run(nvcfg.cmd(cfg, f, root), cwd=root, capture_output=True, text=True, errors="replace")
    rows, cur, entered = set(), "<none>", set()
    for ln in r.stdout.split("\n"):
        if ln.startswith("# "):
            m = MARK.match(ln)
            if m:
                cur = m.group(1); entered.add(cur)
            continue
        m = DEF.match(ln)
        if m and m.group(2) != "(":
            rows.add((m.group(1), cur, cfg))
    return rows, entered, (f, cfg, r.returncode, r.stderr.strip().split("\n")[0] if r.returncode else "")
allrows, allentered, errs = set(), set(), []
with ThreadPoolExecutor(8) as ex:
    for rows, entered, st in ex.map(run, jobs):
        allrows |= rows; allentered |= entered
        if st[2]: errs.append(st)
def origin(path):
    if path.startswith("<built-in>"): return "builtin"
    if path.startswith("<command line>"): return "cmdline"
    p = os.path.normpath(path if os.path.isabs(path) else os.path.join(root, path))
    if p.startswith(root + os.sep):
        return "repo:" + os.path.relpath(p, root)
    return "system"
with open(W + "/cdefs.tsv", "w") as f:
    for n, p, c in sorted(allrows):
        f.write("%s\t%s\t%s\n" % (n, origin(p), c))
with open(W + "/cdefs.tsv.entered", "w") as f:
    for p in sorted({origin(x) for x in allentered}):
        f.write(p + "\n")
with open(W + "/cdefs.tsv.errs", "w") as f:
    for e in errs: f.write("%s [%s] rc=%d %s\n" % e)
PY
}

# ------------------------------------------------------------------ compare 1
compare_names() { # <dump>
    python3 - "$1" "$W" "$ROOT" <<'PY'
import collections, hashlib, os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
dump, W, root = sys.argv[1:4]
sys.path.insert(0, W)
import nvcfg
cdefs = W + "/cdefs.tsv"
dnames, dloc = set(), {}
for ln in open(dump):
    p = ln.rstrip("\n").split("\t")
    if len(p) < 4 or ln.startswith("#"): continue
    if p[0] == "define" or (p[0] == "unevaluated" and p[2].endswith("[define]")):
        dnames.add(p[1]); dloc.setdefault(p[1], set()).add(p[3])
byname = collections.defaultdict(set)   # name -> {(origin, config)}
for ln in open(cdefs):
    n, o, c = ln.rstrip("\n").split("\t")
    byname[n].add((o, c))
entered = {l.strip() for l in open(cdefs + ".entered")}
def in_repo_scope(o):   # the dump reads inc/ and src/ only
    return o.startswith("repo:inc/") or o.startswith("repo:src/")

def reached(cands):
    """Which (file, line) does the preprocessor reach in some config? Replace each
    candidate line with '#error', in an overlay copy of inc/ and src/, and
    preprocess every unit in every config: an #error that fires is a line reached."""
    key = hashlib.sha1(repr(sorted(cands)).encode()).hexdigest()[:12]
    cache = "%s/reach-%s.txt" % (W, key)
    if os.path.exists(cache):
        return {tuple(l.rstrip("\n").split("\t")) for l in open(cache)}
    ov = W + "/overlay"
    shutil.rmtree(ov, ignore_errors=True)
    for d in ("inc", "src", "lib", "compat", "libtcod"):
        if os.path.isdir(root + "/" + d):
            shutil.copytree(root + "/" + d, ov + "/" + d, symlinks=True) if d in ("inc", "src") else os.symlink(root + "/" + d, ov + "/" + d)
    bylines = collections.defaultdict(set)
    for f, l in cands: bylines[f].add(int(l))
    for f, ls in bylines.items():
        lines = open(ov + "/" + f, errors="replace").read().split("\n")
        for l in ls: lines[l - 1] = "#error NVREACH"
        open(ov + "/" + f, "w").write("\n".join(lines))
    jobs = [(c, f) for c in nvcfg.CONFIGS for f in nvcfg.units(ov)]
    pat = re.compile(r"^(\S+?):(\d+):\d+: error: NVREACH", re.M)
    def run(job):
        c, f = job
        r = subprocess.run(nvcfg.cmd(c, f, ov), cwd=ov, capture_output=True, text=True, errors="replace")
        out = set()
        for m in pat.finditer(r.stderr):
            p = os.path.normpath(m.group(1) if os.path.isabs(m.group(1)) else os.path.join(ov, m.group(1)))
            out.add((os.path.relpath(p, ov), m.group(2), c))
        return out
    res = set()
    with ThreadPoolExecutor(8) as ex:
        for o in ex.map(run, jobs): res |= o
    with open(cache, "w") as f:
        for t in sorted(res): f.write("\t".join(t) + "\n")
    shutil.rmtree(ov, ignore_errors=True)
    return res

cats = collections.OrderedDict()
bad = []
def put(cat, n): cats.setdefault(cat, []).append(n)
# compiler-only: in the preprocessed output, not in the dump
for n, occ in sorted(byname.items()):
    if n in dnames: continue
    build = {o for o, c in occ if c == "build"}
    tag = ""
    if not build:
        build = {o for o, c in occ}; tag = " (other config only)"
    repo_in = [o for o in build if in_repo_scope(o)]
    if repo_in:
        bad.append(("in compiler, not in dump", n, ",".join(sorted(repo_in))))
    elif any(o.startswith("repo:") for o in build):
        put("defined under compat/ or lib/ (outside the dump's inc/ src/ scope)" + tag, n)
    elif "builtin" in build or "cmdline" in build:
        put("compiler built-in or command-line define" + tag, n)
    elif "system" in build:
        put("system-header macro" + tag, n)
    else:
        bad.append(("in compiler, not in dump", n, str(sorted(build))))
# dump-only: in the dump, not in the build config's output
buildnames = {n for n, occ in byname.items() if any(c == "build" and in_repo_scope(o) for o, c in occ)}
cand = []
for n in sorted(dnames - buildnames):
    other = sorted({c for o, c in byname.get(n, ()) if in_repo_scope(o)})
    files = {x.rsplit(":", 1)[0] for x in dloc[n]}
    if other:
        put("defined in a branch the posix build does not take (taken under: %s)" % "+".join(other), n)
    elif not any(("repo:" + f) in entered for f in files):
        put("defining file is read by no translation unit in any configuration", n)
    else:
        for loc in dloc[n]:
            f, l = loc.rsplit(":", 1); cand.append((n, f, l))
if cand:
    hit = reached({(f, l) for n, f, l in cand})
    for n, f, l in cand:
        r = sorted({c for (ff, ll, c) in hit if ff == f and ll == l})
        if r: bad.append(("in dump, not in compiler", n, "%s:%s reached by the preprocessor under %s but no define seen" % (f, l, "+".join(r))))
        else: put("define line never reached by the preprocessor in any tried configuration (#error probe)", n)
print("part 1 names: dump %d define names; compiler build-config repo names %d" % (len(dnames), len(buildnames)))
for c, ns in cats.items():
    print("  allowlisted by rule: %-95s %5d" % (c, len(set(ns))))
if bad:
    for k, n, d in bad[:60]: print("  UNEXPLAINED: %s: %s %s" % (k, n, d))
    print("  UNEXPLAINED total: %d" % len(bad))
    print("problems: %d" % len(bad))
    print("FAIL part 1 (names)"); sys.exit(1)
print("  unexplained: none")
print("problems: 0")
print("PASS part 1 (names)")
PY
}

# ------------------------------------------------------------------ collect 2
collect_values() { # <dump>  -> $W/values.txt, $W/values.info
    python3 - "$1" "$W" <<'PY'
import os, re, subprocess, sys
dump, W = sys.argv[1:3]
names = {}
for ln in open(dump):
    p = ln.rstrip("\n").split("\t")
    if ln.startswith("#") or len(p) < 4: continue
    if p[0] in ("define", "enum"):
        names.setdefault((p[0], p[1]), 0)
hdrs = sorted(f for f in os.listdir("inc") if f.endswith(".h"))
skip_hdr = {"Incursion.h"}
flags0 = "-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -fpermissive -Wno-narrowing -w -std=c++17".split()
def hdr_ok(h):
    src = '#include "Incursion.h"\n#include "%s"\nint main(){return 0;}\n' % h
    r = subprocess.run(["clang++"] + flags0 + ["-fsyntax-only", "-x", "c++", "-"], input=src, capture_output=True, text=True)
    return h, r.returncode == 0
from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(8) as ex:
    ok = dict(ex.map(hdr_ok, [h for h in hdrs if h not in skip_hdr]))
hdrs = [h for h in hdrs if h in skip_hdr or ok.get(h)]
with open(os.path.join(W, "values.hdrs"), "w") as f:
    f.write("included: %s\nnot self-contained after Incursion.h: %s\n" % (" ".join(h for h in hdrs), " ".join(h for h in sorted(ok) if not ok[h])))
entries = sorted(names)
def build(ents):
    L = ['#include "Incursion.h"']
    for h in hdrs:
        if h not in skip_hdr:
            L.append('#if __has_include("%s")\n#include "%s"\n#endif' % (h, h))
    L.append('#include <cstdio>')
    L.append('#define NVP(n, v) printf("%s %lld\\n", n, (long long)(v))')
    L.append('int main() {')
    pos = {}
    cur = sum(x.count("\n") + 1 for x in L)
    for k, n in ents:
        if k == "define":
            t = '#ifdef %s\nNVP("%s", %s);\n#endif' % (n, n, n)
        else:
            t = 'NVP("%s", %s);' % (n, n)
        L.append(t)
        pos[(k, n)] = (cur + 1, cur + t.count("\n") + 1)
        cur += t.count("\n") + 1
    L.append('return 0; }')
    return L, pos
flags = "-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -fpermissive -Wno-narrowing -w -std=c++17 -ferror-limit=0".split()
cpp = os.path.join(W, "nv_values.cpp")
dropped = {}
for it in range(40):
    L, pos = build([e for e in entries if e not in dropped])
    open(cpp, "w").write("\n".join(L) + "\n")
    r = subprocess.run(["clang++"] + flags + ["-o", os.path.join(W, "nv_values"), cpp], capture_output=True, text=True)
    if r.returncode == 0: break
    bad_lines = {int(m.group(1)) for m in re.finditer(r"nv_values\.cpp:(\d+):\d+: error", r.stderr)}
    if not bad_lines:
        sys.stderr.write(r.stderr[-3000:]); print("COMPILE-FAILED-NO-LOCATION"); sys.exit(3)
    for e, (a, b) in pos.items():
        if e not in dropped and any(a <= l <= b for l in bad_lines):
            dropped[e] = "compile error"
else:
    sys.stderr.write(r.stderr[-3000:]); print("COMPILE-DID-NOT-CONVERGE"); sys.exit(3)
out = subprocess.run([os.path.join(W, "nv_values")], capture_output=True, text=True).stdout
open(os.path.join(W, "values.txt"), "w").write(out)
with open(os.path.join(W, "values.info"), "w") as f:
    for (k, n), why in sorted(dropped.items()):
        f.write("dropped\t%s\t%s\t%s\n" % (k, n, why))
    for (k, n) in entries:
        if (k, n) not in dropped: f.write("tried\t%s\t%s\t\n" % (k, n))
PY
}

# ------------------------------------------------------------------ compare 2
compare_values() { # <dump>
    python3 - "$1" "$W" <<'PY'
import collections, sys
dump, W = sys.argv[1:3]
dv = collections.defaultdict(set)
kinds = {}
for ln in open(dump):
    p = ln.rstrip("\n").split("\t")
    if ln.startswith("#") or len(p) < 4: continue
    if p[0] in ("define", "enum"):
        dv[p[1]].add(p[2]); kinds[(p[0], p[1])] = 1
printed = {}
for ln in open(W + "/values.txt"):
    n, v = ln.split()
    printed.setdefault(n, set()).add(v)
tried = dropped = 0
nd_def = nd_enum = 0
for ln in open(W + "/values.info"):
    t, k, n, _ = ln.rstrip("\n").split("\t")
    if t == "dropped":
        dropped += 1
        if k == "enum": nd_enum += 1
for (k, n) in kinds:
    pass
tot_def = sum(1 for k, n in kinds if k == "define")
tot_enum = sum(1 for k, n in kinds if k == "enum")
unreach_enum = sum(1 for k, n in kinds if k == "enum" and n not in printed)
undef_def = sum(1 for k, n in kinds if k == "define" and n not in printed)
# A name the compiler, the command line or a system header also defines in the
# build config has a compiler value the dump (inc/ and src/ text) does not own.
outside = set()
for ln in open(W + "/cdefs.tsv"):
    n, o, c = ln.rstrip("\n").split("\t")
    if c == "build" and (o in ("builtin", "cmdline", "system")): outside.add(n)
mism, expl = [], []
for n, vs in sorted(printed.items()):
    if not (vs <= dv[n]):
        (expl if n in outside else mism).append((n, sorted(vs), sorted(dv[n])))
print("part 2 values: dump %d defines + %d enum members; compiled and printed %d names" % (tot_def, tot_enum, len(printed)))
print("  defines not defined or not integer in the generated file (no compiler value): %d" % undef_def)
print("  enum members not reachable from the headers (local to a .cpp or a class): %d" % unreach_enum)
if expl:
    print("  allowlisted by rule: name also defined by the compiler, command line or a system header in the build config: %d (%s)"
          % (len(expl), ", ".join(e[0] for e in expl)))
if mism:
    for n, a, b in mism[:40]: print("  MISMATCH %s: compiler %s, dump %s" % (n, a, b))
    print("  mismatches: %d" % len(mism)); print("problems: %d" % len(mism)); print("FAIL part 2 (values)"); sys.exit(1)
print("  mismatches: none")
print("problems: 0")
print("PASS part 2 (values)")
PY
}

# ------------------------------------------------------------------ collect 4
# Part 4, the backward direction (inc-cjos0): start from real save files and
# prove the reader takes every one. Each save is loaded by the game's own reader
# through tools/dump_save.sh (-dump). With INCURSION_TAG_SCAN set, the reader
# (src/SaveV1.cpp v1Find) logs "<owner scope> <tag> <kind> <file:line of the
# field list that asked for it>" for every field the file holds that a field
# list asked for. The reader refuses a field no list asks for (ECORRUPT, the
# "carries field" message), so a successful load means every field in the file
# is one this build asks for. For a revision 7 file the tag is a number local to
# that file's own name table; only revisions 3-6 use the numbers of
# inc/SaveLegacyTags.h, and part 5 maps those.
# An SCAN_GEN entry is <key script>:<seed> or <key script>:<seed>:<fixture to load>.
SCAN_GEN="smoke:1 dive:1 dive-depth-10:2 dive12:1 explore-mage:1 explore-rogue:1 explore-priest:1 stair-cycle:1 spook-ally-save:1 chargen-default-store-save:1 chargen-mage-save:1 marathon:1 followers:3362 terra-save:1:tools/fixtures/chars/elf-mage-illusions-seed1.sav"
# Saves of a format the v1 reader never reads (path:stamp in the file's own header).
KNOWN_UNREAD="docs/evidence/inc-upw.13/Furious_Fox.sav:SF0F7B6EDC docs/evidence/inc-upw.13/Jaoin.sav:0.6.9Y19"
save_stamp() { dd if="$1" bs=1 skip=4 count=12 2>/dev/null | tr -d '\0'; }
scan_one() { # <label> <sav> : appends a manifest row
    local label="$1" sav="$2" n; n="$(wc -l < "$W/scan/manifest.tsv" | tr -d ' ')"
    local out="$W/scan/$n.txt" err="$W/scan/$n.err" st rc
    st="$(save_stamp "$sav")"
    : > "$out"
    INCURSION_TAG_SCAN="$out" ./tools/dump_save.sh "$sav" > /dev/null 2> "$err"; rc=$?
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$sav" "$st" "$rc" "$out" "$err" >> "$W/scan/manifest.tsv"
}
collect_scan() {
    [ -x ./incursion-headless ] || { echo "FAIL: ./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"; return 1; }
    mkdir -p "$W/scan"; : > "$W/scan/manifest.tsv"
    local f
    for f in tools/fixtures/chars/*.sav docs/evidence/inc-upw.13/*.sav docs/evidence/inc-x1f3/*.sav; do
        scan_one "file:$f" "$f"
    done
    local item k seed d rest fix
    for item in $SCAN_GEN; do
        k="${item%%:*}"; rest="${item#*:}"; seed="${rest%%:*}"; fix=""
        [ "$rest" != "$seed" ] && fix="${rest#*:}"
        d="$W/gen/$k-$seed"
        if [ -n "$fix" ]; then
            INCURSION_LOAD="$fix" INCURSION_RUN_DIR="$d" INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
                ./tools/headless.sh "tools/keys/$k.keys" "$seed" > "$W/gen-$k-$seed.log" 2>&1 < /dev/null
        else
            INCURSION_RUN_DIR="$d" INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
                ./tools/headless.sh "tools/keys/$k.keys" "$seed" > "$W/gen-$k-$seed.log" 2>&1 < /dev/null
        fi
        f="$(ls "$d"/save/*.sav 2>/dev/null | head -1)"
        if [ -z "$f" ]; then echo "FAIL: key script $k seed $seed wrote no save"; return 1; fi
        scan_one "gen:$k:$seed" "$f"
    done
}

# ------------------------------------------------------------------ compare 4
compare_scan() { # [manifest] [need: 1 = the full manifest, so the named-unread saves and the TerraRecord save must be in it]
    python3 - "${1:-$W/scan/manifest.tsv}" "${2:-1}" "$ROOT" "$KNOWN_UNREAD" <<'PY'
import collections, os, sys
manifest, need, root, known = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4].split()
unread = dict(k.rsplit(":", 1) for k in known)       # path -> stamp
nlines = {}
def src_lines(f):
    if f not in nlines:
        try: nlines[f] = len(open(os.path.join(root, f), errors="replace").read().split("\n"))
        except OSError: nlines[f] = 0
    return nlines[f]
problems = 0
fmt = collections.Counter(); loaded = 0; nfields = 0
sites = set(); terra = set(); unread_seen = set()
for ln in open(manifest):
    label, sav, stamp, rc, scanf, errf = ln.rstrip("\n").split("\t")
    src = "evidence" if label.startswith("file:docs/") else ("fixture" if label.startswith("file:") else "generated")
    fmt[(src, stamp)] += 1
    path = label[5:] if label.startswith("file:") else None
    if not stamp.startswith("IS1."):
        # a v0 memory image or an unstamped file: the v1 reader never reads it; it must be named
        if path in unread and unread[path] == stamp:
            unread_seen.add(path)
        else:
            print("  FAIL unread format: %s has stamp %r and is not named in KNOWN_UNREAD" % (label, stamp)); problems += 1
        continue
    if path in unread:
        print("  FAIL KNOWN_UNREAD names %s, but its stamp is now %s: remove it from the list" % (path, stamp)); problems += 1
    if rc != "0":
        err = open(errf, errors="replace").read().strip().split("\n")
        print("  FAIL load: %s (%s) was refused, exit %s: %s" % (label, stamp, rc, " | ".join(err[-2:])))
        problems += 1
        continue
    loaded += 1
    n = 0
    for sl in open(scanf):
        p = sl.split()
        if len(p) != 4 or not p[1].isdigit() or not p[2].isdigit() or ":" not in p[3]:
            print("  FAIL scan line of %s is not '<scope> <tag> <kind> <file:line>': %r" % (label, sl.strip()[:80])); problems += 1; continue
        s, t, k, fl = p
        f, l = fl.rsplit(":", 1)
        if not l.isdigit() or not (1 <= int(l) <= src_lines(f)):
            print("  FAIL scan line of %s names %s, which is not a line of the source" % (label, fl)); problems += 1; continue
        n += 1; sites.add((s, fl))
        if s == "TerraRecord" and label.startswith("gen:terra-save"): terra.add(int(t))
    nfields += n
    if n == 0:
        print("  FAIL scan log of %s (%s) is empty: a loaded save holds fields" % (label, stamp)); problems += 1
if need:
    for path in sorted(set(unread) - unread_seen):
        print("  FAIL KNOWN_UNREAD names %s, which is not in the scanned saves" % path); problems += 1
    if not terra:
        print("  FAIL the TerraRecord save (gen:terra-save) logged no TerraRecord field"); problems += 1
print("part 4 saves: %d loaded (%s); %d of a format the v1 reader never reads, named in KNOWN_UNREAD" % (
    loaded, ", ".join("%s %s=%d" % (a, b, c) for (a, b), c in sorted(fmt.items()) if b.startswith("IS1.")), len(unread_seen)))
print("  fields logged: %d, at %d distinct (owner, reading line) sites" % (nfields, len(sites)))
print("  TerraRecord seen: %s" % ("yes, %d fields (tags %s)" % (len(terra), ",".join(map(str, sorted(terra)))) if terra else "no"))
print("problems: %d" % problems)
if problems: print("FAIL part 4 (saves)"); sys.exit(1)
print("PASS part 4 (saves)")
PY
}

# ------------------------------------------------------------------ compare 5
# Part 5 (inc-cjos0 phase 1): the frozen legacy table inc/SaveLegacyTags.h names every
# tag the scanned saves hold. tools/gen_legacy_tags.py --verify-scan reads the part 4
# manifest; the header must also compile.
compare_legacy() { # [header] [manifest]
    local hdr="${1:-inc/SaveLegacyTags.h}" mf="${2:-$W/scan/manifest.tsv}" rc=0
    local abs="$hdr"; case "$hdr" in /*) ;; *) abs="$ROOT/$hdr" ;; esac
    mkdir -p "$W/legacy"
    printf '#include "%s"\nint main() { return (int)(LEGACY_TAG_ROW_COUNT + LEGACY_TAG_RANGE_COUNT); }\n' "$abs" > "$W/legacy/tu.cpp"
    if ! "$CXX" -std=c++17 -fsyntax-only "$W/legacy/tu.cpp" 2> "$W/legacy/cc.err"; then
        head -5 "$W/legacy/cc.err"; echo "  the header does not compile"; echo "problems: 1"; echo "FAIL part 5 (legacy table)"; return 1
    fi
    python3 tools/gen_legacy_tags.py --verify-scan "$hdr" "$mf" || rc=1
    [ "$rc" = 0 ] && echo "PASS part 5 (legacy table)" || echo "FAIL part 5 (legacy table)"
    return "$rc"
}

# Plant one extra tag (60000, K_U8) at the head of the first record of a v1 save,
# for the selftest. Pure stdlib: it follows the container in docs/ENGINE-SERIALISATION.md.
plant_tag() { # <in.sav> <out.sav>
    python3 - "$1" "$2" <<'PY'
import struct, sys, zlib
b = bytearray(open(sys.argv[1], "rb").read())
numGroups, comp = struct.unpack_from("<hh", b, 88)
assert b[4:8] == b"IS1." and numGroups == 1, "need a one-group v1 save"
off = 96
sig, h, gsize, csize, objc, datac, last = struct.unpack_from("<IiiiiiI", b, off)
pay = b[off + 28: off + 28 + (csize if comp else gsize)]
raw = bytearray(zlib.decompress(pay) if comp else pay)
assert len(raw) == gsize
typ, handle, length = struct.unpack_from("<BII", raw, 0)
raw[9:9] = struct.pack("<HBB", 60000, 1, 7)          # a tag no class owns, kind K_U8, value 7
struct.pack_into("<I", raw, 5, length + 4)
newpay = zlib.compress(bytes(raw), 6) if comp else bytes(raw)
struct.pack_into("<ii", b, off + 8, len(raw), len(newpay) if comp else csize)
out = bytes(b[:off + 28]) + newpay + bytes(b[off + 28 + len(pay):])
open(sys.argv[2], "wb").write(out)
PY
}

# ------------------------------------------------------------------ run
if [ "$MODE" = check ]; then
    FAILED=0
    collect_names; compare_names "$DUMP" || FAILED=1
    collect_values "$DUMP" || FAILED=1; compare_values "$DUMP" || FAILED=1
    if collect_scan; then compare_scan || FAILED=1; compare_legacy || FAILED=1; else FAILED=1; fi
    [ "$FAILED" = 0 ] && echo "PASS all parts" || echo "FAIL"
    exit "$FAILED"
fi

# ---- selftest: every part must pass on the real dump, then go red on a damaged copy
echo "selftest: collecting on the real dump"
collect_names; collect_values "$DUMP"
collect_scan || exit 1
ST=0
problems() { "$@" 2>&1 | sed -n 's/^problems: //p'; }
redcheck() { # <label> <fn> <dump-real> <dump-damaged>
    local base dmg
    base="$(problems "$2" "$3")"; dmg="$(problems "$2" "$4")"
    if [ -n "$base" ] && [ -n "$dmg" ] && [ "$dmg" -gt "$base" ]; then
        echo "ok: $1 goes red (problems $base on the real dump, $dmg on the damaged copy)"
    else
        echo "SELFTEST FAIL: $1 (problems $base real, $dmg damaged; wanted damaged > real)"; ST=1
    fi
}
echo "real-dump results (a nonzero problem count here is a finding about the dump, not a selftest failure):"
for f in compare_names compare_values; do echo "  $f: problems $(problems $f "$DUMP")"; done
echo "  compare_scan: problems $(problems compare_scan)"
echo "  compare_legacy: problems $(problems compare_legacy)"
VICTIM="$(awk -F'\t' '$1=="define" && $4 ~ /^inc\/Defines\.h/ {print $2; exit}' "$DUMP")"
[ -n "$VICTIM" ] || { echo "SELFTEST FAIL: no define from inc/Defines.h in the dump"; exit 1; }
# part 1: hide one define the compiler has
grep -v "^define	$VICTIM	" "$DUMP" > "$W/dump-hidden.txt"
redcheck "part 1 with define $VICTIM hidden from the dump" compare_names "$DUMP" "$W/dump-hidden.txt"
# part 2: change one value
awk -F'\t' -v OFS='\t' -v v="$VICTIM" '$1=="define" && $2==v {$3=$3+7} {print}' "$DUMP" > "$W/dump-changed.txt"
redcheck "part 2 with the value of $VICTIM changed in the dump" compare_values "$DUMP" "$W/dump-changed.txt"
# part 4, planted tag: a copy of one generated save with tag 60000 added to its first record must go red
PSRC="$(ls "$W"/gen/smoke-1/save/*.sav | head -1)"
plant_tag "$PSRC" "$W/planted.sav" || { echo "SELFTEST FAIL: could not plant a tag"; ST=1; }
printf 'clean\t%s\t%s\t0\t%s\t%s\n' "$PSRC" "$(save_stamp "$PSRC")" "$W/scan/clean.txt" "$W/scan/clean.err" > "$W/scan/m-clean.tsv"
: > "$W/scan/clean.txt"; INCURSION_TAG_SCAN="$W/scan/clean.txt" ./tools/dump_save.sh "$PSRC" >/dev/null 2> "$W/scan/clean.err"
printf 'planted\t%s\t%s\t' "$W/planted.sav" "$(save_stamp "$W/planted.sav")" > "$W/scan/m-planted.tsv"
: > "$W/scan/planted.txt"; INCURSION_TAG_SCAN="$W/scan/planted.txt" ./tools/dump_save.sh "$W/planted.sav" >/dev/null 2> "$W/scan/planted.err"; PRC=$?
printf '%s\t%s\t%s\n' "$PRC" "$W/scan/planted.txt" "$W/scan/planted.err" >> "$W/scan/m-planted.tsv"
base="$(problems compare_scan "$W/scan/m-clean.tsv" 0)"; dmg="$(problems compare_scan "$W/scan/m-planted.tsv" 0)"
if [ "$base" = 0 ] && [ -n "$dmg" ] && [ "$dmg" -gt 0 ]; then
    echo "ok: part 4 with tag 60000 planted in a copy of a save goes red (problems $base on the clean copy, $dmg on the planted copy; $(compare_scan "$W/scan/m-planted.tsv" 0 2>&1 | grep -m1 'FAIL load' | cut -c1-200))"
else
    echo "SELFTEST FAIL: part 4 planted tag (problems $base clean, $dmg planted; wanted 0 and > 0)"; ST=1
fi
# part 4, load refused: the same clean row with a nonzero load result
sed 's/\t0\t/\t1\t/' "$W/scan/m-clean.tsv" > "$W/scan/m-refused.tsv"
base="$(problems compare_scan "$W/scan/m-clean.tsv" 0)"; dmg="$(problems compare_scan "$W/scan/m-refused.tsv" 0)"
if [ "$base" = 0 ] && [ -n "$dmg" ] && [ "$dmg" -gt 0 ]; then echo "ok: part 4 with a save whose load exit is 1 goes red (problems $base clean, $dmg refused)"
else echo "SELFTEST FAIL: part 4 refused load (problems $base clean, $dmg refused; wanted 0 and > 0)"; ST=1; fi
# part 4, empty scan log: a loaded save logs fields
: > "$W/scan/empty.txt"; sed "s|$W/scan/clean.txt|$W/scan/empty.txt|" "$W/scan/m-clean.tsv" > "$W/scan/m-empty.tsv"
dmg="$(problems compare_scan "$W/scan/m-empty.tsv" 0)"
if [ -n "$dmg" ] && [ "$dmg" -gt 0 ]; then echo "ok: part 4 with an empty scan log goes red (problems $dmg)"
else echo "SELFTEST FAIL: part 4 empty scan log (problems $dmg; wanted > 0)"; ST=1; fi
# part 4, an unnamed unread format: the stamp of the clean row changed to one nobody named
sed 's/\tIS1\.[0-9]*\t/\tSFDEADBEEF\t/' "$W/scan/m-clean.tsv" > "$W/scan/m-unnamed.tsv"
dmg="$(problems compare_scan "$W/scan/m-unnamed.tsv" 0)"
if [ -n "$dmg" ] && [ "$dmg" -gt 0 ]; then echo "ok: part 4 with a save of an unnamed unread format goes red (problems $dmg)"
else echo "SELFTEST FAIL: part 4 unnamed format (problems $dmg; wanted > 0)"; ST=1; fi
# part 4, TerraRecord: the real manifest with the terra save's scan stripped of its TerraRecord lines
TROW="$(grep -n 'gen:terra-save' "$W/scan/manifest.tsv" | head -1 | cut -d: -f1)"
[ -n "$TROW" ] || { echo "SELFTEST FAIL: no terra-save row in the manifest"; ST=1; TROW=1; }
TSCAN="$(sed -n "${TROW}p" "$W/scan/manifest.tsv" | cut -f5)"
grep -v '^TerraRecord ' "$TSCAN" > "$W/scan/terra-stripped.txt"
sed "${TROW}s|$TSCAN|$W/scan/terra-stripped.txt|" "$W/scan/manifest.tsv" > "$W/scan/m-noterra.tsv"
redcheck "part 4 with the TerraRecord fields stripped from the terra-save scan" compare_scan "$W/scan/manifest.tsv" "$W/scan/m-noterra.tsv"
# part 5: pick an Item tag that a revision 3-6 save holds and one fixed header row names
TN="$(python3 - "$W/scan/manifest.tsv" inc/SaveLegacyTags.h <<'PY'
import re, sys
held = set()
for ln in open(sys.argv[1]):
    label, sav, stamp, rc, scanf, errf = ln.rstrip("\n").split("\t")
    m = re.fullmatch(r"IS1\.(\d+)", stamp)
    if rc != "0" or not m or int(m.group(1)) > 6: continue
    for sl in open(scanf):
        s, t = sl.split()[:2]
        if s == "Item": held.add(int(t))
txt = open(sys.argv[2]).read()
rng = [(int(a), int(b)) for a, b in re.findall(r'^\s*\{ "Item[^"]*", (\d+), (\d+), "', txt, re.M)]
fixed = [int(x) for x in re.findall(r'^\s*\{ "Item[^"]*", (\d+), "[^"]*", \d+, \d+ \}', txt, re.M)]
for t in sorted(held):
    if fixed.count(t) == 1 and not any(a <= t < a + c for a, c in rng):
        print(t); break
PY
)"
[ -n "$TN" ] || { echo "SELFTEST FAIL: no Item tag is both held by a revision 3-6 save and named by one fixed row"; ST=1; TN=0; }
# part 5: drop the legacy row of one Item tag the saves hold; the real header must name every tag, the damaged copy must not
grep -v "^  { \"Item\", $TN, " inc/SaveLegacyTags.h > "$W/legacy-dropped.h"
if cmp -s inc/SaveLegacyTags.h "$W/legacy-dropped.h"; then echo "SELFTEST FAIL: part 5 found no Item row $TN in the header to drop"; ST=1
else
    mkdir -p "$W/legacy"; cp "$W/legacy-dropped.h" "$W/legacy/dropped.h"
    redcheck "part 5 with the legacy row of Item tag $TN dropped from the header" compare_legacy inc/SaveLegacyTags.h "$W/legacy/dropped.h"
fi
python3 tools/gen_legacy_tags.py --selftest > "$W/legacy-selftest.log" 2>&1 && echo "ok: tools/gen_legacy_tags.py --selftest passes (each refusal goes red on a damaged table)" \
    || { tail -3 "$W/legacy-selftest.log"; echo "SELFTEST FAIL: tools/gen_legacy_tags.py --selftest"; ST=1; }
[ "$ST" = 0 ] && echo "SELFTEST PASS" || echo "SELFTEST FAIL"
exit "$ST"
