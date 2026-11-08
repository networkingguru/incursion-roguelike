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
             RECORDS what each site decided (into RInf for the gallery, and
             into a .char file when INCURSION_RECORD_CHAR=<path> is set).
     Replay  gallery reincarnation. It answers from RInf exactly what RInf
             holds; every other decision is NOT_RECORDED and the site acts as
             Live (spec A6).

     File    the fixture builder (`incursion-headless -build <file.char>`). It
             answers EVERY decision from a parsed .char file, by (key, context)
             queue, and never lets a site run `live`: a decision the file does
             not state is a build failure that prints the line to add. It
             writes no gallery entry and no recording (src/CharFile.cpp).
   A key is an enum name plus a context: the resource and event whose script
   runs (CreationScope), an optional `sub` name, and the ordinal in that (key,
   context) queue. The recorder writes `<key> [<context>]: <value>`. */
#ifndef CREATIONSOURCE_H
#define CREATIONSOURCE_H

#include <string>
#include <vector>

/* X(name, kind, default). Appending a decision is one line here plus the call
   site. The default is the value `missing` prints for the file author (spec A5);
   a build never uses it. An empty PICK default means "the first candidate
   offered". A NULL default marks a key a build never asks: the screen choice
   whose result other keys already state (the attribute set letter, the point
   buy and reroll confirmations, the abandon prompt, and OPTIONS_FILE, which
   the `options:` line replaced). The recorder does not
   write it and a .char may not state it. A new decision gets its default
   here, in this one place. */
#define CREATION_KEY_LIST(X) \
    X(ALTER_OPTIONS,    PICK, "no") \
    X(EXPLORE_CONTINUE, PICK, "yes") \
    X(FORMULA_SEED,     ROLL, "1") \
    X(GENDER,           PICK, "male") \
    X(NAME,             PICK, "") \
    X(SURNAME,          PICK, "") \
    X(RACE,             PICK, "") \
    X(SUBRACE,          PICK, "") \
    X(CLASS,            PICK, "") \
    X(GOD,              PICK, "") \
    X(ALIGNMENT,        PICK, "") \
    X(PERSONALITY,      PICK, "") \
    X(DOMAIN,           PICK, "") \
    X(DOMAIN_POOL,      PICK, "") \
    X(CRAFT_FORMULA,    PICK, "") \
    X(LEVEL_CLASS,      PICK, "") \
    X(LEVEL_ATTR,       PICK, "") \
    X(ATTR_STR,         ROLL, "10") \
    X(ATTR_DEX,         ROLL, "10") \
    X(ATTR_CON,         ROLL, "10") \
    X(ATTR_INT,         ROLL, "10") \
    X(ATTR_WIS,         ROLL, "10") \
    X(ATTR_CHA,         ROLL, "10") \
    X(ATTR_LUC,         ROLL, "10") \
    X(PERK_TYPE,        PICK, "PERK_NONE") \
    X(PERK_FEAT,        PICK, "") \
    X(PERK_ABILITY,     PICK, "") \
    X(PERK_SPELL,       PICK, "") \
    X(PERK_RESIST,      PICK, "") \
    X(PERK_IMMUNE,      PICK, "") \
    X(PERK_ITEM,        ITEM, "none") \
    X(SKILL_RANKS,      ROLL, "0") \
    X(HP_ROLL,          ROLL, "1") \
    X(MANA_ROLL,        ROLL, "1") \
    X(STORE_SEED,       ROLL, "1") \
    X(CHARACTER_NAME,   PICK, "") \
    X(WIZARD_MODE,      ROLL, "0") \
    X(EXPLORE_MODE,     ROLL, "0") \
    X(REROLLS,          ROLL, "0") \
    X(REROLLED_PERKS,   ROLL, "0") \
    X(STAT_METHOD,      ROLL, "1") \
    X(GEAR_STREAM,      ROLL, "0") \
    X(GEAR_CHANCE,      ROLL, "1") \
    X(KIT_ITEM,         ITEM, "none") \
    X(BEGINKIT_ITEM,    ITEM, "none") \
    X(BEGINKIT_FOOD,    ROLL, "7") \
    X(MISSILE_QUANTITY, ROLL, "80") \
    X(THROWN_QUANTITY,  ROLL, "4") \
    X(AMMO_QUANTITY,    ROLL, "30") \
    X(ABANDON,          PICK, NULL) \
    X(ATTR_SET,         PICK, NULL) \
    X(POINTBUY_CONFIRM, PICK, NULL) \
    X(REROLL_CONFIRM,   PICK, NULL) \
    X(FEAT,             PICK, "") \
    X(SKILL_FOCUS,      PICK, "") \
    X(NATURAL_APTITUDE, PICK, "") \
    X(STUDY_AREA,       PICK, "") \
    X(SCHOOL_FOCUS,     PICK, "") \
    X(IMPCRIT_WEAPON,   PICK, "") \
    X(FEAT_WEAPON,      PICK, "") \
    X(EXOTIC_WEAPON,    PICK, "") \
    X(WEAPON_UNFIT_CONFIRM, PICK, "yes") \
    X(INHERENT_SPELL,   PICK, "") \
    X(LUCUBRATION_BOOK, PICK, "") \
    X(TATTOO,           PICK, "") \
    X(FAV_ENEMY,        PICK, "") \
    X(SPECIALIST_SCHOOL, PICK, "") \
    X(TRAIN_REPLACE,    PICK, "yes") \
    X(SPELL_LEARN,      PICK, "") \
    X(OPTIONS_FILE,     PICK, NULL) \
    X(SCRIPT_ROLL,      ROLL, "1") \
    X(SCRIPT_YN,        PICK, "no") \
    X(SCRIPT_CHOICE,    PICK, "") \
    X(SCRIPT_MENU,      PICK, "") \
    X(PERK_CHARGES,     ROLL, "30")

enum CreationKey {
#define X(n,k,d) CK_##n,
    CREATION_KEY_LIST(X)
#undef X
    CK_COUNT
};

enum CreationKind { CKIND_ROLL, CKIND_PICK, CKIND_ITEM };

const char    *CreationKeyName(CreationKey k);   /* lower case: "attr_str" */
CreationKind   CreationKeyKind(CreationKey k);
const char    *CreationKeyDefault(CreationKey k);   /* the X-macro default ("" if NULL) */
bool           CreationKeyIsInput(CreationKey k);   /* false: observed, never stated */

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

    virtual void NoteRoll(CreationKey k, const CreationContext &c, int32 v) = 0;
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
void CreationNoteRoll(CreationKey k, const char *sub, int32 v);
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
    CreationNoteRoll(k, sub, v);
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
        CreationNoteRoll(k, subName(i), vals[i]);
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

#endif
