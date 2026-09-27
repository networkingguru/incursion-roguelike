#!/usr/bin/env python3
# gate: live -- it -dumps the committed fixture saves through the built binary
# and the module in the tree, so it needs BACKEND=posix ./build_macos.sh first.
"""Case 20 oracle: IS1.3 recovery against an independent pre-fix reading.

The recovered values are read from `-dump`'s "=== Script Variables ==="
section. `-dump` snapshots the values the load placed, before any report step
runs game logic (docs/SAVE-SCHEMA-SPEC.md test plan: the report's own steps,
e.g. DumpStati, run scripts that write variables). `-recovervars` is no longer
used; the report itself is the oracle now.

The expected values are built from the SAVE's own rev-3 payloads, with the
documented pre-fix IS1.3 layout (v1SegUnpackRow), not from any dump:
  row p -> a 16-byte MonMem image at byte 16p; image bytes 0..387 are the 97
  table slots; partial units (k%4 in 1,2,3) drop DT_HOBJ and DT_RID to 0;
  a whole-unit DT_RID converts through the save's own manifest lengths.

Cross-check: the Python image below is validated against the frozen 391e353
build's own reading of the same save (see the report). For
levitate-bottom-seed1.sav, row 0 word0 is 0x174de8 both ways.
"""
import ast, os, pathlib, re, shutil, struct, subprocess, tempfile
from script_vars_save_diff import records

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORK = pathlib.Path(tempfile.mkdtemp(prefix='script-var-recovery.', dir=ROOT/'logs'))
BIN = ROOT/'incursion-headless'
SAVE_DIRS = [ROOT/'tools/fixtures/chars']
print(f'Specimens: {WORK}', flush=True)
for d in ['save', 'logs']:
    (WORK/d).mkdir()
(WORK/'mod').symlink_to(ROOT/'mod')
(WORK/'lib').symlink_to(ROOT/'lib')

def run(save, tag):
    env = dict(os.environ, INCURSIONPATH=str(WORK)+'/')
    r = subprocess.run([str(BIN), '-dump', str(save)], env=env, cwd=WORK,
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, errors='replace')
    (WORK/(tag+'.out')).write_text(r.stdout)
    (WORK/(tag+'.err')).write_text(r.stderr)
    return r

# ---- the committed table --------------------------------------------------
rows = []
for line in (ROOT/'src/SaveV1PrefixVars.inc').read_text().splitlines():
    if line.startswith('    {'):
        rows.append(ast.literal_eval('('+line.strip().rstrip(',')[1:-1]+')'))
assert len(rows) == 97, len(rows)
LENGTHS = [int(v) for v in re.search(r'v1PrefixLengths\[21\] = \{([^}]*)\}',
           (ROOT/'src/SaveV1PrefixVars.inc').read_text()).group(1).split(',')]
assert len(LENGTHS) == 21

# ---- the current module's loaded address for every table row --------------
loaded = {}
v = subprocess.run([str(BIN), '-scriptvars'], cwd=ROOT,
                   env=dict(os.environ, INCURSIONPATH=str(ROOT)+'/'),
                   capture_output=True, text=True, errors='replace')
for line in v.stdout.splitlines():
    c = line.split('\t')
    if len(c) == 7 and re.fullmatch(r'-?\d+', c[0]):
        loaded[(int(c[0]), int(c[1]), int(c[3]))] = int(c[6])

def monster_rows(path):
    fs = next(fs for (t, h), fs in records(path).items() if t == 1)
    if '816.1.3' not in fs:
        return None
    blob = fs['816.1.3'][1]; pos = 0; out = {}
    while pos < len(blob):
        kind = blob[pos]; position, = struct.unpack_from('<I', blob, pos+2); pos += 6
        pl = blob[pos]; pos += 1
        pay = blob[pos:pos+pl]; pos += pl
        if kind == 0 and position < 25:
            out[position] = pay
    return out

def pre_fix_image(rows_by_pos):
    """The 400-byte image the pre-fix rev-3 reader laid, row p at byte 16p.

    MonMem is a bitfield struct (inc/Res.h): Battles:8, Deaths:8, Kills:8,
    pKills:8, Attacks:9, Resists:8, Immune:16, Seen:1, Fought:1, Feats:16,
    Flags:5. A 32-bit-storage compiler gives each run of bitfields that
    cannot finish in the current word a fresh word, so the 88 bits land as
    four little-endian words (sizeof==16):
      word0 Battles|Deaths<<8|Kills<<16|pKills<<24
      word1 Attacks|Resists<<9                     (17 bits)
      word2 Immune|Seen<<16|Fought<<17             (18 bits)
      word3 Feats|Flags<<16                        (21 bits)
    The recovery reads word k; so must we.
    """
    img = bytearray(400)
    for position, pay in rows_by_pos.items():
        att = pay[4] | (pay[5] << 8)          # 9 bits
        res = pay[6]
        imm = pay[7] | (pay[8] << 8)          # 16 bits
        seen = pay[9] & 1
        fought = (pay[9] >> 1) & 1
        feats = pay[10] | (pay[11] << 8)
        flags = pay[12] & 0x1F
        word0 = pay[0] | (pay[1] << 8) | (pay[2] << 16) | (pay[3] << 24)
        word1 = att | (res << 9)
        word2 = imm | (seen << 16) | (fought << 17)
        word3 = feats | (flags << 16)
        row = struct.pack('<IIII', word0, word1, word2, word3)
        img[16*position:16*position+16] = row
    return img

def manifest(path):
    fs = next(fs for (t, h), fs in records(path).items() if t == 1)
    blob = fs['816.1.5'][1]; names = []; off = 0
    while off < len(blob):
        n, = struct.unpack_from('<H', blob, off); off += 2
        names.append(blob[off:off+n].decode(errors='replace')); off += n
    lengths = struct.unpack('<21I', fs['816.1.4'][1][8:])
    return lengths, names

def convert_rid(saved, lengths):
    slot = (saved >> 24) - 1
    idx = saved & 0xFFFFFF
    if slot < 0: return None
    array = -1; position = idx
    for p in range(21):
        if position < lengths[p]: array = p; break
        position -= lengths[p]
    if array < 0: return None
    running = sum(lengths[p] for p in range(array))
    return (running + position + ((slot+1) << 24))

# ---- gather saves ---------------------------------------------------------
files = []
for d in SAVE_DIRS:
    files += sorted(d.glob('*.sav'))
for name in ['Keos', 'Zakfienal']:
    src = pathlib.Path.home()/'Scripts/Incursion/save'/f'{name}.sav'
    if src.exists():
        dst = WORK/f'{name}.sav'; shutil.copyfile(src, dst); files.append(dst)

def is_is13(p):
    try: return p.read_bytes()[4:9] == b'IS1.3'
    except OSError: return False

failures = []; checked_rows = 0; best = None; per_file = {}
for i, file in enumerate(files):
    if not is_is13(file):
        r = subprocess.run([str(BIN), '-dump', str(file)],
                           cwd=WORK, env=dict(os.environ, INCURSIONPATH=str(WORK)+'/'),
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, errors='replace')
        if r.returncode:
            failures.append((file.name, 'load refused', r.returncode, r.stderr.strip()))
        continue
    r = run(file, f'rv-{i}')
    if r.returncode:
        failures.append((file.name, 'recovervars refused', r.returncode, r.stderr.strip()))
        continue
    observed = {int(m[0]): int(m[1]) for m in
                re.findall(r'slot=(\d+) .*?value=(-?\d+)', r.stdout)}
    rows_by_pos = monster_rows(file)
    if rows_by_pos is None:
        failures.append((file.name, 'no monster rows', 0, ''))
        continue
    lengths, names = manifest(file)
    img = pre_fix_image(rows_by_pos)
    slots = [struct.unpack_from('<i', img, 4*k)[0] for k in range(97)]
    # Which of the four units of a 16-byte row carry a NONZERO slot value:
    # unit 0 is whole (32 bits), units 1,2,3 are the 17/18/21-bit partial
    # units the MonMem bitfields leave.
    widths = sorted({k % 4 for k in range(97) if slots[k]})
    ordinals = {}; got_slots = {}
    for k, (array, pos, owner, name, typ) in enumerate(rows):
        ordinal = ordinals.get((array, pos), 0); ordinals[(array, pos)] = ordinal+1
        key = (array, pos, ordinal) if array >= 0 else None
        if key is None:
            continue  # module variable: owner array -1, not part of the image
        if key not in loaded:
            continue  # table row has no loaded slot (drift): not case 20's contract
        expected = struct.unpack_from('<i', img, 4*k)[0]
        partial = k % 4  # 0 whole, 1/2/3 partial
        if typ == 4:                       # DT_HTEXT
            expected = 0
        elif partial and typ in (3, 5):    # cut hObj / rID
            expected = 0
        elif typ == 5 and expected:        # whole-unit rID converts by position
            conv = convert_rid(expected & 0xFFFFFFFF, lengths)
            expected = conv if conv is not None else 0
        got = observed.get(loaded[key])
        got_slots[k] = got
        checked_rows += 1
        if got != expected:
            failures.append((file.name, k, expected, got,
                             dict(zip(['array','pos','owner','name','type'], (array,pos,owner,name,typ)))))
    per_file[file.name] = (widths, slots, got_slots)
    if best is None or len(widths) > len(best[2]):
        best = (file, i, widths, img, slots)

# Case 20's named coverage, with values read independently from each save's
# own rev-3 payloads. No single committed fixture carries nonzero values in
# all four unit widths, so the two home saves together cover them, with the
# partial-unit hObj-drop rule exercised by a real value:
#   Keos      whole (slot 0) + 21-bit partial hObj (slot 31 -> 0)
#   Zakfienal whole (slots 0, 88) + 17-bit partial (61) + 18-bit partial (62)
NAMED = {
    'Keos.sav':      [(0, 0, 1494680), (31, 3, 0)],
    'Zakfienal.sav': [(0, 0, 1494680), (61, 1, 5), (62, 2, 5), (88, 0, 1)],
}
for name, wants in NAMED.items():
    if name not in per_file:
        failures.append((name, 'named save missing from the run', 0, 0, {}))
        continue
    widths, slots, got_slots = per_file[name]
    for slot, unit, want in wants:
        got = got_slots.get(slot)
        if got != want:
            failures.append((name, slot, want, got, {'unit': unit}))
    print(f'named {name}: nonzero-unit-positions={widths}; '
          f'values={[(s, u, got_slots.get(s)) for s, u, _ in wants]}', flush=True)

print(f'case 20 IS1.3 files={sum(is_is13(f) for f in files)}/{len(files)}; '
      f'rows checked={checked_rows}', flush=True)
if best:
    file, i, widths, img, slots = best
    print(f'best={file.name} index={i} nonzero-unit-positions={widths} '
          f'(0=whole,1=17-bit,2=18-bit,3=21-bit); nonzero slots='
          + str([(k, slots[k]) for k in range(97) if slots[k]])[:400], flush=True)
if failures:
    print('FAIL sample:', failures[:12], flush=True)
    raise SystemExit(1)
print('PASS case 20: every recovered slot equals the independent pre-fix image', flush=True)
