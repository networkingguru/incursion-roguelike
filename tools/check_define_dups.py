#!/usr/bin/env python3
# gate: cheap
# gate-fast: static, reads inc/Defines.h only, well under 1 s
"""Do two #define names in one explicitly marked family share one value?

WHY THIS EXISTS. Two worktrees can each add a stati (status effect) define
with the next free number, and both merge cleanly because the lines differ.
The game then treats two effects as one. Spec: docs/superpowers/specs/
2026-10-31-no-shared-tail-design.md section 4.5 (bead inc-mhn1w). The old
check guessed each define's family from its position or name prefix. This
one reads the family from comment marks in inc/Defines.h (bead inc-60xq9).

RULE FOR IMPLEMENTERS. A new #define goes inside its family's marks; a
deliberate second name for an existing value carries `/* alias of <NAME> */`; a
value that is not compared with anything goes in a no-family block.

MARKS (whitespace is free). Own-line block marks use `//` (`/* */` also works).
A TRAILING mark on a #define line MUST use `/* */`, never `//`: the module
compiler (src/cpp6.c) can lose the next define after a trailing `//` comment
(seen: "Undefined Constant: T_TRACE"), and this check refuses the `//` form
with exit 2.
  // family: <name>             opens a block; `// end family: <name>` closes it
  // family: <n1>, <n2>         one block whose defines join several families;
                                the end line names the same list
  // no-family                  opens a block never compared with anything;
                                `// end no-family` closes it
  alias of <NAME>               on a define line (trailing, /* */) or the line just
                                above it: skipped. NAME MUST be a define in a
                                shared family with the same value, else FAIL.
  known collision: <bead>       same placement: reported KNOWN with the bead.
                                Mark every member of a colliding group but one.
Blocks do not nest. A family may have several blocks; they form one family.
An open with no close, a close with no open, a mismatched name, or nesting
exits 2 UNMEASURED naming the line. It never passes.

RULES.
1. Every integer #define sits inside a family block or a no-family block.
   A define in neither FAILS, naming the define and its line.
2. In one family, two names with one value FAIL, unless a name is an alias
   or a known collision.
3. The same value in two different families passes.
4. A no-family block is never compared.

WHAT COUNTS AS A CONSTANT. Every integer `#define NAME <expr>`, comments
removed (`/* */` across lines, and `//`). Values are evaluated, including
expressions over earlier defines, parentheses, + - * / << >> | & ^ ~, hex,
octal, decimal and char literals. The evaluator walks a whitelisted `ast`;
it never calls eval. #if/#ifdef lines are not interpreted. NOT constants, so
rule 1 ignores them: an include guard or any define with an empty body, a
function-like macro `NAME(x)`, a body holding a string literal, a body
holding `; { } [ ] . , =` or `this`/`sizeof`, a body of two or more bare
words (a type such as `unsigned char`), and a single bare word that names no
earlier integer define (a type alias). A single bare word that names an
earlier integer define is a constant. An integer-looking expression that
cannot be evaluated exits 2 naming the line.

Usage: tools/check_define_dups.py [--defines FILE] [--selftest]
Exit:  0 clean   1 unmarked define, duplicate, or bad alias
       2 could not measure (bad marks, unevaluable expression)

# fact: the define values -- read from inc/Defines.h text; no game run, no seed
# fact: each define's family -- read from the marks in that same text; no randomness
# fact: which names share a value -- computed from those values and marks
"""
import ast
import os
import re
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_DEFAULT = os.path.join(ROOT, "inc", "Defines.h")


class Unmeasurable(Exception):
    pass


def strip_comments(text):
    """Remove comments, keep newlines so line numbers survive."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':  # string literal: copy through
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" for ch in text[i:j] if ch == "\n") or " ")
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c); i += 1
    return "".join(out)


def logical_lines(text):
    """Yield (first line number, text) joining backslash continuations."""
    buf, start = "", 0
    for no, line in enumerate(text.split("\n"), 1):
        if not buf:
            start = no
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, buf + line
        buf = ""
    if buf:
        yield start, buf


TOKEN = re.compile(r"\s*(0[xX][0-9a-fA-F]+[uUlL]*|\d+[uUlL]*|'(?:\\.|[^'\\])'"
                   r"|[A-Za-z_]\w*|<<|>>|[-+*/&|^~()%]|\S)")


STMT_TOKENS = set(";{}[].,=")


def tokens(body):
    pos, out = 0, []
    body = body.strip()
    while pos < len(body):
        m = TOKEN.match(body, pos)
        out.append(m.group(1)); pos = m.end()
    return out


def to_python(toks, lineno):
    py = []
    for t in toks:
        if t[0].isdigit():
            t = t.rstrip("uUlL")
            if t[:2].lower() == "0x":
                py.append(str(int(t, 16)))
            elif len(t) > 1 and t[0] == "0":
                try:
                    py.append(str(int(t, 8)))
                except ValueError:
                    raise Unmeasurable("line %d: bad octal literal %s" % (lineno, t))
            else:
                py.append(t)
        elif t[0] == "'":
            ch = ast.literal_eval(t) if t[1] != "\\" else ast.literal_eval(t)
            py.append(str(ord(ch)))
        else:
            py.append(t)
    return " ".join(py)


OK_BIN = {ast.Add: lambda a, b: a + b, ast.Sub: lambda a, b: a - b,
          ast.Mult: lambda a, b: a * b, ast.LShift: lambda a, b: a << b,
          ast.RShift: lambda a, b: a >> b, ast.BitOr: lambda a, b: a | b,
          ast.BitAnd: lambda a, b: a & b, ast.BitXor: lambda a, b: a ^ b,
          ast.Div: lambda a, b: int(a / b), ast.Mod: lambda a, b: a % b}
OK_UN = {ast.USub: lambda a: -a, ast.UAdd: lambda a: a, ast.Invert: lambda a: ~a}


def evaluate(src, env, lineno, name):
    def ev(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id in env:
            return env[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in OK_BIN:
            return OK_BIN[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in OK_UN:
            return OK_UN[type(node.op)](ev(node.operand))
        what = node.id if isinstance(node, ast.Name) else type(node).__name__
        raise Unmeasurable("line %d: %s: cannot evaluate (%s) in: %s"
                           % (lineno, name, what, src))
    try:
        tree = ast.parse(src, mode="eval")
    except SyntaxError:
        raise Unmeasurable("line %d: %s: not a parsable integer expression: %s"
                           % (lineno, name, src))
    try:
        return ev(tree.body)
    except ZeroDivisionError:
        raise Unmeasurable("line %d: %s: division by zero" % (lineno, name))


MARK = re.compile(r"^\s*(?://|/\*)\s*(end\s+)?(?:(family)\s*:\s*(.*?)|(no-family))"
                  r"\s*(?:\*/)?\s*$")
ALIAS = re.compile(r"(?://|/\*).*?\balias\s+of\s+([A-Za-z_]\w*)")
KNOWN = re.compile(r"(?://|/\*).*?\bknown\s+collision\s*:\s*([A-Za-z0-9_.-]+)")
TRAIL_SLASH = re.compile(r"//.*\b(?:alias\s+of|known\s+collision)\b")
COMMENT_ONLY = re.compile(r"^\s*(?://|/\*)")


def read_marks(raw_lines):
    """Return (events, notes). events: sorted (lineno, 'open'|'close', kind,
    tuple of family names). notes: lineno of a define -> (alias, known)."""
    events, open_at = [], None
    for no, line in enumerate(raw_lines, 1):
        m = MARK.match(line)
        if not m:
            continue
        closing = bool(m.group(1))
        if m.group(4):
            kind, fams = "no-family", ()
        else:
            kind = "family"
            fams = tuple(sorted(x.strip() for x in m.group(3).split(",")))
            if not fams or not all(re.fullmatch(r"[A-Za-z_][\w-]*", x) for x in fams):
                raise Unmeasurable("line %d: bad family name list: %s" % (no, line.strip()))
        if not closing:
            if open_at:
                raise Unmeasurable("line %d: a block opens inside the block opened at "
                                   "line %d (blocks do not nest)" % (no, open_at[0]))
            open_at = (no, kind, fams)
            events.append((no, "open", kind, fams))
        else:
            if not open_at:
                raise Unmeasurable("line %d: close mark with no open block" % no)
            if (kind, fams) != open_at[1:]:
                raise Unmeasurable("line %d: close mark does not match the block opened "
                                   "at line %d" % (no, open_at[0]))
            open_at = None
            events.append((no, "close", kind, fams))
    if open_at:
        raise Unmeasurable("line %d: block never closed" % open_at[0])
    notes = {}
    for no, line in enumerate(raw_lines, 1):
        if not re.match(r"\s*#\s*define\b", line):
            continue
        if TRAIL_SLASH.search(line):
            raise Unmeasurable("line %d: a trailing alias or known-collision mark on a "
                               "#define line MUST use /* */, not //. Write "
                               "/* alias of <NAME> */ or /* known collision: <bead> */."
                               % no)
        texts = [line]
        if no >= 2 and COMMENT_ONLY.match(raw_lines[no - 2]):
            texts.append(raw_lines[no - 2])
        alias = known = None
        for t in texts:
            a, k = ALIAS.search(t), KNOWN.search(t)
            alias = alias or (a.group(1) if a else None)
            known = known or (k.group(1) if k else None)
        if alias or known:
            notes[no] = (alias, known)
    return events, notes


def read_defines(raw_text):
    """Return list of (lineno, name, value)."""
    text = strip_comments(raw_text)
    env, rows = {}, []
    for no, line in logical_lines(text):
        m = re.match(r"\s*#\s*define\s+([A-Za-z_]\w*)(\(?)(.*)$", line)
        if not m:
            continue
        name, paren, body = m.group(1), m.group(2), m.group(3)
        if paren or not body.strip() or '"' in body:
            continue
        toks = tokens(body)
        if any(t in STMT_TOKENS or t in ("this", "sizeof") for t in toks):
            continue  # a statement or initializer, not an expression
        has_num_or_op = any(t[0].isdigit() or t[0] in "'-+*/&|^~()<>%" for t in toks)
        if not has_num_or_op:
            # bare words only: an alias of an integer define, or a type
            if len(toks) == 1 and toks[0] in env:
                value = env[toks[0]]
            else:
                continue
        else:
            value = evaluate(to_python(toks, no), env, no, name)
        env[name] = value
        rows.append((no, name, value))
    return rows


def check(defines):
    """Return (exit code, list of message lines)."""
    try:
        with open(defines, encoding="latin-1") as f:
            raw = f.read()
        events, notes = read_marks(raw.split("\n"))
        rows = read_defines(raw)
    except Unmeasurable as e:
        return 2, ["check_define_dups: UNMEASURED: %s" % e]
    except OSError as e:
        return 2, ["check_define_dups: UNMEASURED: cannot read %s: %s" % (defines, e)]
    msgs, bad = [], False
    members = {}  # family -> list of (lineno, name, value, alias, known)
    ev, cur = 0, None
    for no, name, value in rows:
        while ev < len(events) and events[ev][0] < no:
            cur = events[ev][2:] if events[ev][1] == "open" else None
            ev += 1
        if cur is None:
            bad = True
            msgs.append("FAIL: line %d: %s is outside every family block. Fix: put it "
                        "inside its family's marks ('// family: <name>' ... "
                        "'// end family: <name>'), or inside a no-family block "
                        "('// no-family' ... '// end no-family')." % (no, name))
            continue
        kind, fams = cur
        if kind == "no-family":
            continue
        alias, known = notes.get(no, (None, None))
        for fam in fams:
            members.setdefault(fam, []).append((no, name, value, alias, known))
    nknown = 0
    for fam in sorted(members):
        rows_f = members[fam]
        by_name = {}
        for no, name, value, _a, _k in rows_f:
            by_name.setdefault(name, []).append(value)
        groups = {}
        for no, name, value, alias, known in rows_f:
            if alias:
                if value not in by_name.get(alias, []) or alias == name:
                    bad = True
                    msgs.append("FAIL: family %s line %d: %s says 'alias of %s' but %s"
                                % (fam, no, name, alias,
                                   "no such define in the family with value %d" % value
                                   if alias not in by_name else
                                   "its value is %s, not %d"
                                   % (",".join(map(str, by_name[alias])), value)
                                   if alias != name else "a name cannot alias itself"))
                continue
            if known:
                nknown += 1
                msgs.append("KNOWN: family %s line %d: %s = %d, collision tracked by %s"
                            % (fam, no, name, value, known))
                continue
            groups.setdefault(value, []).append((no, name))
        for value, g in sorted(groups.items()):
            if len(g) > 1:
                bad = True
                msgs.append("FAIL: family %s: %s all = %d (lines %s). Renumber your own "
                            "entry; master's number stays. A deliberate second name "
                            "carries '/* alias of <NAME> */'."
                            % (fam, " ".join(n for _l, n in g), value,
                               ", ".join(str(l) for l, _n in g)))
    if not bad:
        msgs.append("check_define_dups: PASS (%d families, %d known collisions)"
                    % (len(members), nknown))
    return (1 if bad else 0), msgs


def selftest():
    os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="define_dups.", dir=os.path.join(ROOT, "logs"))
    n = [0]

    def run(text):
        n[0] += 1
        d = os.path.join(tmp, "d%d.h" % n[0])
        with open(d, "w") as f:
            f.write(text)
        c, m = check(d)
        return c, "\n".join(m)

    def fam(name, body):
        return "// family: %s\n%s// end family: %s\n" % (name, body, name)
    try:
        # a. two names, one value, one family: fail
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234\n"))
        assert c == 1 and "family stati: A_X B_X all = 234" in m, (c, m)
        assert run(fam("stati", "#define A_X 234\n#define B_X 235\n"))[0] == 0
        # b. one value in two families: pass
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_X 7\n"))
        assert c == 0 and "PASS" in m, (c, m)
        # a family in two separate blocks is one family
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_X 8\n")
                   + fam("a", "#define A_Y 7\n"))
        assert c == 1 and "family a: A_X A_Y all = 7" in m, (c, m)
        # c. alias with target's value passes (trailing and line-above forms)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 7 /* alias of A_X */\n"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7\n/* alias of A_X */\n#define A_Y 7\n"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 8 /* alias of A_X */\n"))
        assert c == 1 and "A_Y says 'alias of A_X'" in m and "not 8" in m, (c, m)
        c, m = run(fam("a", "#define A_Y 7 /* alias of NOPE */\n"))
        assert c == 1 and "no such define" in m, (c, m)
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_Y 7 /* alias of A_X */\n"))
        assert c == 1 and "family b" in m, (c, m)  # target must share the family
        # trailing // mark on a define line: refused with exit 2
        for tm in ("#define A_Y 7 // alias of A_X\n", "#define A_Y 7 // known collision: inc-x\n"):
            c, m = run(fam("a", "#define A_X 7\n" + tm))
            assert c == 2 and "MUST use /* */" in m and "line 3" in m, (tm, c, m)
        # d. unmarked define: fail, names it
        c, m = run("#define LOOSE 3\n" + fam("a", "#define A_X 7\n"))
        assert c == 1 and "line 1: LOOSE is outside every family block" in m, (c, m)
        c, m = run(fam("a", "#define A_X 7\n") + "#define LATE 9\n")
        assert c == 1 and "LATE is outside" in m, (c, m)
        # e. no-family block: equal values pass, and are not compared to a family
        c, m = run("// no-family\n#define N_A 5\n#define N_B 5\n// end no-family\n"
                   + fam("a", "#define A_X 5\n"))
        assert c == 0, (c, m)
        # f. known collision: pass, reported with the bead id
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234 /* known collision: inc-upw.57 */\n"))
        assert c == 0 and "KNOWN" in m and "B_X" in m and "inc-upw.57" in m, (c, m)
        # known mark does not excuse a third name
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234 /* known collision: inc-x */\n"
                       "#define C_X 234\n"))
        assert c == 1 and "A_X C_X all = 234" in m, (c, m)
        # g. multi-family block: a duplicate against a member of either family fails
        multi = "// family: a, b\n#define M_X 9\n// end family: a, b\n"
        c, m = run(multi + fam("a", "#define A_X 9\n"))
        assert c == 1 and "family a: M_X A_X all = 9" in m, (c, m)
        c, m = run(multi + fam("b", "#define B_X 9\n"))
        assert c == 1 and "family b: M_X B_X all = 9" in m, (c, m)
        assert run(multi + fam("c", "#define C_X 9\n"))[0] == 0
        # h. unbalanced or nested marks: exit 2
        for bad in ("// family: a\n#define A_X 1\n",
                    "#define A_X 1\n// end family: a\n",
                    "// family: a\n// end family: b\n",
                    "// family: a\n// family: b\n// end family: b\n// end family: a\n",
                    "// no-family\n// family: a\n// end family: a\n// end no-family\n",
                    "// family: a\n// end no-family\n"):
            c, m = run(bad)
            assert c == 2 and "UNMEASURED" in m and "line" in m, (bad, c, m)
        # i. bard-step red/green from the bead
        stati = "#define SICKNESS 1\n#define POISONED 2\n"
        c, m = run(fam("stati", stati) + fam("bard-step", "#define BARD_CHORUS 2\n"))
        assert c == 0, (c, m)
        c, m = run(fam("stati", stati + "#define NEW_STATUS 2\n"))
        assert c == 1 and "POISONED NEW_STATUS all = 2" in m, (c, m)
        # evaluator, comments, continuation, skipped shapes
        c, m = run(fam("q", "#define Q_A 8\n#define Q_B ((1 << 2) | (Q_A / 2)) + 4\n"))
        assert c == 1 and "Q_A Q_B all = 8" in m, (c, m)
        c, m = run(fam("q", "#define Q_C 0x0C\n#define Q_D (Q_C+1)\n#define Q_E 014\n"
                       "#define Q_F 'A'\n#define Q_G 66\n"))
        assert c == 1 and "Q_C Q_E all = 12" in m and "Q_F" not in m, (c, m)
        c, m = run(fam("q", "/* a\n #define HID_A 9\n */ #define V_A 4 // x\n"
                       "#define V_B \\\n 4\n"))
        assert c == 1 and "V_A V_B all = 4" in m and "HID_A" not in m, (c, m)
        c, m = run('#ifndef GUARD_H\n#define GUARD_H\n#define S_A "hi"\n'
                   "#define S_B(x) ((x)+1)\n#define S_C\n#define S_D unsigned char\n"
                   "#define S_E int\n#endif\n")
        assert c == 0, (c, m)  # guards, strings, macros, types are not constants
        c, m = run(fam("u", "#define U_A UNKNOWN_THING + 1\n"))
        assert c == 2 and "line 2" in m, (c, m)
        assert run(fam("u", "#define U_A 1 ? 2 : 3\n"))[0] == 2
        assert check(os.path.join(tmp, "missing.h"))[0] == 2
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("check_define_dups: selftest PASS")
    return 0


def main(argv):
    defines, st = DEF_DEFAULT, False
    it = iter(argv)
    for a in it:
        if a == "--defines":
            defines = next(it, None)
            if defines is None:
                print("--defines needs a file", file=sys.stderr)
                return 2
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    if st:
        return selftest()
    code, msgs = check(defines)
    print("\n".join(msgs), file=sys.stderr if code else sys.stdout)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
