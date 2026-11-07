#!/usr/bin/env python3
# gate: none static; reads C/C++ source text only, needs no build and no game run
# fact: source text read -- the tree named on the command line (default: this repo's inc/ and src/); no seed, no character, no world, no roll
# fact: define/enum/tag values -- evaluated from that text by this tool alone; --selftest builds its own scratch tree
"""Dump every evaluated integer value in the C/C++ source (inc-cjos0 phase 0).

Spec: docs/superpowers/specs/2026-11-06-numbers-land-on-master-design.md 4.2.

  number_values.py [ROOT]            dump to stdout (ROOT defaults to repo root)
  number_values.py --diff A B        compare two dumps; exit 1 on any difference
  number_values.py --selftest        prove the tool on a scratch tree

Output, one line per value, sorted:  <kind>\t<identity>\t<value>\t<file:line>
  kind define|enum|tag.  identity is NAME, or <scope>.<label> for a tag.
After a line "## unevaluated" come the defines/enum members the tool could not
evaluate, kind "unevaluated", value = the reason.  --diff compares
(kind, identity, value) only and ignores file:line.

What it handles
  * files: *.h *.hpp *.c *.cpp under ROOT/inc and ROOT/src, recursive.
  * comments and string/char literals are blanked (line numbers preserved).
  * "#if 0" ... "#else"/"#elif"/"#endif" is excluded (#if 0 / #if 0L / #if (0)
    only; every other conditional is read as if all branches were live).
  * #define NAME body (backslash continuations joined).  Function-like macros
    (NAME followed at once by "(") are skipped.
  * C integer arithmetic: + - * / % << >> & | ^ ~ ! && || == != < > <= >= ?:
    parentheses, decimal/hex/octal/binary literals, suffixes u l ul ll,
    char literals, casts to known integer type words (dropped, no wrapping).
    "/" and "%" truncate toward zero as in C.  sizeof and unknown identifiers
    are "unevaluated".
  * a name with more than one definition (conditional branches, or two enums
    with a member of that name): conditions are NOT evaluated. If every
    definition evaluates to the same value, that value is used. Otherwise the
    name, and every define, enum member or tag value that depends on it, is
    listed as unevaluated: "multiply defined under conditionals".
  * enum members, implicit values counted the C way (previous + 1, first 0).
  * tag: literal integer first argument of FIELD_* (not FIELD_SKIP, which has
    none).  Label = second argument, normalized: identifiers in order, "&" "*"
    and [index] dropped, joined "_".
    Scope = the innermost enclosing brace block that is (a) a class/struct/
    union body, giving its name (an inline method belongs to the class whose
    body holds it, e.g. the FieldsV1 inside "typedef struct StatiCollection {"
    is StatiCollection), or (b) a function body written Name::fn(...) {...},
    giving Name (Map::GridFieldsV1 is Map); a template-id qualifier such as
    Array<S,N,D>::FieldsV1 names no single class: "?".  Any other block
    inherits.  Outside every such block: "?".  Preprocessor lines are blanked
    before the braces are read, and #if conditions are not evaluated.
  * a tag inside a #define body is not listed at the definition.  It is listed
    once per expansion site (a use of that macro name outside any directive
    line), under the scope of the site, at the site's line.
    A define name as the tag is resolved through the define table.  An index
    or variable tag has no value and is not listed.
  * tag, non-FIELD calls V1EmbedBegin V1Str V1Blob V1RidStatus v1Find and both
    tags of V1ArrayWiden16: identity <scope>.<call>#<n> (n = ordinal among
    same-named calls in the scope), second tag of V1ArrayWiden16 gets ".arg2".
  * raw v1PutU16 call sites are only counted (stderr), never listed.
"""
import bisect
import os
import re
import sys
import tempfile

TYPE_WORDS = {
    "unsigned", "signed", "int", "long", "short", "char", "const", "size_t",
    "uint8", "int8", "uint16", "int16", "uint32", "int32", "uint64", "int64",
    "uint8_t", "int8_t", "uint16_t", "int16_t", "uint32_t", "int32_t",
    "uint64_t", "int64_t", "BYTE", "WORD", "DWORD", "uint", "ulong", "ushort",
}
EXTS = (".h", ".hpp", ".c", ".cpp")


def blank_comments(t):
    """Blank comments, strings, char literals; keep every newline."""
    out = []
    i, n = 0, len(t)
    while i < n:
        c = t[i]
        two = t[i:i + 2]
        if two == "//":
            j = i
            while j < n and t[j] != "\n":
                # a backslash-newline continues a // comment
                if t[j] == "\\" and j + 1 < n and t[j + 1] == "\n":
                    out.append("  ")
                    j += 1
                    out[-1] = " \n"
                    j += 1
                    continue
                out.append(" ")
                j += 1
            i = j
        elif two == "/*":
            j = t.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" if ch == "\n" else " " for ch in t[i:j]))
            i = j
        elif c == '"':
            j = i + 1
            while j < n and t[j] != '"' and t[j] != "\n":
                j += 2 if t[j] == "\\" else 1
            j = min(j + 1, n)
            out.append('"' + " " * max(0, j - i - 2) + '"')
            i = j
        elif c == "'":
            j = i + 1
            while j < n and t[j] != "'" and t[j] != "\n":
                j += 2 if t[j] == "\\" else 1
            lit = t[i:j + 1]
            out.append(lit)  # keep char literals: they are values
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


IF0 = re.compile(r"^\s*#\s*if\s*\(?\s*0[lLuU]*\s*\)?\s*$")
IFANY = re.compile(r"^\s*#\s*if(def|ndef)?\b")
ELSE = re.compile(r"^\s*#\s*(else|elif)\b")
ENDIF = re.compile(r"^\s*#\s*endif\b")


def drop_if0(t):
    """Blank lines inside '#if 0' blocks (nesting-aware)."""
    lines = t.split("\n")
    out = []
    stack = []  # entries: 'dead' (inside #if 0), 'nested' (inside dead), 'live'
    for ln in lines:
        dead = any(s in ("dead", "nested") for s in stack)
        if IF0.match(ln) and not dead:
            stack.append("dead")
            out.append("")
            continue
        if IFANY.match(ln):
            stack.append("nested" if dead else "live")
            out.append("" if dead else ln)
            continue
        if ELSE.match(ln) and stack:
            if stack[-1] == "dead":
                stack[-1] = "live"  # #else of an #if 0 is live
                out.append("")
                continue
            out.append("" if dead else ln)
            continue
        if ENDIF.match(ln) and stack:
            out.append("" if dead else ln)
            stack.pop()
            continue
        out.append("" if dead else ln)
    return "\n".join(out)


def clean(text):
    return drop_if0(blank_comments(text))


# ---------------------------------------------------------------- evaluator
TOK = re.compile(
    r"\s*(?:(0[xX][0-9a-fA-F]+|0[bB][01]+|\d+)([uUlL]*)|('(?:\\.|[^'\\])+')"
    r"|([A-Za-z_]\w*)|(<<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^~!<>?:()]))"
)


MULTI = "multiply defined under conditionals"


class Unev(Exception):
    pass


def tokenize(s):
    pos, toks = 0, []
    s = s.strip()
    while pos < len(s):
        m = TOK.match(s, pos)
        if not m or m.end() == pos:
            raise Unev("not an integer expression: %r" % s[pos:pos + 12])
        if m.group(1):
            g = m.group(1)
            if re.fullmatch(r"0[0-7]+", g):
                v = int(g, 8)
            elif g[:2].lower() == "0b":
                v = int(g, 2)
            else:
                v = int(g, 0)
            toks.append(("n", v))
        elif m.group(3):
            body = m.group(3)[1:-1]
            if body.startswith("\\"):
                esc = {"n": 10, "t": 9, "r": 13, "0": 0, "\\": 92, "'": 39,
                       "a": 7, "b": 8, "f": 12, "v": 11}
                if len(body) == 2 and body[1] in esc:
                    v = esc[body[1]]
                elif re.fullmatch(r"\\x[0-9a-fA-F]+", body):
                    v = int(body[2:], 16)
                elif re.fullmatch(r"\\[0-7]+", body):
                    v = int(body[1:], 8)
                else:
                    raise Unev("not an integer expression: char literal")
            elif len(body) == 1:
                v = ord(body)
            else:
                raise Unev("not an integer expression: char literal")
            toks.append(("n", v))
        elif m.group(4):
            toks.append(("i", m.group(4)))
        else:
            toks.append(("o", m.group(5)))
        pos = m.end()
        while pos < len(s) and s[pos].isspace():
            pos += 1
    return toks


def cdiv(a, b):
    if b == 0:
        raise Unev("division by zero")
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


class Parser:
    def __init__(self, toks, lookup):
        self.t, self.p, self.lookup = toks, 0, lookup

    def peek(self):
        return self.t[self.p] if self.p < len(self.t) else (None, None)

    def eat(self, op=None):
        k, v = self.peek()
        if op is not None and not (k == "o" and v == op):
            return False
        self.p += 1
        return True

    def parse(self):
        v = self.ternary()
        if self.p != len(self.t):
            raise Unev("not an integer expression: trailing tokens")
        return v

    def ternary(self):
        c = self.binary(0)
        if self.eat("?"):
            a = self.ternary()
            if not self.eat(":"):
                raise Unev("not an integer expression: bad ?:")
            b = self.ternary()
            return a if c else b
        return c

    LEVELS = [["||"], ["&&"], ["|"], ["^"], ["&"], ["==", "!="],
              ["<", ">", "<=", ">="], ["<<", ">>"], ["+", "-"], ["*", "/", "%"]]

    def binary(self, lvl):
        if lvl == len(self.LEVELS):
            return self.unary()
        v = self.binary(lvl + 1)
        while True:
            k, op = self.peek()
            if k == "o" and op in self.LEVELS[lvl]:
                self.p += 1
                w = self.binary(lvl + 1)
                v = self.apply(op, v, w)
            else:
                return v

    @staticmethod
    def apply(op, a, b):
        if op == "||": return int(bool(a) or bool(b))
        if op == "&&": return int(bool(a) and bool(b))
        if op == "|": return a | b
        if op == "^": return a ^ b
        if op == "&": return a & b
        if op == "==": return int(a == b)
        if op == "!=": return int(a != b)
        if op == "<": return int(a < b)
        if op == ">": return int(a > b)
        if op == "<=": return int(a <= b)
        if op == ">=": return int(a >= b)
        if op == "<<": return a << b
        if op == ">>": return a >> b
        if op == "+": return a + b
        if op == "-": return a - b
        if op == "*": return a * b
        if op == "/": return cdiv(a, b)
        if op == "%":
            return a - cdiv(a, b) * b
        raise Unev("bad operator")

    def is_cast(self):
        # at "(": all tokens up to ")" are type words (and maybe '*')
        j = self.p + 1
        words = 0
        while j < len(self.t):
            k, v = self.t[j]
            if k == "i" and v in TYPE_WORDS:
                words += 1
            elif k == "o" and v == ")":
                return words > 0 and j + 1 < len(self.t), j
            else:
                return False, 0
            j += 1
        return False, 0

    def unary(self):
        k, v = self.peek()
        if k == "o" and v in ("-", "+", "~", "!"):
            self.p += 1
            x = self.unary()
            return {"-": -x, "+": x, "~": ~x, "!": int(not x)}[v]
        if k == "o" and v == "(":
            ok, j = self.is_cast()
            if ok:
                self.p = j + 1
                return self.unary()
            self.p += 1
            x = self.ternary()
            if not self.eat(")"):
                raise Unev("not an integer expression: missing )")
            return x
        if k == "n":
            self.p += 1
            return v
        if k == "i":
            self.p += 1
            if v == "sizeof":
                raise Unev("sizeof")
            nk, nv = self.peek()
            if nk == "o" and nv == "(":
                raise Unev("function call or function-like macro: " + v)
            return self.lookup(v)
        raise Unev("not an integer expression: unexpected token")


class Env:
    """name -> definitions; lazy, cycle-checked evaluation.

    A name with more than one definition (a #define repeated under #if/#else,
    or an enum member name used by two enums) is not resolved to the last one.
    Conditions are never evaluated, so: if every definition evaluates to the
    same value that value is used; otherwise the name, and every define or enum
    member whose value depends on it, is unevaluated with the reason
    MULTI.
    """

    def __init__(self):
        self.defs = {}   # name -> [distinct expr, in file order]
        self.items = []  # every (kind, name, expr, loc)
        self.cache = {}
        self.busy = set()

    def add(self, kind, name, expr, loc):
        self.items.append((kind, name, expr, loc))
        lst = self.defs.setdefault(name, [])
        if expr not in lst:
            lst.append(expr)

    def value(self, name):
        if name in self.cache:
            r = self.cache[name]
            if isinstance(r, Unev):
                raise r
            return r
        if name not in self.defs:
            raise Unev("undefined identifier: " + name)
        if name in self.busy:
            raise Unev("cycle: " + name)
        self.busy.add(name)
        try:
            exprs = self.defs[name]
            if len(exprs) == 1:
                v = self.eval_expr(exprs[0])
            else:
                vals = set()
                try:
                    for e in exprs:
                        vals.add(self.eval_expr(e))
                except Unev as e:
                    if str(e).startswith(MULTI):
                        raise
                    raise Unev(MULTI)
                if len(vals) != 1:
                    raise Unev(MULTI)
                v = vals.pop()
            self.cache[name] = v
            return v
        except Unev as e:
            self.cache[name] = e
            raise
        finally:
            self.busy.discard(name)

    def eval_expr(self, expr):
        if expr is None or not expr.strip():
            raise Unev("empty body")
        return Parser(tokenize(expr), self.value).parse()


# ----------------------------------------------------------------- scanning
DEFINE = re.compile(r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)(\()?", re.M)
ENUM = re.compile(r"\benum\b(?:\s+(?:class|struct))?(?:\s+\w+)?(?:\s*:\s*[\w ]+?)?\s*\{")


def lineno(text, off):
    return text.count("\n", 0, off) + 1


def split_top(s, sep=","):
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == sep and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def balanced(text, open_pos):
    """text[open_pos] == '('; return index of matching ')' or -1."""
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def normalize_label(expr):
    e = expr
    # drop index expressions (balanced [...])
    out, depth = [], 0
    for ch in e:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return "_".join(re.findall(r"[A-Za-z_]\w*", "".join(out)))


FIELD = re.compile(r"\bFIELD_(?!SKIP\b)[A-Z0-9_]+\s*\(")
CALLS = re.compile(r"\b(V1EmbedBegin|V1Str|V1Blob|V1RidStatus|v1Find|V1ArrayWiden16)\s*\(")
RAWPUT = re.compile(r"\bv1PutU16\s*\(")
RAW_PUTU16 = 0
LOGICAL_PP = re.compile(r"^[ \t]*#(?:\\\n|[^\n])*", re.M)
CLASS_HEAD = re.compile(r"\b(?:class|struct|union)\s+(\w+)\s*(?:final\s*)?(?::(?!:)|$)")
FUNC_HEAD = re.compile(r"(\w+(?:<[^;{}]*?>)?)\s*::\s*~?\w+\s*\(")


def blank_lines(text, ranges):
    """Blank the given (start, end) ranges, keeping newlines."""
    out, pos = [], 0
    for a, b in ranges:
        out.append(text[pos:a])
        out.append("".join("\n" if c == "\n" else " " for c in text[a:b]))
        pos = b
    out.append(text[pos:])
    return "".join(out)


def scope_intervals(text):
    """(open, close, scope) for every brace block that names a scope.

    The scope of a position is the innermost enclosing block that is
      * a class/struct/union body: its name (an inline method belongs to the
        class whose body holds it), or
      * a function body written Name::fn(...) {...}: Name; a template-id
        qualifier (Array<S,N>::fn) names no single class: "?".
    Any other block inherits; outside every such block the scope is "?".
    Preprocessor lines (and so #define bodies) are blanked first, so braces in
    a macro body open nothing; conditions are not evaluated.
    """
    masked = blank_lines(text, [(m.start(), m.end()) for m in LOGICAL_PP.finditer(text)])
    stack, out, last = [], [], 0
    for i, ch in enumerate(masked):
        if ch == "{":
            h = masked[last:i]
            sc = None
            if not re.search(r"\benum\b", h):
                if "(" not in h:
                    m = CLASS_HEAD.search(h)
                    sc = m.group(1) if m else None
                else:
                    m = FUNC_HEAD.search(h)
                    if m:
                        sc = "?" if m.group(1).endswith(">") else m.group(1)
            stack.append((i, sc))
            last = i + 1
        elif ch == "}":
            if stack:
                o, sc = stack.pop()
                if sc:
                    out.append((o, i, sc))
            last = i + 1
        elif ch == ";":
            last = i + 1
    return out


def events_in(text):
    """[(offset, kind, name, args)] for FIELD_* and tag-taking calls in text."""
    ev = []
    for rx, kind in ((FIELD, "F"), (CALLS, "C")):
        for m in rx.finditer(text):
            op = m.end() - 1
            cl = balanced(text, op)
            args = None if cl < 0 else split_top(text[op + 1:cl])
            ev.append((m.start(), kind, m.group(1) if kind == "C" else m.group(0), args))
    ev.sort(key=lambda e: e[0])
    return ev


def scan_file(path, rel, env, macros, store):
    """Phase A: defines, enums, macro bodies. The cleaned text goes to store."""
    with open(path, encoding="utf-8", errors="replace") as f:
        text = clean(f.read())
    store.append((rel, text))
    for m in DEFINE.finditer(text):
        end = m.end()
        j = end
        while True:
            k = text.find("\n", j)
            if k < 0:
                k = len(text)
                break
            if text[k - 1:k] == "\\":
                j = k + 1
                continue
            break
        body = text[end:k].replace("\\\n", " ").strip()
        ev = events_in(body)
        if ev:
            macros[m.group(1)] = ev
        if m.group(2):
            continue  # function-like: no value
        env.add("define", m.group(1), body, "%s:%d" % (rel, lineno(text, m.start())))
    # enums
    for m in ENUM.finditer(text):
        start = m.end()
        depth, j = 1, start
        while j < len(text) and depth:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        body = text[start:j - 1]
        prev = None
        for part in split_top(body):
            p = part.strip()
            if not p:
                continue
            mm = re.match(r"([A-Za-z_]\w*)\s*(?:=(.*))?$", p, re.S)
            if not mm:
                continue
            name, expr = mm.group(1), mm.group(2)
            if expr is None:
                expr = "0" if prev is None else "(%s)+1" % prev
            loc = "%s:%d" % (rel, lineno(text, start + body.find(p)))
            env.add("enum", name, expr.strip(), loc)
            prev = name


def scan_tags(rel, text, macros, tags, raw):
    """Phase B: tags. #define bodies are not scanned in place; a macro whose
    body holds tags is listed once per expansion site, under the site's scope."""
    pp = [(m.start(), m.end()) for m in LOGICAL_PP.finditer(text)]
    defs = [r for r in pp if re.match(r"[ \t]*#[ \t]*define\b", text[r[0]:r[1]])]
    starts = [r[0] for r in defs]
    pstarts = [r[0] for r in pp]

    def in_pp(off):   # any directive line: #define, #undef, #if ...
        i = bisect.bisect_right(pstarts, off) - 1
        return i >= 0 and off < pp[i][1]

    def in_define(off):
        i = bisect.bisect_right(starts, off) - 1
        return i >= 0 and off < defs[i][1]

    ivs = scope_intervals(text)

    def scope_at(off):
        best = None
        for o, c, sc in ivs:
            if o < off < c and (best is None or o > best[0]):
                best = (o, sc)
        return best[1] if best else "?"

    events = []   # (offset, relpos, kind, name, args, line_offset)
    for off, kind, name, args in events_in(text):
        if not in_define(off):
            events.append((off, 0, kind, name, args, off))
    if macros:
        mrx = re.compile(r"\b(%s)\b" % "|".join(re.escape(n) for n in sorted(macros)))
        for m in mrx.finditer(text):
            if in_pp(m.start()):
                continue
            for roff, kind, name, args in macros[m.group(1)]:
                events.append((m.start(), roff + 1, kind, name, args, m.start()))
    events.sort(key=lambda e: (e[0], e[1]))
    ordinals = {}
    for off, _, kind, name, args, loff in events:
        loc = "%s:%d" % (rel, lineno(text, loff))
        sc = scope_at(off)
        if kind == "F":
            if args and len(args) >= 2:
                tags.append((sc + "." + normalize_label(args[1]), args[0].strip(), loc))
            continue
        # a call: ordinal counts every call of that name in the scope,
        # resolvable or not, so a literal turning into a define keeps it
        if not args or re.fullmatch(r"\s*\w+[\s*&]+\w+\s*", args[0]):
            continue  # a declaration or definition, not a call
        n = ordinals[(sc, name)] = ordinals.get((sc, name), 0) + 1
        tags.append(("%s.%s#%d" % (sc, name, n), args[0].strip(), loc))
        if name == "V1ArrayWiden16" and len(args) > 1:
            tags.append(("%s.%s#%d.arg2" % (sc, name, n), args[1].strip(), loc))
    for m in RAWPUT.finditer(text):
        if not in_define(m.start()) and not text[:m.start()].rstrip().endswith("void"):
            op = m.end() - 1
            cl = balanced(text, op)
            args = None if cl < 0 else split_top(text[op + 1:cl])
            if args and len(args) == 2 and not re.fullmatch(r"\s*V1Buf\s*\*\s*\w+\s*", args[0]) and "uint16" not in args[0]:
                raw.append(args[1].strip())


def dump(root):
    env, tags, raw, macros, store = Env(), [], [], {}, []
    files = []
    for sub in ("inc", "src"):
        base = os.path.join(root, sub)
        for dp, dn, fn in os.walk(base):
            dn.sort()
            for f in sorted(fn):
                if f.endswith(EXTS):
                    files.append(os.path.join(dp, f))
    files.sort()
    for p in files:
        scan_file(p, os.path.relpath(p, root), env, macros, store)
    for rel, text in store:
        scan_tags(rel, text, macros, tags, raw)
    rows, bad = [], []
    for kind, name, expr, loc in env.items:
        try:
            v = env.value(name)
            rows.append((kind, name, str(v), loc))
        except Unev as e:
            bad.append(("unevaluated", name, "%s [%s]" % (e, kind), loc))
    for ident, expr, loc in tags:
        try:
            rows.append(("tag", ident, str(env.eval_expr(expr)), loc))
        except Unev as e:
            if str(e).startswith(MULTI):
                bad.append(("unevaluated", ident, "%s [tag]" % e, loc))
            # else: not a literal or a define (an index, a variable): no value
    global RAW_PUTU16
    RAW_PUTU16 = len(raw)
    rows = sorted(set(rows))
    bad = sorted(set(bad))
    lines = ["\t".join(r) for r in rows]
    lines.append("## unevaluated")
    lines += ["\t".join(r) for r in bad]
    return "\n".join(lines) + "\n"


def parse_dump(path):
    s = set()
    with open(path) as f:
        for ln in f:
            ln = ln.rstrip("\n")
            if not ln or ln.startswith("#"):
                continue
            p = ln.split("\t")
            if len(p) < 3:
                continue
            s.add((p[0], p[1], p[2]))
    return s


def diff(a, b):
    A, B = parse_dump(a), parse_dump(b)
    ka = {(k, i): v for k, i, v in A}
    kb = {(k, i): v for k, i, v in B}
    n = 0
    for k, i, v in sorted(A - B):
        if (k, i) in kb and any(x == (k, i) for x in ((k2, i2) for k2, i2, _ in B)):
            continue  # reported as changed below
        print("removed\t%s\t%s\t%s" % (k, i, v))
        n += 1
    for k, i, v in sorted(B - A):
        if (k, i) in ka:
            continue
        print("added\t%s\t%s\t%s" % (k, i, v))
        n += 1
    for (k, i) in sorted(set(ka) & set(kb)):
        if ka[(k, i)] != kb[(k, i)] or ((k, i, ka[(k, i)]) not in B):
            if ka[(k, i)] != kb[(k, i)]:
                print("changed\t%s\t%s\t%s -> %s" % (k, i, ka[(k, i)], kb[(k, i)]))
                n += 1
    # same (kind, identity) defined twice with different value sets
    if n == 0 and A != B:
        for k, i, v in sorted(A - B):
            print("removed\t%s\t%s\t%s" % (k, i, v))
        for k, i, v in sorted(B - A):
            print("added\t%s\t%s\t%s" % (k, i, v))
        n = 1
    return 1 if n else 0


def selftest_faults(check):
    """One case per fault found by tools/check_number_values.sh (inc-cjos0)."""
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(d + "/inc"); os.makedirs(d + "/src")
        # (1) multiply defined under conditionals
        with open(d + "/inc/c.h", "w") as f:
            f.write("""#ifdef A
#define HOST 1
#else
#define HOST 0
#endif
#define TARGET HOST
#define OTHER (TARGET + 1)
#define SAME 4
#define SAME 4
#define PLAIN 9
enum E1 { DUP = 1 };
enum E2 { DUP = 2 };
""")
        out = dump(d)
        rows = {tuple(l.split("\t")[:3]) for l in out.split("## unevaluated")[0].splitlines() if l}
        un = out.split("## unevaluated")[1]
        check(all(("define", n, v) not in rows for n in ("HOST", "TARGET", "OTHER") for v in ("0", "1", "2")),
              "multiply defined: HOST, TARGET and OTHER get no value")
        check(all(("unevaluated\t%s\t" % n + MULTI) in un for n in ("HOST", "TARGET", "OTHER", "DUP")),
              "multiply defined: HOST, dependents TARGET and OTHER, and enum DUP are unevaluated with the reason")
        check(("define", "SAME", "4") in rows and ("define", "PLAIN", "9") in rows,
              "same value in every definition, and a single definition, still evaluate")
        # (2) a tag inside a macro body: once per expansion site, under the site's scope
        with open(d + "/src/m.cpp", "w") as f:
            f.write("""#define ELEM(S) \\
    { FIELD_U32(1, Count); \\
      V1Str(7, Name); }
class Alpha {
  void FieldsV1(Registry &r) { ELEM(A) }
};
void Beta::FieldsV1(Registry &r)
  {
    ELEM(B)
    ELEM(C)
  }
#undef ELEM
""")
        out = dump(d)
        trows = [l.split("\t") for l in out.splitlines() if l.startswith("tag\t")]
        ids = sorted({(r[1], r[2]) for r in trows})
        check(ids == [("Alpha.Count", "1"), ("Alpha.V1Str#1", "7"), ("Beta.Count", "1"),
                      ("Beta.V1Str#1", "7"), ("Beta.V1Str#2", "7")],
              "macro body tags: listed per expansion site under the site scope, ordinals per scope, none at the define or #undef (%r)" % ids)
        check(sorted(r[3] for r in trows if r[1] == "Beta.Count") == ["src/m.cpp:10", "src/m.cpp:9"],
              "macro body tags: one row per expansion site, located at the site line")
        # (3) scope follows the code structure
        with open(d + "/src/s.cpp", "w") as f:
            f.write("""class Thing2 {
  ARCHIVE_CLASS(Thing2,Object,r)
    FIELD_U8(1, a);
  END_ARCHIVE
};
typedef struct Coll {
  int pad;
  void FieldsV1(Registry &r) {
    FIELD_U8(2, inl);
  }
} Coll;
void Other::FieldsV1(Registry &r) { FIELD_U8(3, o); }
void Map2::GridFieldsV1(Registry &r)
  {
    if (1) { FIELD_U8(4, g); }
  }
template<> void Arr<Z,1,1>::FieldsV1(Registry &r) { FIELD_U8(5, t); }
void freefn(Registry &r) { FIELD_U8(6, f); }
""")
        out = dump(d)
        got = {r.split("\t")[1]: r.split("\t")[2] for r in out.splitlines()
               if r.startswith("tag\t") and "src/s.cpp" in r}
        check(got == {"Thing2.a": "1", "Coll.inl": "2", "Other.o": "3", "Map2.g": "4", "?.t": "5", "?.f": "6"},
              "scope: class body, inline method of a struct, Name::fn body, nested block, template-id and free function (%r)" % got)


def selftest():
    def check(cond, msg):
        if not cond:
            print("SELFTEST FAIL: " + msg)
            sys.exit(1)
        print("ok: " + msg)

    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "inc"))
        os.makedirs(os.path.join(d, "src"))
        hdr = os.path.join(d, "inc", "a.h")
        src = os.path.join(d, "src", "b.cpp")
        H = """#define FT_BASE 100
#define FT_X (FT_BASE + 49)
#define SH (1 << 4)
#define HX (uint8)0x1F
#define FN(a) ((a)+1)
#define FLAG
/* #define IN_COMMENT 5 */
#if 0
#define DEAD 9
#endif
#define LONGV (FT_BASE + \\
   7)
#define BAD (UNKNOWN_THING + 1)
enum Color { RED, GREEN, BLUE = 10, CYAN, MAG = FT_X };
class Foo {
  ARCHIVE_CLASS(Foo,Thing,r)
    FIELD_I16(7, t[i].why.data);
    FIELD_U8 (8, Items[i]);
    FIELD_U8 (9, &x);
    FIELD_SKIP(pad);
  END_ARCHIVE
};
"""
        S = "void Bar::FieldsV1(Registry &r) {\n    FIELD_RID(1, eID);\n    FIELD_I16(0x20, *ptr);\n}\n"
        with open(hdr, "w") as f: f.write(H)
        with open(src, "w") as f: f.write(S)
        base = dump(d)
        bp = os.path.join(d, "base.txt")
        with open(bp, "w") as f: f.write(base)
        rows = {tuple(l.split("\t")[:3]) for l in base.splitlines() if l and not l.startswith("#")}
        check(("define", "FT_X", "149") in rows, "define chain evaluates (FT_BASE + 49 = 149)")
        check(("define", "SH", "16") in rows and ("define", "HX", "31") in rows and ("define", "LONGV", "107") in rows,
              "shift, cast-drop and continuation defines")
        check(not any(r[1] in ("FN", "DEAD", "IN_COMMENT") for r in rows), "function-like, #if 0 and comment defines skipped")
        check("## unevaluated" in base and "BAD\t" in base.split("## unevaluated")[1] and "FLAG\t" in base.split("## unevaluated")[1],
              "unevaluable defines are listed, not dropped")
        # (3) implicit enum counting
        check(("enum", "RED", "0") in rows and ("enum", "GREEN", "1") in rows and
              ("enum", "BLUE", "10") in rows and ("enum", "CYAN", "11") in rows and ("enum", "MAG", "149") in rows,
              "implicit enum members count the C way")
        # (4) label normalization
        check(normalize_label("&t[i].why.data") == "t_why_data", "label &t[i].why.data -> t_why_data")
        check(normalize_label("Items[i]") == "Items", "label Items[i] -> Items")
        check(("tag", "Foo.t_why_data", "7") in rows and ("tag", "Foo.Items", "8") in rows and
              ("tag", "Foo.x", "9") in rows and ("tag", "Bar.eID", "1") in rows and
              ("tag", "Bar.ptr", "32") in rows, "tags found with scope and normalized label")
        check(not any(r[0] == "tag" and r[2] == "pad" for r in rows), "FIELD_SKIP gives no tag")
        # non-FIELD tag: literal -> define, same value then different value
        S2 = S + "void Bar::Other(Registry &r) {\n  r.V1Str(522, a);\n  r.V1ArrayWiden16(448, 434, p, 3);\n  r.V1EmbedBegin((uint16)(1+i), &q, 4);\n}\n"
        with open(src, "w") as f: f.write(S2)
        pa = os.path.join(d, "lit.txt")
        with open(pa, "w") as f: f.write(dump(d))
        la = open(pa).read()
        check("tag\tBar.V1Str#1\t522" in la and "tag\tBar.V1ArrayWiden16#1\t448" in la and
              "tag\tBar.V1ArrayWiden16#1.arg2\t434" in la and "V1EmbedBegin#1" not in la,
              "non-FIELD tags dumped with #n and .arg2; index tag has no value")
        S3 = S2.replace("V1Str(522,", "V1Str(TAG_X,")
        with open(hdr, "w") as f: f.write(H + "#define TAG_X 522\n")
        with open(src, "w") as f: f.write(S3)
        pb = os.path.join(d, "def.txt")
        with open(pb, "w") as f: f.write(dump(d))
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = diff(pa, pb)
        check(rc == 1 and "TAG_X" in buf.getvalue() and "V1Str" not in buf.getvalue(),
              "literal -> same-value define: only the new define differs, tag identical")
        a2 = {l for l in la.splitlines() if l.startswith("tag\t")}
        b2 = {l.split("\t")[0:3] and "\t".join(l.split("\t")[0:3]) for l in open(pb).read().splitlines() if l.startswith("tag\t")}
        check({"\t".join(l.split("\t")[0:3]) for l in a2} == b2, "tag lines identical (kind, identity, value)")
        with open(hdr, "w") as f: f.write(H + "#define TAG_X 523\n")
        with open(pb, "w") as f: f.write(dump(d))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = diff(pa, pb)
        check(rc == 1 and "V1Str#1" in buf.getvalue(), "literal -> different-value define: exit 1 on the tag")
        with open(hdr, "w") as f: f.write(H)
        with open(src, "w") as f: f.write(S)
        # (1) planted value change
        with open(hdr, "w") as f: f.write(H.replace("#define FT_BASE 100", "#define FT_BASE 101"))
        p2 = os.path.join(d, "changed.txt")
        with open(p2, "w") as f: f.write(dump(d))
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = diff(bp, p2)
        check(rc == 1 and "FT_BASE" in buf.getvalue(), "planted define change: diff non-empty, exit 1")
        # (2) line shift only
        with open(hdr, "w") as f: f.write("\n\n/* c */\n\n" + H)
        with open(src, "w") as f: f.write("// x\n\n" + S)
        p3 = os.path.join(d, "shifted.txt")
        with open(p3, "w") as f: f.write(dump(d))
        check(open(p3).read() != base, "shifted dump differs in file:line column")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = diff(bp, p3)
        check(rc == 0 and buf.getvalue() == "", "line shift only: diff empty, exit 0")
    selftest_faults(check)
    print("SELFTEST PASS")


def main(argv):
    if argv[:1] == ["--selftest"]:
        selftest()
        return 0
    if argv[:1] == ["--diff"] and len(argv) == 3:
        return diff(argv[1], argv[2])
    root = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sys.stdout.write(dump(os.path.abspath(root)))
    sys.stderr.write("raw v1PutU16 call sites: %d\n" % RAW_PUTU16)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
