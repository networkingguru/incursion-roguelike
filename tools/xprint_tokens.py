"""Literal __XPrint argument audit (inc-upw.30); no C++ build or execution.

Lexes comments, strings and balanced argument expressions. Checks literal
alternatives, adjacent literals and Format(literal, ...) feeding a print call.
Runtime strings, macro expansion and tags inserted by printf substitutions are
outside this static sweep. Format alone is printf, not an __XPrint call.
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

LEX = re.compile(r'(?P<space>\s+|\\\r?\n|//[^\n]*|/\*[\s\S]*?\*/)|'
                 r'(?P<string>(?:u8|[LuU])?"(?:\\[\s\S]|[^"\\])*")|'
                 r"(?P<char>'(?:\\[\s\S]|[^'\\])*')|"
                 r'(?P<word>[A-Za-z_]\w*)|(?P<other>.)', re.S)
# Format positions and the first variadic position, from Message.cpp.
PRINTS = {'IPrint': (0, 1), 'IDPrint': (0, 2), 'DPrint': (1, 3),
          'VPrint': (1, 3), 'TPrint': (1, 4), 'XPrint': (0, 1)}
OBJECT = re.compile(r'(?:hobj|hmon|hitm|obj|mon|itm)(\d*)\Z')
OTHER = re.compile(r'(?:str|num|rid|res|ht[a-z]*)(\d*)\Z')


def lex(source):
    return [(m[0], m.start(), m.lastgroup) for m in LEX.finditer(source)
            if m.lastgroup != 'space']


def arguments(tokens, opening):
    stack = [')']
    start = opening + 1
    result = []
    for j in range(start, len(tokens)):
        value, _, kind = tokens[j]
        if kind in ('string', 'char'):
            continue
        if value in ('(', '[', '{'):
            stack.append({'(': ')', '[': ']', '{': '}'}[value])
        elif value == stack[-1]:
            stack.pop()
            if not stack:
                if j > start:
                    result.append(tokens[start:j])
                return result, j
        elif value == ',' and len(stack) == 1:
            result.append(tokens[start:j])
            start = j + 1
    raise ValueError('unclosed print call')


def decode(token):
    text = token[token.index('"') + 1:-1]
    escapes = {'n': '\n', 'r': '\r', 't': '\t', 'a': '\a',
               'b': '\b', 'f': '\f', 'v': '\v'}
    def replace(m):
        s = m[1]
        if s.startswith('x'):
            return chr(int(s[1:], 16))
        if s[0] in '01234567':
            return chr(int(s, 8))
        return escapes.get(s, '' if s == '\n' else s)
    return re.sub(r'\\(x[0-9a-fA-F]+|[0-7]{1,3}|[\s\S])', replace, text)


def literals(tokens):
    """Return known format alternatives, never strings in unrelated arguments."""
    if not tokens:
        return []
    if tokens[0][0] == '(':
        parts, end = arguments(tokens, 0)
        if end == len(tokens) - 1 and len(parts) == 1:
            return literals(parts[0])
        if len(parts) == 1 and [t[0] for t in parts[0]] in (
                ['const', 'char', '*'], ['char', 'const', '*'], ['char', '*']):
            return literals(tokens[end + 1:])
    if all(t[2] == 'string' for t in tokens):
        return [(''.join(decode(t[0]) for t in tokens), tokens[0][1])]
    if len(tokens) > 2 and tokens[0][0] == 'Format' and tokens[1][0] == '(':
        parts, end = arguments(tokens, 1)
        if end == len(tokens) - 1 and parts:
            return literals(parts[0])
    # Only top-level ?: operands produce the format. Conditions may contain
    # arbitrary calls or string comparisons and must not count as formats.
    depth = 0
    question = None
    nested = 0
    for j, (value, _, kind) in enumerate(tokens):
        if kind in ('string', 'char'):
            continue
        if value in ('(', '[', '{'):
            depth += 1
        elif value in (')', ']', '}'):
            depth -= 1
        elif depth == 0 and value == '?':
            if question is None:
                question = j
            else:
                nested += 1
        elif depth == 0 and value == ':' and question is not None:
            if nested:
                nested -= 1
            else:
                return literals(tokens[question + 1:j]) + literals(tokens[j + 1:])
    return []


def consumption(message):
    n = 0
    objects = False
    for tag in re.finditer(r'<([^<>]*)>', message.split('\0', 1)[0]):
        # __XPrint ignores a glyph's encoded literal '<' byte.
        if tag.start() >= 2 and ord(message[tag.start() - 2]) == 236:
            continue
        parts = tag[1].lower().split(':')
        first, subject = parts[0], parts[-1]
        if first[:1].isdigit() or first.startswith('char'):
            continue
        other = OTHER.fullmatch(first)
        obj = None if other else OBJECT.fullmatch(subject)
        match = other or obj
        if match:
            n = max(n, int(match[1]) if match[1] else n + 1)
            objects |= obj is not None
        # ea/ev/et/ei/ei2 and presentation tags consume nothing.
    return n, objects


def scan(root):
    files = sorted((root / 'src').glob('*.cpp'))
    if not files:
        raise ValueError('no src/*.cpp files')
    findings = []
    measured = 0
    for path in files:
        source = path.read_text(encoding='utf-8', errors='surrogateescape')
        tokens = lex(source)
        for j, (name, pos, kind) in enumerate(tokens[:-1]):
            if kind != 'word' or name not in PRINTS or tokens[j + 1][0] != '(':
                continue
            args, _ = arguments(tokens, j + 1)
            first, fixed = PRINTS[name]
            if len(args) < fixed:
                continue
            supplied = len(args) - fixed
            for slot in range(first, fixed):
                for message, location in literals(args[slot]):
                    measured += 1
                    needed, objects = consumption(message)
                    if objects and needed > supplied:
                        line = source.count('\n', 0, location) + 1
                        call_line = source.count('\n', 0, pos) + 1
                        findings.append(f'{path.relative_to(root)}:{line}: {name} '
                                        f'(call line {call_line}, format {slot - first + 1}) '
                                        f'needs {needed}, supplies {supplied}: {message!r}')
    if not measured:
        raise ValueError('no literal print formats measured')
    return findings, measured


def verdict(count, baseline):
    print(f'xprint-token warnings: {count}   baseline: {baseline}')
    if count > baseline:
        print(f'FAIL: {count - baseline} xprint-token warning(s) above the baseline')
        return 1
    if count < baseline:
        print('FAIL: stale baseline; re-record with tools/check_xprint_tokens.sh --baseline')
        return 1
    print('PASS')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--baseline', action='store_true')
    mode.add_argument('--prove-red', action='store_true')
    args = parser.parse_args()
    findings, measured = scan(args.root)
    baseline_path = args.root / 'tools/xprint_tokens.baseline'
    if args.baseline:
        baseline_path.write_text(f'{len(findings)}\n')
        print(f'recorded baseline: {len(findings)}')
        return 0
    baseline = int(baseline_path.read_text().strip())
    if baseline < 0:
        raise ValueError('negative baseline')
    if args.prove_red:
        if len(findings) != baseline or not baseline:
            raise ValueError('--prove-red needs a matching nonzero backlog baseline')
        # Re-run the real checker with a lower baseline in an isolated tree.
        with tempfile.TemporaryDirectory(prefix='xprint-red-') as directory:
            scratch = Path(directory)
            shutil.copytree(args.root / 'src', scratch / 'src')
            (scratch / 'tools').mkdir()
            (scratch / 'tools/xprint_tokens.baseline').write_text(f'{baseline - 1}\n')
            result = subprocess.run([sys.executable, str(Path(__file__).resolve()),
                                     '--root', str(scratch)], capture_output=True, text=True)
        print('mutation: lower scratch baseline by 1')
        if result.returncode != 1:
            raise ValueError('mutation did not fail')
        print('\n'.join(result.stdout.splitlines()[-2:]))
        print('PASS: --prove-red observed exit 1')
        return 0
    print(f'literal print formats measured: {measured}')
    for finding in findings:
        print(finding)
    return verdict(len(findings), baseline)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as e:
        print('COULD NOT MEASURE: ' + str(e))
        sys.exit(2)
