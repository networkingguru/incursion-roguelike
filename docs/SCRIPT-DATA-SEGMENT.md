<!-- citations: this-port -->

# The module script data segment

Scope: the `szDataSeg` bytes at the front of each `Game::MDataSeg[i]` block.
This note answers whether the v1 save schema (`docs/SAVE-SCHEMA-SPEC.md`,
"The resource memory segment") must carry that front region, and how. It is
the first task of phase 4 and governs how Task 9 writes the v1 segment record.

Evidence tiers follow the project's ledger convention: **Observed** (a byte
value or count this note ran), **Traced** (read from source, no run), **Reasoned**
(an inference from traced facts).

## Verdict (read this first)

**Task 9 MUST carry the script data segment as a length-prefixed raw blob, and
MUST throw `ECORRUPT` on load when the saved blob's length does not equal the
loaded module's `szDataSeg`.**

The segment is **0 bytes in every real module** (Observed) and its length does
**not** depend on the resource pools (Observed and Traced), so this rule is free
today and does not make ordinary saves fragile. See "Why carry-raw is safe here"
and "What Task 9 must do" below.

## What it is

`Game::MDataSeg[i]` is one flat byte block per loaded module. Its length is
`MDataSegSize[i]`, computed at `src/Main.cpp:594` as:

```
szDataSeg + ( szMon*sizeof(MonMem) + szItm*sizeof(ItemMem)
            + szEff*sizeof(EffMem) + szReg*sizeof(RegMem) ) * NumPlayers()
```

The block has two parts, in this order (Traced):

1. **The script data segment** — bytes `[0, szDataSeg)`. This is the module's
   VM global-variable storage. The virtual machine reads it as `int32 Memory[]`
   (`src/VMachine.cpp:464`, `Memory = (int32*)theGame->MDataSeg[mn]`), and a
   global variable is a bare index into it (`MEMORY(pv)` in `VMachine::Value1`,
   `src/VMachine.cpp:347`).
2. **The per-player resource memory rows** — bytes `[szDataSeg, MDataSegSize)`.
   `Module::GetMemoryPtr` (`src/Res.cpp:711`) addresses these arithmetically;
   it starts its offset at `szDataSeg` (`src/Res.cpp:714`, `ptr = szDataSeg`)
   and adds `MonMem`/`ItemMem`/`EffMem`/`RegMem` rows keyed by the resource's
   position. Those rows are what the spec's "resource memory segment" section
   replaces with name-keyed records; this note is only about part 1 in front of
   them.

`szDataSeg` is a serialized field of the `Module` object (`inc/Res.h:848`,
`FIELD_I32(2, szDataSeg)`; declared at `inc/Res.h:988`).

## How it is written

**Nothing in the port ever assigns `szDataSeg`.** (Traced, and this is the
central finding.)

- A grep of `src/` and `inc/` for an assignment to `szDataSeg` finds none. The
  compiler assigns its two siblings — `szCodeSeg` at `src/RComp.cpp:196` and
  `szTextSeg` at `src/RComp.cpp:445` — but never `szDataSeg`.
- `Module` is created with `new Module`, and `Object::operator new` zeroes the
  whole allocation (`inc/Base.h:668`, `memset(vp,0,sz + pad)`). So `szDataSeg`
  starts at 0 and, absent any assignment, stays 0 through compile and through
  the serialize at `inc/Res.h:848`.
- The VM's global-variable machinery does exist: the grammar assigns each
  global an address `Address = HeapHead++` (`lang/Grammar.acc:1363`, generated
  into `src/yygram.cpp:7797`), where `HeapHead` is a plain counter starting at 0
  (`src/RComp.cpp:65`). But `HeapHead` is never written back into `szDataSeg`.
  The compiler counts globals and forgets the count.

So the "compiled script state whose layout the resource compiler chooses" that
the spec anticipates (`docs/SAVE-SCHEMA-SPEC.md`, risk 5) **does not exist in
this port**: the region in front of the memory rows is empty.

### Measurements

Method: the resource compiler writes each module as an LZ-compressed group
(`src/Registry.cpp:1460`, `SaveGroup(..., true, true)`; the compress happens at
`src/Registry.cpp:808`). Inside the group each object is written as one type
byte then its raw struct bytes (`src/Registry.cpp:760` and `:762`). A scratch C
harness (`scratchpad/modpeek3.c`) decompresses the group with the game's own
`LZ_Uncompress` and reads `szTextSeg`, `szDataSeg`, `szCodeSeg` straight out of
the `Module` struct image. The read is cross-checked: the `szTextSeg` value must
equal the size of the module's `QTextSeg` data node, and it does, which fixes
the field offset beyond doubt. The `Module` struct is 49464 bytes, matching the
pin at `inc/Res.h:833`.

Three modules, all built at HEAD `0e62b33`:

| Module | szTextSeg | **szDataSeg** | szCodeSeg | group size |
|---|---|---|---|---|
| Shipped `mod/Incursion.Mod` | 1539725 | **0** | 99989 | 2955566 |
| Clean sandbox rebuild | 1539725 | **0** | 99989 | 2955566 |
| Sandbox + one extra `Effect` | 1539819 | **0** | 99989 | 2955732 |

The sandbox technique is `tools/check_dup_names.sh`'s: `lib/` copied, `inc/`
symlinked, `mod/` empty, compiled with `./incursion -compile main.irc` under an
`INCURSIONPATH` sandbox; no tracked file was touched.

Commands (run from the repo root, sandboxes under the scratch directory):

```
# clean rebuild == shipped module (validates the method)
INCURSIONPATH="$SB/clean/" ./incursion -compile main.irc

# one extra AI_STONE Effect "Scratch Segment Probe" appended to
# the sandbox copy of lib/m_items.irh, then:
INCURSIONPATH="$SB/plus1/" ./incursion -compile main.irc

# read szDataSeg from each module:
clang -O0 -o modpeek3 modpeek3.c src/lz.c
./modpeek3 <module>
```

What the numbers show:

- **The clean rebuild reproduces the shipped module exactly** (identical
  `szTextSeg`, `szCodeSeg`, group size). The measurement method is sound.
- **Adding one `Effect` changed the module** — `szTextSeg` grew by 94 bytes (the
  effect's name and description text) and the group grew by 166 bytes — so the
  build genuinely differs.
- **`szDataSeg` stayed 0 across all three.** (Observed.)

## What renumbering does to it

Nothing, and it could not, even if the segment were non-empty. (Q3.)

- **Today: there is no content.** With `szDataSeg == 0` the segment is
  0 bytes, so there is nothing to renumber. (Observed.)
- **Hypothetically, if globals were wired up:** the data segment would hold VM
  global variables addressed by `HeapHead` index (`lang/Grammar.acc:1363`),
  assigned in *global-declaration order*, not resource order. Adding or removing
  an `Effect`/`Item`/`Monster` does not add or remove a global, so it cannot
  move a global's address. The data segment is welded to the *global-variable
  declarations*, which are orthogonal to the resource pools that the renumbering
  defect (`docs/SAVE-SCHEMA-SPEC.md`) is about. (Reasoned, from the traced
  addressing scheme.)
- **One residual `rID` risk, and it is runtime data not layout:** a script may
  store a resource `rID` into a global `int32`. That stored *value* would be a
  raw `rID` and would renumber like any other. But it is runtime state written
  by a running game, not compiler-chosen layout, and there is 0 bytes of it
  today. If globals are ever wired up, Task 9's name-table routing for `rID`
  values would have to be extended to cover globals that hold `rID`s — the
  segment record cannot know which globals those are. This note flags it; it is
  not actionable now. (Reasoned.)

## Why carry-raw is safe here

The brief's warning is that a carry-raw-with-length-check verdict forces an
abort on any module change, which would make converted and old saves fragile.
That warning does **not** apply to this segment, because `szDataSeg` is
**build-independent**: it is 0 for the clean module and 0 for the module with an
extra `Effect` (Observed), and no compile path can make it otherwise (Traced).
The length check therefore never fires on the module changes Task 9 exists to
survive (added/removed/reordered resources). It would fire only if a future
change added or removed a *global-variable declaration* AND a save straddled
that change — and in that case the opaque global state genuinely has no safe
automatic reconciliation, so aborting is the correct, honest failure rather than
silently truncating or zero-extending someone's global VM state.

Rejected alternatives:

- **carry-raw-and-truncate/extend:** would silently corrupt global VM state on
  a real length change. Rejected: the segment is opaque; the loader cannot know
  which bytes to drop or zero.
- **rebuild-from-module:** there is nothing to rebuild — the compiler produces
  no data-segment content (Traced). A "rebuild" would just be "write
  `szDataSeg` zero bytes", which is what carry-raw already does today, minus the
  length guard that protects a future wired-up build.
- **omit the segment entirely and assert `szDataSeg == 0`:** viable today, but
  it hard-codes the current defect (globals never wired) into the save format.
  Carry-raw-with-length-check degrades gracefully instead: it writes 0 bytes now
  and N bytes with a guard later, with no format change.

## What Task 9 must do

1. Write the v1 segment record for module `i` as two things: the module's
   `szDataSeg` (as its own length, from the loaded module — it is authoritative
   at save time) and a raw blob of exactly that many bytes copied from the front
   of `MDataSeg[i]`. Today that blob is empty.
2. Write the resource memory *rows* that follow (bytes `[szDataSeg, MDataSegSize)`)
   as the name-keyed records the spec requires. These replace the raw
   `FIELD_BLOB` at `inc/Res.h:1234` and its embed at `inc/Res.h:1231`.
3. On load, after the loaded module is known, compare the saved segment length
   against the loaded module's `szDataSeg`. If they differ, throw `ECORRUPT`.
   If they match (always, today), copy the blob to the front of the freshly
   allocated `MDataSeg[i]` (allocated at `src/Main.cpp:600`) and lay the
   name-keyed rows in behind it.

**If a future change wires `szDataSeg` to `HeapHead` and a global ever holds an
`rID`:** carry-raw preserves the bytes but does not renumber a stored `rID`
inside them. Task 9's `rID` name-table routing covers object *fields*, not
global VM slots. That gap must be closed at that time, not now; there are 0
bytes of global state today. Task 9 differs from a rebuild-from-module verdict
in exactly this: it never tries to reconstruct or reinterpret the segment's
bytes — it moves them verbatim and guards their length — because the bytes are
opaque compiled/runtime state the loader has no key to.

## Commands, verbatim

```
# repo root
SB=<scratchpad>
# clean sandbox
mkdir -p "$SB/clean/mod" "$SB/clean/save" "$SB/clean/logs"
cp -R lib "$SB/clean/lib"; ln -sfn "$PWD/inc" "$SB/clean/inc"
INCURSIONPATH="$SB/clean/" ./incursion -compile main.irc < /dev/null
# +1 Effect sandbox: same, plus this appended to $SB/plus1/lib/m_items.irh:
#   AI_STONE Effect "Scratch Segment Probe" : EA_GRANT
#     { xval: ADJUST; yval: A_WIS; pval: PLUS_1PER1;
#       Flags: EF_NEEDS_PLUS, EF_NAMEONLY; SC_THE; Level: PLUS_2PER1;
#       Desc: "..."; Lists: * ITEM_COST ABIL_BOOST_COST(150); }
INCURSIONPATH="$SB/plus1/" ./incursion -compile main.irc < /dev/null
# read szDataSeg (scratchpad/modpeek3.c decompresses with src/lz.c):
clang -O0 -o modpeek3 modpeek3.c src/lz.c
./modpeek3 mod/Incursion.Mod
./modpeek3 "$SB/clean/mod/Incursion.Mod"
./modpeek3 "$SB/plus1/mod/Incursion.Mod"
```

Output for all three: `szDataSeg=0`.
