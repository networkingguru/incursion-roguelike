#!/usr/bin/env python3
"""Structural check for inc-30ps phase 5 (see "Phase 5 -- the effect
declarations" in docs/specs/2026-09-21-line-of-fire-spec.md and
docs/specs/2026-09-21-line-of-fire-brief-phase56.md).

Reads lib/*.irh as text -- no build needed -- and asserts, for each of the
15 bolt/ray effects that gained an attack roll, that its PRIMARY block
carries the EF_ATTACK flag and carries exactly the save state the brief
specifies (removed for the six that used to save against the damage,
unchanged for the rest). It also asserts the negative cases the brief names:
Call Companions gained neither EF_ATTACK nor a changed aval, and Magic
Missile, Force Missiles and Acid;wand still carry no EF_ATTACK.

A "primary block" is found by locating the effect's declaration line (by
its exact quoted name and archetype) and then brace-matching the first
`{ ... }` that follows, skipping over string literals and comments so a
brace inside a Desc string or a // comment cannot desync the count.

Usage: tools/check_line_of_fire_effects.sh   (wraps this file)
Exit: 0 all assertions hold, 1 something drifted, 2 could not find a block.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def mask_comments_and_strings(s: str) -> str:
    """Replace the CONTENTS of every // comment and /* */ comment with
    spaces (newlines kept, so line numbers/positions do not move). String
    literals ("...") are left untouched -- a spell's own quoted name must
    stay visible for the header search -- but are still tracked so a `/`
    inside one is never mistaken for the start of a comment. Used so a
    declaration's name mentioned only in a header-comment spell list, or a
    field name mentioned only in prose, cannot be mistaken for the real
    thing -- the exact trap that bit lib/pspells.irh's own "Alicorn Lance"
    and "Call Companions", each named once in a listing comment and once
    for real, and lib/m_items.irh's "Striking;wand" upstream: note, which
    says "sval: REF" in prose right beside the real field of the same
    name."""
    out = list(s)
    i = 0
    in_str = in_line_comment = in_block_comment = False
    while i < len(s):
        c = s[i]
        nxt = s[i + 1] if i + 1 < len(s) else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            else:
                out[i] = " "
        elif in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                out[i] = out[i + 1] = " "
                i += 1
            elif c != "\n":
                out[i] = " "
        elif in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif c == "/" and nxt == "/":
            in_line_comment = True
            out[i] = " "
        elif c == "/" and nxt == "*":
            in_block_comment = True
            out[i] = out[i + 1] = " "
            i += 1
        elif c == '"':
            in_str = True
        i += 1
    return "".join(out)


def extract_block(path: Path, header_pattern: str, occurrence: int = 1):
    """Return (primary_block_text, rider_block_texts) for the first (or Nth)
    declaration in `path` whose line matches `header_pattern`, by brace-
    matching from the first '{' after that line. The header search runs
    over a comment/string-masked copy of the file, so a name that appears
    only inside a comment (a header spell-list, a stale note) cannot be
    mistaken for the real declaration."""
    text = path.read_text(encoding="utf-8", errors="replace")
    masked = mask_comments_and_strings(text)
    lines = masked.split("\n")
    header_re = re.compile(header_pattern)
    seen = 0
    header_line_idx = None
    for i, line in enumerate(lines):
        if header_re.search(line):
            seen += 1
            if seen == occurrence:
                header_line_idx = i
                break
    if header_line_idx is None:
        return None, []

    # Reassemble from the header line onward, from the REAL text (masking
    # was only to find the right line), and brace-match blocks one at a
    # time, skipping strings and comments so an embedded brace (inside a
    # Desc string, or inside an On Event handler's own C-like code) cannot
    # desync the depth count.
    real_lines = text.split("\n")
    rest = "\n".join(real_lines[header_line_idx:])

    def find_blocks(s, start, count):
        """Find `count` consecutive brace-delimited blocks starting the
        search at `start`, allowing `and EA_TYPE` between them. Returns
        (list_of_block_texts, end_offset)."""
        blocks = []
        pos = start
        for _ in range(count):
            brace = s.find("{", pos)
            if brace == -1:
                break
            depth = 0
            i = brace
            in_str = False
            in_line_comment = False
            in_block_comment = False
            block_start = brace
            while i < len(s):
                c = s[i]
                nxt = s[i + 1] if i + 1 < len(s) else ""
                if in_line_comment:
                    if c == "\n":
                        in_line_comment = False
                elif in_block_comment:
                    if c == "*" and nxt == "/":
                        in_block_comment = False
                        i += 1
                elif in_str:
                    if c == "\\":
                        i += 1
                    elif c == '"':
                        in_str = False
                elif c == "/" and nxt == "/":
                    in_line_comment = True
                    i += 1
                elif c == "/" and nxt == "*":
                    in_block_comment = True
                    i += 1
                elif c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        blocks.append(s[block_start:i + 1])
                        pos = i + 1
                        break
                i += 1
            else:
                break
        return blocks, pos

    # Primary block.
    primary_list, pos = find_blocks(rest, 0, 1)
    if not primary_list:
        return None, []
    primary = primary_list[0]

    # Any further "and EA_TYPE { ... }" riders, contiguous.
    riders = []
    while True:
        m = re.match(r"\s*and\s+EA_\w+", rest[pos:pos + 200])
        if not m:
            break
        and_start = pos + m.start()
        rider_list, new_pos = find_blocks(rest, and_start, 1)
        if not rider_list:
            break
        riders.append(rider_list[0])
        pos = new_pos

    return primary, riders


# All four field-inspecting helpers below mask comments and string
# literals FIRST: a field name mentioned only in an upstream: comment (as
# this file's own Striking;wand note now does -- "The knockback rider's
# sval: REF, below") or only in a Desc string must not read as the field.

def has_flag(block: str, flag: str) -> bool:
    masked = mask_comments_and_strings(block)
    for m in re.finditer(r"[Ff]lags\s*:\s*([^;]*);", masked):
        names = [t.strip() for t in m.group(1).split(",")]
        if flag in names:
            return True
    return False


def has_sval(block: str) -> bool:
    return re.search(r"\bsval\s*:", mask_comments_and_strings(block)) is not None


def sval_value(block: str):
    m = re.search(r"\bsval\s*:\s*([A-Za-z_]+)", mask_comments_and_strings(block))
    return m.group(1).upper() if m else None


def has_aval(block: str, aval: str) -> bool:
    masked = mask_comments_and_strings(block)
    return re.search(r"\baval\s*:\s*" + re.escape(aval) + r"\b", masked) is not None


CASES = [
    # (label, file, header regex, expect EF_ATTACK, expect sval present, expect sval value or None)
    ("Caustic Vitae", "lib/pspells.irh", r'Effect "Caustic Vitae"\s*:\s*EA_BLAST', True, False, None),
    ("Chill Blood", "lib/wspells.irh", r'Effect "Chill Blood"\s*:\s*EA_BLAST', True, False, None),
    ("Fire Bolts", "lib/m_items.irh", r'Effect "Fire Bolts"\s*:\s*EA_BLAST', True, False, None),
    ("Thunderbolts", "lib/m_items.irh", r'Effect "Thunderbolts"\s*:\s*EA_BLAST', True, False, None),
    ("Striking;wand", "lib/m_items.irh", r'Effect "Striking;wand"\s*:\s*EA_BLAST', True, False, None),
    ("Venom of Khasrach", "lib/religion.irh", r'Effect "Venom of Khasrach"\s*:\s*EA_BLAST', True, False, None),
    ("Acid Arrow", "lib/wspells.irh", r'Spell "Acid Arrow"\s*:\s*EA_BLAST', True, False, None),
    ("Disintegrate", "lib/wspells.irh", r'Spell "Disintegrate"\s*:\s*EA_BLAST', True, True, "FORT"),
    ("Telekinesis;thrust", "lib/wspells.irh", r'Effect "Telekinesis;thrust"\s*:\s*EA_BLAST', True, False, None),
    ("Telekinesis;psi-thrust", "lib/alchemy.irh", r'Effect "Telekinesis;psi-thrust"\s*:\s*EA_BLAST', True, False, None),
    ("the Ram", "lib/m_items.irh", r'Effect "the Ram"\s*:\s*EA_BLAST', True, True, "REF"),
    ("Force Bolt", "lib/wspells.irh", r'Spell "Force Bolt"\s*:\s*EA_BLAST', True, True, "REF"),
    ("Icelance", "lib/wspells.irh", r'Spell "Icelance"\s*:\s*EA_BLAST', True, True, "NOSAVE"),
    ("tongue of flame", "lib/m_items.irh", r'Effect "tongue of flame"\s*:\s*EA_BLAST', True, False, None),
    ("Alicorn Lance", "lib/pspells.irh", r'Spell "Alicorn Lance"\s*:\s*EA_BLAST', True, False, None),
]


def main():
    failures = []
    passes = []

    for label, relpath, pattern, want_attack, want_sval_present, want_sval_value in CASES:
        path = ROOT / relpath
        primary, riders = extract_block(path, pattern)
        if primary is None:
            failures.append(f"{label}: could not find its declaration in {relpath}")
            continue

        got_attack = has_flag(primary, "EF_ATTACK")
        if got_attack != want_attack:
            failures.append(
                f"{label}: EF_ATTACK on primary block is {got_attack}, want {want_attack}")
            continue

        got_sval_present = has_sval(primary)
        if got_sval_present != want_sval_present:
            failures.append(
                f"{label}: primary block sval present={got_sval_present}, "
                f"want {want_sval_present} (sval={sval_value(primary)!r})")
            continue

        if want_sval_present and want_sval_value is not None:
            got_val = sval_value(primary)
            if got_val != want_sval_value:
                failures.append(
                    f"{label}: primary block sval is {got_val!r}, want {want_sval_value!r}")
                continue

        passes.append(f"{label}: EF_ATTACK={got_attack} sval_present={got_sval_present}"
                       + (f" sval={want_sval_value}" if want_sval_value else ""))

    # inc-30ps Task 1: five Desc strings still promised a Reflex save against
    # DAMAGE after Phase 5 removed that save (the six bolt effects that lost
    # their sval; Striking;wand's own Desc was already rewritten in an
    # earlier pass). Each of the five below must now describe the required
    # ranged touch attack, and must no longer carry the specific stale
    # promise this change removed. This is a prose-vs-mechanics guard, not a
    # grammar check: it does not care how the sentence is phrased, only that
    # the new mechanic is named and the old, now-false promise is gone.
    PROSE_CASES = [
        ("Caustic Vitae", "lib/pspells.irh", r'Effect "Caustic Vitae"\s*:\s*EA_BLAST',
         "ranged touch attack",
         "A Reflex saving throw is allowed for half damage"),
        ("Chill Blood", "lib/wspells.irh", r'Effect "Chill Blood"\s*:\s*EA_BLAST',
         "ranged touch attack",
         "suffers half normal damage and is not stunned"),
        ("Fire Bolts", "lib/m_items.irh", r'Effect "Fire Bolts"\s*:\s*EA_BLAST',
         "ranged touch attack",
         "represents dodging the bolt, and\n      completely negates the damage"),
        ("Thunderbolts", "lib/m_items.irh", r'Effect "Thunderbolts"\s*:\s*EA_BLAST',
         "ranged touch attack",
         "A Reflex save indicates dodging the bolt utterly"),
        ("Venom of Khasrach", "lib/religion.irh", r'Effect "Venom of Khasrach"\s*:\s*EA_BLAST',
         "ranged touch attack",
         "allowing the victim a saving throw for half damage"),
    ]
    for label, relpath, pattern, want_phrase, forbid_phrase in PROSE_CASES:
        primary, _ = extract_block(ROOT / relpath, pattern)
        if primary is None:
            failures.append(f"{label}: could not find its declaration for the prose check")
            continue
        desc_m = re.search(r'Desc\s*:\s*"(.*?)";', primary, re.DOTALL)
        desc = desc_m.group(1) if desc_m else primary
        norm = " ".join(desc.split())
        if want_phrase not in norm:
            failures.append(f"{label}: Desc no longer mentions {want_phrase!r}")
        elif " ".join(forbid_phrase.split()) in norm:
            failures.append(f"{label}: Desc still promises the removed save ({forbid_phrase!r})")
        else:
            passes.append(f"{label}: Desc requires a ranged touch attack, stale save promise gone")

    # Alicorn Lance: also assert the damage type moved off AD_PIERCE onto
    # AD_MAGC (this engine's "force damage" type -- see inc/Defines.h's own
    # comment on AD_MAGC: "magic missiles, force bolts,...").
    primary, _ = extract_block(ROOT / "lib/pspells.irh", r'Spell "Alicorn Lance"\s*:\s*EA_BLAST')
    if primary is not None:
        if not re.search(r"\bxval\s*:\s*AD_MAGC\b", primary):
            failures.append("Alicorn Lance: xval is not AD_MAGC")
        else:
            passes.append("Alicorn Lance: xval=AD_MAGC (force damage)")

    # Chill Blood: the rider (STUNNED) must keep ITS OWN sval, unchanged.
    primary, riders = extract_block(ROOT / "lib/wspells.irh", r'Effect "Chill Blood"\s*:\s*EA_BLAST')
    if riders and sval_value(riders[0]) == "REF":
        passes.append("Chill Blood: rider (STUNNED) still carries sval: REF")
    else:
        failures.append(f"Chill Blood: rider sval is {sval_value(riders[0]) if riders else None!r}, want REF")

    # Striking;wand: the knockback rider must keep ITS OWN sval, unchanged.
    primary, riders = extract_block(ROOT / "lib/m_items.irh", r'Effect "Striking;wand"\s*:\s*EA_BLAST')
    if riders and sval_value(riders[0]) == "REF":
        passes.append("Striking;wand: knockback rider still carries sval: REF")
    else:
        failures.append(f"Striking;wand: rider sval is {sval_value(riders[0]) if riders else None!r}, want REF")

    # Thunderbolts: the sonic/stun rider carries no sval field at all (its
    # Fortitude save is a hardcoded SavingThrow() call, not a data field),
    # and that must stay untouched.
    primary, riders = extract_block(ROOT / "lib/m_items.irh", r'Effect "Thunderbolts"\s*:\s*EA_BLAST')
    if riders and not has_sval(riders[0]):
        passes.append("Thunderbolts: sonic/stun rider still carries no sval field")
    else:
        failures.append("Thunderbolts: sonic/stun rider's sval state changed")

    # Icelance's Desc must no longer claim "automatically hits".
    primary, _ = extract_block(ROOT / "lib/wspells.irh", r'Spell "Icelance"\s*:\s*EA_BLAST')
    if primary is not None and "automatically hits" in primary:
        failures.append("Icelance: Desc still says \"automatically hits\"")
    else:
        passes.append("Icelance: Desc no longer claims \"automatically hits\"")

    # Alicorn Lance's Desc must no longer promise a saving throw, and must
    # still keep the ghost-touch sentence.
    primary, _ = extract_block(ROOT / "lib/pspells.irh", r'Spell "Alicorn Lance"\s*:\s*EA_BLAST')
    if primary is not None:
        if "saving throw for half" in primary:
            failures.append("Alicorn Lance: Desc still promises a saving throw for half damage")
        elif "ghost touch" not in primary:
            failures.append("Alicorn Lance: Desc lost the ghost-touch sentence")
        else:
            passes.append("Alicorn Lance: Desc drops the save, keeps ghost touch")

    # --- Negative cases -----------------------------------------------
    primary, _ = extract_block(ROOT / "lib/pspells.irh", r'Spell "Call Companions"\s*:\s*EA_GENERIC', occurrence=1)
    if primary is None:
        failures.append("Call Companions: could not find its declaration")
    else:
        if has_flag(primary, "EF_ATTACK"):
            failures.append("Call Companions: gained EF_ATTACK -- it is not an attack")
        elif not has_aval(primary, "AR_BOLT"):
            failures.append("Call Companions: aval is no longer AR_BOLT")
        else:
            passes.append("Call Companions: no EF_ATTACK, aval still AR_BOLT")

    for label, relpath, pattern in [
        ("Magic Missile", "lib/wspells.irh", r'Spell "Magic Missile"\s*:\s*EA_BLAST'),
        ("Force Missiles", "lib/wspells.irh", r'Spell "Force Missiles"\s*:\s*EA_BLAST'),
        ("Acid;wand", "lib/m_items.irh", r'Effect "Acid;wand"\s*:\s*EA_BLAST'),
    ]:
        primary, riders = extract_block(ROOT / relpath, pattern)
        if primary is None:
            failures.append(f"{label}: could not find its declaration")
            continue
        blocks = [primary] + riders
        if any(has_flag(b, "EF_ATTACK") for b in blocks):
            failures.append(f"{label}: gained EF_ATTACK -- it must stay unerring")
        else:
            passes.append(f"{label}: still carries no EF_ATTACK (stays unerring)")

    print(f"line_of_fire_effects: {len(passes)} passed, {len(failures)} failed")
    for p in passes:
        print(f"  PASS {p}")
    for f in failures:
        print(f"  FAIL {f}")

    if failures:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
