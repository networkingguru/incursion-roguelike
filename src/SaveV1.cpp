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

/* src/Registry.cpp's staged-write-failure probe; shared so the fired-once
   state covers both writers, keeping tools/check_save_fail.sh meaningful. */
extern void SaveFailProbe(bool isData, int32 index);

/* src/Registry.cpp: bytes per whole object of a given type byte. */
extern size_t typeSize(int8 Type);

/* The decimal after "IS1." in fileHeader.Version. Any change to the meaning
   of an existing tag or record shape bumps it (wire-format section, schema
   revisions). */
#define SCHEMA_REV 0

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

/* -- coverage (DEBUG, save direction only) --------------------------------*/

struct SchemaPad { uint32 off, len; };
struct SchemaPin { const char *cls; int16 type; size_t size;
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
   switch news a Coin. ObjectSize() reports the class the object really is. */

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

static const SchemaPin SchemaPins[] = {
    { "Item", T_ITEM, sizeof(Item), ItemPads,
      (int)(sizeof(ItemPads)/sizeof(ItemPads[0])) },
    { "Creature", T_CREATURE, sizeof(Creature), CreaturePads,
      (int)(sizeof(CreaturePads)/sizeof(CreaturePads[0])) },
    { "Monster", T_MONSTER, sizeof(Monster), MonsterPads,
      (int)(sizeof(MonsterPads)/sizeof(MonsterPads[0])) },
    { "Character", T_CREATURE, sizeof(Character), CharacterPads,
      (int)(sizeof(CharacterPads)/sizeof(CharacterPads[0])) },
    { "Player", T_PLAYER, sizeof(Player), PlayerPads,
      (int)(sizeof(PlayerPads)/sizeof(PlayerPads[0])) },
    { "Feature", T_FEATURE, sizeof(Feature), FeaturePads,
      (int)(sizeof(FeaturePads)/sizeof(FeaturePads[0])) },
    { "Door", T_DOOR, sizeof(Door), DoorPads,
      (int)(sizeof(DoorPads)/sizeof(DoorPads[0])) },
    { "Trap", T_TRAP, sizeof(Trap), TrapPads,
      (int)(sizeof(TrapPads)/sizeof(TrapPads[0])) },
    { "Portal", T_PORTAL, sizeof(Portal), PortalPads,
      (int)(sizeof(PortalPads)/sizeof(PortalPads[0])) },
};

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
    /* Two passes: an exact (size, type) match first, because Feature and
       Portal share one layout (Portal adds no members) while Door and Trap
       share a different one (Door.SecretSavedGlyph and Trap.tID both start
       at the same offset) -- all four are sizeof 144 on arm64/LP64, so size
       alone cannot tell them apart (measured 2026-08-24: feat/door/trap/
       portal offsets of cHP/mHP/fID/MoveMod are identical at 128/130/132/
       136 in every one of them; Door and Trap add their own member at 137
       and diverge only there). The size-only fallback pass keeps every
       earlier row's behaviour unchanged: Item's row carries type T_ITEM but
       real Item objects carry T_RING/T_POTION/etc, so it has always relied
       on size-only matching and must keep doing so. */
    for (size_t i = 0; i != sizeof(SchemaPins)/sizeof(SchemaPins[0]); i++)
      if (SchemaPins[i].size == sz && SchemaPins[i].type == (int16)o->Type)
        { v1Cov.pin = &SchemaPins[i]; v1Cov.cls = SchemaPins[i].cls; break; }
    if (!v1Cov.pin)
      for (size_t i = 0; i != sizeof(SchemaPins)/sizeof(SchemaPins[0]); i++)
        if (SchemaPins[i].size == sz)
          { v1Cov.pin = &SchemaPins[i]; v1Cov.cls = SchemaPins[i].cls; break; }
    if (!v1Cov.pin)
      {
        v1CovFindings++;
        Error("SCHEMA COVERAGE: no pin row for class of size %lu (type %d)",
              (unsigned long)sz, (int)o->Type);
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

/* The resolve state (name table + queues) outlives LoadGroupV1 on purpose:
   SaveV1_ResolveNames() consumes it after the module reload. */
static void v1ResolveTeardown(void)
  {
    v1NamesFree();
    v1QueuesFree();
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

/* Deferred resolution: called once after each load path's module-reload
   loop (Game::LoadGame, RunSaveDump, and the -schematest/-schemaload
   drivers). Resolves every queued slot or aborts naming EVERY failure --
   an unresolvable entry MUST NOT be zeroed and MUST NOT be skipped
   (constraint 3). A v0 load queues nothing and returns immediately. */
void SaveV1_ResolveNames()
  {
    uint32 i;
    long failures = 0;

    if (!v1.slotQCount && !v1.statQCount && !v1.nameCount)
      return;

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
        uint32 idx = (uint32) *(v1.slotQ[i]);
        if (idx >= v1.nameCount)
          {
            failures++;
            fprintf(stderr,
                "incursion: v1 rID field references name table entry %u "
                "of %u\n", (unsigned)idx, (unsigned)v1.nameCount);
            continue;
          }
        if (v1.names[idx].bad)
          continue;   /* already reported above */
        *(v1.slotQ[i]) = v1.names[idx].resolved;
      }

    for (i = 0; i != v1.statQCount; i++)
      {
        uint32 idx = (uint32) v1.statQ[i]->eID;
        if (idx >= v1.nameCount)
          {
            failures++;
            fprintf(stderr,
                "incursion: v1 Status::eID references name table entry %u "
                "of %u\n", (unsigned)idx, (unsigned)v1.nameCount);
            continue;
          }
        if (v1.names[idx].bad)
          continue;
        v1.statQ[i]->eID = (int32) v1.names[idx].resolved;
      }

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
        uint32 idx = (m == 0) ? 0xFFFFFFFFu : V1InternRid(m);
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_RID);
        v1PutU32(&v1Out, idx);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      { m = 0; return; }
    if (e->kind != K_RID)
      throw ECORRUPT;
    uint32 idx;
    memcpy(&idx, e->pay, 4);
    if (idx == 0xFFFFFFFFu)
      { m = 0; return; }
    /* Deferred: park the table index in the slot and queue its address for
       SaveV1_ResolveNames(), which runs after the modules are reloaded. */
    m = (rID)idx;
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
        uint32 idx = (e == 0) ? 0xFFFFFFFFu : V1InternRid(e);
        v1PutU16(&v1Out, tag);
        v1PutU8(&v1Out, K_RID);
        v1PutU32(&v1Out, idx);
        return;
      }
    const V1Ent *e = v1Find(tag);
    if (!e)
      { s.eID = 0; return; }
    if (e->kind != K_RID)
      throw ECORRUPT;
    uint32 idx;
    memcpy(&idx, e->pay, 4);
    if (idx == 0xFFFFFFFFu)
      { s.eID = 0; return; }
    s.eID = (int32)idx;
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
        CFile *cf = new CFile(&t);
        cf->FWrite(v1Out.p, v1Out.len);
        gh.compSize = cf->CommitCompressed(t.Tell(), false);
        delete cf;
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
            CFile *cf = new CFile(&t);
            try
              {
                cf->LoadCompressed(t.Tell(), gh.compSize, gh.groupSize, false);
                cf->Seek(0, SEEK_SET);
                cf->FRead(buf, gh.groupSize);
              }
            catch (...)
              { delete cf; throw; }
            delete cf;
          }
        else
          throw ECORRUPT;

        LastUsedHandle = max(LastUsedHandle, gh.LastHandle);

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

            V1Ent *ents; int entCount;
            v1ScanFields(buf + pos, recLen, &ents, &entCount);
            v1PushFrame(ents, entCount);

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
            hCurrent = o->myHandle;

            o->Serialize(*this, false);
            ASSERT(v1FrameDepth == 1);
            v1PopFrame();

            if (o->isCreature())
              ((Creature*)o)->ts.SanitizeLoadedTargets();

            RegisterObject(o, true);
            pos += recLen;
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
        free(buf);
        throw;
      }
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
