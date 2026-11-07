#!/bin/bash
# gate: none heavy; needs clang and a posix build (BACKEND=posix ./build_macos.sh); run by hand
# fact: source tree -- the working tree this script runs in; the dump and the compiler both read it, nothing else
# fact: compiler flags -- the posix flags of build_macos.sh (-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -std=c++17 -fpermissive), copied here, plus three alternate configs only to explain names
# fact: character and world -- fixture options tools/fixtures/options-2026-08-22.dat; key script tools/keys/smoke.keys; seed 1 pinned for the runtime tag probe (inc-cjos0). The seed only decides which records get written, and the check asserts a subset (runtime tags in dump), which holds for any seed
# fact: saved files scanned by part 4 -- the committed fixtures tools/fixtures/chars/*.sav (frozen bytes), docs/evidence/inc-upw.13 and inc-x1f3 (frozen bytes), plus fresh saves from the key scripts in SCAN_GEN at the seeds named there, all run with options tools/fixtures/options-2026-08-22.dat; the assertion is "every tag in a loaded file has a dump row", which holds for any seed, while the coverage count (reported, never asserted) depends on them
# fact: reader behavior on an unknown tag -- Registry::LoadGroupV1 refuses a tag no field list asks for (v1PopFrame, ECORRUPT); the planted-tag selftest proves it on this build
# fact: save revision -- the build under test (incursion-headless built from this tree)
# fact: legacy tag table -- inc/SaveLegacyTags.h, committed and frozen (generated once from master by tools/gen_legacy_tags.py); part 5 reads it and nothing else of the tag numbers
# fact: revision of a scanned file -- the IS1.<n> stamp in the file's own header bytes; fixtures and evidence are frozen bytes, generated saves carry this build's SCHEMA_REV
#
# Cross-checks tools/number_values.py (the "dump") by methods that share no
# parsing code with it (inc-cjos0):
#   1. NAMES   the real preprocessor (clang -E -dD) vs the dump's define names
#   2. VALUES  a generated C++ file, compiled and run, prints every dumped
#              define and enum member; compared with the dump
#   3. TAGS    INCURSION_TAG_PROBE=<file> in the save writer lists every
#              (scope, tag) a real session writes; each must be in the dump
#   4. SAVES   every tag in a real save file traces to a dump row
#   5. LEGACY  every tag in those saves maps to exactly one name through the frozen
#              table inc/SaveLegacyTags.h, by the save's own revision (inc-cjos0 phase 1)
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

# ------------------------------------------------------------------ collect 3
collect_tags() {
    [ -x ./incursion-headless ] || { echo "FAIL: ./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"; return 1; }
    : > "$W/probe.txt"
    INCURSION_TAG_PROBE="$W/probe.txt" INCURSION_RUN_DIR="$W/run1" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        ./tools/headless.sh tools/keys/smoke.keys 1 > "$W/s1.log" 2>&1 < /dev/null \
        || { tail -10 "$W/s1.log"; echo "FAIL: session 1 exited non-zero"; return 1; }
    local sv; sv="$(ls "$W"/run1/save/*.sav 2>/dev/null | head -1)"
    [ -n "$sv" ] || { echo "FAIL: session 1 wrote no save"; return 1; }
    mkdir -p "$W/run2/save"; cp "$sv" "$W/run2/save/"
    INCURSION_TAG_PROBE="$W/probe.txt" INCURSION_RUN_DIR="$W/run2" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        ./tools/headless.sh tools/keys/loadsave.keys 1 > "$W/s2.log" 2>&1 < /dev/null \
        || { tail -10 "$W/s2.log"; echo "FAIL: load-and-save session exited non-zero"; return 1; }
    [ -s "$W/probe.txt" ] || { echo "FAIL: the tag probe wrote nothing (is incursion-headless built from this tree?)"; return 1; }
}

# ------------------------------------------------------------------ compare 3
compare_tags() { # <dump>
    python3 - "$1" "$W/probe.txt" "$ROOT" <<'PY'
import collections, re, sys
dump, probe, root = sys.argv[1:4]
# Runtime scope = nearest enclosing ARCHIVE_CLASS / FieldsV1 owner, set by the
# probe; dump scope = nearest earlier ARCHIVE_CLASS(Name) or Name::FieldsV1 in
# the file. Template Array<S>::FieldsV1 has no class name in the dump: "?".
MAP = {"Array": "?"}
drows = collections.defaultdict(list)   # (file, value) -> [(line, scope, identity)]
dscopes = collections.Counter()
for ln in open(dump):
    p = ln.rstrip("\n").split("\t")
    if ln.startswith("#") or len(p) < 4 or p[0] != "tag": continue
    f, l = p[3].rsplit(":", 1)
    drows[(f, int(p[2]))].append((int(l), p[1].split(".", 1)[0], p[1]))
ndump = sum(len(v) for v in drows.values())
sites = collections.defaultdict(lambda: collections.defaultdict(set))   # (file,line) -> tag -> scopes
nwrites = 0
for ln in open(probe):
    s, t, fl = ln.split()
    f, l = fl.rsplit(":", 1)
    sites[(f, int(l))][int(t)].add(s); nwrites += 1
srccache = {}
def stmt_text(f, l):
    if f not in srccache:
        try: srccache[f] = open(root + "/" + f, errors="replace").read().split("\n")
        except OSError: srccache[f] = []
    L = srccache[f]
    lo = l - 1
    while lo > 0 and l - lo < 4 and not re.search(r"[;{}]\s*$", L[lo - 1]):
        lo -= 1
    return " ".join(L[max(lo - 1, 0):l])
IDX = re.compile(r"(V1\w+|FIELD_\w+)\s*\(\s*\(\s*uint16\s*\)")
# An index tag written through a macro: the write site is a macro invocation.
# Read that macro's #define body from the source (not the dump); the tag is an
# index tag only if the body has a (uint16)(k + i) tag with k <= the tag value.
IDXBASE = re.compile(r"(?:V1\w+|FIELD_\w+)\s*\(\s*\(\s*uint16\s*\)\s*\(\s*(\d+)\s*\+")
srcfiles = None
macro_cache = {}
def macro_bases(name):
    global srcfiles
    if name in macro_cache: return macro_cache[name]
    if srcfiles is None:
        import glob
        srcfiles = glob.glob(root + "/inc/*.h") + glob.glob(root + "/src/*.cpp") + glob.glob(root + "/src/*.c")
    out = []
    rx = re.compile(r"^[ \t]*#[ \t]*define[ \t]+" + re.escape(name) + r"\b((?:\\\n|[^\n])*)", re.M)
    for f in srcfiles:
        for m in rx.finditer(open(f, errors="replace").read()):
            out += [int(b) for b in IDXBASE.findall(m.group(1).replace("\\\n", " "))]
    macro_cache[name] = out
    return out
def macro_index_tag(text, t):
    return any(b <= t for n in re.findall(r"\b([A-Za-z_]\w*)\s*\(", text) for b in macro_bases(n))
seen = set(); matched = 0; indexed = []; missing = []
scope_ok = scope_diff = 0; pairs = collections.Counter()
for (f, l), tags in sorted(sites.items()):
    for t, scopes in sorted(tags.items()):
        hit = [r for r in drows.get((f, t), []) if 0 <= l - r[0] <= 3]
        if hit:
            matched += 1
            for r in hit: seen.add((f, t, r[0]))
            ds = {r[1] for r in hit}
            for sc in scopes:
                if MAP.get(sc, sc) in ds or (sc == "Map" and "MapGrid" in ds): scope_ok += 1
                else: scope_diff += 1; pairs[(sc, "/".join(sorted(ds)))] += 1
        elif IDX.search(stmt_text(f, l)) or macro_index_tag(stmt_text(f, l), t):
            indexed.append((f, l, t))
        else:
            missing.append((f, l, t, sorted(scopes)))
unseen = [(f, t, l, sc, i) for (f, t), rs in drows.items() for (l, sc, i) in rs if (f, t, l) not in seen]
by = collections.Counter(u[3] for u in unseen)
nsites = len(sites)
print("part 3 tags: %d write sites (file:line) seen at runtime, %d writes; dump holds %d tag rows" % (nsites, nwrites, ndump))
print("  runtime (site, tag) matched to a dump row by file, value and line: %d" % matched)
print("  runtime tags whose call has a (uint16)(...) index expression as its tag (no literal to list): %d tags at %d sites"
      % (len(indexed), len({(f, l) for f, l, t in indexed})))
print("  scope check on matched tags: runtime scope agrees with dump scope %d, differs %d" % (scope_ok, scope_diff))
for (a, b), c in pairs.most_common(5): print("    scope differs: runtime %s, dump %s: %d" % (a, b, c))
print("  dump tags never seen at runtime: %d (read-only migration tags and unreached records); largest scopes: %s"
      % (len(unseen), ", ".join("%s=%d" % kv for kv in by.most_common(5))))
for f, l, t, sc in missing[:40]: print("  MISSING from dump: %s:%d tag %d (runtime scope %s)" % (f, l, t, "/".join(sc)))
print("  runtime tags missing from dump: %d" % len(missing) if missing else "  runtime tags missing from dump: none")
print("problems: %d" % len(missing))
if missing: print("FAIL part 3 (tags)"); sys.exit(1)
print("PASS part 3 (tags)")
PY
}

# ------------------------------------------------------------------ collect 4
# Part 4, the backward direction (inc-cjos0): start from real save files and
# prove every tag in them traces to a dump row. Each save is loaded by the
# game's own reader through tools/dump_save.sh (-dump). With INCURSION_TAG_SCAN
# set, the reader (src/SaveV1.cpp v1Find) logs "<owner scope> <tag> <kind>
# <file:line of the field list that asked for it>" for every tag the file holds.
# The reader already refuses a tag no field list asks for (ECORRUPT), so a
# successful load means every tag in the file was asked for by some line.
SCAN_GEN="smoke:1 dive:1 dive-depth-10:2 dive12:1 explore-mage:1 explore-rogue:1 explore-priest:1 stair-cycle:1 spook-ally-save:1 chargen-default-store-save:1 chargen-mage-save:1 marathon:1 followers:3362"
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
    local item k seed d
    for item in $SCAN_GEN; do
        k="${item%%:*}"; seed="${item##*:}"; d="$W/gen/$k-$seed"
        INCURSION_RUN_DIR="$d" INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
            ./tools/headless.sh "tools/keys/$k.keys" "$seed" > "$W/gen-$k-$seed.log" 2>&1 < /dev/null
        f="$(ls "$d"/save/*.sav 2>/dev/null | head -1)"
        if [ -z "$f" ]; then echo "FAIL: key script $k seed $seed wrote no save"; return 1; fi
        scan_one "gen:$k:$seed" "$f"
    done
}

# ------------------------------------------------------------------ compare 4
compare_scan() { # <dump> [manifest]
    python3 - "$1" "${2:-$W/scan/manifest.tsv}" "$ROOT" <<'PY'
import collections, re, sys
dump, manifest, root = sys.argv[1:4]
drows = collections.defaultdict(list)   # (file, value) -> [(line, scope, identity)]
for ln in open(dump):
    p = ln.rstrip("\n").split("\t")
    if ln.startswith("#") or len(p) < 4 or p[0] != "tag": continue
    f, l = p[3].rsplit(":", 1)
    drows[(f, int(p[2]))].append((int(l), p[1].split(".", 1)[0], p[1]))
ndump = sum(len(v) for v in drows.values())
srccache = {}
def stmt_text(f, l):
    if f not in srccache:
        try: srccache[f] = open(root + "/" + f, errors="replace").read().split("\n")
        except OSError: srccache[f] = []
    L = srccache[f]; lo = l - 1
    while lo > 0 and l - lo < 4 and not re.search(r"[;{}]\s*$", L[lo - 1]):
        lo -= 1
    return " ".join(L[max(lo - 1, 0):l])
IDX = re.compile(r"(V1\w+|FIELD_\w+)\s*\(\s*\(\s*uint16\s*\)")
IDXBASE = re.compile(r"(?:V1\w+|FIELD_\w+)\s*\(\s*\(\s*uint16\s*\)\s*\(\s*(\d+)\s*\+")
srcfiles = None; macro_cache = {}
def macro_bases(name):
    global srcfiles
    if name in macro_cache: return macro_cache[name]
    if srcfiles is None:
        import glob
        srcfiles = glob.glob(root + "/inc/*.h") + glob.glob(root + "/src/*.cpp") + glob.glob(root + "/src/*.c")
    out = []
    rx = re.compile(r"^[ \t]*#[ \t]*define[ \t]+" + re.escape(name) + r"\b((?:\\\n|[^\n])*)", re.M)
    for f in srcfiles:
        for m in rx.finditer(open(f, errors="replace").read()):
            out += [int(b) for b in IDXBASE.findall(m.group(1).replace("\\\n", " "))]
    macro_cache[name] = out
    return out
def is_index(f, l, t):
    text = stmt_text(f, l)
    return bool(IDX.search(text)) or any(b <= t for n in re.findall(r"\b([A-Za-z_]\w*)\s*\(", text) for b in macro_bases(n))
WILD = {"?"}            # dump scope of a template (Array<S>) or a hand-written reader line
problems = 0
fmt = collections.Counter(); bysrc = collections.Counter()
seen_rows = set(); first = {}            # (scope, tag, file, line) -> first save label
nfiles = 0; allscans = set()
for ln in open(manifest):
    label, sav, stamp, rc, scanf, errf = ln.rstrip("\n").split("\t")
    src = "evidence" if label.startswith("file:docs/") else ("fixture" if label.startswith("file:") else "generated")
    fmt[(src, stamp)] += 1
    if not stamp.startswith("IS1."):
        # v0 memory image or an unstamped file: it holds no tags, so there is nothing to trace
        continue
    nfiles += 1
    if rc != "0":
        err = open(errf, errors="replace").read().strip().split("\n")
        print("  FAIL load: %s (%s) was refused, exit %s: %s" % (label, stamp, rc, " | ".join(err[-2:])))
        problems += 1
        continue
    for sl in open(scanf):
        s, t, k, fl = sl.split()
        allscans.add((s, int(t), fl, label))
agg = {}
for s, t, fl, label in allscans:
    key = (s, t, fl)
    if key not in agg: agg[key] = label
    elif label < agg[key]: agg[key] = label
matched = idx = wild = 0; scope_bad = []; missing = []
hits_rows = set()
for (s, t, fl), label in sorted(agg.items()):
    f, l = fl.rsplit(":", 1); l = int(l)
    rows = [r for r in drows.get((f, t), []) if 0 <= l - r[0] <= 3]
    if rows:
        ok = [r for r in rows if r[1] == s or (s == "Map" and r[1] == "MapGrid")]   # runtime scope of GridFieldsV1 is still Map until inc-cjos0 phase 2
        if not ok: ok = [r for r in rows if r[1] in WILD or s == "Array"]; wild += bool(ok)
        if ok:
            matched += 1
            for r in ok: hits_rows.add((f, t, r[0], r[1]))
        else:
            scope_bad.append((s, t, fl, label, "/".join(sorted({r[1] for r in rows}))))
    elif is_index(f, l, t):
        idx += 1
    else:
        missing.append((s, t, fl, label))
print("part 4 tags: %d v1 saves loaded (%s)" % (nfiles, ", ".join("%s %s=%d" % (a, b, c) for (a, b), c in sorted(fmt.items()) if c)))
print("  distinct (owner, tag, reading line) in those saves: %d" % len(agg))
print("  matched to a dump row by file, value, line and owner: %d (of which %d through a '?' wildcard owner: Array<T> or hand-written reader)" % (matched, wild))
print("  index tags traced to a (uint16)(k+i) loop site: %d" % idx)
for s, t, fl, label, ds in scope_bad[:40]:
    print("  OWNER DIFFERS: %s tag %d read at %s (first in %s): dump owner %s" % (s, t, fl, label, ds))
for s, t, fl, label in missing[:40]:
    print("  NO SOURCE ROW: owner %s tag %d read at %s, first in %s" % (s, t, fl, label))
problems += len(scope_bad) + len(missing)
# coverage: dump tag rows (literal tags) that appear in at least one save
allrows = {(f, v, l, sc): ident for (f, v), rs in drows.items() for (l, sc, ident) in rs}
unseen = [(ident, f, v, l) for (f, v, l, sc), ident in allrows.items() if (f, v, l, sc) not in hits_rows]
print("  coverage: %d of %d dump tag rows appear in at least one save; %d appear in none" % (len(allrows) - len(unseen), len(allrows), len(unseen)))
by = collections.defaultdict(list)
for ident, f, v, l in unseen: by[ident.split(".", 1)[0]].append("%s=%d" % (ident.split(".", 1)[1], v))
for sc, items in sorted(by.items(), key=lambda kv: -len(kv[1])):
    print("    never seen, owner %s (%d): %s" % (sc, len(items), " ".join(sorted(items)[:60]) + (" ..." if len(items) > 60 else "")))
print("problems: %d" % problems)
if problems: print("FAIL part 4 (backward tag scan)"); sys.exit(1)
print("PASS part 4 (backward tag scan)")
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
    if collect_tags; then compare_tags "$DUMP" || FAILED=1; else FAILED=1; fi
    if collect_scan; then compare_scan "$DUMP" || FAILED=1; compare_legacy || FAILED=1; else FAILED=1; fi
    [ "$FAILED" = 0 ] && echo "PASS all parts" || echo "FAIL"
    exit "$FAILED"
fi

# ---- selftest: every part must pass on the real dump, then go red on a damaged copy
echo "selftest: collecting on the real dump"
collect_names; collect_values "$DUMP"; collect_tags || exit 1
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
for f in compare_names compare_values compare_tags compare_scan; do echo "  $f: problems $(problems $f "$DUMP")"; done
echo "  compare_legacy: problems $(problems compare_legacy)"
VICTIM="$(awk -F'\t' '$1=="define" && $4 ~ /^inc\/Defines\.h/ {print $2; exit}' "$DUMP")"
[ -n "$VICTIM" ] || { echo "SELFTEST FAIL: no define from inc/Defines.h in the dump"; exit 1; }
# part 1: hide one define the compiler has
grep -v "^define	$VICTIM	" "$DUMP" > "$W/dump-hidden.txt"
redcheck "part 1 with define $VICTIM hidden from the dump" compare_names "$DUMP" "$W/dump-hidden.txt"
# part 2: change one value
awk -F'\t' -v OFS='\t' -v v="$VICTIM" '$1=="define" && $2==v {$3=$3+7} {print}' "$DUMP" > "$W/dump-changed.txt"
redcheck "part 2 with the value of $VICTIM changed in the dump" compare_values "$DUMP" "$W/dump-changed.txt"
# part 3: drop one tag (all Item tags with that value, so no other row covers the runtime write)
TN="$(awk -F'\t' '$1=="tag" && $2 ~ /^Item\./ {print $3; exit}' "$DUMP")"
awk -F'\t' -v n="$TN" '!($1=="tag" && $2 ~ /^Item\./ && $3==n)' "$DUMP" > "$W/dump-notag.txt"
redcheck "part 3 with Item tag $TN dropped from the dump" compare_tags "$DUMP" "$W/dump-notag.txt"
# part 3, macro body: drop the literal Count tag the macro V1_ELEM_ARRAY_FIELDS expands to
awk -F'\t' '!($1=="tag" && $2=="?.Count" && $4 ~ /^src\/SaveV1\.cpp:/)' "$DUMP" > "$W/dump-nomacrotag.txt"
redcheck "part 3 with the literal Count tag of the V1_ELEM_ARRAY_FIELDS expansions dropped from the dump" compare_tags "$DUMP" "$W/dump-nomacrotag.txt"
# part 4, planted tag: a copy of one generated save with tag 60000 added to its first record must go red
PSRC="$(ls "$W"/gen/smoke-1/save/*.sav | head -1)"
plant_tag "$PSRC" "$W/planted.sav" || { echo "SELFTEST FAIL: could not plant a tag"; ST=1; }
printf 'clean\t%s\t%s\t0\t%s\t%s\n' "$PSRC" "$(save_stamp "$PSRC")" "$W/scan/clean.txt" "$W/scan/clean.err" > "$W/scan/m-clean.tsv"
: > "$W/scan/clean.txt"; INCURSION_TAG_SCAN="$W/scan/clean.txt" ./tools/dump_save.sh "$PSRC" >/dev/null 2> "$W/scan/clean.err"
printf 'planted\t%s\t%s\t' "$W/planted.sav" "$(save_stamp "$W/planted.sav")" > "$W/scan/m-planted.tsv"
: > "$W/scan/planted.txt"; INCURSION_TAG_SCAN="$W/scan/planted.txt" ./tools/dump_save.sh "$W/planted.sav" >/dev/null 2> "$W/scan/planted.err"; PRC=$?
printf '%s\t%s\t%s\n' "$PRC" "$W/scan/planted.txt" "$W/scan/planted.err" >> "$W/scan/m-planted.tsv"
base="$(problems compare_scan "$DUMP" "$W/scan/m-clean.tsv")"; dmg="$(problems compare_scan "$DUMP" "$W/scan/m-planted.tsv")"
if [ "$base" = 0 ] && [ -n "$dmg" ] && [ "$dmg" -gt 0 ]; then
    echo "ok: part 4 with tag 60000 planted in a copy of a save goes red (problems $base on the clean copy, $dmg on the planted copy; $(compare_scan "$DUMP" "$W/scan/m-planted.tsv" 2>&1 | grep -m1 'FAIL load' | cut -c1-200))"
else
    echo "SELFTEST FAIL: part 4 planted tag (problems $base clean, $dmg planted; wanted 0 and > 0)"; ST=1
fi
# part 4, dump side: drop every Item tag with one value; the real saves hold an Item with that tag
awk -F'\t' -v n="$TN" '!($1=="tag" && $2 ~ /^Item\./ && $3==n)' "$DUMP" > "$W/dump-notag4.txt"
redcheck "part 4 with Item tag $TN dropped from the dump" compare_scan "$DUMP" "$W/dump-notag4.txt"
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
