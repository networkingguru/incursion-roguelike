#!/bin/bash
# gate: cheap
# Does every derived member function track the base declaration it redeclares?
# (bd inc-rgzr)
#
# WHY. C++ matches an override on the exact parameter list. A derived class that
# redeclares a base virtual with ANY difference there -- int32 for int16, one
# parameter fewer, a missing const -- has declared a new function. It HIDES the
# base name instead of overriding it, takes a vtable slot of its own, and every
# call made through the base type, or from inside a base-class method, reaches
# the base body. Nothing warns: build_macos.sh builds with -w, and the code runs
# clean. Creature::gainFavour took int16 and Character::gainFavour int32, the
# base body was empty, and five favour awards made from inside Creature::
# methods wrote nothing for as long as the code has existed (inc-rgzr).
#
# WHAT THIS REPORTS, for each class in inc/*.h and src/W*.cpp (the three
# terminals live there) against every ancestor that declares the same name:
#
#   hides     an ancestor's virtual overload that this class does not override,
#             although it declares the name: parameter types, arity or const
#             differ. The defect above. clang's -Woverloaded-virtual finds this
#             kind too, and this check must find everything it finds.
#   virtual   the same signature, virtual here and not in the ancestor. The
#             ancestor's call sites never reach this body.
#   return    the same signature, a different return type.
#   defaults  the same signature, a different default-argument set. A default
#             is chosen by the caller's STATIC type, so one call means two
#             things depending on the pointer it goes through.
#
# NOT reported: an override that leaves out the word `virtual` while its
# ancestor has it. C++ makes such a function virtual anyway, so it overrides and
# dispatch is intact. Nine exist (2026-09-13). Nor is hiding reported where
# neither side is virtual: that is ordinary name lookup, not dispatch.
#
# THE BASELINE. tools/virtual_override.baseline names the findings already
# filed, each with the bead that tracks it. A finding it lists is KNOWN; a
# finding it does not list fails this check. The baseline only shrinks: fix
# one, then delete its line. A line whose finding is no longer found FAILS this
# check until it is deleted, because a line left behind would read the same
# mismatch as KNOWN if it ever came back.
#
# THE PARSER is a reader for this codebase's headers, not for C++ at large. It
# drops comments, literals and preprocessor lines, finds class and struct
# bodies by brace matching, and reads the declarations at their top level. So
# that it cannot quietly stop reading anything, it refuses to pass on fewer
# than 100 classes or 300 redeclarations compared; 2026-09-13 reads 145 and
# 512.
#
# PROVED RED on 2026-09-13. Before the fix it failed on gainFavour and nothing
# else, and it failed again the same way with int16 put back after the fix:
#
#   NEW   hides    Character::gainFavour  (inc/Creature.h:843)
#                  virtual void gainFavour(rID, int32, bool=false, bool=true)
#         against  Creature::gainFavour  (inc/Creature.h:615)
#                  virtual void gainFavour(rID, int16, bool=false, bool=true)
#   FAIL: 1 finding(s) the baseline does not know, 0 malformed baseline line(s).
#
# clang agreed: -Woverloaded-virtual named four hiding functions before the fix
# -- Character::ChallengeRating, Character::gainFavour, Armour::Remove and
# Feature::StatiOff, the four "hides" findings here -- and three after.
#
# Usage: tools/check_virtual_override.sh [--selftest]   (0 pass, 1 fail, 2 could not measure)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/tools/$(basename "$0")"
# The four overrides exist for --selftest, which points the checker at a
# made-up tree and baseline.
SRC="${VIRTUAL_OVERRIDE_ROOT:-$ROOT}"
BASELINE="${VIRTUAL_OVERRIDE_BASELINE:-$ROOT/tools/virtual_override.baseline}"
MIN_CLASSES="${VIRTUAL_OVERRIDE_MIN_CLASSES:-100}"
MIN_COMPARED="${VIRTUAL_OVERRIDE_MIN_COMPARED:-300}"

run() {
    command -v python3 >/dev/null || { echo "INCONCLUSIVE: no python3"; return 2; }
    python3 - "$SRC" "$BASELINE" "$MIN_CLASSES" "$MIN_COMPARED" <<'PY'
import os, re, sys

src, baseline_path = sys.argv[1], sys.argv[2]
min_classes, min_compared = int(sys.argv[3]), int(sys.argv[4])

def strip(text):
    """Blank comments, literals and preprocessor lines; keep every newline."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j])); i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(c + re.sub(r"[^\n]", " ", text[i + 1:j - 1]) + c); i = j
        else:
            out.append(c); i += 1
    lines = "".join(out).split("\n")
    k = 0
    while k < len(lines):
        if lines[k].lstrip().startswith("#"):
            while lines[k].rstrip().endswith("\\") and k + 1 < len(lines):
                lines[k] = ""; k += 1
            lines[k] = ""
        k += 1
    return "\n".join(lines)

CLASS_RE = re.compile(r"\b(class|struct)\s+(\w+)\s*(:\s*([^{;()]*))?\{")
DECL_RE = re.compile(r"^(?P<pre>[\w\s\*&:<>,~]*?)\b(?P<name>~?\w+|operator\s*\S+)\s*"
                     r"\((?P<params>.*)\)(?P<post>[^()]*)$", re.S)
TYPE_WORDS = {"const", "volatile", "unsigned", "signed", "short", "long", "int",
              "char", "bool", "void", "float", "double", "struct", "class", "enum"}

def close_brace(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{": depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0: return j
    return len(s) - 1

def split_top(s, sep=","):
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in "(<[": depth += 1
        elif ch in ")>]": depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts

def norm(t):
    return re.sub(r"\s*([*&])\s*", r"\1", re.sub(r"\s+", " ", t).strip())

def param(p):
    """(type, default) of one parameter. The parameter's name is dropped."""
    parts = split_top(p.strip(), "=")
    p, default = parts[0], ("=".join(parts[1:]) if len(parts) > 1 else None)
    toks = re.findall(r"\w+|[*&]+|\[[^\]]*\]|\S", p)
    if len(toks) > 1 and re.match(r"^[A-Za-z_]\w*$", toks[-1]) and toks[-1] not in TYPE_WORDS:
        toks = toks[:-1]
    return norm(" ".join(toks)), (re.sub(r"\s+", "", default) if default else None)

def members(body, cname):
    stmts, depth, start, i = [], 0, 0, 0
    while i < len(body):
        ch = body[i]
        if ch == "{":
            if depth == 0:
                stmts.append((body[start:i], start, True))
                i = close_brace(body, i) + 1
                start = i
                continue
            depth += 1
        elif ch == "}":
            depth -= 1
        elif ch == ";" and depth == 0:
            stmts.append((body[start:i], start, False))
            start = i + 1
        elif ch == ":" and depth == 0 and re.search(r"\b(public|private|protected)\s*$", body[start:i]):
            start = i + 1
        i += 1
    decls = []
    for stmt, off, has_body in stmts:
        off += len(stmt) - len(stmt.lstrip())
        s = stmt.strip()
        if "(" not in s or re.match(r"^(friend|typedef|using)\b", s):
            continue
        m = re.match(r"^(.*?\))\s*:(?!:)", s, re.S)     # a constructor's initialisers
        if m and has_body:
            s = m.group(1)
        m = DECL_RE.match(s)
        if not m:
            continue
        name = re.sub(r"\s+", "", m.group("name"))
        if name in (cname, "~" + cname) or name.startswith("~"):
            continue
        words = m.group("pre").split()
        rtype = norm(" ".join(w for w in words
                              if w not in ("virtual", "static", "inline", "explicit", "extern")))
        if not rtype:
            continue                                     # a macro call, not a declaration
        params = m.group("params").strip()
        plist = [] if params in ("", "void") else [param(p) for p in split_top(params)]
        decls.append(dict(name=name, rtype=rtype, off=off,
                          virtual="virtual" in words, static="static" in words,
                          ptypes=tuple(t for t, _ in plist),
                          defaults=tuple(d for _, d in plist),
                          const=bool(re.search(r"\bconst\b", m.group("post")))))
    return decls

def scan():
    files = [os.path.join("inc", f) for f in sorted(os.listdir(os.path.join(src, "inc")))
             if f.endswith(".h") and f != "Api.h"]          # Api.h is the script view
    files += [os.path.join("src", f) for f in sorted(os.listdir(os.path.join(src, "src")))
              if re.match(r"W\w*\.cpp$", f)]
    classes = {}
    for rel in files:
        s = strip(open(os.path.join(src, rel), encoding="utf-8", errors="replace").read())
        for m in CLASS_RE.finditer(s):
            cname, bases = m.group(2), []
            for b in (split_top(m.group(4)) if m.group(4) else []):
                w = [x for x in re.findall(r"\w+", b)
                     if x not in ("public", "private", "protected", "virtual")]
                if w: bases.append(w[-1])
            ob = m.end() - 1
            body = s[ob + 1:close_brace(s, ob)]
            first = s.count("\n", 0, ob + 1) + 1
            decls = members(body, cname)
            for d in decls:
                d["where"] = "%s:%d" % (rel, first + body.count("\n", 0, d["off"]))
            if cname not in classes or not classes[cname]["decls"]:
                classes[cname] = dict(bases=bases, decls=decls)
    return classes

def ancestors(classes, c, seen):
    for b in classes.get(c, {}).get("bases", []):
        if b in classes and b not in seen:
            seen.append(b)
            ancestors(classes, b, seen)
    return seen

def sig(d):
    return (d["ptypes"], d["const"])

def show(d):
    args = ", ".join(t + ("=" + v if v else "") for t, v in zip(d["ptypes"], d["defaults"]))
    return "%s%s %s(%s)%s" % ("virtual " if d["virtual"] else "", d["rtype"], d["name"], args,
                              " const" if d["const"] else "")

def findings(classes):
    out, compared = [], 0
    for c in sorted(classes):
        anc = ancestors(classes, c, [])
        mine_all = [d for d in classes[c]["decls"] if not d["static"]]
        for name in sorted({d["name"] for d in mine_all}):
            mine = [d for d in mine_all if d["name"] == name]
            theirs = [(a, d) for a in anc for d in classes[a]["decls"]
                      if d["name"] == name and not d["static"]]
            if not theirs:
                continue
            # hides: an ancestor's virtual signature this class never redeclares
            for k, (a, bd) in enumerate(theirs):
                if not bd["virtual"] or any(sig(md) == sig(bd) for md in mine):
                    continue
                if any(sig(d2) == sig(bd) for _, d2 in theirs[:k]):
                    continue                     # a nearer ancestor already has it
                stray = next((md for md in mine if not any(sig(md) == sig(d2) for _, d2 in theirs)), mine[0])
                out.append(("hides", c, a, name, stray, bd))
            # the rest: a signature this class redeclares, against its nearest owner
            for md in mine:
                a, bd = next(((a, d) for a, d in theirs if sig(d) == sig(md)), (None, None))
                if bd is None:
                    continue
                compared += 1
                if not (bd["virtual"] or md["virtual"]):
                    continue
                if md["virtual"] and not bd["virtual"]:
                    out.append(("virtual", c, a, name, md, bd))
                if md["rtype"] != bd["rtype"]:
                    out.append(("return", c, a, name, md, bd))
                if md["defaults"] != bd["defaults"]:
                    out.append(("defaults", c, a, name, md, bd))
    return out, compared

def load_baseline():
    known, bad = {}, []
    if not os.path.exists(baseline_path):
        return known, bad
    for n, line in enumerate(open(baseline_path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        f = line.split()
        if len(f) < 4 or not re.search(r"\binc-[a-z0-9.]+\b", " ".join(f[3:])):
            bad.append("%s:%d: want '<kind> <Derived::name> <Base::name> <bead> ...': %s"
                       % (os.path.basename(baseline_path), n, line))
            continue
        known[tuple(f[:3])] = (" ".join(f[3:]), n)
    return known, bad

classes = scan()
found, compared = findings(classes)
known, bad = load_baseline()

if len(classes) < min_classes or compared < min_compared:
    print("INCONCLUSIVE: the parser read %d classes and compared %d redeclarations;"
          % (len(classes), compared))
    print("      it must read at least %d and %d, or it has stopped reading the headers."
          % (min_classes, min_compared))
    sys.exit(2)

new, seen = 0, set()
for kind, c, a, name, md, bd in found:
    key = (kind, "%s::%s" % (c, name), "%s::%s" % (a, name))
    seen.add(key)
    tag = "KNOWN" if key in known else "NEW  "
    new += key not in known
    print("%s %-8s %s  (%s)" % (tag, kind, key[1], md["where"]))
    print("               %s" % show(md))
    print("      against  %s  (%s)" % (key[2], bd["where"]))
    print("               %s" % show(bd))
    if key in known:
        print("      tracked  %s" % known[key][0])
stale = sorted(set(known) - seen)
for key in stale:
    print("STALE BASELINE LINE  %s:%d: %s %s %s: no longer found; delete the line"
          % ((os.path.basename(baseline_path), known[key][1]) + key))
for b in bad:
    print("BAD BASELINE LINE  " + b)

print()
print("%d classes, %d redeclarations compared, %d findings: %d known, %d new."
      % (len(classes), compared, len(found), len(found) - new, new))
if new or stale or bad:
    print("FAIL: %d finding(s) the baseline does not know, %d stale baseline line(s), "
          "%d malformed baseline line(s)." % (new, len(stale), len(bad)))
    sys.exit(1)
print("PASS: every derived redeclaration tracks its base, or is a filed exception.")
PY
}

# The checker proves itself on a made-up tree: one class of each kind, one
# clean override, one terminal subclass in src/W*.cpp, and a baseline line.
selftest() {
    local dir fails=0 out rc
    dir="$(mktemp -d -t virtualoverride)" || return 2
    trap "rm -rf '$dir'" EXIT
    mkdir -p "$dir/inc" "$dir/src"
    cat > "$dir/inc/Base.h" <<'H'
class Base {
  public:
    virtual void width(int a, int b = 0);    // the gainFavour shape
    virtual int  count(bool neg = false);    // the ChallengeRating shape
    virtual void look() const;
    virtual int  kind();
    bool         magic();                    // the isMagic shape: not virtual
    virtual void size(int *w = 0);           // the Size shape
    virtual void fine(int a, char *s);       // overridden cleanly below
    void         plain(int a);               // ordinary hiding, not a finding
};
class Term { public: virtual void chdir(const char *c, bool set = false) = 0; };
H
    cat > "$dir/inc/Derived.h" <<'H'
class Derived : public Base {
  public:
    virtual void width(long a, int b = 0);
    virtual int  count();
    virtual void look();
    virtual long kind();
    virtual bool magic();
    virtual void size(int *w);
    virtual void fine(int x, char* str);
    void         plain(char c);
};
H
    printf 'class posixTerm : public Term {\n  void chdir(const char * c, bool set);\n};\n' > "$dir/src/Wposix.cpp"
    printf '# test\nhides Derived::count Base::count inc-test\n' > "$dir/baseline"

    _case() { # <want exit> <text wanted in the output> <what it proves> [min classes]
        out="$(VIRTUAL_OVERRIDE_ROOT="$dir" VIRTUAL_OVERRIDE_BASELINE="$dir/baseline" \
               VIRTUAL_OVERRIDE_MIN_CLASSES="${4:-1}" VIRTUAL_OVERRIDE_MIN_COMPARED=1 \
               "$SELF" 2>&1)"
        rc=$?
        if [ "$rc" = "$1" ] && printf '%s' "$out" | grep -qF -- "$2"; then
            printf '  ok    %s\n' "$3"
        else
            printf '  FAIL  %s (exit %s, wanted %s and "%s")\n' "$3" "$rc" "$1" "$2"
            printf '%s\n' "$out" | sed 's/^/        | /'
            fails=$((fails + 1))
        fi
    }

    _case 1 'NEW   hides    Derived::width'    'a different parameter type hides the base'
    _case 1 'KNOWN hides    Derived::count'    'a baselined finding is reported as known'
    _case 1 'NEW   hides    Derived::look'     'a missing const hides the base'
    _case 1 'NEW   return   Derived::kind'     'a different return type is found'
    _case 1 'NEW   virtual  Derived::magic'    'virtual over a non-virtual base is found'
    _case 1 'NEW   defaults Derived::size'     'a dropped default is found'
    _case 1 'NEW   defaults posixTerm::chdir'  'a terminal in src/W*.cpp is read'
    _case 1 '7 findings: 1 known, 6 new'       'a clean override and a non-virtual hide are not reported'
    _case 2 'INCONCLUSIVE' 'a parser that read too few classes refuses to pass' 1000

    # Every finding baselined and nothing more: the check passes.
    {
        printf 'hides Derived::width Base::width inc-test\nhides Derived::count Base::count inc-test\n'
        printf 'hides Derived::look Base::look inc-test\nreturn Derived::kind Base::kind inc-test\n'
        printf 'virtual Derived::magic Base::magic inc-test\ndefaults Derived::size Base::size inc-test\n'
        printf 'defaults posixTerm::chdir Term::chdir inc-test\n'
    } > "$dir/full"
    cp "$dir/full" "$dir/baseline"
    _case 0 'PASS' 'a fully baselined tree with no stale line passes'
    # A line whose finding is gone must fail, or it would excuse the finding's return.
    printf 'hides Gone::x Base::x inc-test\n' >> "$dir/baseline"
    _case 1 'baseline:8: hides Gone::x Base::x: no longer found; delete the line' 'a stale baseline line fails'
    cp "$dir/full" "$dir/baseline"
    printf 'hides Derived::width Base::width\n' >> "$dir/baseline"
    _case 1 'BAD BASELINE LINE' 'a baseline line that names no bead fails'

    echo
    [ "$fails" = 0 ] && { echo "SELFTEST PASS"; return 0; }
    echo "SELFTEST FAIL: $fails"
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "")         run; exit $? ;;
    -h|--help)  sed -n '3,60p' "$0"; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 2 ;;
esac
