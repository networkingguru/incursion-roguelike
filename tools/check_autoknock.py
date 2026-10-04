#!/usr/bin/env python3
# gate: none -- parser for check_autoknock.sh (inc-e3oo)
"""Selection oracle; spell dispatch is intercepted, kick events run normally."""
import contextlib
import io
from pathlib import Path
import sys

EXPECTED = {'levitation': 'none', 'levitation-innate': 'none',
            'wizard-lock': 'none', 'knock': 'knock', 'warp-wood': 'warp-wood',
            'levitation-knock': 'knock', 'none': 'none'}


def analyse(text):
    rows = {}
    try:
        lines = text.splitlines()
        if 'DONE' not in lines or not any(x.startswith('RIG ') for x in lines):
            raise ValueError('missing RIG/DONE')
        if any(x.startswith('INCONCLUSIVE') for x in lines):
            raise ValueError('probe reported inconclusive')
        for line in lines:
            if line.startswith('AUTO '):
                row = dict(x.split('=', 1) for x in line.split()[1:])
                name = row['case']
                if name in rows:
                    raise ValueError('duplicate case ' + name)
                rows[name] = row
        if set(rows) != set(EXPECTED):
            raise ValueError('missing or unexpected case lines')
        for row in rows.values():
            if row['eligible'] != '1':
                raise ValueError('spell eligibility mismatch: ' + row['case'])
            for field in ('attempts', 'kicks', 'timeout'):
                int(row[field])
            row['spell']
    except (ValueError, KeyError) as e:
        print('INCONCLUSIVE: ' + str(e))
        return 2
    failures = 0
    for name, spell in EXPECTED.items():
        row = rows[name]
        kick = spell == 'none'
        good = (row['spell'] == spell and int(row['attempts']) == int(not kick)
                and int(row['kicks']) == int(kick)
                and (int(row['timeout']) > 0 if kick else int(row['timeout']) == 0))
        failures += not good
        print(f"{'ok' if good else 'FAIL'} case={name} spell={row['spell']} "
              f"attempts={row['attempts']} kicks={row['kicks']} timeout={row['timeout']} "
              f"expected={spell}")
    print(('FAIL' if failures else 'PASS') + ': Auto-Knock selects only passage/unlock spells')
    return int(bool(failures))


def selftest():
    good = 'RIG\u0020depth=1\n' + ''.join(
        f'AUTO case={name} eligible=1 spell={spell} attempts={int(spell != "none")} '
        f'kicks={int(spell == "none")} timeout={20 if spell == "none" else 0}\n'
        for name, spell in EXPECTED.items()) + 'DONE\n'
    tests = [('good', good, 0), ('bad', good.replace('spell=none', 'spell=levitation', 1), 1),
             ('missing-case', '\n'.join(x for x in good.splitlines() if 'case=none ' not in x), 2),
             ('empty', '', 2), ('malformed', good.replace('kicks=1', 'kicks=x', 1), 2)]
    failed = False
    for name, text, want in tests:
        with contextlib.redirect_stdout(io.StringIO()):
            got = analyse(text)
        print(f'selftest {name}: exit {got} (want {want})')
        failed |= got != want
    return int(failed)


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--selftest':
        sys.exit(selftest())
    try:
        text = Path(sys.argv[1]).read_text()
    except (OSError, IndexError) as e:
        print(f'INCONCLUSIVE: cannot read log: {e}')
        sys.exit(2)
    sys.exit(analyse(text))
