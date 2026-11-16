#!/usr/bin/env python3
"""Follow a resource rename in a plant spec (inc-cjos0 phase 9, G31 route M).

  plant_rename.py <program.i> <spec>     print the spec; stdout is the rewritten spec
  plant_rename.py --selftest             exit 0 pass, 1 fail

INCURSION_PRESSURE_RENAMES="old>new|old2>new2" names the renames a case makes on purpose. A spec written before a
rename still names the old resource. When the tree the spec plants into (its lib/program.i) declares `new` and does
not declare `old`, every whole-name occurrence of `old` in a spec line becomes `new`, wherever the line kind puts a
resource name (item, monster, known, iflags, slot @, var and varrid owners, ...). A name both trees hold is left alone.
This is test tooling only; the engine's plant parser is not changed.

# fact: the spec -- a case file, symbolic names only
# fact: the tree's resources -- lib/program.i of the built tree; no seed, no key script
"""
import os
import re
import sys


def declared(program_i_text, name):
    return re.search(r'^\w+ "' + re.escape(name) + r'" *:', program_i_text, re.M) is not None


def rewrite(spec_text, program_i_text, renames_env):
    for pair in renames_env.split("|"):
        if ">" not in pair:
            continue
        old, new = pair.split(">", 1)
        if not old or not new or declared(program_i_text, old) or not declared(program_i_text, new):
            continue
        # the name starts right after the line keyword or an "@ ": "grw-b flask" is another resource, not `flask`
        pat = re.compile(r"((?:^\s*\w+ |@ ))" + re.escape(old) + r"(?![\w;-])", re.M)
        spec_text = "".join(l if l.lstrip().startswith("#") else pat.sub(lambda m: m.group(1) + new, l)
                            for l in spec_text.splitlines(True))
    return spec_text


def selftest():
    tree_new = 'Monster "barbazu;grw" : 73\nItem "flask;retired" : 5\n'
    tree_both = 'Monster "barbazu" : 73\nMonster "barbazu;grw" : 74\n'
    tree_old = 'Monster "barbazu" : 73\n'
    ren = "barbazu>barbazu;grw|flask>flask;retired"
    spec = "# barbazu note\nitem grw-b flask\nvar barbazu claw_hits 11\nmonster barbazu\nitem flask;retired\nslot SL_WIELD @ flask\n"
    want = "# barbazu note\nitem grw-b flask\nvar barbazu;grw claw_hits 11\nmonster barbazu;grw\nitem flask;retired\nslot SL_WIELD @ flask;retired\n"
    checks = [
        ("old name follows the rename", rewrite(spec, tree_new, ren), want),
        ("a name both trees hold is left alone", rewrite(spec, tree_both, ren), spec),
        ("new name absent: unchanged", rewrite(spec, tree_old, ren), spec),
        ("no rename in effect: unchanged", rewrite(spec, tree_new, ""), spec),
    ]
    bad = 0
    for what, got, exp in checks:
        if got == exp:
            print("ok: " + what)
        else:
            print("FAIL: " + what + "\n--got--\n" + got + "--want--\n" + exp)
            bad = 1
    return bad


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    if len(sys.argv) != 3:
        sys.exit("usage: plant_rename.py <program.i> <spec> | --selftest")
    with open(sys.argv[1], errors="replace") as f:
        prog = f.read()
    with open(sys.argv[2]) as f:
        sys.stdout.write(rewrite(f.read(), prog, os.environ.get("INCURSION_PRESSURE_RENAMES", "")))
