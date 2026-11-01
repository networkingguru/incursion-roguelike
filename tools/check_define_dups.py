#!/usr/bin/env python3
# gate: cheap
# gate-fast: static, reads inc/Defines.h only, well under 1 s
"""Do two #define names in one family share one integer value?

WHY THIS EXISTS. Two worktrees can each add a stati (status effect) define
with the next free number, and both merge cleanly because the lines differ.
The game then treats two effects as one. MAGIC_AURA and SOCIAL_MOD are both
234 today (inc/Defines.h, inc-upw.57). Spec: docs/superpowers/specs/
2026-10-31-no-shared-tail-design.md section 4.5 (bead inc-mhn1w). Detection
only: the landing bead renumbers its own entry, master's number stays.

WHAT IT READS. Every integer `#define NAME <expr>` in inc/Defines.h, with
comments removed (`/* */` across lines, and `//`). It evaluates each value,
including expressions over earlier defines (FT_TUVWXYZ+48), parentheses,
+ - * / << >> | & ^ ~, hex/octal/decimal literals and char literals. The
evaluator walks a whitelisted `ast`; it never calls eval. #if/#ifdef lines are
not interpreted: every #define in the file counts.

SKIPPED SHAPES (not integer defines): a body holding a string literal, a
function-like macro `NAME(x)`, an empty define, and a body holding `; { } [ ] . , =` or `this`/`sizeof`
(a statement or initializer such as `__debugbreak();`), a body of two or more
bare words with no operator or number (a type such as `unsigned char`). A
single bare word counts only when it names an earlier integer define; any
other single bare word is skipped as a type alias. Anything else that looks
like an integer expression but cannot be evaluated (unknown name, operator
outside the list) exits 2 naming the line. It is never skipped.

FAMILIES. Lines from `#define SICKNESS` to `#define LAST_STATI`, inclusive,
form the family `stati`, whatever the names (a sub-define inside the block
that equals a stati value reads as a duplicate). Outside the block the family
is the text before the first `_`; a name with no `_` is not checked.

BASELINE. tools/define_dups.baseline holds today's duplicates, one group per
line: `<family><TAB><value><TAB><NAME1 NAME2 ...>`, sorted; `#` lines are
comments. A group that is in the baseline passes. A group not in it fails. A
baseline group that grows a name not listed fails. A baseline group that is no
longer a duplicate is STALE: reported as a warning, exit 0. Regenerate with
--write-baseline (review the diff: it must only shrink).

Usage: tools/check_define_dups.py [--defines FILE] [--baseline FILE]
                                  [--write-baseline] [--selftest]
Exit:  0 clean (stale baseline lines warn)   1 new or grown duplicate
       2 could not measure (unevaluable expression, SICKNESS/LAST_STATI missing)

# fact: the define values -- read from inc/Defines.h text; no game run, no seed
# fact: which names share a value -- computed from those values; no randomness
# fact: today's accepted duplicates -- tools/define_dups.baseline, committed
"""
import ast
import os
import re
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_DEFAULT = os.path.join(ROOT, "inc", "Defines.h")
BASE_DEFAULT = os.path.join(ROOT, "tools", "define_dups.baseline")

BASE_HEADER = (
    "# Today's duplicate define values in inc/Defines.h, from inc-mhn1w.\n"
    "# A landing bead renumbers its own entry; it MUST NOT grow a group here.\n"
    "# Format: family<TAB>value<TAB>NAME1 NAME2 ... (sorted). See\n"
    "# tools/check_define_dups.py.\n")


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


def read_defines(path):
    """Return list of (lineno, name, value, in_stati)."""
    with open(path, encoding="latin-1") as f:
        text = strip_comments(f.read())
    env, rows, in_stati, seen_s, seen_e = {}, [], False, False, False
    for no, line in logical_lines(text):
        m = re.match(r"\s*#\s*define\s+([A-Za-z_]\w*)(\(?)(.*)$", line)
        if not m:
            continue
        name, paren, body = m.group(1), m.group(2), m.group(3)
        if name == "SICKNESS":
            in_stati = seen_s = True
        block = in_stati
        if name == "LAST_STATI":
            seen_e = True
            if not seen_s:
                raise Unmeasurable("LAST_STATI comes before SICKNESS")
            in_stati = False
        if paren or not body.strip() or '"' in body:
            continue
        toks = tokens(body)
        if any(t in STMT_TOKENS or t in ("this", "sizeof") for t in toks):
            continue  # a statement or initializer, not an expression
        words = [t for t in toks if re.match(r"[A-Za-z_]", t)]
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
        rows.append((no, name, value, block))
    if not seen_s:
        raise Unmeasurable("no '#define SICKNESS' in %s" % path)
    if not seen_e:
        raise Unmeasurable("no '#define LAST_STATI' in %s" % path)
    return rows


def groups(rows):
    g = {}
    for _no, name, value, block in rows:
        if block:
            fam = "stati"
        elif "_" in name:
            fam = name.split("_", 1)[0]
        else:
            continue
        g.setdefault((fam, value), [])
        if name not in g[(fam, value)]:
            g[(fam, value)].append(name)
    return {k: sorted(v) for k, v in g.items() if len(v) > 1}


def read_baseline(path):
    base = {}
    if not os.path.exists(path):
        return base
    with open(path) as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw.strip() or raw.startswith("#"):
                continue
            fam, val, names = raw.split("\t")
            base[(fam, int(val))] = set(names.split())
    return base


def baseline_text(dups):
    lines = ["%s\t%d\t%s" % (f, v, " ".join(n))
             for (f, v), n in sorted(dups.items(), key=lambda kv: (kv[0][0], kv[0][1]))]
    return BASE_HEADER + "\n".join(lines) + "\n"


def check(defines, baseline):
    """Return (exit code, list of message lines)."""
    try:
        dups = groups(read_defines(defines))
    except Unmeasurable as e:
        return 2, ["check_define_dups: UNMEASURED: %s" % e]
    base = read_baseline(baseline)
    msgs, bad = [], False
    for key, names in sorted(dups.items()):
        fam, val = key
        if key not in base:
            bad = True
            msgs.append("FAIL: family %s: %s all = %d (new duplicate; renumber "
                        "your own entry, master's number stays)" % (fam, " ".join(names), val))
        elif not set(names) <= base[key]:
            bad = True
            extra = sorted(set(names) - base[key])
            msgs.append("FAIL: family %s value %d: baseline group grew by %s "
                        "(renumber it; do not add to the baseline)" % (fam, val, " ".join(extra)))
    for key, names in sorted(base.items()):
        if key not in dups:
            msgs.append("WARN: stale baseline line: family %s value %d (%s) is no "
                        "longer a duplicate; delete it" % (key[0], key[1], " ".join(sorted(names))))
    if not bad:
        msgs.append("check_define_dups: PASS (%d accepted duplicate groups)" % len(dups))
    return (1 if bad else 0), msgs


def selftest():
    tmp = tempfile.mkdtemp(prefix="define_dups.", dir=os.path.join(ROOT, "logs"))
    n = [0]

    def run(text, base=""):
        n[0] += 1
        d = os.path.join(tmp, "d%d.h" % n[0]); b = os.path.join(tmp, "b%d" % n[0])
        open(d, "w").write(text); open(b, "w").write(base)
        return check(d, b)

    def mk(body, extra_outside="", stati_head=True):
        return ("#define FOO 1\n" + extra_outside +
                ("#define SICKNESS 1\n" if stati_head else "") + body +
                "#define LAST_STATI 251\n")
    try:
        assert run(mk("#define A_X 2\n#define B_X 3\n"))[0] == 0
        c, m = run(mk("#define A_X 234\n#define B_X 234\n"))
        assert c == 1 and "A_X B_X all = 234" in m[0], (c, m)  # AC4 red
        assert run(mk("#define A_X 234\n#define B_X 234\n"),
                   "stati\t234\tA_X B_X\n")[0] == 0           # baseline pair passes
        c, m = run(mk("#define A_X 234\n#define B_X 234\n#define C_X 234\n"),
                   "stati\t234\tA_X B_X\n")
        assert c == 1 and "grew by C_X" in m[0], (c, m)        # grown group fails
        c, m = run(mk("#define A_X 5\n"), "stati\t234\tA_X B_X\n")
        assert c == 0 and any("stale" in x for x in m), (c, m)  # stale warns
        # evaluator: |, <<, nested parens, earlier-define reference, hex, octal, char
        c, m = run(mk("", "#define Q_A 8\n#define Q_B ((1 << 2) | (Q_A / 2)) + 4\n"
                      "#define Q_C 0x0C\n#define Q_D (Q_A+4)\n#define Q_E 014\n"
                      "#define Q_F 'A'\n#define Q_G 65\n"),
                   "Q\t8\tQ_A Q_B\nQ\t12\tQ_C Q_D Q_E\nQ\t65\tQ_F Q_G\n")
        assert c == 0, (c, m)
        c, m = run(mk("", "#define Q_A 8\n#define Q_B ((1 << 2) | (Q_A / 2)) + 4\n#define Q_C 8\n"))
        assert c == 1 and "Q_A Q_B Q_C all = 8" in m[0], (c, m)   # Q_B evaluates to 8
        c, m = run(mk("#define U_A UNKNOWN_THING + 1\n"))
        assert c == 2 and "line 3" in m[0], (c, m)             # unevaluable exits 2
        assert run(mk("#define U_A 1 ? 2 : 3\n"))[0] == 2
        assert run("#define LAST_STATI 5\n")[0] == 2
        assert run("#define SICKNESS 1\n")[0] == 2
        # skipped shapes
        assert run(mk('#define S_A "hi"\n#define S_B(x) ((x)+1)\n#define S_C\n'
                      "#define S_D unsigned char\n#define S_E int\n"))[0] == 0
        # no '_' outside the block is ignored; same prefix outside collides
        assert run("#define AA 7\n#define BB 7\n" + mk("#define A_X 2\n"))[0] == 0
        c, m = run("#define P_AA 7\n#define P_BB 7\n" + mk("#define A_X 2\n"))
        assert c == 1 and "family P" in m[0], (c, m)
        # same value in different families is fine
        assert run("#define P_AA 7\n#define R_BB 7\n" + mk(""))[0] == 0
        # sub-define in the stati block equal to a stati value reads as duplicate
        c, m = run(mk("#define A_X 3\n#define SUB_Y A_X\n"))
        assert c == 1 and "A_X SUB_Y" in m[0], (c, m)
        # comments, multiline block comments, continuation
        c, m = run(mk("/* a\n #define HID_A 9\n */ #define V_A 4 // x\n#define V_B \\\n 4\n"))
        assert c == 1 and "V_A V_B all = 4" in m[0], (c, m)
        # write-baseline round trip
        d = os.path.join(tmp, "w.h"); b = os.path.join(tmp, "w.base")
        open(d, "w").write(mk("#define A_X 9\n#define B_X 9\n"))
        write_baseline(d, b)
        assert check(d, b)[0] == 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("check_define_dups: selftest PASS")
    return 0


def write_baseline(defines, baseline):
    dups = groups(read_defines(defines))
    with open(baseline, "w") as f:
        f.write(baseline_text(dups))
    return len(dups)


def main(argv):
    defines, baseline, write, st = DEF_DEFAULT, BASE_DEFAULT, False, False
    it = iter(argv)
    for a in it:
        if a == "--defines":
            defines = next(it)
        elif a == "--baseline":
            baseline = next(it)
        elif a == "--write-baseline":
            write = True
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    if st:
        return selftest()
    if write:
        try:
            n = write_baseline(defines, baseline)
        except Unmeasurable as e:
            print("check_define_dups: UNMEASURED: %s" % e, file=sys.stderr)
            return 2
        print("wrote %d groups to %s" % (n, baseline))
        return 0
    code, msgs = check(defines, baseline)
    print("\n".join(msgs), file=sys.stderr if code else sys.stdout)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
