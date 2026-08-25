/* SAVEV1.CPP -- See the Incursion LICENSE file for copyright information.

     The v1 tagged-record save schema (docs/SAVE-SCHEMA-SPEC.md). A v1 file
   keeps the 96-byte fileHeader and 28-byte groupHeader shapes of the v0
   format, but the payload is a stream of tagged records -- one per object,
   each field carrying a stable tag and a wire kind -- followed by a resource
   name table that replaces positional rIDs with (pool, module, ordinal,
   name) entries. Field declarations live inside the ARCHIVE_CLASS bodies as
   FIELD_* macro lines (inc/Base.h) and serve the v0 path, the v1 write, the
   v1 read, and the DEBUG coverage check from one declaration.

     EVERY piece of v1 state lives in the file-scope context objects below,
   never in Registry data members: sizeof(Registry) is an input to
   SaveLayoutDigest() (src/AbiCheck.cpp:144-163), and moving it orphans
   every v0 save.

     Name resolution is case-SENSITIVE: strcmp only, never stricmp.
   Measured basis (2026-08-24, lib/program.i, 3430 named resources): names
   are same-case unique in every pool except Flavour.

     int16 Registry::SaveGroupV1(Term&, hObj)
     int16 Registry::LoadGroupV1(Term&, fileHeader&, hObj)
     void  Registry::V1Field/V1Str/V1Blob/V1Rid/V1RidStatus/V1Array/
           V1EmbedBegin/V1EmbedEnd/V1Cover
     void  SaveV1_ResolveNames()
     const char* SaveSchemaID();  bool SaveV1_Raw();
     bool  RunSchemaTest(const char*);  bool RunSchemaLoad(const char*)
*/

#include "Incursion.h"
#include <zlib.h>   /* IS1.x compressed payloads are zlib-6; libz was
                       already a link dependency (CFile's LZ path) */

/* src/Registry.cpp's staged-write-failure probe; shared so the fired-once
   state covers both writers, keeping tools/check_save_fail.sh meaningful. */
extern void SaveFailProbe(bool isData, int32 index);

/* src/Registry.cpp: bytes per whole object of a given type byte. */
extern size_t typeSize(int8 Type);

/* The decimal after "IS1." in fileHeader.Version. Any change to the meaning
   of an existing tag or record shape bumps it (wire-format section, schema
   revisions). History: 0 -> 1, Map's tag 672 (the grid) changed from one
   raw K_BLOB of LocationInfo to the packed K_EMBED grid record
   (Map::GridFieldsV1 below). 1 -> 2, Game's tag 816 (the per-module
   resource memory segment) changed from raw K_BLOB slots to per-slot
   K_EMBED segment records: script blob + name-keyed memory rows
   (SaveV1_SegmentFields below), so a module rebuild that adds, removes or
   reorders a resource no longer shifts every row or renumbers the stored
   flavour rIDs. 2 -> 3, each module slot's tag-816 scope gained its
   21-array length and position-ordered resource-name manifest. */
#define SCHEMA_REV 3

const char* SaveSchemaID()
  {
    static char id[12];
    if (!id[0])
      snprintf(id, sizeof(id), "IS1.%d", SCHEMA_REV);
    return id;
  }

/* Raw (uncompressed) payload mode, for the mutation tools: DEBUG builds
   write Compression = 0 when INCURSION_V1_RAW=1. The reader always follows
   the file's own Compression field, so this only affects writers. */
bool SaveV1_Raw()
  {
#ifdef DEBUG
    const char *e = getenv("INCURSION_V1_RAW");
    return e && !strcmp(e, "1");
#else
    return false;
#endif
  }

/* ------------------------------------------------------------------------ */
/*                          the file-scope context                          */
/* ------------------------------------------------------------------------ */

enum { V1_OFF = 0, V1_SAVE = 1, V1_LOAD = 2 };

#define V1_MAX_DEPTH 10   /* record scope + nested embeds */

/* -- writer ---------------------------------------------------------------*/

struct V1Buf {
    uint8 *p;
    size_t len, cap;
};

static V1Buf v1Out;

static void v1BufFree(V1Buf *b)
  { free(b->p); b->p = NULL; b->len = b->cap = 0; }

static void v1BufNeed(V1Buf *b, size_t extra)
  {
    if (b->len + extra <= b->cap)
      return;
    size_t ncap = b->cap ? b->cap * 2 : 65536;
    while (ncap < b->len + extra)
      ncap *= 2;
    uint8 *np = (uint8*) realloc(b->p, ncap);
    if (!np)
      throw EMEMORY;
    b->p = np; b->cap = ncap;
  }

static void v1Put(V1Buf *b, const void *src, size_t n)
  { v1BufNeed(b, n); memcpy(b->p + b->len, src, n); b->len += n; }

static void v1PutU8(V1Buf *b, uint8 v)   { v1Put(b, &v, 1); }
static void v1PutU16(V1Buf *b, uint16 v) { v1Put(b, &v, 2); }
static void v1PutU32(V1Buf *b, uint32 v) { v1Put(b, &v, 4); }

static void v1Patch32(V1Buf *b, size_t off, uint32 v)
  { memcpy(b->p + off, &v, 4); }

/* Name-table entries, in first-use order so a second save of the same
   registry is byte-identical. */
struct V1NameEntry {
    uint8  pool;
    uint8  slot;
    uint16 ordinal;
    char  *name;      /* owned */
    rID    resolved;  /* load side, after SaveV1_ResolveNames */
    bool   bad;       /* load side: could not be resolved */
};

/* Embed scopes open on the writer: the byte offset of each scope's length
   placeholder. */
struct V1Ctx {
    int mode;                       /* V1_OFF / V1_SAVE / V1_LOAD */

    /* writer */
    size_t wEmbedPatch[V1_MAX_DEPTH];
    int    wEmbedDepth;

    /* name table (writer builds it; reader loads it and keeps it for
       SaveV1_ResolveNames) */
    V1NameEntry *names;
    uint32 nameCount, nameCap;

    /* reader: deferred rID resolution queues */
    rID  **slotQ;    uint32 slotQCount,   slotQCap;
    Status **statQ;  uint32 statQCount,   statQCap;
};

static V1Ctx v1;

/* -- reader ---------------------------------------------------------------*/

struct V1Ent {
    uint16 tag;
    uint8  kind;
    const uint8 *pay;
    uint32 size;
};

struct V1Frame {
    V1Ent *ents;
    int count;
};

static V1Frame v1Frames[V1_MAX_DEPTH];
static int v1FrameDepth;

/* -- the pending resource memory segment (phase 4) ------------------------*/

/* One parsed memory row, held between the record read and the deferred
   placement. The payload is copied out of the group buffer because
   LoadGroupV1 frees that buffer before SaveV1_ResolveNames() runs. */
#define V1_SEG_MAX_PAY 13   /* the largest packed row payload (MonMem) */

struct V1SegRow {
    uint8  kind;                 /* 0 MonMem, 1 ItemMem, 2 EffMem, 3 RegMem */
    uint16 ordinal;              /* among same-pool, same-name resources */
    char  *name;                 /* owned */
    uint8  payLen;
    uint8  pay[V1_SEG_MAX_PAY];
};

/* Per-slot pending state: what the segment record carried, plus WHERE the
   placement must land -- captured at record-read time so the -schematest /
   -schemaload drivers place into the object the record loaded into, not
   into some global. */
struct V1SegPending {
    bool     present;            /* this slot's record was in the file */
    char   **target;             /* &Game::MDataSeg[slot] of the loaded Game */
    uint32  *sizeTarget;         /* &Game::MDataSegSize[slot] */
    uint8   *script;             /* the script data segment blob (owned) */
    uint32   scriptLen;          /* its saved length (== saved szDataSeg) */
    V1SegRow *rows;              /* owned */
    uint32   rowCount;
};

static V1SegPending v1Seg[MAX_MODULES];

/* The module manifest is parsed while the save group still owns its input
   buffer, then consumed by later phases after the modules have reloaded.
   Keep owned copies here, beside the pending segment state with the same
   lifetime. */
struct V1ManifestPending {
    bool    present;
    uint32  lengths[21];
    char  **names;              /* owned, in pool/position wire order */
    uint32  nameCount;
};

static V1ManifestPending v1Manifest[MAX_MODULES];
/* True once a v1 Game record's segment loop ran this load: the deferred
   placement then DEMANDS a record for every loaded module (a module whose
   record is missing would otherwise play with a NULL MDataSeg). */
static bool v1SegSawGame;

/* -- coverage (DEBUG, save direction only) --------------------------------*/

struct SchemaPad { uint32 off, len; };
struct SchemaPin { const char *cls; size_t size;
                   const SchemaPad *pads; int npads; };
/* One row per archived class. size pins sizeof(Class): a member added or
   removed by upstream moves it and the v1 field list must be revisited ON
   PURPOSE (add the FIELD_/FIELD_SKIP line, re-pin). pads lists the byte
   ranges the compiler leaves between members plus the vptr at offset 0;
   the failing check PRINTS the actual uncovered ranges, so filling a row
   is mechanical. Anything uncovered, double-covered, or outside its pinned
   pad is an Error() naming class, offset and length.

   The lookup key is ObjectSize(), NEVER typeSize(): the two disagree on the
   purpose-preserved upstream defects (spec risk 3) -- typeSize(T_STAFF)
   returns sizeof(Weapon) while the placement-new switch constructs a bare
   Item, and typeSize's default returns sizeof(Item) for T_COIN while the
   switch news a Coin. ObjectSize() reports the class the object really is.

   ROW SELECTION does not use ObjectSize() alone. v1CovBegin (below) first
   maps the record's Type byte to a class name through v1PinClassForType,
   which is a direct transcription of the placement-new switch in
   Registry::LoadGroup (src/Registry.cpp:941-983) and Registry::LoadGroupV1
   (src/SaveV1.cpp, "the placement-new switch, as LoadGroup's"): several
   Type bytes construct the SAME C++ class -- T_CHEST and T_CONTAIN both
   placement-new a Container, T_WEAPON/T_BOW/T_MISSILE all placement-new a
   Weapon, T_ARMOUR/T_SHIELD/T_GAUNTLETS/T_BOOTS all placement-new an
   Armour, T_STATUE/T_FIGURE/T_CORPSE all placement-new a Corpse -- and
   every one of those aliases must resolve to the ONE row for its class.
   size is then a CROSS-CHECK against that row, not the selector: a
   mismatch is a fatal SCHEMA COVERAGE finding (upstream moved the class
   without the field list being revisited), never a silent fall-through to
   another row. Before this, the code matched by (size, type) exact-match
   then size-only fallback; several 232-byte rows shared that size, so a
   real T_CONTAIN or T_BOW record -- built via an alias this table's single
   `type` field never named -- fell through to whichever 232-byte row
   happened to sit first in the array, and any of that row's pinned pads
   that the falling-through object's own fields actually covered fired a
   false "pinned pad is covered by a field" fatal (inc-review, Task 5
   follow-up). T_STAFF is the one alias the placement-new switch does NOT
   list for Weapon (T_MISSILE/T_BOW/T_WEAPON only) -- v1PinClassForType
   mirrors that omission and maps T_STAFF to Item, matching what actually
   gets constructed: a staff record loads as a bare Item, and its QItem/
   Weapon-range tags are skipped as unknown. This is unreachable today (no
   T_STAFF record exists until Task 10 converts an old save that names
   one), it is a preserved v0 quirk (spec risk 3, see above), and the
   shipping module declares every staff resource T_WEAPON at compile time
   -- but a save that outlived a staff's removal from a module, or hand-
   crafted test data, could still carry a T_STAFF record. Task 10's
   convert-guard must know this when it reasons about which old records
   are safe to carry forward. */

/* Item chain on arm64/LP64: vptr 0-8; pad after Object::Type 10-12; pad
   after Item::DmgType 133-134; pad after Item::swingCount 151-152; pad
   before Item::Inscrip 156-160; tail pad 218-224. Every other byte is a
   FIELD_ line, a FIELD_SKIP, an embed range, or the record envelope. */
static const SchemaPad ItemPads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 218, 6 }
};

/* Creature chain on arm64/LP64: vptr 0-8 and the pad after Object::Type
   10-12, both shared with the Item row above; pad after Creature::cFP
   1558-1560; pad after Creature::concentUsed 1577-1578; tail pad after
   Creature::NatureSight 1677-1680. ts covers 128-1540 whole, because the
   FIELD_OBJ embed marks the range and so takes TargetSystem's own interior
   padding with it. */
static const SchemaPad CreaturePads[] = {
    { 0, 8 }, { 10, 2 }, { 1558, 2 }, { 1577, 1 }, { 1677, 3 }
};

/* Monster: CreaturePads, plus the tail pad after Recent[6] ends at 1692
   and sizeof(Monster) is 1696. */
static const SchemaPad MonsterPads[] = {
    { 0, 8 }, { 10, 2 }, { 1558, 2 }, { 1577, 1 }, { 1677, 3 },
    { 1692, 4 }
};

/* Character: CreaturePads, plus the pads the compiler leaves between its
   own members. Each one is the gap before the next member's alignment:
   1937 after SkillRanks[49], 2173 after Abilities[143], 2263 after
   RageCount, 2278 before LastRest, 2583 after NotifiedLevel, 7038 before
   SacVals, 8390 before lastPulse, and the 4-byte tail after
   Proficiencies.

   No object is ever exactly a Character -- the class is abstract
   (AdvanceLevel is pure virtual) -- so this row is never the one
   ObjectSize() selects. It is here because Character's field list is real
   and its padding is what Player's row inherits: if upstream adds a member
   to Character, the two rows move together and both must be re-measured. */
static const SchemaPad CharacterPads[] = {
    { 0, 8 }, { 10, 2 }, { 1558, 2 }, { 1577, 1 }, { 1677, 3 },
    { 1937, 1 }, { 2173, 1 }, { 2263, 1 }, { 2278, 2 }, { 2583, 1 },
    { 7038, 2 }, { 8390, 2 }, { 8548, 4 }
};

/* Player: CharacterPads without Character's tail pad -- Player's
   MapMemoryMask occupies 8548 -- plus Player's own seven gaps and its
   6-byte tail. MessageQueue, QuickKeys, Macros, JournalInfo and
   GameTimeInfo carry no rows: each travels as an embed over its whole
   range, which marks its interior padding too. */
static const SchemaPad PlayerPads[] = {
    { 0, 8 }, { 10, 2 }, { 1558, 2 }, { 1577, 1 }, { 1677, 3 },
    { 1937, 1 }, { 2173, 1 }, { 2263, 1 }, { 2278, 2 }, { 2583, 1 },
    { 7038, 2 }, { 8390, 2 },
    { 8553, 1 }, { 8618, 2 }, { 17500, 4 }, { 17826, 6 }, { 17858, 6 },
    { 18258, 6 }, { 18649, 3 }, { 19610, 6 }
};

/* Feature chain on arm64/LP64: vptr 0-8 and the pad after Object::Type
   10-12, both shared with the Item/Creature rows above (same Thing base,
   measured identical by the absence of any other coverage finding below
   offset 128 while these four classes' own fields were still undeclared).
   Feature's own members (cHP 128, mHP 130, fID 132, MoveMod 136) run
   128-137; tail pad 137-144. sizeof(Feature) 144.

   Feature, Door, Trap and Portal are all sizeof 144 -- Feature's own tail
   padding (7 bytes) is roomy enough to swallow Door's and Trap's one extra
   member without growing the object -- so size alone cannot select the
   right row for these four the way it does for every earlier class. v1Cov-
   Begin's exact (size, type) pass (below) picks the right row by Object::
   Type; the size-only fallback pass is what still selects this row for a
   real Feature or Portal object (both share this exact layout: Portal adds
   nothing, see PortalPads). */
static const SchemaPad FeaturePads[] = {
    { 0, 8 }, { 10, 2 }, { 137, 7 }
};

/* Door: Feature's base pads, but Door itself uses the 137-144 range instead
   of leaving it padding -- DoorFlags at 137, a 2-byte alignment gap before
   the uint32 SecretSavedGlyph at 140. Only that internal gap is padding.
   sizeof(Door) 144, same as Feature (measured; see FeaturePads). */
static const SchemaPad DoorPads[] = {
    { 0, 8 }, { 10, 2 }, { 138, 2 }
};

/* Trap: same shape as Door -- TrapFlags at 137, a 2-byte alignment gap,
   then the uint32 tID at 140. sizeof(Trap) 144. */
static const SchemaPad TrapPads[] = {
    { 0, 8 }, { 10, 2 }, { 138, 2 }
};

/* Portal: FeaturePads verbatim -- Portal adds no members of its own, so its
   layout is byte-for-byte Feature's (measured: cHP/mHP/fID/MoveMod land at
   the same offsets, tail pad 137-144). This row still lands (spec: a class
   with no own members still gets pinned) so an upstream addition to Portal
   is caught, and the (size, type) match in v1CovBegin picks it over
   Feature's row for a real Portal object. */
static const SchemaPad PortalPads[] = {
    { 0, 8 }, { 10, 2 }, { 137, 7 }
};

/* QItem chain on arm64/LP64: ItemPads' five interior/vptr pads (0-8, 10-12,
   133-134, 151-152, 156-160), unchanged -- QItem adds no members before
   offset 218. QItem's own members, Qualities[8] and KnownQualities, land in
   and past Item's former 218-224 tail pad (9 bytes don't fit in 6, so
   sizeof(QItem) grows to 232); tail pad 227-232.

   No T_* type placement-news a bare QItem (every concrete descendant
   does), and v1PinClassForType (below) never maps a Type to "QItem" for
   that reason -- so, UNLIKE Item's row, this row is never selected by
   v1CovBegin at all, by construction, not by a coincidence of size or
   fallback order. (An earlier version of this comment claimed the same
   for the OLD size-only-fallback selector, which was false: T_CONTAIN and
   T_BOW records, whose class the old single-`type` field never named,
   fell through by size and landed on whichever 232-byte row was first in
   the array -- often this one. v1PinClassForType removed that fallback
   path entirely; a row is now selected only by an alias this function
   names explicitly.) This row exists purely so QItem's own layout is
   documented once, in the one place every QItem descendant's own pads are
   measured against.

   Armour declares no members of its own (spec: a class with no own
   members still gets pinned). Its OWN row, below, is selected via
   T_ARMOUR/T_SHIELD/T_GAUNTLETS/T_BOOTS in v1PinClassForType -- never via
   this row -- and simply reuses this array because a real Armour object's
   layout is measured byte-identical to QItem's own: its only uncovered
   range past offset 156 is (227, 5), the same as QItem's tail. */
static const SchemaPad QItemPads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 227, 5 }
};

/* Food chain: QItemPads' shape through offset 227, but Food's own Eaten
   (int16) fills part of QItem's spare tail room instead of leaving it as
   padding: a 1-byte alignment gap at 227, Eaten at 228-229, a 2-byte tail
   pad 230-232. sizeof(Food) 232, same as QItem/Container/Weapon/Armour --
   Food's 2-byte member fits in QItem's spare room without growing the
   object (measured, mirrors the Feature/Door/Trap/Portal precedent above). */
static const SchemaPad FoodPads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 227, 1 },
    { 230, 2 }
};

/* Corpse chain: FoodPads' shape through offset 232 (Corpse adds no member
   inside QItem's tail room; mID/TurnCreated/LastDiseaseDCCheck are new
   members past 232, not padding), plus a 6-byte tail after
   LastDiseaseDCCheck. sizeof(Corpse) 248. */
static const SchemaPad CorpsePads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 227, 1 },
    { 230, 2 }, { 242, 6 }
};

/* Container chain: QItemPads' shape through offset 227, but Contents (hObj,
   4 bytes) fills QItem's spare tail room exactly, after the same 1-byte
   alignment gap -- no tail pad left. sizeof(Container) 232, same as
   QItem/Food/Weapon/Armour. */
static const SchemaPad ContainerPads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 227, 1 }
};

/* Weapon chain: same shape as FoodPads -- Bane (int16) lands where Food's
   Eaten does, for the same reason (the sole 2-byte member added after
   QItem's own tail room, same alignment gap and tail pad). sizeof(Weapon)
   232. */
static const SchemaPad WeaponPads[] = {
    { 0, 8 }, { 10, 2 }, { 133, 1 }, { 151, 1 }, { 156, 4 }, { 227, 1 },
    { 230, 2 }
};

/* Map on arm64/LP64: the shared Object prefix (vptr 0-8, pad after Type
   10-12), then one gap per alignment step between its own members --
   23 after inGenerate (bool), 2131 after QueueSP (int8), 2139 after
   inDaysPassed (bool), 2214 after Day (int16, before the 8-aligned
   Overlay), 4228 after ov (Overlay is 2012 bytes, the arrays behind it are
   8-aligned), 4314 after FieldCount, and the 6-byte tail after
   PreviousAuguries. Every static member is generation scratch outside the
   object. Measured 2026-08-24; sizeof(Map) 4344. */
static const SchemaPad MapPads[] = {
    { 0, 8 }, { 10, 2 }, { 23, 1 }, { 2131, 1 }, { 2139, 1 }, { 2214, 2 },
    { 4228, 4 }, { 4314, 2 }, { 4338, 6 }
};

/* Game on arm64/LP64: the shared Object prefix, then 2110 after Day (int16),
   2116 after Turn (uint32, before the 8-aligned String SaveFile), 3698
   after Difficulty (int8, before the 4-aligned DungeonID), 3892 after
   DungeonSize (int16[32], before the 8-aligned DungeonLevels pointers),
   8794 after szFindCache (int16, before the 8-aligned VM), and the 4-byte
   tail after BarrierCount. Modules[] and the destroy queues are static and
   outside the object. Measured 2026-08-24; sizeof(Game) 8840. */
static const SchemaPad GamePads[] = {
    { 0, 8 }, { 10, 2 }, { 2110, 2 }, { 2116, 4 }, { 3698, 2 },
    { 3892, 4 }, { 8794, 6 }, { 8836, 4 }
};

/* Module on arm64/LP64: the shared Object prefix, then 49178 after Slot
   (int16, before the 8-aligned Q* pointers), 49380 after szCodeSeg (int32,
   before the 8-aligned Annotations), and 49458 after szEnc (int16, before
   the 4-aligned TurnLastUsed). No tail pad. Measured 2026-08-24;
   sizeof(Module) 49464. The row matters even though no check ever produces
   a T_MODULE v1 record (see the field list's own comment in inc/Res.h):
   an upstream member change must still be caught on purpose. */
static const SchemaPad ModulePads[] = {
    { 0, 8 }, { 10, 2 }, { 49178, 6 }, { 49380, 4 }, { 49458, 2 }
};

static const SchemaPin SchemaPins[] = {
    { "Item", sizeof(Item), ItemPads,
      (int)(sizeof(ItemPads)/sizeof(ItemPads[0])) },
    { "QItem", sizeof(QItem), QItemPads,
      (int)(sizeof(QItemPads)/sizeof(QItemPads[0])) },
    { "Food", sizeof(Food), FoodPads,
      (int)(sizeof(FoodPads)/sizeof(FoodPads[0])) },
    { "Corpse", sizeof(Corpse), CorpsePads,
      (int)(sizeof(CorpsePads)/sizeof(CorpsePads[0])) },
    { "Container", sizeof(Container), ContainerPads,
      (int)(sizeof(ContainerPads)/sizeof(ContainerPads[0])) },
    { "Weapon", sizeof(Weapon), WeaponPads,
      (int)(sizeof(WeaponPads)/sizeof(WeaponPads[0])) },
    /* Coin declares no own members (ARCHIVE_CLASS body is empty; pin row
       only). Measured sizeof(Coin) == sizeof(Item) == 224 and Coin's
       uncovered range is identical to ItemPads' own tail -- typeSize(T_COIN)
       reports sizeof(Item) while the placement-new switch constructs a Coin
       (docs/ENGINE-SERIALISATION.md defect 3, spec risk 3, preserved on
       purpose), but the two sizes coincide here, so no allocation shortfall
       follows from the mismatch. */
    { "Coin", sizeof(Coin), ItemPads,
      (int)(sizeof(ItemPads)/sizeof(ItemPads[0])) },
    /* Armour declares no own members (pin row only); see the QItemPads
       comment above -- this row's pads ARE QItemPads, because a real
       Armour object's layout is measured byte-identical to QItem's own. */
    { "Armour", sizeof(Armour), QItemPads,
      (int)(sizeof(QItemPads)/sizeof(QItemPads[0])) },
    { "Creature", sizeof(Creature), CreaturePads,
      (int)(sizeof(CreaturePads)/sizeof(CreaturePads[0])) },
    { "Monster", sizeof(Monster), MonsterPads,
      (int)(sizeof(MonsterPads)/sizeof(MonsterPads[0])) },
    { "Character", sizeof(Character), CharacterPads,
      (int)(sizeof(CharacterPads)/sizeof(CharacterPads[0])) },
    { "Player", sizeof(Player), PlayerPads,
      (int)(sizeof(PlayerPads)/sizeof(PlayerPads[0])) },
    { "Feature", sizeof(Feature), FeaturePads,
      (int)(sizeof(FeaturePads)/sizeof(FeaturePads[0])) },
    { "Door", sizeof(Door), DoorPads,
      (int)(sizeof(DoorPads)/sizeof(DoorPads[0])) },
    { "Trap", sizeof(Trap), TrapPads,
      (int)(sizeof(TrapPads)/sizeof(TrapPads[0])) },
    { "Portal", sizeof(Portal), PortalPads,
      (int)(sizeof(PortalPads)/sizeof(PortalPads[0])) },
    { "Map", sizeof(Map), MapPads,
      (int)(sizeof(MapPads)/sizeof(MapPads[0])) },
    { "Game", sizeof(Game), GamePads,
      (int)(sizeof(GamePads)/sizeof(GamePads[0])) },
    { "Module", sizeof(Module), ModulePads,
      (int)(sizeof(ModulePads)/sizeof(ModulePads[0])) },
};

/* Maps a record's Type byte to the class its row is filed under, by
   transcribing the placement-new switch's arms (Registry::LoadGroup,
   src/Registry.cpp:941-983, and Registry::LoadGroupV1, src/SaveV1.cpp)
   exactly -- see the SchemaPin comment above for why this replaced the old
   (size, type) exact-match / size-only-fallback selector, and for the
   T_STAFF arm's absence below. Returns NULL only for a Type neither switch
   constructs; such a record never reaches v1CovBegin, because the writer
   only ever sees objects the registry holds. */
static const char* v1PinClassForType(int16 type)
  {
    switch (type)
      {
        case T_GAME:     return "Game";
        case T_MAP:      return "Map";
        case T_MODULE:   return "Module";
        case T_MONSTER:  return "Monster";
        case T_PLAYER:   return "Player";
        case T_PORTAL:   return "Portal";
        case T_DOOR:     return "Door";
        case T_TRAP:     return "Trap";
        case T_FEATURE:  return "Feature";
        case T_CHEST:    case T_CONTAIN:  return "Container";
        case T_COIN:     return "Coin";
        case T_FOOD:     return "Food";
        case T_STATUE:   case T_FIGURE:   case T_CORPSE:
          return "Corpse";
        case T_MISSILE:  case T_BOW:      case T_WEAPON:
          return "Weapon";
        case T_ARMOUR:   case T_SHIELD:   case T_GAUNTLETS: case T_BOOTS:
          return "Armour";
        default:
          /* T_STAFF deliberately falls through to here: it is absent from
             both placement-new switches' own Weapon arm, so a T_STAFF
             record actually placement-news a bare Item (spec risk 3;
             see the SchemaPin comment). */
          if (type >= T_FIRSTITEM && type <= T_LASTITEM)
            return "Item";
          return NULL;
      }
  }

static const SchemaPin* v1FindPinByClass(const char *cls)
  {
    for (size_t i = 0; i != sizeof(SchemaPins)/sizeof(SchemaPins[0]); i++)
      if (!strcmp(SchemaPins[i].cls, cls))
        return &SchemaPins[i];
    return NULL;
  }

#ifdef DEBUG
struct V1Cov {
    uint8 *map;                    /* one byte per object byte */
    size_t len;
    const char *base;              /* the object being written */
    const SchemaPin *pin;          /* NULL when no row matched */
    const char *cls;
    struct { size_t off, len; } open[V1_MAX_DEPTH];  /* embed ranges */
    int openDepth;
};
static V1Cov v1Cov;
#endif

static long v1CovFindings;         /* per -schematest run; never reset by a
                                      single record */

static void v1CovBegin(Object *o)
  {
#ifdef DEBUG
    size_t sz = o->ObjectSize();
    v1Cov.map = (uint8*) calloc(1, sz);
    v1Cov.len = sz;
    v1Cov.base = (const char*) o;
    v1Cov.openDepth = 0;
    v1Cov.pin = NULL;
    v1Cov.cls = "?";
    /* Select the row by what the record's Type byte ACTUALLY constructs
       (v1PinClassForType, a transcription of the placement-new switch),
       never by ObjectSize() alone -- see the SchemaPin comment for why.
       size is then a cross-check, not the selector: a real mismatch (the
       class moved and the field list was not revisited) is its own fatal
       finding, distinct from "no row at all" so the two are never
       conflated in the log. */
    {
      const char *cls = v1PinClassForType((int16)o->Type);
      const SchemaPin *p = cls ? v1FindPinByClass(cls) : NULL;
      if (p && p->size == sz)
        { v1Cov.pin = p; v1Cov.cls = p->cls; }
      else if (p)
        {
          v1CovFindings++;
          Error("SCHEMA COVERAGE: %s: pin row size %lu does not match "
                "ObjectSize() %lu for a real type %d object -- the class "
                "moved and its field list needs revisiting",
                p->cls, (unsigned long)p->size, (unsigned long)sz,
                (int)o->Type);
        }
      else
        {
          v1CovFindings++;
          Error("SCHEMA COVERAGE: no pin row for class of size %lu (type %d)",
                (unsigned long)sz, (int)o->Type);
        }
    }
#else
    (void)o;
#endif
  }

#ifdef DEBUG
static bool v1CovInsideOpen(size_t b)
  {
    for (int i = 0; i != v1Cov.openDepth; i++)
      if (b >= v1Cov.open[i].off && b < v1Cov.open[i].off + v1Cov.open[i].len)
        return true;
    return false;
  }
#endif

static void v1CovMark(const void *p, size_t size)
  {
#ifdef DEBUG
    if (!v1Cov.map || !size)
      return;
    const char *cp = (const char*) p;
    if (cp < v1Cov.base || cp + size > v1Cov.base + v1Cov.len)
      return;   /* a stack temporary or other out-of-object staging: legal */
    size_t off = (size_t)(cp - v1Cov.base);
    for (size_t b = off; b != off + size; b++)
      {
        if (v1Cov.map[b])
          {
            if (v1CovInsideOpen(b))
              continue;      /* redundant mark inside an open embed: legal */
            v1CovFindings++;
            Error("SCHEMA COVERAGE: %s: byte at offset %lu is covered twice",
                  v1Cov.cls, (unsigned long)b);
            return;
          }
        v1Cov.map[b] = 1;
      }
#else
    (void)p; (void)size;
#endif
  }

static void v1CovOpenEmbed(const void *p, size_t size)
  {
#ifdef DEBUG
    if (!v1Cov.map)
      return;
    const char *cp = (const char*) p;
    size_t off = 0, len = 0;
    if (cp >= v1Cov.base && cp + size <= v1Cov.base + v1Cov.len)
      {
        v1CovMark(p, size);   /* interior padding of the embedded type too */
        off = (size_t)(cp - v1Cov.base);
        len = size;
      }
    if (v1Cov.openDepth < V1_MAX_DEPTH)
      {
        v1Cov.open[v1Cov.openDepth].off = off;
        v1Cov.open[v1Cov.openDepth].len = len;
        v1Cov.openDepth++;
      }
#else
    (void)p; (void)size;
#endif
  }

static void v1CovCloseEmbed(void)
  {
#ifdef DEBUG
    if (v1Cov.map && v1Cov.openDepth > 0)
      v1Cov.openDepth--;
#endif
  }

static void v1CovEnd(void)
  {
#ifdef DEBUG
    if (!v1Cov.map)
      return;
    /* Compare the uncovered set against the pinned pads, exactly. */
    uint8 *want = (uint8*) calloc(1, v1Cov.len);
    if (v1Cov.pin)
      for (int i = 0; i != v1Cov.pin->npads; i++)
        {
          const SchemaPad *pad = &v1Cov.pin->pads[i];
          for (uint32 b = 0; b != pad->len && pad->off + b < v1Cov.len; b++)
            want[pad->off + b] = 1;
        }
    size_t b = 0;
    while (b != v1Cov.len)
      {
        bool covered = v1Cov.map[b] != 0, padded = want[b] != 0;
        if (covered == !padded)
          { b++; continue; }
        size_t start = b;
        while (b != v1Cov.len &&
               (v1Cov.map[b] != 0) == covered && (want[b] != 0) == padded)
          b++;
        v1CovFindings++;
        if (!covered)
          Error("SCHEMA COVERAGE: %s: uncovered bytes at offset %lu, length %lu",
                v1Cov.cls, (unsigned long)start, (unsigned long)(b - start));
        else
          Error("SCHEMA COVERAGE: %s: pinned pad at offset %lu, length %lu is covered by a field",
                v1Cov.cls, (unsigned long)start, (unsigned long)(b - start));
      }
    free(want);
    free(v1Cov.map);
    v1Cov.map = NULL;
#endif
  }

/* ------------------------------------------------------------------------ */
/*                              teardown                                    */
/* ------------------------------------------------------------------------ */

static void v1NamesFree(void)
  {
    for (uint32 i = 0; i != v1.nameCount; i++)
      free(v1.names[i].name);
    free(v1.names);
    v1.names = NULL; v1.nameCount = v1.nameCap = 0;
  }

static void v1QueuesFree(void)
  {
    free(v1.slotQ); v1.slotQ = NULL; v1.slotQCount = v1.slotQCap = 0;
    free(v1.statQ); v1.statQ = NULL; v1.statQCount = v1.statQCap = 0;
  }

static void v1FramesFree(void)
  {
    while (v1FrameDepth > 0)
      {
        v1FrameDepth--;
        free(v1Frames[v1FrameDepth].ents);
        v1Frames[v1FrameDepth].ents = NULL;
        v1Frames[v1FrameDepth].count = 0;
      }
  }

static void v1WriterTeardown(void)
  {
    v1.mode = V1_OFF;
    v1.wEmbedDepth = 0;
    v1BufFree(&v1Out);
    v1NamesFree();
#ifdef DEBUG
    free(v1Cov.map);
    v1Cov.map = NULL;
#endif
  }

static void v1ReaderTeardown(void)
  {
    v1.mode = V1_OFF;
    v1FramesFree();
  }

static void v1SegFree(void)
  {
    for (int i = 0; i != MAX_MODULES; i++)
      {
        V1ManifestPending *mp = &v1Manifest[i];
        if (mp->names)
          {
            for (uint32 k = 0; k != mp->nameCount; k++)
              free(mp->names[k]);
            free(mp->names);
          }
        memset(mp, 0, sizeof(*mp));

        V1SegPending *sp = &v1Seg[i];
        if (sp->rows)
          {
            for (uint32 k = 0; k != sp->rowCount; k++)
              free(sp->rows[k].name);
            free(sp->rows);
          }
        free(sp->script);
        memset(sp, 0, sizeof(*sp));
      }
    v1SegSawGame = false;
  }

/* The resolve state (name table + queues + pending memory segments)
   outlives LoadGroupV1 on purpose: SaveV1_ResolveNames() consumes it after
   the module reload. */
static void v1ResolveTeardown(void)
  {
    v1NamesFree();
    v1QueuesFree();
    v1SegFree();
  }

/* RAII: however SaveGroupV1/LoadGroupV1 leave, the context is not left
   armed -- a later, unrelated Serialize call must not see V1Active(). */
struct V1SaveScope {
    bool *saving;
    V1SaveScope(bool *s) : saving(s) {}
    ~V1SaveScope() { *saving = false; v1WriterTeardown(); }
};

struct V1LoadScope {
    bool committed;
    V1LoadScope() : committed(false) {}
    ~V1LoadScope()
      {
        v1ReaderTeardown();
        if (!committed)
          v1ResolveTeardown();
      }
};

/* ------------------------------------------------------------------------ */
/*                          the resource name table                         */
/* ------------------------------------------------------------------------ */

struct V1Pool { char *base; size_t stride; int32 count; };

static bool V1GetPool(Module *mod, int pool, V1Pool *out)
  {
    switch (pool)
      {
        case SP_MON: out->base=(char*)mod->QMon; out->stride=sizeof(TMonster);   out->count=mod->szMon; return true;
        case SP_ITM: out->base=(char*)mod->QItm; out->stride=sizeof(TItem);      out->count=mod->szItm; return true;
        case SP_FEA: out->base=(char*)mod->QFea; out->stride=sizeof(TFeature);   out->count=mod->szFea; return true;
        case SP_EFF: out->base=(char*)mod->QEff; out->stride=sizeof(TEffect);    out->count=mod->szEff; return true;
        case SP_ART: out->base=(char*)mod->QArt; out->stride=sizeof(TArtifact);  out->count=mod->szArt; return true;
        case SP_QUE: out->base=(char*)mod->QQue; out->stride=sizeof(TQuest);     out->count=mod->szQue; return true;
        case SP_DGN: out->base=(char*)mod->QDgn; out->stride=sizeof(TDungeon);   out->count=mod->szDgn; return true;
        case SP_ROU: out->base=(char*)mod->QRou; out->stride=sizeof(TRoutine);   out->count=mod->szRou; return true;
        case SP_NPC: out->base=(char*)mod->QNPC; out->stride=sizeof(TNPC);       out->count=mod->szNPC; return true;
        case SP_CLA: out->base=(char*)mod->QCla; out->stride=sizeof(TClass);     out->count=mod->szCla; return true;
        case SP_RAC: out->base=(char*)mod->QRac; out->stride=sizeof(TRace);      out->count=mod->szRac; return true;
        case SP_DOM: out->base=(char*)mod->QDom; out->stride=sizeof(TDomain);    out->count=mod->szDom; return true;
        case SP_GOD: out->base=(char*)mod->QGod; out->stride=sizeof(TGod);       out->count=mod->szGod; return true;
        case SP_REG: out->base=(char*)mod->QReg; out->stride=sizeof(TRegion);    out->count=mod->szReg; return true;
        case SP_TER: out->base=(char*)mod->QTer; out->stride=sizeof(TTerrain);   out->count=mod->szTer; return true;
        case SP_TXT: out->base=(char*)mod->QTxt; out->stride=sizeof(TText);      out->count=mod->szTxt; return true;
        case SP_VAR: out->base=(char*)mod->QVar; out->stride=sizeof(TVariable);  out->count=mod->szVar; return true;
        case SP_TEM: out->base=(char*)mod->QTem; out->stride=sizeof(TTemplate);  out->count=mod->szTem; return true;
        case SP_FLA: out->base=(char*)mod->QFla; out->stride=sizeof(TFlavor);    out->count=mod->szFla; return true;
        case SP_BEV: out->base=(char*)mod->QBev; out->stride=sizeof(TBehaviour); out->count=mod->szBev; return true;
        case SP_ENC: out->base=(char*)mod->QEnc; out->stride=sizeof(TEncounter); out->count=mod->szEnc; return true;
      }
    return false;
  }

static const char* V1PoolName(int pool)
  {
    static const char *names[] = {
      "Monster", "Item", "Feature", "Effect", "Artifact", "Quest",
      "Dungeon", "Routine", "NPC", "Class", "Race", "Domain", "God",
      "Region", "Terrain", "Text", "Variable", "Template", "Flavour",
      "Behaviour", "Encounter" };
    if (pool >= 0 && pool <= SP_ENC)
      return names[pool];
    return "?";
  }

static const char* V1ResName(Module *mod, const V1Pool *pool, int32 i)
  {
    Resource *res = (Resource*)(pool->base + (size_t)i * pool->stride);
    const char *nm = mod->GetText(res->Name);
    return nm ? nm : "";
  }

/* The manifest order is a wire constant. The explicit enum checks catch an
   accidental pool-id reorder at compile time; the boundary probes catch a
   disagreement between V1GetPool's switch and Module::__GetResource's walk
   at save time. */
static void v1AssertPoolOrder(Module *mod, const V1Pool pools[21])
  {
    static_assert(SP_MON == 0 && SP_ITM == 1 && SP_FEA == 2 &&
                  SP_EFF == 3 && SP_ART == 4 && SP_QUE == 5 &&
                  SP_DGN == 6 && SP_ROU == 7 && SP_NPC == 8 &&
                  SP_CLA == 9 && SP_RAC == 10 && SP_DOM == 11 &&
                  SP_GOD == 12 && SP_REG == 13 && SP_TER == 14 &&
                  SP_TXT == 15 && SP_VAR == 16 && SP_TEM == 17 &&
                  SP_FLA == 18 && SP_BEV == 19 && SP_ENC == 20,
                  "save manifest pool order is a wire constant");
    uint32 running = 0;
    for (int p = SP_MON; p <= SP_ENC; p++)
      {
        if (pools[p].count < 0)
          throw ECORRUPT;
        if (pools[p].count &&
            (mod->__GetResource((rID)running) !=
                 (Resource*)pools[p].base ||
             mod->__GetResource((rID)(running + pools[p].count - 1)) !=
                 (Resource*)(pools[p].base +
                    (size_t)(pools[p].count - 1) * pools[p].stride)))
          {
            Error("SaveV1: resource pool order disagrees at %s",
                  V1PoolName(p));
            throw ECORRUPT;
          }
        running += (uint32)pools[p].count;
      }
  }

/* Tags inside Game's tag-816 / tag-(1+slot) scope:
     4: K_ARRAY, count 21, element size 4, the pool lengths in wire order.
     5: K_BLOB, for every pool in that order and every position in the pool,
        uint16 name length followed by that many bytes (no NUL).
   Phase 1 deliberately writes these fields only; phase 2 will parse them. */
static void v1WriteModuleManifest(Module *mod)
  {
    V1Pool pools[21];
    uint32 lengths[21];
    for (int p = SP_MON; p <= SP_ENC; p++)
      {
        if (!V1GetPool(mod, p, &pools[p]) || pools[p].count < 0)
          throw ECORRUPT;
        lengths[p] = (uint32)pools[p].count;
      }
    v1AssertPoolOrder(mod, pools);

    v1PutU16(&v1Out, 4);
    v1PutU8(&v1Out, K_ARRAY);
    v1PutU32(&v1Out, 21);
    v1PutU32(&v1Out, sizeof(uint32));
    v1Put(&v1Out, lengths, sizeof(lengths));

    V1Buf names;
    memset(&names, 0, sizeof(names));
    try
      {
        for (int p = SP_MON; p <= SP_ENC; p++)
          for (int32 i = 0; i != pools[p].count; i++)
            {
              const char *name = V1ResName(mod, &pools[p], i);
              size_t len = strlen(name);
              if (len > 0xFFFF)
                {
                  Error("SaveV1: %s resource name at position %d is too long",
                        V1PoolName(p), (int)i);
                  throw ECORRUPT;
                }
              v1PutU16(&names, (uint16)len);
              if (len)
                v1Put(&names, name, len);
            }
        if (names.len > 0xFFFFFFFFu)
          throw ECORRUPT;
        v1PutU16(&v1Out, 5);
        v1PutU8(&v1Out, K_BLOB);
        v1PutU32(&v1Out, (uint32)names.len);
        if (names.len)
          v1Put(&v1Out, names.p, names.len);
      }
    catch (...)
      {
        v1BufFree(&names);
        throw;
      }
    v1BufFree(&names);
  }

/* Save side: intern one rID as a (pool, slot, ordinal, name) entry and
   return its table index. First-use order; duplicates dedupe. */
static uint32 V1InternRid(rID id)
  {
    int slot = (int)(id >> 24) - 1;
    if (slot < 0 || slot >= MAX_MODULES || !Game::Modules[slot])
      {
        Error("SaveV1: rID %u names module slot %d, which is not loaded",
              (unsigned)id, slot);
        throw ECORRUPT;
      }
    Module *mod = Game::Modules[slot];
    uint32 idx = id & 0x00FFFFFF;
    int pool = -1; V1Pool pl;
    for (int p = SP_MON; p <= SP_ENC; p++)
      {
        if (!V1GetPool(mod, p, &pl))
          break;
        if (idx < (uint32)pl.count)
          { pool = p; break; }
        idx -= (uint32)pl.count;
      }
    if (pool < 0)
      {
        Error("SaveV1: rID %u is past every resource pool of module slot %d",
              (unsigned)id, slot);
        throw ECORRUPT;
      }
    const char *name = V1ResName(mod, &pl, (int32)idx);
    /* The ordinal: how many earlier same-pool resources carry this exact
       name, in declaration order. strcmp -- case matters (constraint 2). */
    uint32 ordinal = 0;
    for (uint32 j = 0; j != idx; j++)
      if (!strcmp(V1ResName(mod, &pl, (int32)j), name))
        ordinal++;
    for (uint32 e = 0; e != v1.nameCount; e++)
      if (v1.names[e].pool == (uint8)pool && v1.names[e].slot == (uint8)slot &&
          v1.names[e].ordinal == (uint16)ordinal &&
          !strcmp(v1.names[e].name, name))
        return e;
    if (v1.nameCount == v1.nameCap)
      {
        v1.nameCap = v1.nameCap ? v1.nameCap * 2 : 64;
        V1NameEntry *nn = (V1NameEntry*)
            realloc(v1.names, v1.nameCap * sizeof(V1NameEntry));
        if (!nn)
          throw EMEMORY;
        v1.names = nn;
      }
    V1NameEntry *ent = &v1.names[v1.nameCount];
    ent->pool = (uint8)pool;
    ent->slot = (uint8)slot;
    ent->ordinal = (uint16)ordinal;
    ent->name = strdup(name);
    ent->resolved = 0;
    ent->bad = false;
    return v1.nameCount++;
  }

/* Load side: one entry -> the rID it names in the modules now loaded, or
   failure. An ordinal at or past the count of same-named resources fails. */
static bool V1ResolveEntry(V1NameEntry *ent)
  {
    if (ent->slot >= MAX_MODULES || !Game::Modules[ent->slot])
      return false;
    Module *mod = Game::Modules[ent->slot];
    V1Pool pl;
    if (!V1GetPool(mod, ent->pool, &pl))
      return false;
    int32 found = -1; uint32 running = 0;
    for (int32 i = 0; i != pl.count; i++)
      if (!strcmp(V1ResName(mod, &pl, i), ent->name))
        {
          if (running == ent->ordinal)
            { found = i; break; }
          running++;
        }
    if (found < 0)
      return false;
    uint32 poolBase = 0; V1Pool earlier;
    for (int p = SP_MON; p != ent->pool; p++)
      {
        if (!V1GetPool(mod, p, &earlier))
          return false;
        poolBase += (uint32)earlier.count;
      }
    ent->resolved = poolBase + (uint32)found + ((uint32)(ent->slot + 1) << 24);
    return true;
  }

/* Before resolving ANY resource reference, verify the append-only premise for
   every manifest the save carried. A shrink is a broken module, whether or
   not this particular save happens to reference the removed position. */
static long v1ManifestPreflight(void)
  {
    long failures = 0;
    for (int slot = 0; slot != MAX_MODULES; slot++)
      {
        V1ManifestPending *mp = &v1Manifest[slot];
        if (!mp->present)
          continue;
        Module *mod = Game::Modules[slot];
        if (!mod)
          {
            failures++;
            fprintf(stderr,
                "incursion: v1 manifest names module slot %d, which did "
                "not load\n", slot);
            continue;
          }
        for (int p = SP_MON; p <= SP_ENC; p++)
          {
            V1Pool pl;
            if (!V1GetPool(mod, p, &pl) || pl.count < 0)
              {
                failures++;
                fprintf(stderr,
                    "incursion: loaded module slot %d has invalid %s "
                    "array geometry\n", slot, V1PoolName(p));
                continue;
              }
            if ((uint32)pl.count < mp->lengths[p])
              {
                failures++;
                fprintf(stderr,
                    "incursion: module slot %d %s array shrank: manifest "
                    "recorded %u entries, loaded module has %u\n",
                    slot, V1PoolName(p), (unsigned)mp->lengths[p],
                    (unsigned)pl.count);
              }
          }
      }
    return failures;
  }

/* Convert one plain saved rID through its manifest position. The pre-flight
   above guarantees that rebuilding from the loaded lengths succeeds: every
   covered array position still exists because an array can only have grown.

   EVERY reference goes through here, including one from a file that carries
   no manifest at all. That case is not a formality. The wire value is now
   the rID itself, so an unchecked one reaches Modules[(rID >> 24) - 1] and
   Module::__GetResource straight from the file, and neither is safe to feed
   an arbitrary 32-bit number: a zero slot byte indexes Modules[-1]. The walk
   below is what bounds the index, so it MUST run whether or not a manifest
   supplied the lengths. */
static bool v1ConvertManifestRid(uint32 saved, rID *resolved)
  {
    int slot = (int)(saved >> 24) - 1;
    uint32 index = saved & 0x00FFFFFFu;
    if (slot < 0 || slot >= MAX_MODULES)
      {
        fprintf(stderr,
            "incursion: v1 rID %u names module slot %d outside [0, %d)\n",
            (unsigned)saved, slot, MAX_MODULES);
        return false;
      }
    Module *mod = Game::Modules[slot];
    if (!mod)
      {
        fprintf(stderr,
            "incursion: v1 rID %u names module slot %d, which did not "
            "load\n", (unsigned)saved, slot);
        return false;
      }

    /* Which lengths describe the SAVE's numbering. A file with a Game record
       carries a manifest for every slot it loaded, so a referenced slot
       without one is corruption. The -schematest / -schemaload class groups
       have no Game record, so no manifest: they are not complete saves and
       they reload against the very module geometry they were written from,
       which makes the loaded lengths the save's own numbering. */
    uint32 loaded[21];
    const uint32 *lengths;
    V1ManifestPending *mp = &v1Manifest[slot];
    if (mp->present)
      lengths = mp->lengths;
    else if (v1SegSawGame)
      {
        fprintf(stderr,
            "incursion: v1 rID %u names module slot %d, which has no "
            "manifest\n", (unsigned)saved, slot);
        return false;
      }
    else
      {
        for (int p = SP_MON; p <= SP_ENC; p++)
          {
            V1Pool pl;
            if (!V1GetPool(mod, p, &pl) || pl.count < 0)
              {
                fprintf(stderr,
                    "incursion: loaded module slot %d has invalid %s array "
                    "geometry\n", slot, V1PoolName(p));
                return false;
              }
            loaded[p] = (uint32)pl.count;
          }
        lengths = loaded;
      }

    int array = -1;
    uint32 position = index;
    for (int p = SP_MON; p <= SP_ENC; p++)
      if (position < lengths[p])
        { array = p; break; }
      else
        position -= lengths[p];
    if (array < 0)
      {
        fprintf(stderr,
            "incursion: v1 rID module slot %d index %u is past the last "
            "resource array\n", slot, (unsigned)index);
        return false;
      }

    uint32 running = 0;
    for (int p = SP_MON; p < array; p++)
      {
        V1Pool pl;
        if (!V1GetPool(mod, p, &pl) || pl.count < 0)
          return false;          /* already diagnosed by the pre-flight */
        running += (uint32)pl.count;
      }
    *resolved = (rID)(running + position + ((uint32)(slot + 1) << 24));
    return true;
  }

/* ------------------------------------------------------------------------ */
/*             the resource memory segment record (phase 4)                 */
/* ------------------------------------------------------------------------ */

static const V1Ent* v1Find(uint16 tag);   /* reader primitive, below */

/* Row kind -> wire pool byte, memory row stride, and packed payload size.
   Indexed by the row's kind byte (0 MonMem, 1 ItemMem, 2 EffMem, 3 RegMem).
   The payload layouts are fixed for IS1.2; any change bumps SCHEMA_REV. */
static const uint8  v1SegPool[4]   = { SP_MON, SP_ITM, SP_EFF, SP_REG };
static const size_t v1SegStride[4] = { sizeof(MonMem), sizeof(ItemMem),
                                       sizeof(EffMem), sizeof(RegMem) };
static const uint8  v1SegPayLen[4] = { 13, 1, 9, 4 };

/* The block starts inside MDataSeg[slot], exactly as Module::GetMemoryPtr
   (src/Res.cpp:711) computes them: the script data segment first, then one
   block per pool in Mon/Itm/Eff/Reg order. GetMemoryPtr multiplies the
   in-pool index by NumPlayers() but not the skipped blocks; NumPlayers()
   is 1, which makes the two conventions agree, and GetMemoryPtr is the
   authority this mirrors. */
static void v1SegStarts(Module *mod, size_t np, size_t start[4], size_t *total)
  {
    start[0] = (size_t)mod->szDataSeg;
    start[1] = start[0] + sizeof(MonMem)  * (size_t)mod->szMon * np;
    start[2] = start[1] + sizeof(ItemMem) * (size_t)mod->szItm * np;
    start[3] = start[2] + sizeof(EffMem)  * (size_t)mod->szEff * np;
    *total   = start[3] + sizeof(RegMem)  * (size_t)mod->szReg * np;
  }

/* Pack one memory row's bitfields BY NAME into the fixed little-endian
   payload (never memcpy: the in-memory bitfield layout is the compiler's,
   the wire layout is ours). EffMem is handled by the caller because its
   two flavour values go through the name table. Returns false for an
   all-zero row, which is not written at all: a resource with no row keeps
   zeroed memory, as a new game gives it. */
static bool v1SegPackRow(int kind, const char *rowp, uint8 *out)
  {
    switch (kind)
      {
        case 0:
          {
            const MonMem *m = (const MonMem*)rowp;
            if (!m->Battles && !m->Deaths && !m->Kills && !m->pKills &&
                !m->Attacks && !m->Resists && !m->Immune && !m->Seen &&
                !m->Fought && !m->Feats && !m->Flags)
              return false;
            out[0] = (uint8)m->Battles;
            out[1] = (uint8)m->Deaths;
            out[2] = (uint8)m->Kills;
            out[3] = (uint8)m->pKills;
            out[4] = (uint8)(m->Attacks & 0xFF);
            out[5] = (uint8)(m->Attacks >> 8);
            out[6] = (uint8)m->Resists;
            out[7] = (uint8)(m->Immune & 0xFF);
            out[8] = (uint8)(m->Immune >> 8);
            out[9] = (uint8)((m->Seen ? 1 : 0) | (m->Fought ? 2 : 0));
            out[10] = (uint8)(m->Feats & 0xFF);
            out[11] = (uint8)(m->Feats >> 8);
            out[12] = (uint8)m->Flags;
            return true;
          }
        case 1:
          {
            const ItemMem *m = (const ItemMem*)rowp;
            if (!m->Known && !m->ProfLevel && !m->Tried && !m->Mastered &&
                !m->Unused)
              return false;
            out[0] = (uint8)((m->Known ? 1 : 0) | (m->ProfLevel << 1) |
                             (m->Tried ? 16 : 0) | (m->Mastered ? 32 : 0) |
                             (m->Unused << 6));
            return true;
          }
        case 3:
          {
            const RegMem *m = (const RegMem*)rowp;
            if (!m->Seen)
              return false;
            out[0] = (uint8)(m->Seen & 0xFF);
            out[1] = (uint8)((m->Seen >> 8) & 0xFF);
            out[2] = (uint8)((m->Seen >> 16) & 0xFF);
            out[3] = (uint8)((m->Seen >> 24) & 0xFF);
            return true;
          }
      }
    return false;
  }

/* The other direction, payload -> bitfields by name, for the deferred
   placement. EffMem's flavour values are resolved by the caller. */
static void v1SegUnpackRow(int kind, const uint8 *pay, char *rowp)
  {
    switch (kind)
      {
        case 0:
          {
            MonMem *m = (MonMem*)rowp;
            m->Battles = pay[0];
            m->Deaths  = pay[1];
            m->Kills   = pay[2];
            m->pKills  = pay[3];
            m->Attacks = (unsigned)(pay[4] | (pay[5] << 8)) & 0x1FF;
            m->Resists = pay[6];
            m->Immune  = (unsigned)(pay[7] | (pay[8] << 8));
            m->Seen    = pay[9] & 1;
            m->Fought  = (pay[9] >> 1) & 1;
            m->Feats   = (unsigned)(pay[10] | (pay[11] << 8));
            m->Flags   = pay[12] & 0x1F;
            break;
          }
        case 1:
          {
            ItemMem *m = (ItemMem*)rowp;
            m->Known     = pay[0] & 1;
            m->ProfLevel = (pay[0] >> 1) & 7;
            m->Tried     = (pay[0] >> 4) & 1;
            m->Mastered  = (pay[0] >> 5) & 1;
            m->Unused    = (pay[0] >> 6) & 3;
            break;
          }
        case 3:
          {
            RegMem *m = (RegMem*)rowp;
            m->Seen = (unsigned)pay[0] | ((unsigned)pay[1] << 8) |
                      ((unsigned)pay[2] << 16) | ((unsigned)pay[3] << 24);
            break;
          }
      }
  }

/* Write pre-flight, shared by Game::SaveGame and RunSaveConvert: the same
   segment-geometry refusals SaveV1_SegmentFields makes at write time, made
   BEFORE any destructive step, so a refused save leaves the existing file
   byte-intact (inc-ew8r fails safe). It catches a module that GREW past the
   save's segment -- the 4ba035b class of mismatch; a same-size renumbering
   is invisible to any size check and remains the operator's responsibility,
   per docs/SAVE-SCHEMA-SPEC.md "Compatibility". The write-time checks in
   SaveV1_SegmentFields stay: this is the early copy of them. */
bool SaveV1_CanWrite(Game &g, String &whyNot)
  {
    for (int i = 0; i != MAX_MODULES; i++)
      {
        if (!g.MDataSeg[i])
          continue;
        Module *mod = Game::Modules[i];
        if (!mod)
          {
            whyNot = Format("MDataSeg[%d] is allocated but module slot %d "
                            "is not loaded", i, i);
            return false;
          }
        size_t start[4], total;
        v1SegStarts(mod, (size_t)g.NumPlayers(), start, &total);
        if (total > (size_t)g.MDataSegSize[i])
          {
            whyNot = Format("the save's memory segment for module slot %d "
                            "is %u bytes but the loaded module needs %lu "
                            "-- the module does not match the save's "
                            "numbering", i, (unsigned)g.MDataSegSize[i],
                            (unsigned long)total);
            return false;
          }
      }
    return true;
  }

/* The per-slot segment record, called from Game's ARCHIVE_CLASS body inside
   the slot's K_EMBED scope (inc/Res.h, tag 816 scope, inner tag 1+slot).
   The embed's contents are three ordinary tagged fields, so the generic
   scanner and the harness field parsers keep working:

     1: K_BLOB  the script data segment: the first szDataSeg bytes, raw.
                Carried with its own length and length-checked against the
                LOADED module's szDataSeg at placement time, per
                docs/SCRIPT-DATA-SEGMENT.md's Verdict (0 bytes in every
                real module today).
     2: K_U32   rowCount
     3: K_BLOB  rowCount packed row sub-records, memory-layout order:
                  u8  rowKind   0=MonMem 1=ItemMem 2=EffMem 3=RegMem
                  u8  pool      SP_MON/SP_ITM/SP_EFF/SP_REG (must match
                                rowKind; the redundancy is a cheap check)
                  u16 ordinal   among same-pool same-name resources
                  u16 nameLen + name bytes -- an INLINE key, not a global
                                table index: memory rows have
                                discard-on-missing semantics (constraint
                                3's exception), the global table aborts
                  u8  payLen  + payload (v1SegPackRow's layouts; EffMem is
                                two uint32 GLOBAL name-table indices for
                                FlavorID/PFlavorID -- abort semantics --
                                plus one Known/Tried/PKnown/PTried flags
                                byte)

   On load this only PARSES into v1Seg[] -- no resolution, no allocation
   from module geometry: Game::Modules is stale or zeroed here, because
   both load paths reload modules only AFTER the save group
   (src/Registry.cpp:1317-1334, src/Dump.cpp:151-172). v1SegPlace() does
   the real work from SaveV1_ResolveNames(), after the reload. */
void SaveV1_SegmentFields(Registry &r, Game &g, int slot)
  {
    (void)r;
    if (v1.mode == V1_SAVE)
      {
        Module *mod = Game::Modules[slot];
        if (mod)
          v1WriteModuleManifest(mod);
        if (!g.MDataSeg[slot])
          return;               /* no segment fields for this slot */
        if (!mod)
          {
            Error("SaveV1: MDataSeg[%d] is allocated but module slot %d "
                  "is not loaded", slot, slot);
            throw ECORRUPT;
          }
        const char *seg = g.MDataSeg[slot];
        size_t start[4], total;
        v1SegStarts(mod, (size_t)g.NumPlayers(), start, &total);
        if (total > (size_t)g.MDataSegSize[slot])
          {
            Error("SaveV1: MDataSeg[%d] is %u bytes but the loaded module "
                  "needs %lu", slot, (unsigned)g.MDataSegSize[slot],
                  (unsigned long)total);
            throw ECORRUPT;
          }

        /* 1: the script data segment, raw, with its own length. */
        v1PutU16(&v1Out, 1);
        v1PutU8(&v1Out, K_BLOB);
        v1PutU32(&v1Out, (uint32)mod->szDataSeg);
        if (mod->szDataSeg)
          v1Put(&v1Out, seg, (size_t)mod->szDataSeg);

        /* The rows, in memory-layout order (pool by pool, declaration
           order within the pool) -- deterministic, so the fixpoint's
           byte-identity holds. */
        V1Buf rows;
        memset(&rows, 0, sizeof(rows));
        uint32 rowCount = 0;
        try
          {
            for (int kind = 0; kind != 4; kind++)
              {
                V1Pool pl;
                if (!V1GetPool(mod, v1SegPool[kind], &pl))
                  throw ECORRUPT;
                for (int32 j = 0; j != pl.count; j++)
                  {
                    const char *rowp = seg + start[kind] +
                        (size_t)j * v1SegStride[kind] *
                        (size_t)g.NumPlayers();
                    uint8 pay[V1_SEG_MAX_PAY];
                    if (kind == 2)
                      {
                        /* EffMem: the flavour rID VALUES go through the
                           GLOBAL name table, like any other resource
                           reference (abort semantics on load). */
                        const EffMem *m = (const EffMem*)rowp;
                        if (!m->FlavorID && !m->PFlavorID && !m->Known &&
                            !m->Tried && !m->PKnown && !m->PTried)
                          continue;
                        uint32 fi = m->FlavorID ?
                            V1InternRid((rID)m->FlavorID) : 0xFFFFFFFFu;
                        uint32 pfi = m->PFlavorID ?
                            V1InternRid((rID)m->PFlavorID) : 0xFFFFFFFFu;
                        memcpy(pay, &fi, 4);
                        memcpy(pay + 4, &pfi, 4);
                        pay[8] = (uint8)((m->Known ? 1 : 0) |
                                         (m->Tried ? 2 : 0) |
                                         (m->PKnown ? 4 : 0) |
                                         (m->PTried ? 8 : 0));
                      }
                    else if (!v1SegPackRow(kind, rowp, pay))
                      continue;
                    const char *name = V1ResName(mod, &pl, j);
                    size_t nameLen = strlen(name);
                    ASSERT(nameLen <= 0xFFFF);
                    uint32 ordinal = 0;
                    for (int32 q = 0; q != j; q++)
                      if (!strcmp(V1ResName(mod, &pl, q), name))
                        ordinal++;
                    v1PutU8(&rows, (uint8)kind);
                    v1PutU8(&rows, v1SegPool[kind]);
                    v1PutU16(&rows, (uint16)ordinal);
                    v1PutU16(&rows, (uint16)nameLen);
                    v1Put(&rows, name, nameLen);
                    v1PutU8(&rows, v1SegPayLen[kind]);
                    v1Put(&rows, pay, v1SegPayLen[kind]);
                    rowCount++;
                  }
              }
            /* 2: rowCount.  3: the packed rows. */
            v1PutU16(&v1Out, 2);
            v1PutU8(&v1Out, K_U32);
            v1PutU32(&v1Out, rowCount);
            v1PutU16(&v1Out, 3);
            v1PutU8(&v1Out, K_BLOB);
            v1PutU32(&v1Out, (uint32)rows.len);
            if (rows.len)
              v1Put(&v1Out, rows.p, rows.len);
          }
        catch (...)
          {
            v1BufFree(&rows);
            throw;
          }
        v1BufFree(&rows);
        return;
      }

    if (v1.mode != V1_LOAD)
      return;   /* v0: the raw dump path never calls this (inc/Res.h) */

    /* Record read, phase 1: parse into the file-scope context ONLY. */
    v1SegSawGame = true;
    const V1Ent *eScript = v1Find(1);
    const V1Ent *eCount  = v1Find(2);
    const V1Ent *eRows   = v1Find(3);
    const V1Ent *eLengths = v1Find(4);
    const V1Ent *eNames   = v1Find(5);

    /* The writer emits a manifest even when this slot has no memory
       segment, so this must precede the empty-embed return below. */
    if (!!eLengths != !!eNames)
      {
        Error("SaveV1: module slot %d has only one of manifest tags 4 and 5",
              slot);
        throw ECORRUPT;
      }
    if (eLengths)
      {
        V1ManifestPending *mp = &v1Manifest[slot];
        if (mp->present)
          {
            Error("SaveV1: module slot %d has two manifests", slot);
            throw ECORRUPT;
          }
        if (eLengths->kind != K_ARRAY)
          {
            Error("SaveV1: module slot %d manifest tag 4 is not an array",
                  slot);
            throw ECORRUPT;
          }
        uint32 count, elemSize;
        memcpy(&count, eLengths->pay, 4);
        memcpy(&elemSize, eLengths->pay + 4, 4);
        if (count != 21 || elemSize != sizeof(uint32))
          {
            Error("SaveV1: module slot %d manifest lengths have count %u "
                  "and element size %u; expected 21 and %lu", slot,
                  (unsigned)count, (unsigned)elemSize,
                  (unsigned long)sizeof(uint32));
            throw ECORRUPT;
          }
        if (eNames->kind != K_BLOB)
          {
            Error("SaveV1: module slot %d manifest tag 5 is not a blob",
                  slot);
            throw ECORRUPT;
          }

        unsigned long long total = 0;
        for (int p = 0; p != 21; p++)
          {
            uint32 length;
            memcpy(&length, eLengths->pay + 8 + p * sizeof(uint32),
                   sizeof(length));
            if (length > 0xFFFFFFu)
              {
                Error("SaveV1: module slot %d manifest array %d length %u "
                      "exceeds 0xFFFFFF", slot, p, (unsigned)length);
                throw ECORRUPT;
              }
            total += (unsigned long long)length;
            if (total > 0xFFFFFFu)
              {
                Error("SaveV1: module slot %d manifest length sum exceeds "
                      "0xFFFFFF at array %d", slot, p);
                throw ECORRUPT;
              }
            mp->lengths[p] = length;
          }

        if (total)
          {
            mp->names = (char**) calloc((size_t)total, sizeof(char*));
            if (!mp->names)
              throw EMEMORY;
          }
        const uint8 *p = eNames->pay;
        size_t len = eNames->size, pos = 0;
        for (uint32 k = 0; k != (uint32)total; k++)
          {
            uint16 nameLen;
            if (len - pos < sizeof(nameLen))
              {
                Error("SaveV1: module slot %d manifest name %u has no "
                      "complete length", slot, (unsigned)k);
                throw ECORRUPT;
              }
            memcpy(&nameLen, p + pos, sizeof(nameLen));
            pos += sizeof(nameLen);
            if (nameLen > len - pos)
              {
                Error("SaveV1: module slot %d manifest name %u length %u "
                      "runs past the blob", slot, (unsigned)k,
                      (unsigned)nameLen);
                throw ECORRUPT;
              }
            mp->names[k] = (char*) malloc((size_t)nameLen + 1);
            if (!mp->names[k])
              throw EMEMORY;
            memcpy(mp->names[k], p + pos, nameLen);
            mp->names[k][nameLen] = 0;
            mp->nameCount = k + 1; /* now, so a later throw frees this name */
            pos += nameLen;
          }
        if (pos != len)
          {
            Error("SaveV1: module slot %d manifest blob has %lu trailing "
                  "bytes after %u names", slot, (unsigned long)(len - pos),
                  (unsigned)mp->nameCount);
            throw ECORRUPT;
          }
        mp->present = true;
      }

    if (!eScript && !eCount && !eRows)
      return;                   /* an empty embed: slot not in use */
    if (!eScript || !eCount || !eRows)
      throw ECORRUPT;           /* a partial segment record is corruption */
    if (eScript->kind != K_BLOB || eCount->kind != K_U32 ||
        eRows->kind != K_BLOB)
      throw ECORRUPT;           /* known tag, unexpected kind */

    V1SegPending *sp = &v1Seg[slot];
    if (sp->present)
      throw ECORRUPT;           /* two records for one slot */

    uint32 rowCount;
    memcpy(&rowCount, eCount->pay, 4);
    /* Every row is at least 7 bytes of header, so this bounds the
       allocation below by the blob the scanner already bounded. */
    if (rowCount > eRows->size / 7)
      throw ECORRUPT;

    /* Copied OUT of the group buffer: LoadGroupV1 frees it before the
       deferred placement runs. */
    sp->scriptLen = eScript->size;
    if (eScript->size)
      {
        sp->script = (uint8*) malloc(eScript->size);
        if (!sp->script)
          throw EMEMORY;
        memcpy(sp->script, eScript->pay, eScript->size);
      }
    if (rowCount)
      {
        sp->rows = (V1SegRow*) calloc(rowCount, sizeof(V1SegRow));
        if (!sp->rows)
          throw EMEMORY;
      }
    {
      const uint8 *p = eRows->pay;
      size_t len = eRows->size, pos = 0;
      for (uint32 k = 0; k != rowCount; k++)
        {
          V1SegRow *row = &sp->rows[k];
          uint16 ordinal, nameLen;
          if (pos + 6 > len)
            throw ECORRUPT;
          uint8 kind = p[pos];
          uint8 pool = p[pos + 1];
          if (kind > 3 || pool != v1SegPool[kind])
            throw ECORRUPT;
          memcpy(&ordinal, p + pos + 2, 2);
          memcpy(&nameLen, p + pos + 4, 2);
          pos += 6;
          if (nameLen > len - pos)
            throw ECORRUPT;
          row->kind = kind;
          row->ordinal = ordinal;
          row->name = (char*) malloc((size_t)nameLen + 1);
          if (!row->name)
            throw EMEMORY;
          memcpy(row->name, p + pos, nameLen);
          row->name[nameLen] = 0;
          sp->rowCount = k + 1;   /* now, so a throw below still frees it */
          pos += nameLen;
          if (pos + 1 > len)
            throw ECORRUPT;
          row->payLen = p[pos];
          pos += 1;
          if (row->payLen != v1SegPayLen[kind] || row->payLen > len - pos)
            throw ECORRUPT;       /* IS1.2 payloads are fixed-size */
          memcpy(row->pay, p + pos, row->payLen);
          pos += row->payLen;
        }
      if (pos != len)
        throw ECORRUPT;           /* trailing bytes after the last row */
    }
    sp->present = true;
    sp->target = &g.MDataSeg[slot];
    sp->sizeTarget = &g.MDataSegSize[slot];
  }

/* Placement, phase 2: runs inside SaveV1_ResolveNames(), after the module
   reload, with the name-table entries already resolved. Allocates each
   pending slot's MDataSeg from the LOADED module's geometry, places the
   script blob (length-checked, docs/SCRIPT-DATA-SEGMENT.md), and walks the
   parsed rows: an inline key that no longer names a resource DISCARDS its
   row silently-by-design (one stderr line per discard in DEBUG builds, so
   the behaviour is observable); the EffMem flavour values resolve through
   the global table with ABORT semantics. Returns the failure count; the
   caller aggregates and throws. */
static long v1SegPlace(void)
  {
    long failures = 0;
    size_t np = theGame ? (size_t)theGame->NumPlayers() : 1;

    /* Only a load that replayed a Game record has a segment to place.
       A group without one -- the -schematest/-schemaload class groups --
       must not have modules-without-records demanded of it. */
    if (!v1SegSawGame)
      return 0;

    for (int slot = 0; slot != MAX_MODULES; slot++)
      {
        V1SegPending *sp = &v1Seg[slot];
        Module *mod = Game::Modules[slot];
        if (!sp->present)
          {
            if (mod)
              {
                /* The save must carry a record for every module it lists
                   in ModFiles: a missing one would leave the VM and every
                   memory accessor a NULL MDataSeg to walk. */
                failures++;
                fprintf(stderr,
                    "incursion: v1 save carries no memory segment record "
                    "for loaded module slot %d\n", slot);
              }
            continue;
          }
        if (!mod)
          {
            failures++;
            fprintf(stderr,
                "incursion: v1 memory segment record names module slot %d, "
                "which did not load\n", slot);
            continue;
          }
        if (sp->scriptLen != (uint32)mod->szDataSeg)
          {
            /* The Verdict's length guard: the script data segment is
               opaque VM state and cannot be truncated or zero-extended. */
            failures++;
            fprintf(stderr,
                "incursion: saved script data segment for module slot %d "
                "is %u bytes; the loaded module's szDataSeg is %u\n",
                slot, (unsigned)sp->scriptLen, (unsigned)mod->szDataSeg);
            continue;
          }

        size_t start[4], total;
        v1SegStarts(mod, np, start, &total);
        char *seg = (char*) malloc(total ? total : 1);
        if (!seg)
          throw EMEMORY;
        memset(seg, 0, total);
        if (sp->scriptLen)
          memcpy(seg, sp->script, sp->scriptLen);

        for (uint32 k = 0; k != sp->rowCount; k++)
          {
            V1SegRow *row = &sp->rows[k];
            V1Pool pl;
            if (!V1GetPool(mod, v1SegPool[row->kind], &pl))
              { failures++; continue; }
            int32 found = -1;
            uint32 running = 0;
            for (int32 j = 0; j != pl.count; j++)
              if (!strcmp(V1ResName(mod, &pl, j), row->name))
                {
                  if (running == row->ordinal)
                    { found = j; break; }
                  running++;
                }
            if (found < 0)
              {
                /* Silently-by-design: a memory row is annotation, not a
                   reference (constraint 3's exception). */
#ifdef DEBUG
                fprintf(stderr,
                    "incursion: v1 memory row discarded: %s \"%s\" "
                    "(ordinal %u) is no longer in module slot %d\n",
                    V1PoolName(v1SegPool[row->kind]), row->name,
                    (unsigned)row->ordinal, slot);
#endif
                continue;
              }
            char *rowp = seg + start[row->kind] +
                (size_t)found * v1SegStride[row->kind] * np;
            if (row->kind == 2)
              {
                EffMem *m = (EffMem*)rowp;
                uint32 idx[2];
                rID val[2] = { 0, 0 };
                memcpy(&idx[0], row->pay, 4);
                memcpy(&idx[1], row->pay + 4, 4);
                for (int f = 0; f != 2; f++)
                  {
                    if (idx[f] == 0xFFFFFFFFu)
                      continue;               /* encoded null */
                    if (idx[f] >= v1.nameCount)
                      {
                        failures++;
                        fprintf(stderr,
                            "incursion: v1 EffMem flavour references name "
                            "table entry %u of %u\n",
                            (unsigned)idx[f], (unsigned)v1.nameCount);
                        continue;
                      }
                    if (v1.names[idx[f]].bad)
                      continue;               /* counted and reported */
                    val[f] = v1.names[idx[f]].resolved;
                  }
                m->FlavorID  = (unsigned)val[0];
                m->PFlavorID = (unsigned)val[1];
                m->Known  = row->pay[8] & 1;
                m->Tried  = (row->pay[8] >> 1) & 1;
                m->PKnown = (row->pay[8] >> 2) & 1;
                m->PTried = (row->pay[8] >> 3) & 1;
              }
            else
              v1SegUnpackRow(row->kind, row->pay, rowp);
          }

        *(sp->target) = seg;
        *(sp->sizeTarget) = (uint32) total;
      }
    return failures;
  }

/* Deferred resolution: called once after each load path's module-reload
   loop (Game::LoadGame, RunSaveDump, and the -schematest/-schemaload
   drivers). Resolves every queued slot or aborts naming EVERY failure --
   an unresolvable entry MUST NOT be zeroed and MUST NOT be skipped
   (constraint 3). A v0 load queues nothing and returns immediately. */
void SaveV1_ResolveNames()
  {
    uint32 i;
    long failures = 0;

    if (!v1.slotQCount && !v1.statQCount && !v1.nameCount && !v1SegSawGame)
      return;

    failures += v1ManifestPreflight();
    if (failures)
      {
        v1ResolveTeardown();
        throw ECORRUPT;
      }

    for (i = 0; i != v1.nameCount; i++)
      {
        V1NameEntry *ent = &v1.names[i];
        if (V1ResolveEntry(ent))
          continue;
        ent->bad = true;
        failures++;
        fprintf(stderr,
            "incursion: v1 name table entry %u does not resolve: "
            "pool %s, module slot %u, ordinal %u, name \"%s\"\n",
            (unsigned)i, V1PoolName(ent->pool), (unsigned)ent->slot,
            (unsigned)ent->ordinal, ent->name);
      }

    for (i = 0; i != v1.slotQCount; i++)
      {
        rID resolved;
        if (!v1ConvertManifestRid((uint32)*(v1.slotQ[i]), &resolved))
          { failures++; continue; }
        *(v1.slotQ[i]) = resolved;
      }

    for (i = 0; i != v1.statQCount; i++)
      {
        rID resolved;
        if (!v1ConvertManifestRid((uint32)v1.statQ[i]->eID, &resolved))
          { failures++; continue; }
        v1.statQ[i]->eID = (int32)resolved;
      }

    /* Phase 2 of the memory segment record: allocation from the LOADED
       modules' geometry, script-blob placement, and the name-keyed row
       walk. Runs after the entry loop above because the EffMem flavour
       values read the resolved entries. */
    failures += v1SegPlace();

    v1ResolveTeardown();
    if (failures)
      throw ECORRUPT;
  }

/* Drop any pending (unconsumed) resolve state. A load path that parks
   state in LoadGroupV1 and then fails before its SaveV1_ResolveNames() call
   runs -- Game::LoadGame's null-map/player return is one such path -- must
   not leave it behind for the NEXT load attempt to consume against the
   wrong file. Game::LoadGame calls this at entry. */
void SaveV1_DiscardPending()
  {
    v1ResolveTeardown();
  }

/* ------------------------------------------------------------------------ */
/*                            reader primitives                             */
/* ------------------------------------------------------------------------ */

static size_t v1KindFixedSize(uint8 kind)
  {
    switch (kind)
      {
        case K_U8: case K_I8:   return 1;
        case K_U16: case K_I16: return 2;
        case K_U32: case K_I32:
        case K_RID: case K_H:   return 4;
      }
    return 0;   /* variable or unknown */
  }

/* Scan one field stream [p, p+len) into an entry list. The stream must end
   with its tag-0 terminator exactly at len. Unknown TAGS are kept (and so
   skipped by never being looked up); an unknown KIND cannot be sized and is
   corruption. Strict bounds on every read. */
static void v1ScanFields(const uint8 *p, size_t len, V1Ent **outEnts,
                         int *outCount)
  {
    V1Ent *ents = NULL;
    int count = 0, cap = 0;
    size_t pos = 0;
    for (;;)
      {
        uint16 tag; uint8 kind;
        if (pos + 2 > len)
          { free(ents); throw ECORRUPT; }
        memcpy(&tag, p + pos, 2); pos += 2;
        if (tag == 0)
          break;
        if (pos + 1 > len)
          { free(ents); throw ECORRUPT; }
        kind = p[pos]; pos += 1;
        const uint8 *pay; uint32 size;
        size_t fixed = v1KindFixedSize(kind);
        if (fixed)
          {
            if (pos + fixed > len)
              { free(ents); throw ECORRUPT; }
            pay = p + pos; size = (uint32)fixed; pos += fixed;
          }
        else if (kind == K_STR || kind == K_BLOB || kind == K_EMBED)
          {
            uint32 l;
            if (pos + 4 > len)
              { free(ents); throw ECORRUPT; }
            memcpy(&l, p + pos, 4); pos += 4;
            if (l > len - pos)
              { free(ents); throw ECORRUPT; }
            pay = p + pos; size = l; pos += l;
          }
        else if (kind == K_ARRAY)
          {
            uint32 c, e;
            if (pos + 8 > len)
              { free(ents); throw ECORRUPT; }
            memcpy(&c, p + pos, 4);
            memcpy(&e, p + pos + 4, 4);
            unsigned long long total = (unsigned long long)c * e;
            if (total > (unsigned long long)(len - pos - 8))
              { free(ents); throw ECORRUPT; }
            pay = p + pos;                       /* count field included */
            size = 8 + (uint32)total;
            pos += size;
          }
        else
          { free(ents); throw ECORRUPT; }        /* unknown kind */
        if (count == cap)
          {
            cap = cap ? cap * 2 : 16;
            V1Ent *ne = (V1Ent*) realloc(ents, cap * sizeof(V1Ent));
            if (!ne)
              { free(ents); throw EMEMORY; }
            ents = ne;
          }
        ents[count].tag = tag;
        ents[count].kind = kind;
        ents[count].pay = pay;
        ents[count].size = size;
        count++;
      }
    if (pos != len)
      { free(ents); throw ECORRUPT; }
    *outEnts = ents;
    *outCount = count;
  }

static void v1PushFrame(V1Ent *ents, int count)
  {
    if (v1FrameDepth == V1_MAX_DEPTH)
      { free(ents); throw ECORRUPT; }
    v1Frames[v1FrameDepth].ents = ents;
    v1Frames[v1FrameDepth].count = count;
    v1FrameDepth++;
  }

static void v1PopFrame(void)
  {
    if (v1FrameDepth == 0)
      return;
    v1FrameDepth--;
    free(v1Frames[v1FrameDepth].ents);
    v1Frames[v1FrameDepth].ents = NULL;
    v1Frames[v1FrameDepth].count = 0;
  }

static const V1Ent* v1Find(uint16 tag)
  {
    if (v1FrameDepth == 0)
      return NULL;
    V1Frame *f = &v1Frames[v1FrameDepth - 1];
    for (int i = 0; i != f->count; i++)
      if (f->ents[i].tag == tag)
        return &f->ents[i];
    return NULL;
  }

/* ------------------------------------------------------------------------ */
/*                          the Registry methods                            */
/* ------------------------------------------------------------------------ */

bool Registry::V1Active()
  { return v1.mode != V1_OFF; }

void Registry::V1Field(uint16 tag, uint8 kind, void *p, size_t size)
  {
    if (v1.mode == V1_OFF)
      return;   /* v0: the raw dump already carries scalars */
    ASSERT(v1KindFixedSize(kind) == size);
    if (v1.mode == V1_SAVE)
      {
        v1CovMark(p, size);
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, kind);
        v1Put(&v1Out, p, size);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      return;   /* absent field: the constructed (zero) default stands */
    if (e->kind != kind)
      throw ECORRUPT;   /* known tag, unexpected kind */
    memcpy(p, e->pay, size);
  }

void Registry::V1Str(uint16 tag, String &s)
  {
    if (v1.mode == V1_OFF)
      return;   /* unreached: FIELD_STR takes the legacy branch in v0 */
    if (v1.mode == V1_SAVE)
      {
        v1CovMark(&s, sizeof(String));
        const char *data = s.GetData();
        uint32 len = data ? (uint32)s.GetLength() : 0;
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_STR);
        v1PutU32(&v1Out, len);
        if (len)
          v1Put(&v1Out, data, len);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      return;
    if (e->kind != K_STR)
      throw ECORRUPT;
    if (!e->size)
      return;   /* empty writes as len 0 and loads as the zeroed default */
    char *tmp = (char*) malloc((size_t)e->size + 1);
    if (!tmp)
      throw EMEMORY;
    memcpy(tmp, e->pay, e->size);
    tmp[e->size] = 0;
    s = tmp;
    free(tmp);
  }

void Registry::V1Blob(uint16 tag, void **p, size_t sz)
  {
    if (v1.mode == V1_OFF)
      return;   /* unreached: FIELD_BLOB takes the legacy branch in v0 */
    if (v1.mode == V1_SAVE)
      {
        v1CovMark(p, sizeof(void*));
        uint32 len = *p ? (uint32)sz : 0;
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_BLOB);
        v1PutU32(&v1Out, len);
        if (len)
          v1Put(&v1Out, *p, len);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      return;
    if (e->kind != K_BLOB)
      throw ECORRUPT;
    if (!e->size)
      { *p = NULL; return; }
    /* Every FIELD_BLOB caller loads its size fields before its blob line
       (load-direction ordering), so sz here is what the object's own loaded
       counts say the blob must be. A non-empty blob of any other length is
       corruption: the consumers index the allocation by those counts, so a
       shorter blob is a heap overread waiting in At()/GetText()/Execute.
       (The empty case above stays permissive: a NULL pointer wrote len 0
       regardless of what sz evaluated to at save time.)

       BOTH checks below are load-bearing, in this order. sz is a size_t
       computed from file-fed counts (sizeX*sizeY, DungeonSize, the module
       counts), so a crafted pair like sizeX=32767 sizeY=6554 makes it
       4,295,106,360 -- and a compare truncated to 32 bits would pass a
       139,064-byte blob (the product's low half) that the game then
       indexes as 214 million cells. The ceiling rejects any expected size
       past the same CFILE_SANE_MAX_SIZE bound every reader allocation
       honours; the full-width compare rejects any lie the ceiling lets
       through. The adversarial mutant map_grid_size_overflow
       (tools/craft_bad_v1_saves.py) holds this exact door shut. */
    if ((unsigned long long)sz > (unsigned long long)CFILE_SANE_MAX_SIZE)
      throw ECORRUPT;
    if ((unsigned long long)e->size != (unsigned long long)sz)
      throw ECORRUPT;
    void *blk = malloc(e->size);
    if (!blk)
      throw EMEMORY;
    memcpy(blk, e->pay, e->size);
    *p = blk;
  }

void Registry::V1Rid(uint16 tag, rID &m)
  {
    if (v1.mode == V1_OFF)
      return;   /* v0: the raw dump already carries the rID */
    if (v1.mode == V1_SAVE)
      {
        v1CovMark(&m, sizeof(rID));
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_RID);
        v1PutU32(&v1Out, (uint32)m);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      { m = 0; return; }
    if (e->kind != K_RID)
      throw ECORRUPT;
    uint32 saved;
    memcpy(&saved, e->pay, 4);
    if (saved == 0)
      { m = 0; return; }
    /* Deferred: park the saved rID in the slot and queue its address for
       SaveV1_ResolveNames(), which runs after the modules are reloaded. */
    m = (rID)saved;
    if (v1.slotQCount == v1.slotQCap)
      {
        v1.slotQCap = v1.slotQCap ? v1.slotQCap * 2 : 64;
        rID **nq = (rID**) realloc(v1.slotQ, v1.slotQCap * sizeof(rID*));
        if (!nq)
          throw EMEMORY;
        v1.slotQ = nq;
      }
    v1.slotQ[v1.slotQCount++] = &m;
  }

/* Status's members are bitfields: FIELD_RID cannot bind Status::eID to an
   rID&, and a stack temporary cannot be queued (it dies before the deferred
   resolve runs). So the Status itself -- heap-stable inside its collection's
   S array -- is queued, and the index parks in the eID bitfield. */
void Registry::V1RidStatus(uint16 tag, Status &s)
  {
    if (v1.mode == V1_OFF)
      return;
    if (v1.mode == V1_SAVE)
      {
        rID e = (rID)s.eID;
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_RID);
        v1PutU32(&v1Out, (uint32)e);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      { s.eID = 0; return; }
    if (e->kind != K_RID)
      throw ECORRUPT;
    uint32 saved;
    memcpy(&saved, e->pay, 4);
    if (saved == 0)
      { s.eID = 0; return; }
    s.eID = (int32)saved;
    if (v1.statQCount == v1.statQCap)
      {
        v1.statQCap = v1.statQCap ? v1.statQCap * 2 : 64;
        Status **nq = (Status**)
            realloc(v1.statQ, v1.statQCap * sizeof(Status*));
        if (!nq)
          throw EMEMORY;
        v1.statQ = nq;
      }
    v1.statQ[v1.statQCount++] = &s;
  }

void Registry::V1Array(uint16 tag, void *p, size_t elemSize, uint32 count)
  {
    if (v1.mode == V1_OFF)
      /* REACHED, and it must stay a no-op return. FIELD_ARRAY sits in an
         ARCHIVE_CLASS body -- Creature's Attr[ATTR_LAST] (inc/Creature.h) --
         so the v0 save and load paths run this line for every creature. The
         v0 raw dump already carries the array's bytes; writing anything here
         would corrupt the v0 format. */
      return;
    if (v1.mode == V1_SAVE)
      {
        /* A fixed array is a field like any other, so it covers its own
           bytes. Without this, the first array member declared -- Creature's
           Attr[ATTR_LAST] -- read as 82 uncovered bytes and no pin row could
           honestly account for them. */
        v1CovMark(p, (size_t)count * elemSize);
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_ARRAY);
        v1PutU32(&v1Out, count);
        v1PutU32(&v1Out, (uint32)elemSize);
        if (count)
          v1Put(&v1Out, p, (size_t)count * elemSize);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      return;
    if (e->kind != K_ARRAY)
      throw ECORRUPT;
    uint32 c, es;
    memcpy(&c, e->pay, 4);
    memcpy(&es, e->pay + 4, 4);
    /* The count landed through its own field line before this call, and the
       caller allocated for it; the wire disagreeing with either is
       corruption, not extension. */
    if (c != count || es != (uint32)elemSize)
      throw ECORRUPT;
    if (c)
      memcpy(p, e->pay + 8, (size_t)c * es);
  }

void Registry::V1EmbedBegin(uint16 tag, void *member, size_t size)
  {
    if (v1.mode == V1_OFF)
      return;
    if (v1.mode == V1_SAVE)
      {
        v1CovOpenEmbed(member, size);
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_EMBED);
        if (v1.wEmbedDepth == V1_MAX_DEPTH)
          { Error("SaveV1: embed nesting too deep"); throw ECORRUPT; }
        v1.wEmbedPatch[v1.wEmbedDepth++] = v1Out.len;
        v1PutU32(&v1Out, 0);   /* length placeholder */
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      { v1PushFrame(NULL, 0); return; }   /* absent: defaults stand */
    if (e->kind != K_EMBED)
      throw ECORRUPT;
    V1Ent *ents; int count;
    v1ScanFields(e->pay, e->size, &ents, &count);
    v1PushFrame(ents, count);
  }

void Registry::V1EmbedEnd()
  {
    if (v1.mode == V1_OFF)
      return;
    if (v1.mode == V1_SAVE)
      {
        v1PutU16(&v1Out, 0);   /* the nested scope's terminator */
        ASSERT(v1.wEmbedDepth > 0);
        size_t patch = v1.wEmbedPatch[--v1.wEmbedDepth];
        v1Patch32(&v1Out, patch, (uint32)(v1Out.len - (patch + 4)));
        v1CovCloseEmbed();
        return;
      }
    v1PopFrame();
  }

void Registry::V1Cover(const void *p, size_t size)
  {
    if (v1.mode != V1_SAVE)
      return;
    v1CovMark(p, size);
  }

/* ------------------------------------------------------------------------ */
/*              per-element field lists for non-POD array elements          */
/* ------------------------------------------------------------------------ */

/* These run only on the v1 path: the arrays' owners reach them through
   FIELD_OBJ's V1Active() branch, and the elements through FIELD_EMBED,
   which has no v0 branch at all. The v0 path still raw-dumps the arrays
   through Array::Serialize, exactly as before. Embedded tag scopes start
   at 1. */

void Field::FieldsV1(Registry &r)
  {
    FIELD_RID(1, eID);
    FIELD_U32(2, FType);
    FIELD_U32(3, Image);          /* Glyph */
    FIELD_U8 (4, cx);
    FIELD_U8 (5, cy);
    FIELD_U8 (6, rad);
    FIELD_I16(7, Dur);
    FIELD_H  (8, Creator);
    FIELD_H  (9, Next);
    FIELD_I8 (10, Color);
  }

void TerraRecord::FieldsV1(Registry &r)
  {
    FIELD_I16(1, key);
    FIELD_I16(2, Duration);
    FIELD_I8 (3, SaveDC);
    FIELD_I8 (4, DType);
    FIELD_I8 (5, pval.Number);
    FIELD_I8 (6, pval.Sides);
    FIELD_I8 (7, pval.Bonus);
    FIELD_RID(8, eID);
    FIELD_H  (9, Creator);
  }

void LimboEntry::FieldsV1(Registry &r)
  {
    FIELD_H  (1, h);
    FIELD_H  (2, Target);
    FIELD_U8 (3, x);
    FIELD_U8 (4, y);
    FIELD_RID(5, mID);
    FIELD_I8 (6, Depth);
    FIELD_I8 (7, OldDepth);
    FIELD_U32(8, Arrival);
    /* v0 raw-dumped the String struct itself, restoring a Buffer pointer
       into the writing process's dead heap; v1 stores the text. A zeroed
       String (the load side's memset below) is a valid empty one -- Buffer
       NULL, Length 0, Canary 0 -- so plain assignment works. */
    FIELD_STR(9, Message);
  }

void ModuleRecord::FieldsV1(Registry &r)
  {
    FIELD_U8 (1, Slot);
    FIELD_H  (2, hMod);
    FIELD_ARRAY(3, FName, 1, 1024);
  }

/* ------------------------------------------------------------------------ */
/*                     the packed map grid (Map tag 672)                    */
/* ------------------------------------------------------------------------ */

/* The 8-byte packed tile the grid record carries. The comment and
   static_asserts beside LocationInfo (inc/Map.h) are the normative layout
   statement; these two loops implement it, reading and writing every
   bitfield BY NAME -- never a memcpy of the bitfield block, because the
   compiler owns that block's bit order and padding, and letting them reach
   the file was the layout defect this record removed (SCHEMA_REV 0 -> 1).
   Glyph, Memory and Contents travel as sibling blobs in the grid record;
   they are not part of this element. */
static void v1PackTile(const LocationInfo *t, uint8 *d)
  {
    uint16 flags = (uint16)
        ( ((uint16)t->Opaque     << 0)  | ((uint16)t->Obscure    << 1)
        | ((uint16)t->Lit        << 2)  | ((uint16)t->Bright     << 3)
        | ((uint16)t->Solid      << 4)  | ((uint16)t->Shade      << 5)
        | ((uint16)t->hasField   << 6)  | ((uint16)t->Dark       << 7)
        | ((uint16)t->mLight     << 8)  | ((uint16)t->mTerrain   << 9)
        | ((uint16)t->cOpaque    << 10) | ((uint16)t->Special    << 11)
        | ((uint16)t->isWall     << 12) | ((uint16)t->isVault    << 13)
        | ((uint16)t->isSkylight << 14) | ((uint16)t->mObscure   << 15) );
    d[0] = (uint8)t->Region;
    d[1] = (uint8)t->Terrain;
    d[2] = (uint8)(flags & 0xFF);
    d[3] = (uint8)(flags >> 8);
    d[4] = (uint8)(t->Visibility & 0xFF);
    d[5] = (uint8)((t->Visibility >> 8) & 0xFF);
    d[6] = 0;   /* reserved */
    d[7] = 0;   /* reserved */
  }

static void v1UnpackTile(const uint8 *d, LocationInfo *t)
  {
    uint16 flags = (uint16)(d[2] | ((uint16)d[3] << 8));
    t->Region     = d[0];
    t->Terrain    = d[1];
    t->Opaque     = (flags >> 0)  & 1;
    t->Obscure    = (flags >> 1)  & 1;
    t->Lit        = (flags >> 2)  & 1;
    t->Bright     = (flags >> 3)  & 1;
    t->Solid      = (flags >> 4)  & 1;
    t->Shade      = (flags >> 5)  & 1;
    t->hasField   = (flags >> 6)  & 1;
    t->Dark       = (flags >> 7)  & 1;
    t->mLight     = (flags >> 8)  & 1;
    t->mTerrain   = (flags >> 9)  & 1;
    t->cOpaque    = (flags >> 10) & 1;
    t->Special    = (flags >> 11) & 1;
    t->isWall     = (flags >> 12) & 1;
    t->isVault    = (flags >> 13) & 1;
    t->isSkylight = (flags >> 14) & 1;
    t->mObscure   = (flags >> 15) & 1;
    t->Visibility = (uint16)(d[4] | ((uint16)d[5] << 8));
    /* d[6], d[7]: reserved, ignored until a flag is appended there */
  }

#ifdef DEBUG
/* Runs once, at the first grid write. Fills one LocationInfo with all-ones
   in EVERY declared field -- the fill list below is maintained WITH the
   pack loop -- packs it, unpacks into a zeroed second tile, and memcmps
   the two. Any field the pack or the unpack loop drops, truncates or
   mis-orders fails immediately; a field added to the struct and to this
   fill list but not to both loops fails the same way. Glyph, Memory and
   Contents travel as sibling blobs in the grid record, so the probe routes
   them the way the real loops do: whole-word copies. */
static void v1GridProbe(void)
  {
    static bool fired;
    if (fired)
      return;
    fired = true;
    LocationInfo a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    a.Glyph = 0xFFFFFFFFu;
    a.Region = 0xFF;   a.Terrain = 0xFF;
    a.Opaque = 1;      a.Obscure = 1;    a.Lit = 1;        a.Bright = 1;
    a.Solid = 1;       a.Shade = 1;      a.hasField = 1;   a.Dark = 1;
    a.mLight = 1;      a.mTerrain = 1;   a.cOpaque = 1;    a.Special = 1;
    a.isWall = 1;      a.isVault = 1;    a.isSkylight = 1; a.mObscure = 1;
    a.Visibility = 0xFFFF;
    a.Memory = 0xFFFFFFFFu;
    a.Contents = (hObj)-1;
    uint8 d[8];
    v1PackTile(&a, d);
    v1UnpackTile(d, &b);
    b.Glyph    = a.Glyph;      /* sibling blob, as GridFieldsV1's copy */
    b.Memory   = a.Memory;     /* sibling blob */
    b.Contents = a.Contents;   /* sibling blob */
    if (memcmp(&a, &b, sizeof(a)))
      Fatal("SaveV1: the packed tile layout dropped or mis-ordered a "
            "LocationInfo field; fix the pack/unpack loops and the fill "
            "list in v1GridProbe together");
  }
#endif

/* Map's grid record (tag 672, K_EMBED -- the SCHEMA_REV 0 -> 1 change):
     1: K_I16 sizeX      2: K_I16 sizeY     3: K_U8 elemSize (= 8)
     4: K_BLOB packed    sizeX*sizeY*8 bytes -- the tile image above
     5: K_BLOB glyphs    sizeX*sizeY*4 bytes -- LocationInfo::Glyph
     6: K_BLOB memory    sizeX*sizeY*4 bytes -- LocationInfo::Memory
     7: K_BLOB contents  sizeX*sizeY*4 bytes -- LocationInfo::Contents
   Called only from the tag-672 embed in Map's ARCHIVE_CLASS body, so it
   runs on the v1 path alone. Map's own sizeX/sizeY field lines sit ABOVE
   the embed line (load-direction ordering), so on load they hold the
   file's values by the time this runs; the record's own dimensions are
   cross-checked against them, and elemSize must be 8 -- either
   disagreement is corruption, named on stderr. The blob sizes are computed
   in size_t from the already-bounded dimensions, and V1Blob's
   CFILE_SANE_MAX_SIZE ceiling + full-width compare (see its own comment)
   reject any lie about their lengths -- nothing is re-truncated here. */
void Map::GridFieldsV1(Registry &r)
  {
    size_t n = (size_t)sizeX * (size_t)sizeY;
    int16 gx = 0, gy = 0;
    uint8 elem = 0;
    uint8 *packed = NULL;
    uint32 *glyphs = NULL, *memw = NULL;
    hObj *conts = NULL;
    size_t i;

    if (r.Saving())
      {
#ifdef DEBUG
        v1GridProbe();
#endif
        gx = sizeX; gy = sizeY; elem = 8;
        if (Grid && n)
          {
            packed = (uint8*)  malloc(n * 8);
            glyphs = (uint32*) malloc(n * 4);
            memw   = (uint32*) malloc(n * 4);
            conts  = (hObj*)   malloc(n * 4);
            if (!packed || !glyphs || !memw || !conts)
              {
                free(packed); free(glyphs); free(memw); free(conts);
                throw EMEMORY;
              }
            for (i = 0; i != n; i++)
              {
                v1PackTile(&Grid[i], packed + i * 8);
                glyphs[i] = Grid[i].Glyph;
                memw[i]   = Grid[i].Memory;
                conts[i]  = Grid[i].Contents;
              }
          }
      }

    try
      {
        FIELD_I16(1, gx);
        FIELD_I16(2, gy);
        FIELD_U8 (3, elem);
        if (r.Loading())
          if (gx != sizeX || gy != sizeY || elem != 8)
            {
              fprintf(stderr,
                  "incursion: the grid record claims %d x %d cells of %d "
                  "bytes; the map's own fields say %d x %d of 8\n",
                  (int)gx, (int)gy, (int)elem, (int)sizeX, (int)sizeY);
              throw ECORRUPT;
            }
        r.V1Blob(4, (void**)&packed, n * 8);
        r.V1Blob(5, (void**)&glyphs, n * 4);
        r.V1Blob(6, (void**)&memw,   n * 4);
        r.V1Blob(7, (void**)&conts,  n * 4);
        if (r.Loading())
          {
            Grid = NULL;
            if (n && packed && glyphs && memw && conts)
              {
                Grid = (LocationInfo*) malloc(sizeof(LocationInfo) * n);
                if (!Grid)
                  throw EMEMORY;
                memset(Grid, 0, sizeof(LocationInfo) * n);
                for (i = 0; i != n; i++)
                  {
                    v1UnpackTile(packed + i * 8, &Grid[i]);
                    Grid[i].Glyph    = glyphs[i];
                    Grid[i].Memory   = memw[i];
                    Grid[i].Contents = conts[i];
                  }
              }
            else if (packed || glyphs || memw || conts)
              {
                /* Some of the four payload blobs are empty and others are
                   not: no writer produces that. (All four empty with a
                   non-empty size leaves Grid NULL, and the trailing check
                   in Map's ARCHIVE_CLASS body refuses that file.) */
                fprintf(stderr, "incursion: the grid record is missing "
                        "part of its payload\n");
                throw ECORRUPT;
              }
          }
      }
    catch (...)
      {
        free(packed); free(glyphs); free(memw); free(conts);
        throw;
      }
    free(packed); free(glyphs); free(memw); free(conts);
  }

/* The four Array member specialisations, declared in inc/Map.h and
   inc/Res.h beside their element structs. Same shape as the generic POD
   FieldsV1 in src/Base.cpp -- Count, bound it, allocate, then the elements
   -- except each element is an embed of named fields instead of raw bytes,
   because these element types carry rIDs, handles or a String. The 0xFFF0
   ceiling keeps 3+i inside the uint16 tag space; every one of these arrays
   counts in the tens at most in a real game, so only a crafted file can
   reach it (file-fed impossible value: ECORRUPT). */
#define V1_ELEM_ARRAY_FIELDS(S)                                           \
    {                                                                     \
      uint32 i;                                                           \
      FIELD_U32(1, Count);                                                \
      if (r.Loading())                                                    \
        {                                                                 \
          if (Count > 0xFFF0 ||                                           \
              (unsigned long long)Count * sizeof(S) >                     \
              (unsigned long long)CFILE_SANE_MAX_SIZE)                    \
            throw ECORRUPT;                                               \
          Size = Count;                                                   \
          Items = NULL;                                                   \
          if (Size)                                                       \
            {                                                             \
              Items = (S*) malloc(sizeof(S)*Size);                        \
              if (!Items)                                                 \
                throw EMEMORY;                                            \
              memset(Items,0,sizeof(S)*Size);                             \
            }                                                             \
        }                                                                 \
      for (i = 0; i != Count; i++)                                        \
        FIELD_EMBED((uint16)(3+i), Items[i]);                             \
    }

template<> void Array<Field,10,5>::FieldsV1(Registry &r)
    V1_ELEM_ARRAY_FIELDS(Field)

template<> void Array<TerraRecord,0,5>::FieldsV1(Registry &r)
    V1_ELEM_ARRAY_FIELDS(TerraRecord)

template<> void Array<LimboEntry,20,10>::FieldsV1(Registry &r)
    V1_ELEM_ARRAY_FIELDS(LimboEntry)

template<> void Array<ModuleRecord,5,5>::FieldsV1(Registry &r)
    V1_ELEM_ARRAY_FIELDS(ModuleRecord)

#undef V1_ELEM_ARRAY_FIELDS

/* ------------------------------------------------------------------------ */
/*                               the writer                                 */
/* ------------------------------------------------------------------------ */

/* The caller writes the complete fileHeader first -- SaveSchemaID() into
   Version, Compression = SaveV1_Raw() ? 0 : 1 -- exactly as v0's callers
   write theirs. This writes one group: placeholder groupHeader, the records,
   SIGNATURE_TWO, the name table, then backpatches the real header. */
int16 Registry::SaveGroupV1(Term &t, hObj hGroup)
  {
    groupHeader gh;
    int32 i;
    RegNode *r;
    uint32 ghPos;

    v1WriterTeardown();   /* stale state from an aborted run, if any */
    V1SaveScope guard(&saveMode);
#ifdef DEBUG
    long covBefore = v1CovFindings;
#endif

    t.Seek(0, SEEK_END);
    ghPos = t.Tell();
    memset(&gh, 0, sizeof(gh));
    t.FWrite(&gh, sizeof(gh));

    v1.mode = V1_SAVE;
    saveMode = true;

    gh.objCount = 0;
    for (i = 0; i != OBJ_TABLE_SIZE; i++)
      if (ObjTable[i].pObj)
        {
          r = &(ObjTable[i]);
          while (r)
            {
              if (!r->pObj->inGroup(hGroup))
                { r = r->Next; continue; }

              Object *o = r->pObj;
              hCurrent = o->myHandle;
              gh.objCount++;
              SaveFailProbe(false, gh.objCount);

              v1CovBegin(o);
              /* The envelope carries Type and myHandle; no FIELD_ line
                 does, and they must not be absorbed into pad rows. */
              V1Cover(&(o->Type), sizeof(o->Type));
              V1Cover(&(o->myHandle), sizeof(o->myHandle));

              v1PutU8(&v1Out, (uint8)o->Type);
              v1PutU32(&v1Out, (uint32)o->myHandle);
              size_t lenPos = v1Out.len;
              v1PutU32(&v1Out, 0);   /* length placeholder */

              o->Serialize(*this, true);

              v1PutU16(&v1Out, 0);   /* record terminator */
              v1Patch32(&v1Out, lenPos, (uint32)(v1Out.len - (lenPos + 4)));
              ASSERT(v1.wEmbedDepth == 0);
              v1CovEnd();

              r = r->Next;
            }
        }

#ifdef DEBUG
    /* Constraint 8: the coverage check is non-optional, and a finding on the
       REAL save path must refuse the save loudly, never write a file whose
       records silently miss (or double-carry) bytes. Each finding was
       already reported by Error() as it was found; this turns the batch
       into a save failure. The file is left with its zeroed placeholder
       groupHeader, which no reader accepts (Signature check), and
       Game::SaveGame's catch shows the player "Error writing save file
       (Corrupt File)". DEBUG only: a shipping build carries no coverage
       map to judge by. */
    if (v1CovFindings != covBefore)
      {
        fprintf(stderr,
            "incursion: refusing to write a v1 save: %ld schema coverage "
            "finding(s) -- see the SCHEMA COVERAGE errors above\n",
            v1CovFindings - covBefore);
        throw ECORRUPT;
      }
#endif

    { uint32 sig = SIGNATURE_TWO; v1Put(&v1Out, &sig, 4); }

    v1PutU32(&v1Out, v1.nameCount);
    for (uint32 e = 0; e != v1.nameCount; e++)
      {
        V1NameEntry *ent = &v1.names[e];
        size_t nameLen = strlen(ent->name);
        ASSERT(nameLen <= 0xFFFF);
        v1PutU8(&v1Out, ent->pool);
        v1PutU8(&v1Out, ent->slot);
        v1PutU16(&v1Out, ent->ordinal);
        v1PutU16(&v1Out, (uint16)nameLen);
        v1Put(&v1Out, ent->name, nameLen);
      }

    gh.groupSize = (int32)v1Out.len;
    if (SaveV1_Raw())
      {
        t.FWrite(v1Out.p, v1Out.len);
        gh.compSize = (int32)v1Out.len;
      }
    else
      {
        /* WIRE FORMAT: for IS1.x files, fileHeader.Compression == 1 MEANS
           zlib level 6 (0 stays raw). v0 keeps its CFile RLE untouched.
           RLE was measured hopeless on tagged records -- it compresses
           runs, and a tag stream has none: seed-1 smoke save, 2026-08-24,
           552,209 raw -> 332,517 RLE (60.2%) but 26,430 zlib-6 (4.8%);
           the v0 file of the same seed is 239,535. libz is already a link
           dependency (CFile's LZ path). */
        uLongf clen = compressBound((uLong)v1Out.len);
        Bytef *cbuf = (Bytef*) malloc(clen);
        if (!cbuf)
          throw EMEMORY;
        if (compress2(cbuf, &clen, (const Bytef*)v1Out.p,
                      (uLong)v1Out.len, 6) != Z_OK)
          {
            free(cbuf);
            throw EMEMORY;   /* compress2 fails only on memory/param */
          }
        t.FWrite(cbuf, (size_t)clen);
        free(cbuf);
        gh.compSize = (int32)clen;
      }

    gh.Signature  = SIGNATURE;
    gh.hGroup     = hGroup;
    gh.dataCount  = 0;   /* v1 has no data-block section */
    gh.LastHandle = LastUsedHandle;
    t.Seek(ghPos, SEEK_SET);
    t.FWrite(&gh, sizeof(gh));
    t.Seek(0, SEEK_END);

    /* guard clears saveMode and tears the writer context down. No
       SaveFixupScope: v1 never parks handles in pointer slots and never
       mutates the object -- the hand-written per-mode staging lines in the
       bodies (Thing's hm) are idempotent. */
    return 0;
  }

/* ------------------------------------------------------------------------ */
/*                               the reader                                 */
/* ------------------------------------------------------------------------ */

static bool v1KnownRecordType(uint8 t)
  {
    switch (t)
      {
        case T_GAME: case T_MAP: case T_MONSTER: case T_PLAYER:
        case T_MODULE: case T_PORTAL: case T_DOOR: case T_TRAP:
        case T_FEATURE:
          return true;
      }
    return t >= T_FIRSTITEM && t <= T_LASTITEM;
  }

int16 Registry::LoadGroupV1(Term &t, fileHeader &fh, hObj hGroup)
  {
    groupHeader gh;
    int32 i;
    uint8 *buf = NULL;
    /* Pass-1 bookkeeping for the two-pass load below: each record's scanned
       entry list (pointing into buf) and its constructed object, held until
       pass 2 replays them. */
    struct V1Loaded { V1Ent *ents; int count; Object *o; };
    V1Loaded *loaded = NULL;
    uint32 loadedCount = 0, loadedCap = 0;

    /* Reject a schema revision this binary does not implement, naming both
       (wire-format section, schema revisions). The "IS1." prefix was checked
       by the dispatch in LoadGroup. Bounded compare and bounded print:
       fh.Version is char[12] straight off the file with NO NUL guarantee,
       so plain strcmp/%s on it would read into fh.Name and beyond on a
       crafted header of 12 non-NUL bytes. */
    if (strncmp(fh.Version, SaveSchemaID(), sizeof(fh.Version)))
      {
        fprintf(stderr,
            "incursion: this file is save-schema revision \"%.12s\"; this "
            "binary implements \"%s\"\n", fh.Version, SaveSchemaID());
        throw EBADVER;
      }

    v1ReaderTeardown();
    v1ResolveTeardown();   /* stale state from an aborted load, if any */
    V1LoadScope guard;
    v1.mode = V1_LOAD;

    /* The group walk, as LoadGroup's (src/Registry.cpp). */
    for (i = 0; i != fh.numGroups; i++)
      {
        t.FRead(&gh, sizeof(gh));
        if (gh.Signature != SIGNATURE)
          throw ECORRUPT;
        if ((gh.hGroup == hGroup) || !hGroup)
          goto foundGroup;
        t.Seek(gh.groupSize, SEEK_CUR);
      }
    throw ENOCHUNK;

foundGroup:
    /* The compSize/groupSize range checks, verbatim from LoadGroup
       (src/Registry.cpp:909-920): same ECORRUPT behaviour, same
       CFILE_SANE_MAX_SIZE ceiling. */
    {
        int32 herePos = t.Tell();
        int32 fileEnd;
        t.Seek(0, SEEK_END);
        fileEnd = t.Tell();
        t.Seek(herePos, SEEK_SET);

        if (gh.compSize <= 0 || gh.groupSize <= 0 ||
            gh.compSize > (fileEnd - herePos) ||
            gh.groupSize > CFILE_SANE_MAX_SIZE)
            throw ECORRUPT;
    }

    buf = (uint8*) malloc(gh.groupSize);
    if (!buf)
      throw EMEMORY;

    try
      {
        if (fh.Compression == 0)
          {
            /* Raw payload: exactly groupSize bytes on disk. The adversarial
               suite crafts and loads raw-mode files, so this branch is
               load-bearing, not a debug nicety. */
            if (gh.compSize != gh.groupSize)
              throw ECORRUPT;
            t.FRead(buf, gh.groupSize);
          }
        else if (fh.Compression == 1)
          {
            /* WIRE FORMAT: for IS1.x files, Compression == 1 MEANS zlib
               level 6 -- see the matching note in SaveGroupV1. Bounds: buf
               is groupSize bytes and groupSize passed the
               CFILE_SANE_MAX_SIZE ceiling above, so a crafted header
               cannot drive an unbounded inflate -- uncompress() caps its
               output at dlen; compSize passed the bytes-left-in-file
               check, so cbuf is bounded too. A stream that inflates to
               any size other than groupSize exactly is corruption. */
            Bytef *cbuf = (Bytef*) malloc(gh.compSize);
            if (!cbuf)
              throw EMEMORY;
            uLongf dlen = (uLongf)gh.groupSize;
            int zr;
            try
              {
                t.FRead(cbuf, gh.compSize);
              }
            catch (...)
              { free(cbuf); throw; }
            zr = uncompress((Bytef*)buf, &dlen, cbuf, (uLong)gh.compSize);
            free(cbuf);
            if (zr != Z_OK || dlen != (uLongf)gh.groupSize)
              throw ECORRUPT;
          }
        else
          throw ECORRUPT;

        LastUsedHandle = max(LastUsedHandle, gh.LastHandle);

        /* TWO PASSES, for the same reason v0's LoadGroup ends with a
           whole-group Serialize loop over LoadedObjects
           (src/Registry.cpp:1050-1054): a body's load fixup can look
           another object up by handle -- Thing's `m = oMap(hm)` is the
           one that found this -- and the objects arrive in ObjTable hash
           order, so the referenced object is registered later than the
           referencing one about half the time. Pass 1 constructs and
           registers every object; pass 2 replays every field list against
           a registry that already knows every handle. */
        size_t pos = 0, len = (size_t)gh.groupSize;
        for (i = 0; i != gh.objCount; i++)
          {
            uint8 oType; uint32 handle, recLen;
            if (pos + 9 > len)
              throw ECORRUPT;
            oType = buf[pos];
            memcpy(&handle, buf + pos + 1, 4);
            memcpy(&recLen, buf + pos + 5, 4);
            pos += 9;
            if (recLen > len - pos)
              throw ECORRUPT;

            if (!v1KnownRecordType(oType))
              {
                /* An unknown record type is skipped whole via length --
                   the extensibility rule one level up from unknown tags. */
                pos += recLen;
                continue;
              }

            /* Scanned NOW, in pass 1, so a malformed field stream rejects
               the whole load before any object's fields have landed; kept
               (it points into buf) for pass 2 to replay. */
            V1Ent *ents; int entCount;
            v1ScanFields(buf + pos, recLen, &ents, &entCount);
            if (loadedCount == loadedCap)
              {
                loadedCap = loadedCap ? loadedCap * 2 : 64;
                V1Loaded *nl = (V1Loaded*)
                    realloc(loaded, loadedCap * sizeof(V1Loaded));
                if (!nl)
                  { free(ents); throw EMEMORY; }
                loaded = nl;
              }
            loaded[loadedCount].ents = ents;
            loaded[loadedCount].count = entCount;
            loaded[loadedCount].o = NULL;
            loadedCount++;   /* now, so a throw below still frees ents */

            Object *o;
            if (oType == T_GAME)
              {
                o = theGame;
                memset((void*)o, 0, typeSize(T_GAME));
              }
            else
              {
                o = (Object*) malloc(typeSize(oType));
                if (!o)
                  throw EMEMORY;
                memset((void*)o, 0, typeSize(oType));
              }

            /* The placement-new switch, as LoadGroup's
               (src/Registry.cpp:948-990) -- including the T_COIN/T_STAFF
               behaviour as-is: spec risk 3 says v1 must not fix or be
               blamed for those. */
            switch (oType)
              {
                /* Core game objects */
                case T_GAME:     new(o) Game(this); break;
                case T_MAP:      new(o) Map(this); break;
                case T_MONSTER:  new(o) Monster(this); break;
                case T_PLAYER:   new(o) Player(this); break;
                case T_MODULE:   new(o) Module(this); break;
                /* Features */
                case T_PORTAL:   new(o) Portal(this); break;
                case T_DOOR:     new(o) Door(this); break;
                case T_TRAP:     new(o) Trap(this); break;
                case T_FEATURE:  new(o) Feature(this); break;

                /* Containers */
                case T_CHEST:
                case T_CONTAIN:  new(o) Container(this); break;

                /* Items */
                case T_COIN:     new(o) Coin(this); break;
                case T_FOOD:     new(o) Food(this); break;
                case T_STATUE:
                case T_FIGURE:
                case T_CORPSE:   new(o) Corpse(this); break;
                case T_MISSILE:  case T_BOW:
                case T_WEAPON:   new(o) Weapon(this); break;
                case T_ARMOUR:    case T_SHIELD:
                case T_GAUNTLETS:
                case T_BOOTS:
                                 new(o) Armour(this); break;

                default:
                  if (oType >= T_FIRSTITEM && oType <= T_LASTITEM)
                    new(o) Item(this);
                  else
                    Fatal("Wrong Type right after v1KnownRecordType?!");
              }

            /* v0 got these from the raw bytes; v1's envelope carries them. */
            o->Type = oType;
            o->myHandle = (hObj)handle;

            RegisterObject(o, true);
            loaded[loadedCount - 1].o = o;
            pos += recLen;
          }

        /* Pass 2: every handle is registered; now the field lists replay
           and their load fixups can resolve cross-references. */
        for (i = 0; i != (int32)loadedCount; i++)
          {
            Object *o = loaded[i].o;
            hCurrent = o->myHandle;
            v1PushFrame(loaded[i].ents, loaded[i].count);
            loaded[i].ents = NULL;   /* the frame owns (and frees) it now */
            o->Serialize(*this, false);
            ASSERT(v1FrameDepth == 1);
            v1PopFrame();

            if (o->isCreature())
              ((Creature*)o)->ts.SanitizeLoadedTargets();
          }

        {
          uint32 sep;
          if (pos + 4 > len)
            throw ECORRUPT;
          memcpy(&sep, buf + pos, 4); pos += 4;
          if (sep != SIGNATURE_TWO)
            throw ECORRUPT;
        }

        /* The name table, kept for the deferred SaveV1_ResolveNames(). */
        {
          uint32 entryCount;
          if (pos + 4 > len)
            throw ECORRUPT;
          memcpy(&entryCount, buf + pos, 4); pos += 4;
          if (entryCount > 0x100000)
            throw ECORRUPT;
          if (entryCount)
            {
              v1.names = (V1NameEntry*)
                  calloc(entryCount, sizeof(V1NameEntry));
              if (!v1.names)
                throw EMEMORY;
              v1.nameCap = entryCount;
            }
          for (uint32 e = 0; e != entryCount; e++)
            {
              uint16 ordinal, nameLen;
              if (pos + 6 > len)
                throw ECORRUPT;
              uint8 pool = buf[pos];
              uint8 slot = buf[pos + 1];
              memcpy(&ordinal, buf + pos + 2, 2);
              memcpy(&nameLen, buf + pos + 4, 2);
              pos += 6;
              if (nameLen > len - pos)
                throw ECORRUPT;
              char *nm = (char*) malloc((size_t)nameLen + 1);
              if (!nm)
                throw EMEMORY;
              memcpy(nm, buf + pos, nameLen);
              nm[nameLen] = 0;
              pos += nameLen;
              v1.names[e].pool = pool;
              v1.names[e].slot = slot;
              v1.names[e].ordinal = ordinal;
              v1.names[e].name = nm;
              v1.nameCount = e + 1;
            }
        }

        if (pos != len)
          throw ECORRUPT;   /* trailing bytes: this revision wrote none */
      }
    catch (...)
      {
        for (uint32 li = 0; li != loadedCount; li++)
          free(loaded[li].ents);   /* NULL once pass 2's frame took it */
        free(loaded);
        free(buf);
        throw;
      }
    free(loaded);   /* every ents was consumed (and freed) by pass 2 */
    free(buf);

    /* Resolution is deferred: the modules the names refer to are reloaded
       AFTER the save group in both load paths, so the queues survive this
       return and SaveV1_ResolveNames() consumes them there. */
    guard.committed = true;
    return 0;
  }

/* ------------------------------------------------------------------------ */
/*                        -schematest / -schemaload                         */
/* ------------------------------------------------------------------------ */

/* These live on Registry (statics) because ARCHIVE_CLASS makes Registry a
   friend of every archived class, and the test populates and compares
   protected members directly. */

static long v1TestMismatches;

static void v1Mismatch(int item, const char *field, long a, long b)
  {
    v1TestMismatches++;
    printf("MISMATCH item %d %s: a=%ld b=%ld\n", item, field, a, b);
  }

static void v1MismatchStr(int item, const char *field,
                          const char *a, const char *b)
  {
    if (!a) a = "";
    if (!b) b = "";
    if (!strcmp(a, b))
      return;
    v1TestMismatches++;
    printf("MISMATCH item %d %s: a=\"%s\" b=\"%s\"\n", item, field, a, b);
  }

#define V1CMP(n, fld) do { if ((long)(a->fld) != (long)(b->fld)) \
    v1Mismatch(n, #fld, (long)(a->fld), (long)(b->fld)); } while (0)

static bool v1FilesIdentical(const char *pa, const char *pb, long *outSize)
  {
    FILE *fa = fopen(pa, "rb"), *fb = fopen(pb, "rb");
    bool same = true;
    long size = 0;
    if (!fa || !fb)
      {
        if (fa) fclose(fa);
        if (fb) fclose(fb);
        return false;
      }
    for (;;)
      {
        int ca = fgetc(fa), cb = fgetc(fb);
        if (ca != cb)
          { same = false; break; }
        if (ca == EOF)
          break;
        size++;
      }
    fclose(fa); fclose(fb);
    *outSize = size;
    return same;
  }

bool Registry::V1RunSchemaTest(const char *outDir)
  {
    static const int16 types[4] = { T_RING, T_AMULET, T_POTION, T_SCROLL };
    Item *items[4];
    hObj h[4];
    int i, j;
    bool ok = true;

    v1TestMismatches = 0;
    v1CovFindings = 0;

    /* 1. The modules, the way game start loads them. */
    if (!theGame->LoadModules())
      {
        fprintf(stderr, "incursion -schematest: LoadModules failed\n");
        return false;
      }
    Module *mod = Game::Modules[0];
    if (!mod)
      {
        fprintf(stderr, "incursion -schematest: no module in slot 0\n");
        return false;
      }

    /* Local registries: keeps theGame and everything else in MainRegistry
       OUT of the test group -- their classes have no field lists until
       Tasks 2-6. Heap-allocated because sizeof(Registry) is over a
       megabyte of object table; deliberately leaked, the process exits
       right after this. */
    Registry *regA = new Registry();
    Registry *regB = new Registry();
    Registry *savedReg = theRegistry;

    /* Assignment, not copy-construction: String's implicit copy constructor
       would share the Buffer and double-free it; operator= deep-copies. */
    String pa, pb;
    pa = Format("%s/a.sav", outDir);
    pb = Format("%s/b.sav", outDir);
    fileHeader fh;

    try
      {
        theRegistry = regA;

        /* ---------------------------------------------------------- group 1 --
           items. Four Item instances via the LoadGroup allocation idiom --
           types in the T_FIRSTITEM..T_LASTITEM default branch, so the
           class is exactly Item. */
        for (i = 0; i != 4; i++)
          {
            size_t sz = typeSize((int8)types[i]);
            Item *it = (Item*) malloc(sz);
            if (!it)
              throw EMEMORY;
            memset((void*)it, 0, sz);
            new((Object*)it) Item(regA);
            it->Type = types[i];
            it->myHandle = regA->RegisterObject(it);
            items[i] = it;
            h[i] = it->myHandle;
          }

        /* 3. Every Thing/Item field, distinct and non-zero. hm stays 0:
           a non-zero hm without its Map in the group would turn the load
           fixup (m = oMap(hm)) into an invalid-handle error. */
        for (i = 0; i != 4; i++)
          {
            Item *it = items[i];
            it->Next = h[(i + 1) % 4];
            it->hm = 0;
            it->x = (int16)(11 + i);
            it->y = (int16)(22 + i);
            it->Image = (Glyph)(0x01020300u + (uint32)i);
            it->Timeout = (int16)(100 + i);
            it->StoredMovementTimeout = (int16)(200 + i);
            it->Flags = 0xA5000000u + (uint32)i;
            it->Named = (const char*) Format("Test item %d", i);

            StatiCollection *sc = &it->__Stati;
            sc->Initialize();
            sc->Allocated = 4;
            sc->S = (Status*) malloc(sizeof(Status) * 4);
            sc->Idx = (uint16*) malloc(sizeof(uint16) * LAST_STATI);
            if (!sc->S || !sc->Idx)
              throw EMEMORY;
            memset(sc->S, 0, sizeof(Status) * 4);
            memset(sc->Idx, NO_STATI_ENTRY, sizeof(uint16) * LAST_STATI);
            sc->Last = 2;
            sc->S[0].Nature = 10;
            sc->S[0].Val = (int16)(3 + i);
            sc->S[0].Mag = (int16)(-4 - i);
            sc->S[0].Duration = (int16)(50 + i);
            sc->S[0].Source = 2;
            sc->S[0].CLev = (unsigned)(5 + i) & 0x3F;
            sc->S[0].Dis = i & 1;
            sc->S[0].Once = 1;
            sc->S[0].eID = (int32) mod->EffectID((uint16)(3 + i));
            sc->S[0].h = 0;
            sc->S[1].Nature = (unsigned)(20 + i);
            sc->S[1].Val = (int16)(30 + i);
            sc->S[1].Mag = (int16)(40 + i);
            sc->S[1].Duration = (int16)(-60 - i);
            sc->S[1].Source = 3;
            sc->S[1].CLev = (unsigned)(7 + i) & 0x3F;
            sc->S[1].Dis = (i + 1) & 1;
            sc->S[1].Once = 0;
            sc->S[1].eID = (int32) mod->EffectID((uint16)(8 + i));
            sc->S[1].h = (int32) h[(i + 2) % 4];
            sc->Idx[sc->S[0].Nature] = 0;
            sc->Idx[sc->S[1].Nature] = 1;

            { hObj br = h[(i + 1) % 4]; it->backRefs.Add(br); }
            { hObj br = h[(i + 2) % 4]; it->backRefs.Add(br); }

            it->Known = (uint16)(0x0101 + i);
            it->Plus = (int8)(2 + i);
            it->Charges = (int8)(3 + i);
            it->DmgType = (int8)(4 + i);
            it->GenNum = (int16)(500 + i);
            it->Parent = h[(i + 3) % 4];
            it->homeID = mod->RegionID(1);
            it->Flavor = (int16)(6 + i);
            it->cHP = (int16)(70 + i);
            it->Age = (int16)(80 + i);
            it->swingCount = (uint8)(9 + i);
            it->Quantity = 1000u + (uint32)i;
            it->Inscrip = (const char*) Format("engraved %d", i);
            it->GenStats = (const char*) Format("genstats %d", i);
            it->iID = mod->ItemID((uint16)i);
            it->eID = mod->EffectID((uint16)(3 + i));
            it->IFlags = (uint16)(0x0300 + i);
          }

        /* 4. Save a.sav. The caller writes the complete fileHeader. */
        memset(&fh, 0, sizeof(fh));
        fh.Sig = SIGNATURE;
        strcpy(fh.Version, SaveSchemaID());
        strncpy(fh.Name, "schematest items", 71);
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        T1->OpenWrite(pa);
        T1->FWrite(&fh, sizeof(fh));
        regA->SaveGroupV1(*T1, 0);
        T1->Close();

        /* 5. Load it back into a second, fresh registry, and resolve. */
        theRegistry = regB;
        T1->OpenRead(pa);
        regB->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();

        /* 6. Compare every field by direct accessor. */
        for (i = 0; i != 4; i++)
          {
            Item *a = items[i];
            Item *b = (Item*) regB->Get(h[i]);
            if (!b)
              {
                v1Mismatch(i, "object missing after load", (long)h[i], 0);
                continue;
              }
            V1CMP(i, Type);
            V1CMP(i, myHandle);
            V1CMP(i, Next);
            V1CMP(i, hm);
            if (b->m != NULL)
              v1Mismatch(i, "m (should rebuild to NULL)", 0,
                         (long)(intptr_t)b->m);
            V1CMP(i, x);
            V1CMP(i, y);
            V1CMP(i, Image);
            V1CMP(i, Timeout);
            V1CMP(i, StoredMovementTimeout);
            V1CMP(i, Flags);
            v1MismatchStr(i, "Named", a->Named.GetData(), b->Named.GetData());
            V1CMP(i, __Stati.Last);
            V1CMP(i, __Stati.Allocated);
            V1CMP(i, __Stati.szAdded);
            V1CMP(i, __Stati.Removed);
            V1CMP(i, __Stati.Nested);
            if (b->__Stati.Added != NULL)
              v1Mismatch(i, "__Stati.Added (should be NULL)", 0, 1);
            for (j = 0; j != a->__Stati.Last; j++)
              {
                Status *sa = &a->__Stati.S[j], *sb = &b->__Stati.S[j];
                if (sa->Nature != sb->Nature || sa->Val != sb->Val ||
                    sa->Mag != sb->Mag || sa->Duration != sb->Duration ||
                    sa->Source != sb->Source || sa->CLev != sb->CLev ||
                    sa->Dis != sb->Dis || sa->Once != sb->Once ||
                    sa->eID != sb->eID || sa->h != sb->h)
                  v1Mismatch(i, "__Stati.S[j]", j, j);
              }
            if (memcmp(a->__Stati.Idx, b->__Stati.Idx,
                       sizeof(uint16) * LAST_STATI))
              v1Mismatch(i, "__Stati.Idx", 0, 1);
            V1CMP(i, backRefs.Total());
            for (j = 0; j != a->backRefs.Total() &&
                        j != b->backRefs.Total(); j++)
              if (a->backRefs[j] != b->backRefs[j])
                v1Mismatch(i, "backRefs[j]",
                           (long)a->backRefs[j], (long)b->backRefs[j]);
            V1CMP(i, Known);
            V1CMP(i, Plus);
            V1CMP(i, Charges);
            V1CMP(i, DmgType);
            V1CMP(i, GenNum);
            V1CMP(i, Parent);
            V1CMP(i, homeID);
            V1CMP(i, Flavor);
            V1CMP(i, cHP);
            V1CMP(i, Age);
            V1CMP(i, swingCount);
            V1CMP(i, Quantity);
            v1MismatchStr(i, "Inscrip",
                          a->Inscrip.GetData(), b->Inscrip.GetData());
            v1MismatchStr(i, "GenStats",
                          a->GenStats.GetData(), b->GenStats.GetData());
            V1CMP(i, iID);
            V1CMP(i, eID);
            V1CMP(i, IFlags);
          }

        /* 7. Save b.sav from the second registry; byte-compare. */
        T1->OpenWrite(pb);
        T1->FWrite(&fh, sizeof(fh));
        regB->SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schematest: %s\n",
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }
    theRegistry = savedReg;

    {
      long fsize = 0;
      bool grpOk = true;
      if (v1FilesIdentical((const char*)pa, (const char*)pb, &fsize))
        printf("a.sav and b.sav are byte-identical (%ld bytes)\n", fsize);
      else
        {
          printf("a.sav and b.sav DIFFER\n");
          grpOk = false;
        }
      if (v1TestMismatches)
        {
          printf("%ld field mismatches\n", v1TestMismatches);
          grpOk = false;
        }
      if (v1CovFindings)
        {
          printf("%ld coverage findings\n", v1CovFindings);
          grpOk = false;
        }
      printf("SCHEMATEST GROUP items %s\n", grpOk ? "PASS" : "FAIL");
      ok = ok && grpOk;
    }

    /* ------------------------------------------------------------ group 2 --
       creature. One Monster: the smallest concrete class whose chain reaches
       Creature, so the record exercises Thing's field list and Creature's.
       Monster's own members are not declared until Task 3; the pin table
       carries a pending row that covers them meanwhile. */
    v1TestMismatches = 0;
    v1CovFindings = 0;

    Registry *regC = new Registry();
    Registry *regD = new Registry();
    Monster *mon = NULL;
    hObj mh = 0;
    String pc, pd;
    pc = Format("%s/c.sav", outDir);
    pd = Format("%s/d.sav", outDir);

    try
      {
        theRegistry = regC;

        size_t sz = typeSize((int8)T_MONSTER);
        mon = (Monster*) malloc(sz);
        if (!mon)
          throw EMEMORY;
        memset((void*)mon, 0, sz);
        new((Object*)mon) Monster(regC);
        mon->Type = T_MONSTER;
        mon->myHandle = regC->RegisterObject(mon);
        mh = mon->myHandle;

        /* Thing's own fields, so the chain is exercised end to end. hm stays
           0 for the reason the items group gives. */
        mon->Next = 0;
        mon->hm = 0;
        mon->x = 51;
        mon->y = 52;
        mon->Image = (Glyph)0x0A0B0C0Du;
        mon->Timeout = 53;
        mon->StoredMovementTimeout = 54;
        mon->Flags = 0x5A5A0001u;
        mon->Named = (const char*) Format("Test monster");
        mon->__Stati.Initialize();

        /* Creature's own members, in declaration order, all distinct. */
        mon->mID = mod->MonsterID(1);
        mon->tmID = mod->TemplateID(1);
        mon->PartyID = 61;
        mon->cHP = 62;
        mon->mHP = 63;
        mon->Subdual = 64;
        mon->cFP = 65;
        mon->uMana = 1001;
        mon->mMana = 1002;
        mon->hMana = 1003;
        mon->ManaPulse = 1004;
        mon->concentUsed = 66;
        for (i = 0; i != ATTR_LAST; i++)
          mon->Attr[i] = (int16)(700 + i);
        mon->LastMoveDir = (Dir)5;
        mon->AoO = 67;
        mon->FFCount = 68;
        mon->HideVal = 69;
        mon->StateFlags = 0x0F0F;
        mon->AttrDeath = 70;
        mon->TremorRange = 71;
        mon->SightRange = 72;
        mon->LightRange = 73;
        mon->BlindRange = 74;
        mon->InfraRange = 75;
        mon->PercepRange = 76;
        mon->TelepRange = 77;
        mon->ScentRange = 78;
        mon->ShadowRange = 79;
        mon->NatureSight = 80;

        /* Three live targets, one per arm of Target::data. All three types
           are on SanitizeLoadedTargets's keep list (src/Target.cpp:1549),
           which runs on the v1 load path too (LoadGroupV1 above): a type off
           that list would have its data zeroed after load and the second
           save could not be byte-compared with the first.

           Slot 1 also carries an rID inside TargetWhy's union, which the
           field list moves as raw words -- see the ponytail note in
           TargetSystem::FieldsV1 (src/Target.cpp). */
        mon->ts.tCount = 3;
        mon->ts.shouldRetarget = true;
        mon->ts.t[0].type = TargetEnemy;
        mon->ts.t[0].priority = 81;
        mon->ts.t[0].vis = 1;
        mon->ts.t[0].why.type = TargetHitMe;
        mon->ts.t[0].why.turnOfBirth = 9001;
        mon->ts.t[0].data.Creature.c = mh;
        mon->ts.t[0].data.Creature.damageDoneToMe = 82;
        mon->ts.t[1].type = TargetArea;
        mon->ts.t[1].priority = 83;
        mon->ts.t[1].vis = 0;
        mon->ts.t[1].why.type = TargetSpelledMe;
        mon->ts.t[1].why.turnOfBirth = 9002;
        mon->ts.t[1].why.data.SpelledMe.spellID = mod->EffectID(5);
        mon->ts.t[1].data.Area.x = 84;
        mon->ts.t[1].data.Area.y = 85;
        mon->ts.t[2].type = TargetItem;
        mon->ts.t[2].priority = 86;
        mon->ts.t[2].vis = 1;
        mon->ts.t[2].why.type = TargetGreedy;
        mon->ts.t[2].why.turnOfBirth = 9003;
        mon->ts.t[2].data.Item.i = mh;

        memset(&fh, 0, sizeof(fh));
        fh.Sig = SIGNATURE;
        strcpy(fh.Version, SaveSchemaID());
        strncpy(fh.Name, "schematest creature", 71);
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        T1->OpenWrite(pc);
        T1->FWrite(&fh, sizeof(fh));
        regC->SaveGroupV1(*T1, 0);
        T1->Close();

        theRegistry = regD;
        T1->OpenRead(pc);
        regD->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();

        {
          Monster *a = mon;
          Monster *b = (Monster*) regD->Get(mh);
          if (!b)
            v1Mismatch(0, "monster missing after load", (long)mh, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              V1CMP(0, Next);
              V1CMP(0, hm);
              V1CMP(0, x);
              V1CMP(0, y);
              V1CMP(0, Image);
              V1CMP(0, Timeout);
              V1CMP(0, StoredMovementTimeout);
              V1CMP(0, Flags);
              v1MismatchStr(0, "Named",
                            a->Named.GetData(), b->Named.GetData());
              V1CMP(0, mID);
              V1CMP(0, tmID);
              V1CMP(0, PartyID);
              V1CMP(0, cHP);
              V1CMP(0, mHP);
              V1CMP(0, Subdual);
              V1CMP(0, cFP);
              V1CMP(0, uMana);
              V1CMP(0, mMana);
              V1CMP(0, hMana);
              V1CMP(0, ManaPulse);
              V1CMP(0, concentUsed);
              for (i = 0; i != ATTR_LAST; i++)
                if (a->Attr[i] != b->Attr[i])
                  v1Mismatch(0, "Attr[i]", (long)a->Attr[i], (long)b->Attr[i]);
              V1CMP(0, LastMoveDir);
              V1CMP(0, AoO);
              V1CMP(0, FFCount);
              V1CMP(0, HideVal);
              V1CMP(0, StateFlags);
              V1CMP(0, AttrDeath);
              V1CMP(0, TremorRange);
              V1CMP(0, SightRange);
              V1CMP(0, LightRange);
              V1CMP(0, BlindRange);
              V1CMP(0, InfraRange);
              V1CMP(0, PercepRange);
              V1CMP(0, TelepRange);
              V1CMP(0, ScentRange);
              V1CMP(0, ShadowRange);
              V1CMP(0, NatureSight);
              V1CMP(0, ts.tCount);
              V1CMP(0, ts.shouldRetarget);
              for (i = 0; i != NUM_TARGETS; i++)
                {
                  Target *ta = &a->ts.t[i], *tb = &b->ts.t[i];
                  if (ta->type != tb->type)
                    v1Mismatch(i, "ts.t[].type",
                               (long)ta->type, (long)tb->type);
                  if (ta->priority != tb->priority)
                    v1Mismatch(i, "ts.t[].priority",
                               (long)ta->priority, (long)tb->priority);
                  if (ta->vis != tb->vis)
                    v1Mismatch(i, "ts.t[].vis", (long)ta->vis, (long)tb->vis);
                  if (ta->why.type != tb->why.type)
                    v1Mismatch(i, "ts.t[].why.type",
                               (long)ta->why.type, (long)tb->why.type);
                  if (ta->why.turnOfBirth != tb->why.turnOfBirth)
                    v1Mismatch(i, "ts.t[].why.turnOfBirth",
                               (long)ta->why.turnOfBirth,
                               (long)tb->why.turnOfBirth);
                  if (memcmp(&ta->why.data, &tb->why.data,
                             sizeof(ta->why.data)))
                    v1Mismatch(i, "ts.t[].why.data", i, i);
                  if (memcmp(&ta->data, &tb->data, sizeof(ta->data)))
                    v1Mismatch(i, "ts.t[].data", i, i);
                }
            }
        }

        T1->OpenWrite(pd);
        T1->FWrite(&fh, sizeof(fh));
        regD->SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schematest: %s\n",
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }
    theRegistry = savedReg;

    {
      long fsize = 0;
      bool grpOk = true;
      if (v1FilesIdentical((const char*)pc, (const char*)pd, &fsize))
        printf("c.sav and d.sav are byte-identical (%ld bytes)\n", fsize);
      else
        {
          printf("c.sav and d.sav DIFFER\n");
          grpOk = false;
        }
      if (v1TestMismatches)
        {
          printf("%ld field mismatches\n", v1TestMismatches);
          grpOk = false;
        }
      if (v1CovFindings)
        {
          printf("%ld coverage findings\n", v1CovFindings);
          grpOk = false;
        }
      printf("SCHEMATEST GROUP creature %s\n", grpOk ? "PASS" : "FAIL");
      ok = ok && grpOk;
    }

    /* ------------------------------------------------------------ group 3 --
       character. One Player -- the only concrete class whose chain reaches
       Character, so the record exercises Character's field list and
       Player's -- plus one Monster, whose own four members no other group
       gives a value to. Every rID-bearing member of the two classes is
       filled with a real resource, because those are the renumbering
       victims the whole schema exists for (spec, "Why"). */
    v1TestMismatches = 0;
    v1CovFindings = 0;

    Registry *regE = new Registry();
    Registry *regF = new Registry();
    Player *pl = NULL;
    Monster *mon2 = NULL;
    hObj ph = 0, m2h = 0;
    String pe, pf;
    pe = Format("%s/e.sav", outDir);
    pf = Format("%s/f.sav", outDir);

    try
      {
        theRegistry = regE;

        size_t psz = typeSize((int8)T_PLAYER);
        pl = (Player*) malloc(psz);
        if (!pl)
          throw EMEMORY;
        memset((void*)pl, 0, psz);
        new((Object*)pl) Player(regE);
        pl->Type = T_PLAYER;
        pl->myHandle = regE->RegisterObject(pl);
        ph = pl->myHandle;

        size_t msz = typeSize((int8)T_MONSTER);
        mon2 = (Monster*) malloc(msz);
        if (!mon2)
          throw EMEMORY;
        memset((void*)mon2, 0, msz);
        new((Object*)mon2) Monster(regE);
        mon2->Type = T_MONSTER;
        mon2->myHandle = regE->RegisterObject(mon2);
        m2h = mon2->myHandle;

        /* Thing/Creature slices, so the chain runs end to end. hm stays 0
           for the reason the items group gives. */
        pl->Named = (const char*) Format("Test player");
        pl->__Stati.Initialize();
        pl->x = 91; pl->y = 92;
        pl->mID = mod->MonsterID(2);
        pl->cHP = 93; pl->mHP = 94;
        mon2->Named = (const char*) Format("Test monster two");
        mon2->__Stati.Initialize();
        mon2->x = 95; mon2->y = 96;
        mon2->mID = mod->MonsterID(3);

        /* Monster's own members. */
        mon2->Inv = ph;
        mon2->BuffCount = 11;
        mon2->FoilCount = 12;
        for (i = 0; i != 6; i++)
          mon2->Recent[i] = (uint8)(200 + i);

        /* Character's own members, in declaration order. */
        for (i = 0; i != NUM_SLOTS; i++)
          pl->Inv[i] = (hObj)(i ? 0 : m2h);
        pl->defMelee = m2h; pl->defRanged = ph;
        pl->defAmmo = 0;    pl->defOffhand = m2h;
        for (i = 0; i != 7; i++)
          pl->BAttr[i] = (int16)(10 + i);
        for (i = 0; i != ATTR_LAST; i++)
          pl->KAttr[i] = (int16)(300 + i);
        for (i = 0; i != SK_LASTSKILL; i++)
          pl->SkillRanks[i] = (int8)(i % 20);
        for (i = 0; i != (FT_LAST/8)+1; i++)
          pl->Feats[i] = (uint16)(0x0101u * (uint16)(i + 1));
        for (i = 0; i != CA_LAST; i++)
          pl->Abilities[i] = (uint8)(i % 7);
        for (i = 0; i != 6; i++)
          { pl->SpentSP[i] = (uint16)(i + 1);
            pl->BonusSP[i] = (uint16)(i + 10);
            pl->TotalSP[i] = (uint16)(i + 20); }
        for (i = 0; i != 4; i++)
          { pl->TurnTypes[i] = (uint8)(i + 1);
            pl->TurnLevels[i] = (uint8)(i + 5); }
        for (i = 0; i != 12; i++)
          { pl->FavTypes[i] = (uint8)(i + 2);
            pl->FavLevels[i] = (uint8)(i + 3); }
        for (i = 0; i != STUDY_LAST; i++)
          pl->IntStudy[i] = (uint8)(i + 4);
        pl->FocusWCount = 101; pl->FocusSCount = 102; pl->ExoticCount = 103;
        pl->aStoryPluses = 104; pl->tStoryPluses = 105;
        pl->RageCount = 106; pl->xpTicks = 107;
        pl->Personality = 0xC0FFEE01u; pl->polyTicks = 108;
        pl->alignGE = -109; pl->alignLC = 110;
        pl->LastRest = 111; pl->fracFatigue = 112;
        pl->isFallenPaladin = true;
        pl->Level[0] = 3; pl->Level[1] = 2; pl->Level[2] = 4;
        for (i = 0; i != 3; i++)
          for (j = 0; j != MAX_CHAR_LEVEL; j++)
            { pl->hpRolls[i][j] = (int8)(i * 3 + j);
              pl->manaRolls[i][j] = (int8)(i * 5 + j); }
        for (i = 0; i != 16; i++)
          pl->SaveBonus[i] = (int8)(i - 8);
        for (i = 0; i != 7; i++)
          for (j = 0; j != 15; j++)
            pl->GainAttr[i][j] = (int16)(i * 15 + j);
        pl->NotifiedLevel = 9;
        for (i = 0; i != 6; i++)
          pl->ClassID[i] = mod->ClassID((uint16)(i + 1));
        pl->RaceID = mod->RaceID(2);
        pl->GodID = mod->GodID(1);
        pl->Mount = m2h;
        pl->XP = 123456; pl->XP_Drained = 789;
        for (i = 0; i != 10; i++)
          { pl->SpellsLearned[i] = (uint8)(i + 1);
            pl->SpellSlots[i] = (uint8)(i + 11);
            pl->BonusSlots[i] = (uint8)(i + 21);
            pl->RecentSpells[i] = (uint16)(i + 31); }
        for (i = 0; i != 5; i++)
          { pl->RecentSkills[i] = (uint16)(i + 41);
            pl->RecentItems[i] = (uint16)(i + 51); }
        for (i = 0; i != MAX_SPELLS + 1; i++)
          pl->Spells[i] = (uint16)(i & 0xFF);
        for (i = 0; i != 10; i++)
          pl->Tattoos[i] = mod->EffectID((uint16)(20 + i));
        pl->resChance = 113;
        for (i = 0; i != MAX_GODS; i++)
          { pl->FavourLev[i] = (int16)(i + 1);
            pl->TempFavour[i] = (int32)(1000 + i);
            pl->Anger[i] = (int16)(i + 2);
            pl->FavPenalty[i] = (int16)(i + 3);
            pl->PrayerTimeout[i] = (int16)(i + 4);
            pl->AngerThisTurn[i] = (int16)(i + 5);
            pl->lastPulse[i] = (int32)(2000 + i);
            pl->godFlags[i] = (uint16)(i + 6);
            for (j = 0; j != MAX_SAC_CATS + 2; j++)
              pl->SacVals[i][j] = (int32)(i * 100 + j); }
        pl->desiredAlign = 0xBEEF;
        pl->Proficiencies = 0xDEADBEEFu;

        /* Player's own members, in declaration order. */
        pl->MapMemoryMask = 201;
        pl->GallerySlot = 202;
        pl->MapSP = 3;
        for (i = 0; i != MAX_DUNGEONS; i++)
          pl->MaxDepths[i] = (int16)(i + 1);
        for (i = 0; i != MAX_SPELLS; i++)
          pl->MMArray[i] = (uint32)(i * 3u);
        for (i = 0; i != MAX_MACROS; i++)
          pl->Macros[i] = mod->EffectID((uint16)(40 + i));
        for (i = 0; i != MAX_QKEYS; i++)
          { pl->QuickKeys[i].Value = (uint32)(i + 300);
            pl->QuickKeys[i].Type = (int16)(i % 4);
            pl->QuickKeys[i].hItem = (hObj)(i & 1 ? ph : m2h);
            pl->QuickKeys[i].MM = (uint32)(i * 7u); }
        for (i = 0; i != 8; i++)
          pl->MessageQueue[i] = (const char*) Format("message %d", (int)i);
        /* 63 entries and a terminator, not 64 entries: the load rules
           require a zero somewhere in AutoBuffs, because every walk of it
           stops only on one. */
        for (i = 0; i != 63; i++)
          pl->AutoBuffs[i] = (int16)(i + 1);
        pl->AutoBuffs[63] = 0;
        pl->cAutoBuff = 7;
        pl->GraveText = "Here lies a test player.";
        pl->HungerShown = 203;
        pl->Journal = "Day one: the schema test began.";
        pl->JournalInfo.bestMonster = "Balrog";
        pl->JournalInfo.bestMonsterVal = 204;
        pl->JournalInfo.bestItem = "Vorpal Blade";
        pl->JournalInfo.bestItemVal = 205;
        pl->JournalInfo.numMonSeen = 206;
        for (i = 0; i != MA_LAST_REAL; i++)
          pl->JournalInfo.numMonOfType[i] = (int)(i + 1);
        /* Real YuseCommands indexes, plus the -1 "empty" sentinel in one
           slot: the load rules accept those two shapes and nothing else. */
        for (i = 0; i != 5; i++)
          pl->RecentVerbs[i] = (int16)(i == 2 ? -1 : i);
        for (i = 0; i != 11; i++)   /* LTI[11], inc/Creature.h */
          { pl->GameTimeInfo.LTI[i].turns = (uint32)(i + 1);
            pl->GameTimeInfo.LTI[i].actions = (uint32)(i + 2);
            pl->GameTimeInfo.LTI[i].keystrokes = (uint32)(i + 3);
            pl->GameTimeInfo.LTI[i].seconds = (time_t)(1700000000 + i);
            pl->GameTimeInfo.LTI[i].xp = (int32)(i + 4); }
        pl->GameTimeInfo.start_turn = 301;
        pl->GameTimeInfo.actions = 302;
        pl->GameTimeInfo.keystrokes = 303;
        pl->GameTimeInfo.start_second = (time_t)1700000999;
        pl->GameTimeInfo.start_xp = 304;
        pl->statiChanged = true;
        pl->formulaSeed = 401; pl->storeSeed = 402;
        for (i = 0; i != 12; i++)
          pl->SpellKeys[i] = (int16)(i + 71);
        for (i = 0; i != OPT_LAST; i++)
          pl->Options[i] = (int8)(i % 5);
        pl->shownFF = true;
        pl->VictoryFlag = false; pl->QuitFlag = true;
        pl->UpdateMap = true;    pl->DigMode = false;
        pl->WizardMode = true;   pl->ExploreMode = false;
        pl->rerolledPerks = true;
        pl->deathCount = 403; pl->rerollCount = 404;
        pl->statMethod = 405;

        memset(&fh, 0, sizeof(fh));
        fh.Sig = SIGNATURE;
        strcpy(fh.Version, SaveSchemaID());
        strncpy(fh.Name, "schematest character", 71);
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        T1->OpenWrite(pe);
        T1->FWrite(&fh, sizeof(fh));
        regE->SaveGroupV1(*T1, 0);
        T1->Close();

        theRegistry = regF;
        T1->OpenRead(pe);
        regF->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();

        {
          Player *a = pl;
          Player *b = (Player*) regF->Get(ph);
          if (!b)
            v1Mismatch(0, "player missing after load", (long)ph, 0);
          else
            {
              /* Character's own members. */
              for (i = 0; i != NUM_SLOTS; i++)
                if (a->Inv[i] != b->Inv[i])
                  v1Mismatch(i, "Inv[i]", (long)a->Inv[i], (long)b->Inv[i]);
              V1CMP(0, defMelee);   V1CMP(0, defRanged);
              V1CMP(0, defAmmo);    V1CMP(0, defOffhand);
              for (i = 0; i != 7; i++)
                if (a->BAttr[i] != b->BAttr[i])
                  v1Mismatch(i, "BAttr[i]", (long)a->BAttr[i],
                             (long)b->BAttr[i]);
              for (i = 0; i != ATTR_LAST; i++)
                if (a->KAttr[i] != b->KAttr[i])
                  v1Mismatch(i, "KAttr[i]", (long)a->KAttr[i],
                             (long)b->KAttr[i]);
              if (memcmp(a->SkillRanks, b->SkillRanks, sizeof(a->SkillRanks)))
                v1Mismatch(0, "SkillRanks", 0, 1);
              if (memcmp(a->Feats, b->Feats, sizeof(a->Feats)))
                v1Mismatch(0, "Feats", 0, 1);
              if (memcmp(a->Abilities, b->Abilities, sizeof(a->Abilities)))
                v1Mismatch(0, "Abilities", 0, 1);
              if (memcmp(a->SpentSP, b->SpentSP, sizeof(a->SpentSP)) ||
                  memcmp(a->BonusSP, b->BonusSP, sizeof(a->BonusSP)) ||
                  memcmp(a->TotalSP, b->TotalSP, sizeof(a->TotalSP)))
                v1Mismatch(0, "SP arrays", 0, 1);
              if (memcmp(a->TurnTypes, b->TurnTypes, sizeof(a->TurnTypes)) ||
                  memcmp(a->TurnLevels, b->TurnLevels, sizeof(a->TurnLevels)) ||
                  memcmp(a->FavTypes, b->FavTypes, sizeof(a->FavTypes)) ||
                  memcmp(a->FavLevels, b->FavLevels, sizeof(a->FavLevels)) ||
                  memcmp(a->IntStudy, b->IntStudy, sizeof(a->IntStudy)))
                v1Mismatch(0, "turn/fav/study arrays", 0, 1);
              V1CMP(0, FocusWCount); V1CMP(0, FocusSCount);
              V1CMP(0, ExoticCount); V1CMP(0, aStoryPluses);
              V1CMP(0, tStoryPluses); V1CMP(0, RageCount);
              V1CMP(0, xpTicks);     V1CMP(0, Personality);
              V1CMP(0, polyTicks);   V1CMP(0, alignGE);
              V1CMP(0, alignLC);     V1CMP(0, LastRest);
              V1CMP(0, fracFatigue); V1CMP(0, isFallenPaladin);
              if (memcmp(a->Level, b->Level, sizeof(a->Level)) ||
                  memcmp(a->hpRolls, b->hpRolls, sizeof(a->hpRolls)) ||
                  memcmp(a->manaRolls, b->manaRolls, sizeof(a->manaRolls)) ||
                  memcmp(a->SaveBonus, b->SaveBonus, sizeof(a->SaveBonus)) ||
                  memcmp(a->GainAttr, b->GainAttr, sizeof(a->GainAttr)))
                v1Mismatch(0, "level/roll arrays", 0, 1);
              V1CMP(0, NotifiedLevel);
              for (i = 0; i != 6; i++)
                if (a->ClassID[i] != b->ClassID[i])
                  v1Mismatch(i, "ClassID[i]", (long)a->ClassID[i],
                             (long)b->ClassID[i]);
              V1CMP(0, RaceID); V1CMP(0, GodID); V1CMP(0, Mount);
              V1CMP(0, XP);     V1CMP(0, XP_Drained);
              if (memcmp(a->SpellsLearned, b->SpellsLearned,
                         sizeof(a->SpellsLearned)) ||
                  memcmp(a->SpellSlots, b->SpellSlots,
                         sizeof(a->SpellSlots)) ||
                  memcmp(a->BonusSlots, b->BonusSlots,
                         sizeof(a->BonusSlots)) ||
                  memcmp(a->RecentSpells, b->RecentSpells,
                         sizeof(a->RecentSpells)) ||
                  memcmp(a->RecentSkills, b->RecentSkills,
                         sizeof(a->RecentSkills)) ||
                  memcmp(a->RecentItems, b->RecentItems,
                         sizeof(a->RecentItems)) ||
                  memcmp(a->Spells, b->Spells, sizeof(a->Spells)))
                v1Mismatch(0, "spell/recent arrays", 0, 1);
              for (i = 0; i != 10; i++)
                if (a->Tattoos[i] != b->Tattoos[i])
                  v1Mismatch(i, "Tattoos[i]", (long)a->Tattoos[i],
                             (long)b->Tattoos[i]);
              V1CMP(0, resChance);
              if (memcmp(a->FavourLev, b->FavourLev, sizeof(a->FavourLev)) ||
                  memcmp(a->TempFavour, b->TempFavour,
                         sizeof(a->TempFavour)) ||
                  memcmp(a->Anger, b->Anger, sizeof(a->Anger)) ||
                  memcmp(a->SacVals, b->SacVals, sizeof(a->SacVals)) ||
                  memcmp(a->FavPenalty, b->FavPenalty,
                         sizeof(a->FavPenalty)) ||
                  memcmp(a->PrayerTimeout, b->PrayerTimeout,
                         sizeof(a->PrayerTimeout)) ||
                  memcmp(a->AngerThisTurn, b->AngerThisTurn,
                         sizeof(a->AngerThisTurn)) ||
                  memcmp(a->lastPulse, b->lastPulse, sizeof(a->lastPulse)) ||
                  memcmp(a->godFlags, b->godFlags, sizeof(a->godFlags)))
                v1Mismatch(0, "religion arrays", 0, 1);
              V1CMP(0, desiredAlign); V1CMP(0, Proficiencies);

              /* Player's own members. */
              V1CMP(0, MapMemoryMask); V1CMP(0, GallerySlot); V1CMP(0, MapSP);
              if (memcmp(a->MaxDepths, b->MaxDepths, sizeof(a->MaxDepths)) ||
                  memcmp(a->MMArray, b->MMArray, sizeof(a->MMArray)))
                v1Mismatch(0, "MaxDepths/MMArray", 0, 1);
              for (i = 0; i != MAX_MACROS; i++)
                if (a->Macros[i] != b->Macros[i])
                  v1Mismatch(i, "Macros[i]", (long)a->Macros[i],
                             (long)b->Macros[i]);
              for (i = 0; i != MAX_QKEYS; i++)
                if (a->QuickKeys[i].Value != b->QuickKeys[i].Value ||
                    a->QuickKeys[i].Type  != b->QuickKeys[i].Type  ||
                    a->QuickKeys[i].hItem != b->QuickKeys[i].hItem ||
                    a->QuickKeys[i].MM    != b->QuickKeys[i].MM)
                  v1Mismatch(i, "QuickKeys[i]", (long)a->QuickKeys[i].Value,
                             (long)b->QuickKeys[i].Value);
              for (i = 0; i != 8; i++)
                v1MismatchStr(i, "MessageQueue[i]",
                              a->MessageQueue[i].GetData(),
                              b->MessageQueue[i].GetData());
              if (memcmp(a->AutoBuffs, b->AutoBuffs, sizeof(a->AutoBuffs)))
                v1Mismatch(0, "AutoBuffs", 0, 1);
              V1CMP(0, cAutoBuff);
              v1MismatchStr(0, "GraveText", a->GraveText.GetData(),
                            b->GraveText.GetData());
              V1CMP(0, HungerShown);
              v1MismatchStr(0, "Journal", a->Journal.GetData(),
                            b->Journal.GetData());
              v1MismatchStr(0, "JournalInfo.bestMonster",
                            a->JournalInfo.bestMonster.GetData(),
                            b->JournalInfo.bestMonster.GetData());
              v1MismatchStr(0, "JournalInfo.bestItem",
                            a->JournalInfo.bestItem.GetData(),
                            b->JournalInfo.bestItem.GetData());
              V1CMP(0, JournalInfo.bestMonsterVal);
              V1CMP(0, JournalInfo.bestItemVal);
              V1CMP(0, JournalInfo.numMonSeen);
              if (memcmp(a->JournalInfo.numMonOfType,
                         b->JournalInfo.numMonOfType,
                         sizeof(a->JournalInfo.numMonOfType)))
                v1Mismatch(0, "JournalInfo.numMonOfType", 0, 1);
              if (memcmp(a->RecentVerbs, b->RecentVerbs,
                         sizeof(a->RecentVerbs)))
                v1Mismatch(0, "RecentVerbs", 0, 1);
              if (memcmp(a->GameTimeInfo.LTI, b->GameTimeInfo.LTI,
                         sizeof(a->GameTimeInfo.LTI)))
                v1Mismatch(0, "GameTimeInfo.LTI", 0, 1);
              V1CMP(0, GameTimeInfo.start_turn);
              V1CMP(0, GameTimeInfo.actions);
              V1CMP(0, GameTimeInfo.keystrokes);
              V1CMP(0, GameTimeInfo.start_second);
              V1CMP(0, GameTimeInfo.start_xp);
              V1CMP(0, statiChanged);
              V1CMP(0, formulaSeed); V1CMP(0, storeSeed);
              if (memcmp(a->SpellKeys, b->SpellKeys, sizeof(a->SpellKeys)) ||
                  memcmp(a->Options, b->Options, sizeof(a->Options)))
                v1Mismatch(0, "SpellKeys/Options", 0, 1);
              if (b->MyTerm != T1)
                v1Mismatch(0, "MyTerm (should rebuild to T1)", 0, 1);
              V1CMP(0, shownFF);    V1CMP(0, VictoryFlag);
              V1CMP(0, QuitFlag);   V1CMP(0, UpdateMap);
              V1CMP(0, DigMode);    V1CMP(0, WizardMode);
              V1CMP(0, ExploreMode); V1CMP(0, rerolledPerks);
              V1CMP(0, deathCount); V1CMP(0, rerollCount);
              V1CMP(0, statMethod);
            }

          Monster *ma = mon2;
          Monster *mb = (Monster*) regF->Get(m2h);
          if (!mb)
            v1Mismatch(0, "monster two missing after load", (long)m2h, 0);
          else
            {
              Monster *a = ma, *b = mb;
              V1CMP(0, Inv);
              V1CMP(0, BuffCount);
              V1CMP(0, FoilCount);
              if (memcmp(a->Recent, b->Recent, sizeof(a->Recent)))
                v1Mismatch(0, "Recent", 0, 1);
            }
        }

        T1->OpenWrite(pf);
        T1->FWrite(&fh, sizeof(fh));
        regF->SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schematest: %s\n",
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }
    theRegistry = savedReg;

    {
      long fsize = 0;
      bool grpOk = true;
      if (v1FilesIdentical((const char*)pe, (const char*)pf, &fsize))
        printf("e.sav and f.sav are byte-identical (%ld bytes)\n", fsize);
      else
        {
          printf("e.sav and f.sav DIFFER\n");
          grpOk = false;
        }
      if (v1TestMismatches)
        {
          printf("%ld field mismatches\n", v1TestMismatches);
          grpOk = false;
        }
      if (v1CovFindings)
        {
          printf("%ld coverage findings\n", v1CovFindings);
          grpOk = false;
        }
      printf("SCHEMATEST GROUP character %s\n", grpOk ? "PASS" : "FAIL");
      ok = ok && grpOk;
    }

    /* ------------------------------------------------------------ group 4 --
       feature. One of each of Feature, Door, Trap and Portal -- the four
       concrete classes in the chain Object -> Thing -> Feature ->
       {Door, Trap, Portal} -- built through the LoadGroup allocation idiom,
       each with its own field list's members set to distinct, non-zero
       values and fID/tID pointing at real module resources. */
    v1TestMismatches = 0;
    v1CovFindings = 0;

    Registry *regG = new Registry();
    Registry *regH = new Registry();
    Feature *feat = NULL;
    Door *door = NULL;
    Trap *trap = NULL;
    Portal *portal = NULL;
    hObj hFeat = 0, hDoor = 0, hTrap = 0, hPortal = 0;
    String pgSav, phSav;
    pgSav = Format("%s/g.sav", outDir);
    phSav = Format("%s/h.sav", outDir);

    try
      {
        theRegistry = regG;

        size_t featSz = typeSize((int8)T_FEATURE);
        feat = (Feature*) malloc(featSz);
        if (!feat)
          throw EMEMORY;
        memset((void*)feat, 0, featSz);
        new((Object*)feat) Feature(regG);
        feat->Type = T_FEATURE;
        feat->myHandle = regG->RegisterObject(feat);
        hFeat = feat->myHandle;

        size_t doorSz = typeSize((int8)T_DOOR);
        door = (Door*) malloc(doorSz);
        if (!door)
          throw EMEMORY;
        memset((void*)door, 0, doorSz);
        new((Object*)door) Door(regG);
        door->Type = T_DOOR;
        door->myHandle = regG->RegisterObject(door);
        hDoor = door->myHandle;

        size_t trapSz = typeSize((int8)T_TRAP);
        trap = (Trap*) malloc(trapSz);
        if (!trap)
          throw EMEMORY;
        memset((void*)trap, 0, trapSz);
        new((Object*)trap) Trap(regG);
        trap->Type = T_TRAP;
        trap->myHandle = regG->RegisterObject(trap);
        hTrap = trap->myHandle;

        size_t portalSz = typeSize((int8)T_PORTAL);
        portal = (Portal*) malloc(portalSz);
        if (!portal)
          throw EMEMORY;
        memset((void*)portal, 0, portalSz);
        new((Object*)portal) Portal(regG);
        portal->Type = T_PORTAL;
        portal->myHandle = regG->RegisterObject(portal);
        hPortal = portal->myHandle;

        /* Feature's own members, distinct per object. */
        feat->cHP = 301; feat->mHP = 302;
        feat->fID = mod->FeatureID(1);
        feat->MoveMod = 3;

        door->cHP = 311; door->mHP = 312;
        door->fID = mod->FeatureID(2);
        door->MoveMod = -4;
        door->DoorFlags = 0x15;
        door->SecretSavedGlyph = (Glyph)0x0B0C0D0Eu;

        trap->cHP = 321; trap->mHP = 322;
        trap->fID = mod->FeatureID(3);
        trap->MoveMod = 5;
        trap->TrapFlags = 0x2A;
        trap->tID = mod->EffectID(12);

        portal->cHP = 331; portal->mHP = 332;
        portal->fID = mod->FeatureID(4);
        portal->MoveMod = -6;

        memset(&fh, 0, sizeof(fh));
        fh.Sig = SIGNATURE;
        strcpy(fh.Version, SaveSchemaID());
        strncpy(fh.Name, "schematest feature", 71);
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        T1->OpenWrite(pgSav);
        T1->FWrite(&fh, sizeof(fh));
        regG->SaveGroupV1(*T1, 0);
        T1->Close();

        theRegistry = regH;
        T1->OpenRead(pgSav);
        regH->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();

        {
          Feature *a = feat;
          Feature *b = (Feature*) regH->Get(hFeat);
          if (!b)
            v1Mismatch(0, "feature missing after load", (long)hFeat, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              V1CMP(0, cHP);
              V1CMP(0, mHP);
              V1CMP(0, fID);
              V1CMP(0, MoveMod);
            }
        }
        {
          Door *a = door;
          Door *b = (Door*) regH->Get(hDoor);
          if (!b)
            v1Mismatch(0, "door missing after load", (long)hDoor, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              V1CMP(0, cHP);
              V1CMP(0, mHP);
              V1CMP(0, fID);
              V1CMP(0, MoveMod);
              V1CMP(0, DoorFlags);
              V1CMP(0, SecretSavedGlyph);
            }
        }
        {
          Trap *a = trap;
          Trap *b = (Trap*) regH->Get(hTrap);
          if (!b)
            v1Mismatch(0, "trap missing after load", (long)hTrap, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              V1CMP(0, cHP);
              V1CMP(0, mHP);
              V1CMP(0, fID);
              V1CMP(0, MoveMod);
              V1CMP(0, TrapFlags);
              V1CMP(0, tID);
            }
        }
        {
          Portal *a = portal;
          Portal *b = (Portal*) regH->Get(hPortal);
          if (!b)
            v1Mismatch(0, "portal missing after load", (long)hPortal, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              V1CMP(0, cHP);
              V1CMP(0, mHP);
              V1CMP(0, fID);
              V1CMP(0, MoveMod);
            }
        }

        T1->OpenWrite(phSav);
        T1->FWrite(&fh, sizeof(fh));
        regH->SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schematest: %s\n",
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }
    theRegistry = savedReg;

    {
      long fsize = 0;
      bool grpOk = true;
      if (v1FilesIdentical((const char*)pgSav, (const char*)phSav, &fsize))
        printf("g.sav and h.sav are byte-identical (%ld bytes)\n", fsize);
      else
        {
          printf("g.sav and h.sav DIFFER\n");
          grpOk = false;
        }
      if (v1TestMismatches)
        {
          printf("%ld field mismatches\n", v1TestMismatches);
          grpOk = false;
        }
      if (v1CovFindings)
        {
          printf("%ld coverage findings\n", v1CovFindings);
          grpOk = false;
        }
      printf("SCHEMATEST GROUP feature %s\n", grpOk ? "PASS" : "FAIL");
      ok = ok && grpOk;
    }

    /* ------------------------------------------------------------ group 5 --
       items2. One each of Food, Corpse, Container, Weapon, Coin and Armour
       -- the six concrete classes below Item whose own field lists this
       task declares, built through the LoadGroup allocation idiom. QItem
       itself is never the most-derived class of any constructed object: no
       T_* type placement-news a bare QItem (T_SCROLL, the brief's
       contingency, maps to plain Item -- already exercised in group 1), so
       QItem's own members (Qualities, KnownQualities) are exercised through
       Food, Container, Weapon and Armour, all of which extend it directly.
       Coin extends Item, not QItem, and declares no own members. Corpse::mID
       is a real module Monster rID.

       Plus one Container built as T_CONTAIN and one Weapon built as T_BOW --
       ALIASES of the T_CHEST/T_WEAPON types above that the placement-new
       switch maps to the SAME classes (src/Registry.cpp:941-983,
       src/SaveV1.cpp's LoadGroupV1). Real modules use these aliases: the
       shipping module declares backpacks/scroll cases/quivers T_CONTAIN
       (lib/mundane.irh) and bows/arrows T_BOW (lib/weapons.irh). Before the
       v1PinClassForType fix, a real T_CONTAIN/T_BOW object's ObjectSize()
       still matched the Container/Weapon row's pinned size, but the row
       selector keyed on the single (size, T_CHEST)/(size, T_WEAPON) pair
       those rows carried, so the alias missed the exact match and fell
       through to whichever 232-byte row was first in the table -- QItem's
       -- and that row's own pinned pad (227, 5) collided with the real
       object's FIELD_H(112, Contents) or FIELD_I16(128, Bane) coverage,
       firing a false fatal "pinned pad is covered by a field". These two
       objects reproduce that: RED on the pre-fix selector, GREEN after. */
    v1TestMismatches = 0;
    v1CovFindings = 0;

    Registry *regI = new Registry();
    Registry *regJ = new Registry();
    Food *food = NULL;
    Corpse *corpse = NULL;
    Container *contain = NULL;
    Container *contain2 = NULL;
    Weapon *weapon = NULL;
    Weapon *weapon2 = NULL;
    Coin *coin = NULL;
    Armour *armour = NULL;
    hObj hFood = 0, hCorpse = 0, hContain = 0, hContain2 = 0, hWeapon = 0,
         hWeapon2 = 0, hCoin = 0, hArmour = 0;
    String piSav, pjSav;
    piSav = Format("%s/i.sav", outDir);
    pjSav = Format("%s/j.sav", outDir);

    try
      {
        theRegistry = regI;

        size_t foodSz = typeSize((int8)T_FOOD);
        food = (Food*) malloc(foodSz);
        if (!food)
          throw EMEMORY;
        memset((void*)food, 0, foodSz);
        new((Object*)food) Food(regI);
        food->Type = T_FOOD;
        food->myHandle = regI->RegisterObject(food);
        hFood = food->myHandle;

        size_t corpseSz = typeSize((int8)T_CORPSE);
        corpse = (Corpse*) malloc(corpseSz);
        if (!corpse)
          throw EMEMORY;
        memset((void*)corpse, 0, corpseSz);
        new((Object*)corpse) Corpse(regI);
        corpse->Type = T_CORPSE;
        corpse->myHandle = regI->RegisterObject(corpse);
        hCorpse = corpse->myHandle;

        size_t containSz = typeSize((int8)T_CHEST);
        contain = (Container*) malloc(containSz);
        if (!contain)
          throw EMEMORY;
        memset((void*)contain, 0, containSz);
        new((Object*)contain) Container(regI);
        contain->Type = T_CHEST;
        contain->myHandle = regI->RegisterObject(contain);
        hContain = contain->myHandle;

        size_t weaponSz = typeSize((int8)T_WEAPON);
        weapon = (Weapon*) malloc(weaponSz);
        if (!weapon)
          throw EMEMORY;
        memset((void*)weapon, 0, weaponSz);
        new((Object*)weapon) Weapon(regI);
        weapon->Type = T_WEAPON;
        weapon->myHandle = regI->RegisterObject(weapon);
        hWeapon = weapon->myHandle;

        /* T_CONTAIN alias of Container -- see the group comment above. */
        size_t contain2Sz = typeSize((int8)T_CONTAIN);
        contain2 = (Container*) malloc(contain2Sz);
        if (!contain2)
          throw EMEMORY;
        memset((void*)contain2, 0, contain2Sz);
        new((Object*)contain2) Container(regI);
        contain2->Type = T_CONTAIN;
        contain2->myHandle = regI->RegisterObject(contain2);
        hContain2 = contain2->myHandle;

        /* T_BOW alias of Weapon -- see the group comment above. */
        size_t weapon2Sz = typeSize((int8)T_BOW);
        weapon2 = (Weapon*) malloc(weapon2Sz);
        if (!weapon2)
          throw EMEMORY;
        memset((void*)weapon2, 0, weapon2Sz);
        new((Object*)weapon2) Weapon(regI);
        weapon2->Type = T_BOW;
        weapon2->myHandle = regI->RegisterObject(weapon2);
        hWeapon2 = weapon2->myHandle;

        size_t coinSz = typeSize((int8)T_COIN);
        coin = (Coin*) malloc(coinSz);
        if (!coin)
          throw EMEMORY;
        memset((void*)coin, 0, coinSz);
        new((Object*)coin) Coin(regI);
        coin->Type = T_COIN;
        coin->myHandle = regI->RegisterObject(coin);
        hCoin = coin->myHandle;

        size_t armourSz = typeSize((int8)T_ARMOUR);
        armour = (Armour*) malloc(armourSz);
        if (!armour)
          throw EMEMORY;
        memset((void*)armour, 0, armourSz);
        new((Object*)armour) Armour(regI);
        armour->Type = T_ARMOUR;
        armour->myHandle = regI->RegisterObject(armour);
        hArmour = armour->myHandle;

        /* QItem's own members, distinct per object, on every QItem
           descendant. Coin has none: it extends Item, not QItem. */
        for (i = 0; i != 8; i++)
          {
            food->Qualities[i]     = (int8)(1 + i);
            corpse->Qualities[i]   = (int8)(11 + i);
            contain->Qualities[i]  = (int8)(21 + i);
            weapon->Qualities[i]   = (int8)(31 + i);
            armour->Qualities[i]   = (int8)(41 + i);
            contain2->Qualities[i] = (int8)(51 + i);
            weapon2->Qualities[i]  = (int8)(61 + i);
          }
        food->KnownQualities     = 0xA5;
        corpse->KnownQualities   = 0xB6;
        contain->KnownQualities  = 0xC7;
        weapon->KnownQualities   = 0xD8;
        armour->KnownQualities   = 0xE9;
        contain2->KnownQualities = 0xFA;
        weapon2->KnownQualities  = 0x6C;

        /* Food's own member. Corpse inherits it and gets its own value. */
        food->Eaten = 501;
        corpse->Eaten = 502;

        /* Corpse's own members: mID is a real module Monster rID. */
        corpse->mID = mod->MonsterID(1);
        corpse->TurnCreated = 60606u;
        corpse->LastDiseaseDCCheck = -7;

        /* Container's own member: a handle to another object in this
           group, so FIELD_H moves a real, resolvable value. */
        contain->Contents = hFood;
        contain2->Contents = hCorpse;

        /* Weapon's own member. */
        weapon->Bane = -333;
        weapon2->Bane = -444;

        memset(&fh, 0, sizeof(fh));
        fh.Sig = SIGNATURE;
        strcpy(fh.Version, SaveSchemaID());
        strncpy(fh.Name, "schematest items2", 71);
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        T1->OpenWrite(piSav);
        T1->FWrite(&fh, sizeof(fh));
        regI->SaveGroupV1(*T1, 0);
        T1->Close();

        theRegistry = regJ;
        T1->OpenRead(piSav);
        regJ->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();

        {
          Food *a = food;
          Food *b = (Food*) regJ->Get(hFood);
          if (!b)
            v1Mismatch(0, "food missing after load", (long)hFood, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Food.Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Eaten);
            }
        }
        {
          Corpse *a = corpse;
          Corpse *b = (Corpse*) regJ->Get(hCorpse);
          if (!b)
            v1Mismatch(0, "corpse missing after load", (long)hCorpse, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Corpse.Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Eaten);
              V1CMP(0, mID);
              V1CMP(0, TurnCreated);
              V1CMP(0, LastDiseaseDCCheck);
            }
        }
        {
          Container *a = contain;
          Container *b = (Container*) regJ->Get(hContain);
          if (!b)
            v1Mismatch(0, "container missing after load", (long)hContain, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Container.Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Contents);
            }
        }
        {
          Weapon *a = weapon;
          Weapon *b = (Weapon*) regJ->Get(hWeapon);
          if (!b)
            v1Mismatch(0, "weapon missing after load", (long)hWeapon, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Weapon.Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Bane);
            }
        }
        {
          Container *a = contain2;
          Container *b = (Container*) regJ->Get(hContain2);
          if (!b)
            v1Mismatch(0, "T_CONTAIN container missing after load",
                       (long)hContain2, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Container(T_CONTAIN).Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Contents);
            }
        }
        {
          Weapon *a = weapon2;
          Weapon *b = (Weapon*) regJ->Get(hWeapon2);
          if (!b)
            v1Mismatch(0, "T_BOW weapon missing after load",
                       (long)hWeapon2, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Weapon(T_BOW).Qualities", 0, 1);
              V1CMP(0, KnownQualities);
              V1CMP(0, Bane);
            }
        }
        {
          Coin *a = coin;
          Coin *b = (Coin*) regJ->Get(hCoin);
          if (!b)
            v1Mismatch(0, "coin missing after load", (long)hCoin, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
            }
        }
        {
          Armour *a = armour;
          Armour *b = (Armour*) regJ->Get(hArmour);
          if (!b)
            v1Mismatch(0, "armour missing after load", (long)hArmour, 0);
          else
            {
              V1CMP(0, Type);
              V1CMP(0, myHandle);
              if (memcmp(a->Qualities, b->Qualities, sizeof(a->Qualities)))
                v1Mismatch(0, "Armour.Qualities", 0, 1);
              V1CMP(0, KnownQualities);
            }
        }

        T1->OpenWrite(pjSav);
        T1->FWrite(&fh, sizeof(fh));
        regJ->SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schematest: %s\n",
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }
    theRegistry = savedReg;

    {
      long fsize = 0;
      bool grpOk = true;
      if (v1FilesIdentical((const char*)piSav, (const char*)pjSav, &fsize))
        printf("i.sav and j.sav are byte-identical (%ld bytes)\n", fsize);
      else
        {
          printf("i.sav and j.sav DIFFER\n");
          grpOk = false;
        }
      if (v1TestMismatches)
        {
          printf("%ld field mismatches\n", v1TestMismatches);
          grpOk = false;
        }
      if (v1CovFindings)
        {
          printf("%ld coverage findings\n", v1CovFindings);
          grpOk = false;
        }
      printf("SCHEMATEST GROUP items2 %s\n", grpOk ? "PASS" : "FAIL");
      ok = ok && grpOk;
    }

    if (ok)
      printf("SCHEMATEST PASS\n");
    return ok;
  }

bool Registry::V1RunSchemaLoad(const char *path)
  {
    int32 i, j;

    if (!T1->Exists(path))
      {
        fprintf(stderr, "incursion -schemaload: no such file: %s\n", path);
        return false;
      }
    if (!theGame->LoadModules())
      {
        fprintf(stderr, "incursion -schemaload: LoadModules failed\n");
        return false;
      }

    Registry *reg = new Registry();   /* deliberately leaked; see above */
    Registry *savedReg = theRegistry;
    theRegistry = reg;

    try
      {
        T1->OpenRead(path);
        reg->LoadGroup(*T1, 0, false);
        T1->Close();
        SaveV1_ResolveNames();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -schemaload: %s: %s\n", path,
                Lookup(FileErrors, error_number));
        theRegistry = savedReg;
        return false;
      }

    /* One line per declared field of every loaded object, labeled by the
       class that DECLARES the member -- tools/check_v1_adversarial.sh greps
       these. Table order is record order: handles ascend through the
       buckets the same way SaveGroupV1 walked them. */
    for (i = 0; i != OBJ_TABLE_SIZE; i++)
      for (RegNode *r = &reg->ObjTable[i]; r; r = r->Next)
        {
          if (!r->pObj)
            continue;
          Object *o = r->pObj;
          printf("record type=%d handle=%d\n", (int)o->Type, (int)o->myHandle);
          if (o->Type == T_PLAYER)
            {
              /* Only the two members the load rules CLAMP rather than
                 refuse. A clamp that stops clamping is invisible from the
                 outside -- the file loads either way -- so
                 tools/check_v1_adversarial.sh asserts the landed values
                 here. Everything else about a Player is compared by the
                 round-trip check instead. */
              Player *pl = (Player*) o;
              printf("field Character.NotifiedLevel=%d\n",
                     (int)pl->NotifiedLevel);
              printf("field Player.cAutoBuff=%d\n", (int)pl->cAutoBuff);
              continue;
            }
          if (!o->isItem())
            continue;
          Item *it = (Item*) o;
          printf("field Thing.Next=%d\n", (int)it->Next);
          printf("field Thing.hm=%d\n", (int)it->hm);
          printf("field Thing.x=%d\n", (int)it->x);
          printf("field Thing.y=%d\n", (int)it->y);
          printf("field Thing.Image=%u\n", (unsigned)it->Image);
          printf("field Thing.Timeout=%d\n", (int)it->Timeout);
          printf("field Thing.StoredMovementTimeout=%d\n",
                 (int)it->StoredMovementTimeout);
          printf("field Thing.Flags=%u\n", (unsigned)it->Flags);
          printf("field Thing.Named=%s\n",
                 it->Named.GetData() ? it->Named.GetData() : "");
          printf("field Thing.__Stati.Last=%d\n", (int)it->__Stati.Last);
          for (j = 0; j != it->__Stati.Last; j++)
            {
              Status *s = &it->__Stati.S[j];
              printf("field Thing.__Stati.S[%d]=%u,%d,%d,%d,%u,%u,%u,%u,"
                     "%d,%d\n", (int)j, s->Nature, (int)s->Val, (int)s->Mag,
                     (int)s->Duration, s->Source, s->CLev, s->Dis, s->Once,
                     (int)s->eID, (int)s->h);
            }
          printf("field Thing.backRefs.Count=%d\n",
                 (int)it->backRefs.Total());
          for (j = 0; j != it->backRefs.Total(); j++)
            printf("field Thing.backRefs[%d]=%d\n", (int)j,
                   (int)it->backRefs[j]);
          printf("field Item.Known=%u\n", (unsigned)it->Known);
          printf("field Item.Plus=%d\n", (int)it->Plus);
          printf("field Item.Charges=%d\n", (int)it->Charges);
          printf("field Item.DmgType=%d\n", (int)it->DmgType);
          printf("field Item.GenNum=%d\n", (int)it->GenNum);
          printf("field Item.Parent=%d\n", (int)it->Parent);
          printf("field Item.homeID=%u\n", (unsigned)it->homeID);
          printf("field Item.Flavor=%d\n", (int)it->Flavor);
          printf("field Item.cHP=%d\n", (int)it->cHP);
          printf("field Item.Age=%d\n", (int)it->Age);
          printf("field Item.swingCount=%u\n", (unsigned)it->swingCount);
          printf("field Item.Quantity=%u\n", (unsigned)it->Quantity);
          printf("field Item.Inscrip=%s\n",
                 it->Inscrip.GetData() ? it->Inscrip.GetData() : "");
          printf("field Item.GenStats=%s\n",
                 it->GenStats.GetData() ? it->GenStats.GetData() : "");
          printf("field Item.iID=%u\n", (unsigned)it->iID);
          printf("field Item.eID=%u\n", (unsigned)it->eID);
          printf("field Item.IFlags=%u\n", (unsigned)it->IFlags);
        }

    theRegistry = savedReg;
    return true;
  }

bool RunSchemaTest(const char *outDir)
  { return Registry::V1RunSchemaTest(outDir); }

bool RunSchemaLoad(const char *path)
  { return Registry::V1RunSchemaLoad(path); }

/* ------------------------------------------------------------------------ */
/*                      -convert: a v0 file becomes v1                      */
/* ------------------------------------------------------------------------ */

/* Byte-copy src to dst. Plain stdio, same as Game::SaveGame's backup loop
   (src/Registry.cpp:1126-1146), because this runs before any Term file
   state is involved. Returns false (with the partial dst left for the
   caller to remove) on any short read or write. */
static bool V1CopyBytes(const char *src, const char *dst)
  {
    FILE *fin = fopen(src, "rb"), *fout = NULL;
    char buf[4096];
    bool ok = false;
    size_t n;
    if (fin && (fout = fopen(dst, "wb")))
      {
        ok = true;
        while ((n = fread(buf, 1, sizeof(buf), fin)) > 0)
          if (fwrite(buf, 1, n, fout) != n)
            { ok = false; break; }
        if (ferror(fin))
          ok = false;
      }
    if (fin)
      fclose(fin);
    if (fout && fclose(fout))
      ok = false;
    return ok;
  }

/* True when the two files hold exactly the same bytes. */
static bool V1SameBytes(const char *a, const char *b)
  {
    FILE *fa = fopen(a, "rb"), *fb = fopen(b, "rb");
    char bufa[4096], bufb[4096];
    bool same = (fa && fb);
    while (same)
      {
        size_t na = fread(bufa, 1, sizeof(bufa), fa);
        size_t nb = fread(bufb, 1, sizeof(bufb), fb);
        if (na != nb || memcmp(bufa, bufb, na))
          same = false;
        else if (na < sizeof(bufa))
          { same = !ferror(fa) && !ferror(fb); break; }
      }
    if (fa)
      fclose(fa);
    if (fb)
      fclose(fb);
    return same;
  }

/* -convert <file> (docs/SAVE-SCHEMA-SPEC.md, "Compatibility, and Brian's
   character"): read a v0 save through the EXISTING v0 flow -- the same
   LoadGroup call and module-reload loop RunSaveDump uses
   (src/Dump.cpp:152-221) -- and write it back in place as v1, keeping the
   original bytes at <file>.v0. The conversion is where the renumbering is
   repaired: the v0 read resolves every rID against the loaded module, and
   the v1 write records the resulting names. So this MUST be run with a
   module whose numbering matches the save; that is the operator's
   responsibility and cannot be checked here.

   Returns the process exit code (tools/check_convert_guard.sh holds the
   contract):
     0  converted; the original v0 bytes are kept at <file>.v0
     2  missing / unreadable / already v1 / a load or write failure
     3  refused: the file resolves under docs/evidence/ (the committed
        fixtures are evidence of the v0 defects and are NEVER converted --
        plan constraint 7), or a <file>.v0 already exists (overwriting it
        would destroy the only v0 copy). */
int RunSaveConvert(const char *path)
  {
    char resolved[4096], v0path[4104];
    fileHeader oldfh;
    FILE *f;
    int32 i;

    /* The fixture guard matches the RESOLVED path, so a symlink from
       outside docs/evidence/ into it still refuses, and a fixture named by
       relative path is still recognised. realpath also answers "does this
       file exist" -- it fails on a path with no file behind it. */
#ifdef _WIN32
    if (!_fullpath(resolved, path, sizeof(resolved)))
#else
    if (!realpath(path, resolved))
#endif
      {
        fprintf(stderr, "incursion -convert: no such file: %s\n", path);
        return 2;
      }
    if (strstr(resolved, "/docs/evidence/") ||
        strstr(resolved, "\\docs\\evidence\\"))
      {
        fprintf(stderr,
            "incursion -convert: refused: %s\n"
            "  resolves under docs/evidence/. The committed fixtures are\n"
            "  evidence of the v0 defects and are never converted\n"
            "  (docs/SAVE-SCHEMA-SPEC.md, \"Compatibility\").\n", resolved);
        return 3;
      }

    /* The old header: its Version tells v0 from v1 before any load work,
       and its Name (the character description line) carries over into the
       converted file's header below. */
    if (!(f = fopen(resolved, "rb")))
      {
        fprintf(stderr, "incursion -convert: cannot read %s\n", resolved);
        return 2;
      }
    if (fread(&oldfh, 1, sizeof(oldfh), f) != sizeof(oldfh))
      {
        fclose(f);
        fprintf(stderr,
            "incursion -convert: %s is too short to be a save file\n",
            resolved);
        return 2;
      }
    fclose(f);
    if (!strncmp(oldfh.Version, "IS", 2))
      {
        fprintf(stderr,
            "incursion -convert: %s is already a v1 save (%.12s); there are\n"
            "  no v0 bytes to convert or to back up.\n",
            resolved, oldfh.Version);
        return 2;
      }

    snprintf(v0path, sizeof(v0path), "%s.v0", resolved);
    if ((f = fopen(v0path, "rb")))
      {
        fclose(f);
        fprintf(stderr,
            "incursion -convert: refused: %s already exists.\n"
            "  It is the only v0 copy of a previous conversion; overwriting\n"
            "  it would destroy the original bytes. Move it aside first if\n"
            "  you really mean to re-convert.\n", v0path);
        return 3;
      }

    /* The v0 load, exactly as RunSaveDump does it: LoadGroup, then the
       module-reload loop over the ModFiles list the group restored, so the
       v1 write below has the module names to record. */
    try
      {
        T1->OpenRead(resolved);
        MainRegistry.RemoveObject(theGame);
        MainRegistry.LoadGroup(*T1, 0, false);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr, "incursion -convert: %s: %s\n", resolved,
            Lookup(FileErrors, error_number));
        if (error_number == EBADVER)
          fprintf(stderr,
              "incursion -convert: this build wants save-format %s\n",
              SaveFormatID());
        return 2;
      }
    if (!theGame->p[0] || !theGame->m[0])
      {
        fprintf(stderr,
            "incursion -convert: %s has no player/map after load\n",
            resolved);
        return 2;
      }
    theRegistry = &ResourceRegistry;
    memset(Game::Modules, 0, sizeof(Module*) * MAX_MODULES);
    for (i = 0; theGame->ModFiles[i]; i++)
      {
        try
          {
            char *filespec = theGame->ModFiles[i]->FName;
            T1->ChangeDirectory(T1->ModuleSubDir());
            T1->OpenRead(filespec);
            ResourceRegistry.LoadGroup(*T1, theGame->ModFiles[i]->hMod, true);
            T1->Close();
            if (!oThing(theGame->ModFiles[i]->hMod))
              throw EHANDLE;
            Game::Modules[theGame->ModFiles[i]->Slot] =
                oModule(theGame->ModFiles[i]->hMod);
            T1->ChangeDirectory(T1->IncursionDirectory);
          }
        catch (int error_number)
          {
            fprintf(stderr, "incursion -convert: module '%s': %s\n",
                theGame->ModFiles[i]->FName,
                Lookup(FileErrors, error_number));
            theRegistry = &MainRegistry;
            T1->ChangeDirectory(T1->IncursionDirectory);
            return 2;
          }
      }
    theRegistry = &MainRegistry;
    /* No SaveV1_ResolveNames() here: the "IS" check above already refused
       every v1 file, and a v0 load queues nothing to resolve. */

    /* Pre-flight the module-matching requirement BEFORE anything is
       written: SaveV1_CanWrite is the shared early copy of the geometry
       check SaveV1_SegmentFields makes at write time -- Game::SaveGame
       makes the same call before its own destructive steps. Made here it
       stops a mismatched run with the target file untouched, instead of
       after OpenWrite has truncated it. */
    {
      String whyNot;
      if (!SaveV1_CanWrite(*theGame, whyNot))
        {
          fprintf(stderr,
              "incursion -convert: refusing to convert %s:\n"
              "  %s. Run -convert against the module the\n"
              "  save was written with (docs/SAVE-SCHEMA-SPEC.md,\n"
              "  \"Compatibility\"). Nothing was written.\n",
              resolved, (const char*)whyNot);
          return 2;
        }
    }

    /* The backup, AFTER the load proved the file readable and BEFORE the
       write below touches it -- and verified byte for byte, because from
       here on this copy is the only v0 form of the save. */
    if (!V1CopyBytes(resolved, v0path))
      {
        remove(v0path);
        fprintf(stderr,
            "incursion -convert: could not write the backup %s;\n"
            "  nothing was converted.\n", v0path);
        return 2;
      }
    if (!V1SameBytes(resolved, v0path))
      {
        fprintf(stderr,
            "incursion -convert: the backup %s does not match the\n"
            "  original; nothing was converted.\n", v0path);
        return 2;
      }

    /* The v1 write, exactly as Game::SaveGame writes a fresh save
       (src/Registry.cpp:1195-1214): the caller writes the COMPLETE header
       -- SaveSchemaID() into Version AND the Compression flag -- because
       SaveGroupV1 trusts both. Only the Name line carries over from the
       old header. */
    try
      {
        fileHeader fh;
        T1->OpenWrite(resolved);
        memset(&fh, 0, sizeof(fh));
        strcpy(fh.Version, SaveSchemaID());
        fh.Sig = SIGNATURE;
        fh.numGroups = 1;
        fh.Compression = SaveV1_Raw() ? 0 : 1;
        memcpy(fh.Name, oldfh.Name, sizeof(fh.Name));
        T1->FWrite(&fh, sizeof(fh));
        MainRegistry.SaveGroupV1(*T1, 0);
        T1->Close();
      }
    catch (int error_number)
      {
        fprintf(stderr,
            "incursion -convert: writing %s failed: %s\n"
            "  The original v0 bytes are intact at %s; the partial file at\n"
            "  the original path must not be trusted.\n",
            resolved, Lookup(FileErrors, error_number), v0path);
        return 2;
      }

    printf("incursion -convert: %s is now %s; the v0 original is kept at\n"
           "%s\n", resolved, SaveSchemaID(), v0path);
    return 0;
  }
