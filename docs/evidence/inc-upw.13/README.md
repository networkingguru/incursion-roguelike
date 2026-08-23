# Save-file specimens

Two of Brian's own save files, copied here on 2026-08-21 before `save/` was
cleared. Both were cited by documents that had no durable copy of them, which
is the failure this directory repairs: the citation would have outlived the
file.

## Jaoin.sav

The specimen behind the "Base-code bugs fixed locally" row for **inc-upw.13**
in `docs/REPORTING-GATE.md`. That row's evidence is a 20-turn sandboxed walk on
a read-only copy of this save, which logged 74 `ASSERT failed:
'...Get(h)->isCreature()'` lines under a binary carrying c9201dd but not the
`SanitizeLoadedTargets` fix, and 0 with the fix in place.

It is also the only specimen of the **pre-digest save format stamp**,
`0.6.9Y19`, which `SaveFormatMatches` still accepts. `docs/ENGINE-SERIALISATION.md`
cites it twice for that, at line 29 and in the worked example at line 103:

    head -c 16 docs/evidence/inc-upw.13/Jaoin.sav | xxd

**Already damaged as a record of play.** `docs/PORT-STATUS.md:190` notes that on
2026-08-14 an agent loaded this save and drove 24 moves through it, so it is no
longer the position Brian left. It remains valid as a format specimen and as
the input to the inc-upw.13 measurement, which is what it is cited for.

## Furious_Fox.sav

The current-format counterpart, cited at `docs/ENGINE-SERIALISATION.md:29` as
carrying the same signature and version stamp as `mod/Incursion.Mod`
(`Sig`=0x1234ABCD, `Version`="SF0F7B6EDC"). Kept so that document has a live
example on both sides of the format change.

## Do not play these

They are read-only records. Loading one in a normal session rewrites it, and
`tools/dump_save.sh` reads a save without opening a game:

    tools/dump_save.sh docs/evidence/inc-upw.13/Jaoin.sav
