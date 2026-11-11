/* CreationSource.h -- the one place every character-creation decision is made
   or replayed (bead inc-10v7f; spec sections 1-2, amendments A6 and B18).

   A decision site in src/Create.cpp (or src/Skills.cpp) wraps its draw or
   prompt in ONE of three primitives:

     SourcedRoll(key, live)        a number
     SourcedPick(key, list, live)  a choice among named candidates
     SourcedItem(key, item, live)  a generated item, as a complete description
   `live` is the code the site ran before this file existed; it runs unchanged
   whenever the active source holds no answer. The active source is one of:
     Live    normal play. It answers nothing, so every site runs `live`, and it
             RECORDS each decision (into RInf for the gallery; with
             INCURSION_RECORD_CHAR=<path>, also into a .char file and a
             <path minus extension>.walk.sav, saved at the end of setup).
     Replay  gallery reincarnation. It answers from RInf what RInf holds; any
             other decision is NOT_RECORDED and the site acts as Live (spec A6).
     File    the fixture builder (`incursion-headless -build <file.char>`). It
             answers EVERY decision from a parsed .char file by (key, context)
             queue and never runs `live`: an unstated decision fails the build
             and prints the line to add. No gallery entry, no recording
             (src/CharFile.cpp).
   A key is an enum name plus a context: the resource and event whose script
   runs (CreationScope), an optional `sub` name, and the ordinal in that (key,
   context) queue. The recorder writes `<key> [<context>]: <value>`. */
#ifndef CREATIONSOURCE_H
#define CREATIONSOURCE_H

#include <string>
#include <vector>

/* X(name, kind, default, reach, seen). Appending a decision is one line here plus the
   call site. `seen` is SEEN, or UNSEEN for a ROLL whose value a dump shows only
   through its result (the char tools search it; see CreationKeyIsUnseen). `reach` says whether character creation (Player::Create and
   everything it calls) can reach the decision: REACHED, or NOT_REACHED for a
   decision made only after creation (a level gained later, training, a tattoo)
   or by a feat a level-1 character cannot take. The equivalence check
   (tools/check_fixture_equivalence.sh) reads it at run time and demands that
   some creation walk hit every REACHED key it can state; it lists the
   NOT_REACHED keys and demands nothing of them.
   The default is the value `missing` prints for the file author (spec A5);
   a build never uses it. An empty PICK default means "the first candidate
   offered". A NULL default marks a key a build never asks: the screen choice
   whose result other keys already state (the attribute set letter, the point
   buy and reroll confirmations, the abandon prompt, and OPTIONS_FILE, which
   the `options:` line replaced). The recorder does not
   write it and a .char may not state it. A new decision gets its default
   here, in this one place. */
/* Why MISSILE_QUANTITY is NOT_REACHED: the branch that draws it (the
   T_MISSILE case in the Weapon Focus loop, src/Create.cpp near line 1424)
   dates from when the halfling rock was a missile. The rock is now T_WEAPON
   (lib/weapons.irh, Item "rock"), and no creation menu offers Weapon Focus in
   a T_MISSILE item, so the branch is not reached.
   Why SCRIPT_MENU is NOT_REACHED: the only class-script LMenu runs in the
   Rogue's EV_ADVANCE at levels 6, 9, 12, 15 and 18 (lib/classes.irh, about
   lines 2592-2676), and a level-1 character does not advance. The other
   LMenu calls in lib/*.irh sit in item, spell and ability effects.
   A walk whose .char states a NOT_REACHED key fails the equivalence check. */
#define CREATION_KEY_LIST(X) \
    X(ALTER_OPTIONS,    PICK, "no", REACHED, SEEN) \
    X(EXPLORE_CONTINUE, PICK, "yes", REACHED, SEEN) \
    X(FORMULA_SEED,     ROLL, "1", REACHED, SEEN) \
    X(GENDER,           PICK, "male", REACHED, SEEN) \
    X(NAME,             PICK, "", REACHED, SEEN) \
    X(SURNAME,          PICK, "", REACHED, SEEN) \
    X(RACE,             PICK, "", REACHED, SEEN) \
    X(SUBRACE,          PICK, "", REACHED, SEEN) \
    X(CLASS,            PICK, "", REACHED, SEEN) \
    X(GOD,              PICK, "", REACHED, SEEN) \
    X(ALIGNMENT,        PICK, "", REACHED, SEEN) \
    X(PERSONALITY,      PICK, "", REACHED, SEEN) \
    X(DOMAIN,           PICK, "", REACHED, SEEN) \
    X(DOMAIN_POOL,      PICK, "", REACHED, SEEN) \
    X(CRAFT_FORMULA,    PICK, "", REACHED, SEEN) \
    X(LEVEL_CLASS,      PICK, "", NOT_REACHED, SEEN) \
    X(LEVEL_ATTR,       PICK, "", NOT_REACHED, SEEN) \
    X(ATTR_STR,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_DEX,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_CON,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_INT,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_WIS,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_CHA,         ROLL, "10", REACHED, SEEN) \
    X(ATTR_LUC,         ROLL, "10", REACHED, SEEN) \
    X(PERK_TYPE,        PICK, "PERK_NONE", REACHED, SEEN) \
    X(PERK_FEAT,        PICK, "", REACHED, SEEN) \
    X(PERK_ABILITY,     PICK, "", REACHED, SEEN) \
    X(PERK_SPELL,       PICK, "", REACHED, SEEN) \
    X(PERK_RESIST,      PICK, "", REACHED, SEEN) \
    X(PERK_IMMUNE,      PICK, "", REACHED, SEEN) \
    X(PERK_ITEM,        ITEM, "none", REACHED, SEEN) \
    X(SKILL_RANKS,      ROLL, "0", REACHED, SEEN) \
    X(HP_ROLL,          ROLL, "1", REACHED, SEEN) \
    X(MANA_ROLL,        ROLL, "1", REACHED, SEEN) \
    X(STORE_SEED,       ROLL, "1", REACHED, SEEN) \
    X(CHARACTER_NAME,   PICK, "", REACHED, SEEN) \
    X(WIZARD_MODE,      ROLL, "0", REACHED, SEEN) \
    X(EXPLORE_MODE,     ROLL, "0", REACHED, SEEN) \
    X(REROLLS,          ROLL, "0", REACHED, SEEN) \
    X(REROLLED_PERKS,   ROLL, "0", REACHED, SEEN) \
    X(STAT_METHOD,      ROLL, "1", REACHED, SEEN) \
    X(GEAR_STREAM,      ROLL, "0", REACHED, SEEN) \
    X(GEAR_CHANCE,      ROLL, "1", REACHED, SEEN) \
    X(KIT_ITEM,         ITEM, "none", REACHED, SEEN) \
    X(BEGINKIT_ITEM,    ITEM, "none", REACHED, SEEN) \
    X(BEGINKIT_FOOD,    ROLL, "7", REACHED, SEEN) \
    X(MISSILE_QUANTITY, ROLL, "80", NOT_REACHED, SEEN) \
    X(THROWN_QUANTITY,  ROLL, "4", REACHED, SEEN) \
    X(AMMO_QUANTITY,    ROLL, "30", REACHED, SEEN) \
    X(ABANDON,          PICK, NULL, REACHED, SEEN) \
    X(ATTR_SET,         PICK, NULL, REACHED, SEEN) \
    X(POINTBUY_CONFIRM, PICK, NULL, REACHED, SEEN) \
    X(REROLL_CONFIRM,   PICK, NULL, REACHED, SEEN) \
    X(FEAT,             PICK, "", REACHED, SEEN) \
    X(SKILL_FOCUS,      PICK, "", REACHED, SEEN) \
    X(NATURAL_APTITUDE, PICK, "", REACHED, SEEN) \
    X(STUDY_AREA,       PICK, "", NOT_REACHED, SEEN) \
    X(SCHOOL_FOCUS,     PICK, "", REACHED, SEEN) \
    X(IMPCRIT_WEAPON,   PICK, "", NOT_REACHED, SEEN) \
    X(FEAT_WEAPON,      PICK, "", REACHED, SEEN) \
    X(EXOTIC_WEAPON,    PICK, "", REACHED, SEEN) \
    X(WEAPON_UNFIT_CONFIRM, PICK, "yes", REACHED, SEEN) \
    X(INHERENT_SPELL,   PICK, "", REACHED, SEEN) \
    X(LUCUBRATION_BOOK, PICK, "", NOT_REACHED, SEEN) \
    X(TATTOO,           PICK, "", NOT_REACHED, SEEN) \
    X(FAV_ENEMY,        PICK, "", REACHED, SEEN) \
    X(SPECIALIST_SCHOOL, PICK, "", REACHED, SEEN) \
    X(TRAIN_REPLACE,    PICK, "yes", NOT_REACHED, SEEN) \
    X(SPELL_LEARN,      PICK, "", REACHED, SEEN) \
    X(OPTIONS_FILE,     PICK, NULL, REACHED, SEEN) \
    X(SCRIPT_ROLL,      ROLL, "1", REACHED, UNSEEN) \
    X(SCRIPT_YN,        PICK, "no", REACHED, SEEN) \
    X(SCRIPT_CHOICE,    PICK, "", REACHED, SEEN) \
    X(SCRIPT_MENU,      PICK, "", NOT_REACHED, SEEN) \
    X(PERK_CHARGES,     ROLL, "30", REACHED, SEEN) \
    X(EFFECT_ROLL,      ROLL, "1", REACHED, UNSEEN)

enum CreationKey {
#define X(n,k,d,r,u) CK_##n,
    CREATION_KEY_LIST(X)
#undef X
    CK_COUNT
};

enum CreationKind { CKIND_ROLL, CKIND_PICK, CKIND_ITEM };

const char    *CreationKeyName(CreationKey k);   /* lower case: "attr_str" */
CreationKind   CreationKeyKind(CreationKey k);
const char    *CreationKeyDefault(CreationKey k);   /* the X-macro default ("" if NULL) */
bool           CreationKeyIsInput(CreationKey k);   /* false: observed, never stated */
/* A ROLL whose value a dump shows only through its result: a script's draw and
   an effect's damage roll. It is the fifth column of CREATION_KEY_LIST
   (UNSEEN; every other key is SEEN). The recorder writes the inclusive range of
   each such roll beside the .char (<name>.rolls, bead inc-10v7f phase 11g), and
   tools/char_roll_search.py searches that range for the value that rebuilds an
   old save. The column is the game's; a tool holds no key name. */
bool           CreationKeyIsUnseen(CreationKey k);

/* The inclusive range a ROLL site's own code fixes (a die, a rank cap, a
   quantity span). The default holds no range. Live and Replay ignore it; the
   File backend fails a stated value outside it. */
struct CreationRange {
    int32 lo, hi;
    CreationRange() : lo(1), hi(0) {}
    CreationRange(int32 a, int32 b) : lo(a), hi(b) {}
    bool Set() const { return lo <= hi; }
};

struct CreationContext {
    std::string resource;   /* resource whose script runs, or "" */
    int         event;      /* event whose script runs, or 0 */
    std::string sub;        /* the site's own qualifier, or "" */
    int         ordinal;    /* position in this (key, context) queue */
};

/* A script event that makes a sourced decision pushes its context here, so
   the primitives find it without any change at the decision site. */
struct CreationScope {
    bool pushed;
    /* `active` false pushes nothing: a caller that opens a scope only while the
       creation window is open passes CreationWindowOpen() here. */
    CreationScope(const char *resource, int event, bool active = true);
    ~CreationScope();
};

/* The candidates of a pick: display-independent names, and the value the
   site's `live` code returns for each (an index, a letter, a menu value). */
struct CreationPickList {
    std::vector<std::string> names;
    std::vector<int32>       values;
    void Add(const char *name, int32 value)
        { names.push_back(name ? name : ""); values.push_back(value); }
    void Add(const char *name)
        { Add(name, (int32)names.size()); }
    void Clear() { names.clear(); values.clear(); }
};

/* One status a script set on a generated item (spec section 7 gap 4: the
   poison duration of a vial). */
struct CreationStati {
    int16 nature;
    int32 val, mag, duration;
    rID   eID;
};

/* The item flags generation sets, as the text form names them. */
#define CREATION_ITEM_FLAGS (IF_BLESSED | IF_CURSED | IF_MASTERWORK | IF_RUNIC)

/* A generated item, described completely (spec B2, B15). */
struct CreationItem {
    rID   iID, eID;
    int16 plus, bane;
    int16 q[8];
    int32 quantity, charges;
    uint16 flags;   /* IFlags & CREATION_ITEM_FLAGS: blessed, cursed, masterwork, runic */
    std::vector<CreationStati> stati;
    CreationItem() : iID(0), eID(0), plus(0), bane(0), quantity(0), charges(0), flags(0)
        { for (int i = 0; i != 8; i++) q[i] = 0; }
};

class CreationSource {
public:
    virtual ~CreationSource() {}
    virtual const char *Backend() const = 0;
    /* The Term mode creation runs in: MO_CREATE (Live) or MO_RECREATE. */
    virtual int  TermMode() const = 0;
    /* May the player ESC out of a menu and be asked to abandon? */
    virtual bool CanBackUp() const = 0;
    /* May a source's stream seed re-seed the generator? Live and Replay yes;
       File no: it answers each later draw by its own key (spec B1). */
    virtual bool Reseeds() const { return true; }
    /* True when the source never lets a site run its `live` code: it answers
       every decision or fails the build. */
    virtual bool NeverLive() const { return false; }
    /* RInf set-up, at the point Create used to test `reincarnate`. */
    virtual void BeginState(Player *p) = 0;
    /* Back-navigation: drop the response the abandon prompt recorded. */
    virtual void PopResponse(Player *p) = 0;
    /* End of a finished creation: Live writes the gallery entry and sets
       *slot; Replay refreshes the display. *slot stays -2 when unchanged. */
    virtual void Finish(Player *p, int16 *slot) = 0;

    virtual bool AnswerRoll(CreationKey k, const CreationContext &c, int32 &v,
        const CreationRange &range) = 0;
    virtual bool AnswerPick(CreationKey k, const CreationContext &c,
        const CreationPickList &list, int32 &value, std::string &text,
        bool &inList) = 0;
    virtual bool AnswerPerks(PerkSet &out) = 0;
    virtual bool AnswerItem(CreationKey k, const CreationContext &c,
        CreationItem &it) = 0;

    virtual void NoteRoll(CreationKey k, const CreationContext &c, int32 v,
        const CreationRange &range) = 0;
    virtual void NotePick(CreationKey k, const CreationContext &c,
        const std::string &text) = 0;
    virtual void NotePerks(const PerkSet &set) = 0;
    /* The option bytes the creation option screen left, when it changed them
       (spec B11). Live writes them beside the .char; Replay ignores them. */
    virtual void NoteOptions(const int8 *opts, int n) = 0;
    virtual void NoteItem(CreationKey k, const CreationContext &c,
        const CreationItem &it) = 0;
    /* Window close: Live writes the .char file when it is asked for. */
    virtual void Close(bool completed) = 0;
};

CreationSource *CreationSourceNow();
CreationSource *SetCreationSource(CreationSource *s);   /* returns the old */
CreationSource &CreationLiveSource();
CreationSource &CreationReplaySource();
/* The save of the walked character that Game::NewGameTail writes before the
   first turn while INCURSION_RECORD_CHAR=<path> is set: <path without its
   extension>.walk.sav, beside the .char. "" when recording is off (then
   NewGameTail writes nothing). The fixture round trip dumps this save as the
   walk side, because the walk's own later save has played turns (R1). */
std::string CreationWalkSavePath();
/* src/CharFile.cpp. The File backend; CharFileLoad parses a .char first. */
CreationSource &CreationFileSource();

/* The text of a context as the recorder writes it and the parser reads it. */
std::string CreationContextText(const CreationContext &c);
/* The context of a decision of `key` made now, as the primitives build it. */
CreationContext CreationMakeContext(CreationKey k, const char *sub);
/* A resource's name in full, ";tag" included ("none" for rID 0). NAME() drops
   the tag, and two resources can share a name without it, so a pick whose
   candidates are resources (items, spells, tattoos) names them by this. */
std::string CreationFullName(rID x);
/* A pick label with colour codes and markup stripped, case kept (spec 3). */
std::string CreationNormalize(const std::string &label);

/* One field of a Perk, as ONE table the serializer and the parser both walk
   (spec 3, B18). `perkType` is the PERK_* the field belongs to; `key` is the
   decision key its line uses. */
struct CreationPerkField {
    int          perkType;
    CreationKey  key;
    std::string (*write)(const Perk &p);
    bool        (*read)(const std::string &text, Perk &p, std::string &err);
};
extern const CreationPerkField CreationPerkFields[];
extern const int               CreationPerkFieldCount;
/* The name the PERK_TYPE line carries, and its inverse (-1 when unknown). */
const char *CreationPerkTypeName(int perkType);
int         CreationPerkTypeFromName(const std::string &name);
/* The ITEM text form, both ways. Read fills `it` from the text or says why not. */
std::string CreationItemText(const CreationItem &it);
bool        CreationItemRead(const std::string &text, CreationItem &it, std::string &err);
/* Build the item an answered CreationItem describes, through the engine's own
   item functions. NULL for "none". */
Item       *CreationMakeItem(const CreationItem &d);

/* Fail a build: one line on stderr beginning `BUILD FAILED:`, then exit. */
void CreationBuildFail(const char *fmt, ...);

/* The window spans one Player::Create. Outside it every primitive is a pure
   pass-through to `live`, so level-ups in play record nothing. */
struct CreationWindow {
    bool done;
    CreationWindow();
    ~CreationWindow();
};
bool CreationWindowOpen();
/* Fill `io` from a generated item: item, effect, plus, bane, qualities,
   quantity, charges and every status on it. Does nothing outside the window
   or for a NULL item, so a site calls it without a guard. */
void CreationDescribeItem(CreationItem &io, Item *it);

/* While a SourcedItem's `live` runs, the item is the one decision: a primitive
   called inside it acts Live and records nothing (spec B2). SourcedItem sets
   this depth; the halves below read it. */
struct CreationItemDepth {
    CreationItemDepth();
    ~CreationItemDepth();
};
bool CreationInsideItem();

/* Building the candidates of a decision (the five attribute sets and the
   perks in them) is not a decision: a script draw an item makes while it is
   generated for a candidate belongs to the candidate, which the File backend
   never generates. While one of these lives, the primitives act Live and
   record nothing, as they do inside an item. */
struct CreationCandidates : CreationItemDepth {};

/* While a primitive's `live` runs, a draw or prompt the code makes is part of
   that decision. The draw census reads this to tell a sourced draw from an
   unsourced one (phase 6c). The primitives below set it. */
struct CreationLiveDepth {
    CreationLiveDepth();
    ~CreationLiveDepth();
};
bool CreationInsideLive();

/* The halves the primitives are built from. Answer returns false for
   NOT_RECORDED; a successful Answer or a Note advances the ordinal. */
bool CreationAnswerRoll(CreationKey k, const char *sub, int32 &v,
    const CreationRange &range = CreationRange());
void CreationNoteRoll(CreationKey k, const char *sub, int32 v,
    const CreationRange &range = CreationRange());
bool CreationAnswerPick(CreationKey k, const char *sub,
    const CreationPickList &list, int32 &value, std::string &text, bool &inList);
void CreationNotePick(CreationKey k, const char *sub, const std::string &text);
bool CreationAnswerItem(CreationKey k, const char *sub, CreationItem &it);
void CreationNoteItem(CreationKey k, const char *sub, const CreationItem &it);
/* The retained perk set: the one set the player kept from the five offered. */
bool CreationAnswerPerks(PerkSet &out);
void CreationNotePerks(const PerkSet &set);
/* A multi-answer pick: the source gives one answer per call, in order, until
   it gives none; every answer is a name in `list`. Returns false when the
   source holds no answer, or an answer names nothing in `list`. The recorder
   writes one line per value, in the order given. */
bool CreationAnswerPickMany(CreationKey k, const char *sub,
    const CreationPickList &list, std::vector<int32> &values);
void CreationNotePickMany(CreationKey k, const char *sub,
    const CreationPickList &list, const std::vector<int32> &values);
void CreationNoteOptions(const int8 *opts, int n);
/* True while CreationAnswerPickMany asks for its answers one at a time. */
bool CreationInPickMany();
/* Player::AbandonCreation marks where the step began, so PopResponse can drop
   what the abandoned step recorded (a position, not a key). */
void CreationMarkStep();

template<class Live>
int32 SourcedRoll(CreationKey k, Live live, const char *sub = NULL,
    const CreationRange &range = CreationRange())
{
    int32 v;
    if (CreationAnswerRoll(k, sub, v, range))
        return v;
    {
        CreationLiveDepth inside;
        v = (int32)live();
    }
    CreationNoteRoll(k, sub, v, range);
    return v;
}

/* `live` returns the chosen value (a value from list.values), or -1 when the
   player backed out; a back-out is not a decision and is not recorded. */
template<class Live>
int32 SourcedPick(CreationKey k, const CreationPickList &list, Live live,
    const char *sub = NULL)
{
    int32 v; std::string text; bool inList;
    if (CreationAnswerPick(k, sub, list, v, text, inList) && inList)
        return v;
    {
        CreationLiveDepth inside;
        v = (int32)live();
    }
    for (size_t i = 0; i != list.values.size(); i++)
        if (list.values[i] == v) {
            CreationNotePick(k, sub, list.names[i]);
            break;
        }
    return v;
}

/* A screen that decides many numbers at once (the skill ranks): n rolls, each
   with its own sub name. `live` runs the screen and fills vals[0..n); a source
   that holds every number answers them all and `live` does not run. `ranges`,
   when given, holds one range per number. */
template<class Live>
void SourcedRoll(CreationKey k, int32 *vals, int16 n, const char *(*subName)(int16),
    Live live, const CreationRange *ranges = NULL)
{
    int16 i;
    for (i = 0; i != n; i++)
        if (!CreationAnswerRoll(k, subName(i), vals[i],
                ranges ? ranges[i] : CreationRange()))
            break;
    if (i == n)
        return;
    {
        CreationLiveDepth inside;
        live();
    }
    for (i = 0; i != n; i++)
        CreationNoteRoll(k, subName(i), vals[i], ranges ? ranges[i] : CreationRange());
}

/* A table that decides a set of choices (the spell table). `live(out)` fills
   `out` with the chosen values (values from list.values, in the order to
   record) and returns false when the player backed out; a back-out is not a
   decision and is not recorded. Returns true when a decision was made, by the
   source or by `live`. */
template<class Live>
bool SourcedPick(CreationKey k, const CreationPickList &list,
    std::vector<int32> &out, Live live, const char *sub = NULL)
{
    if (CreationAnswerPickMany(k, sub, list, out))
        return true;
    out.clear();
    bool decided;
    {
        CreationLiveDepth inside;
        decided = live(out);
    }
    if (!decided)
        return false;
    CreationNotePickMany(k, sub, list, out);
    return true;
}

/* `live` fills `io` with the item it generated. Returns true when the source
   answered: `io` then describes the item (iID 0 means none) and the site MUST
   build it with CreationMakeItem. Returns false when `live` ran. */
template<class Live>
bool SourcedItem(CreationKey k, CreationItem &io, Live live, const char *sub = NULL)
{
    if (CreationAnswerItem(k, sub, io))
        return true;
    {
        CreationItemDepth inside;
        CreationLiveDepth liveInside;
        live(io);
    }
    CreationNoteItem(k, sub, io);
    return false;
}

/* ---- the tripwires (spec section 2; bead inc-10v7f phase 7b) -------------- */

/* T1 and T2 are armed by the creation window when the File source is active.
   T1 stays armed to the end of the build; T2 only while the window is open.
   A key read or a main-stream draw that no sourced decision made fails the
   build, in one stderr line beginning `BUILD FAILED: T1` or `BUILD FAILED: T2`
   (src/CreationSource.cpp). */
extern bool g_t1Armed;

/* A key read that only acknowledges what the screen shows ([MORE], -- more --,
   a message box). While one lives, an armed T1 answers the read itself with
   Enter and logs one line, naming the kind and the text, to logs/build-acks.log
   in the build's sandbox. The three sites are in src/TextTerm.cpp. */
struct CreationAck {
    const char *prevKind, *prevText;
    CreationAck(const char *kind, const char *text);
    ~CreationAck();
};

/* INCURSION_TRIPWIRE_PROBE=<case>: tools/check_fixture_tripwires.sh inserts a
   fault at a place the code names. Cases: yn, rawkey, random-create,
   random-advance, random-mapgen, random-unstated. Unset, every probe site does
   nothing. CreationTripwireProbe says true for the named case and writes one
   stderr line first, so the check can tell a fault that ran and passed from a
   fault that never ran. */
bool CreationTripwireProbe(const char *name);
/* The rawkey fault: draw a titled screen and read a key from it. It lives here,
   not in src/Create.cpp, because tools/check_creation_source_sites.sh refuses
   any key read in that file outside a sourced decision. */
void CreationTripwireRawKeyScreen(Term *t);
#define CREATION_TRIPWIRE_PROBE_RANDOM(name) \
    do { if (CreationTripwireProbe(name)) (void)random(2); } while (0)

#endif
