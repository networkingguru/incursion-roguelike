/* CreationSource.h -- the one place every character-creation decision is made
   or replayed (bead inc-10v7f, phase 4; spec sections 1-2, amendments A6 and
   B18).

   A decision site in src/Create.cpp (or src/Skills.cpp for the craft-formula
   picks) wraps its draw or prompt in ONE of three primitives:

     SourcedRoll(key, live)        a number
     SourcedPick(key, list, live)  a choice among named candidates
     SourcedItem(key, item, live)  a generated item, as a complete description

   `live` is the code the site ran before this file existed. It runs, unchanged
   and in the same order, whenever the active source holds no answer. The
   active source is one of:

     Live    normal play. It answers nothing, so every site runs `live`, and it
             RECORDS what each site decided (into RInf for the gallery, and
             into a .char file when INCURSION_RECORD_CHAR=<path> is set).
     Replay  gallery reincarnation. It answers from RInf exactly what RInf
             holds; every other decision is NOT_RECORDED and the site acts as
             Live (spec A6).

   The File backend is phase 7 and does not exist yet.

   A key is an enum name plus a context the primitive fills in: the resource
   and event whose script is running (CreationScope), an optional `sub` name
   the site gives, and the ordinal of the decision in that (key, context)
   queue. The recorder writes `<key> [<context>]: <value>`. */
#ifndef CREATIONSOURCE_H
#define CREATIONSOURCE_H

#include <string>
#include <vector>

/* X(name, kind). Appending a decision is one line here plus the call site. */
#define CREATION_KEY_LIST(X) \
    X(ALTER_OPTIONS,    PICK) \
    X(EXPLORE_CONTINUE, PICK) \
    X(FORMULA_SEED,     ROLL) \
    X(GENDER,           PICK) \
    X(NAME,             PICK) \
    X(SURNAME,          PICK) \
    X(RACE,             PICK) \
    X(SUBRACE,          PICK) \
    X(CLASS,            PICK) \
    X(GOD,              PICK) \
    X(ALIGNMENT,        PICK) \
    X(PERSONALITY,      PICK) \
    X(DOMAIN,           PICK) \
    X(DOMAIN_POOL,      PICK) \
    X(CRAFT_FORMULA,    PICK) \
    X(LEVEL_CLASS,      PICK) \
    X(LEVEL_ATTR,       PICK) \
    X(ATTR_STR,         ROLL) \
    X(ATTR_DEX,         ROLL) \
    X(ATTR_CON,         ROLL) \
    X(ATTR_INT,         ROLL) \
    X(ATTR_WIS,         ROLL) \
    X(ATTR_CHA,         ROLL) \
    X(ATTR_LUC,         ROLL) \
    X(PERK_TYPE,        PICK) \
    X(PERK_FEAT,        PICK) \
    X(PERK_ABILITY,     PICK) \
    X(PERK_SPELL,       PICK) \
    X(PERK_RESIST,      PICK) \
    X(PERK_IMMUNE,      PICK) \
    X(PERK_ITEM,        ITEM) \
    X(SKILL_RANKS,      ROLL) \
    X(HP_ROLL,          ROLL) \
    X(MANA_ROLL,        ROLL) \
    X(STORE_SEED,       ROLL) \
    X(CHARACTER_NAME,   PICK) \
    X(WIZARD_MODE,      ROLL) \
    X(EXPLORE_MODE,     ROLL) \
    X(REROLLS,          ROLL) \
    X(REROLLED_PERKS,   ROLL) \
    X(STAT_METHOD,      ROLL) \
    X(GEAR_STREAM,      ROLL) \
    X(GEAR_CHANCE,      ROLL) \
    X(KIT_ITEM,         ITEM) \
    X(BEGINKIT_ITEM,    ITEM) \
    X(BEGINKIT_FOOD,    ROLL) \
    X(MISSILE_QUANTITY, ROLL) \
    X(THROWN_QUANTITY,  ROLL) \
    X(AMMO_QUANTITY,    ROLL) \
    X(ABANDON,          PICK) \
    X(ATTR_SET,         PICK) \
    X(POINTBUY_CONFIRM, PICK) \
    X(REROLL_CONFIRM,   PICK) \
    X(FEAT,             PICK) \
    X(SKILL_FOCUS,      PICK) \
    X(NATURAL_APTITUDE, PICK) \
    X(STUDY_AREA,       PICK) \
    X(SCHOOL_FOCUS,     PICK) \
    X(IMPCRIT_WEAPON,   PICK) \
    X(FEAT_WEAPON,      PICK) \
    X(EXOTIC_WEAPON,    PICK) \
    X(WEAPON_UNFIT_CONFIRM, PICK) \
    X(INHERENT_SPELL,   PICK) \
    X(LUCUBRATION_BOOK, PICK) \
    X(TATTOO,           PICK) \
    X(FAV_ENEMY,        PICK) \
    X(SPECIALIST_SCHOOL, PICK) \
    X(TRAIN_REPLACE,    PICK)

enum CreationKey {
#define X(n,k) CK_##n,
    CREATION_KEY_LIST(X)
#undef X
    CK_COUNT
};

enum CreationKind { CKIND_ROLL, CKIND_PICK, CKIND_ITEM };

const char    *CreationKeyName(CreationKey k);   /* lower case: "attr_str" */
CreationKind   CreationKeyKind(CreationKey k);

struct CreationContext {
    std::string resource;   /* resource whose script runs, or "" */
    int         event;      /* event whose script runs, or 0 */
    std::string sub;        /* the site's own qualifier, or "" */
    int         ordinal;    /* position in this (key, context) queue */
};

/* A script event that makes a sourced decision pushes its context here, so
   the primitives find it without any change at the decision site. */
struct CreationScope {
    CreationScope(const char *resource, int event);
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

/* A generated item, described completely (spec B2, B15). */
struct CreationItem {
    rID   iID, eID;
    int16 plus, bane;
    int16 q[8];
    int32 quantity, charges;
    std::vector<CreationStati> stati;
    CreationItem() : iID(0), eID(0), plus(0), bane(0), quantity(0), charges(0)
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
    /* RInf set-up, at the point Create used to test `reincarnate`. */
    virtual void BeginState(Player *p) = 0;
    /* Back-navigation: drop the response the abandon prompt recorded. */
    virtual void PopResponse(Player *p) = 0;
    /* End of a finished creation: Live writes the gallery entry and sets
       *slot; Replay refreshes the display. *slot stays -2 when unchanged. */
    virtual void Finish(Player *p, int16 *slot) = 0;

    virtual bool AnswerRoll(CreationKey k, const CreationContext &c, int32 &v) = 0;
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
    virtual void NoteItem(CreationKey k, const CreationContext &c,
        const CreationItem &it) = 0;
    /* Window close: Live writes the .char file when it is asked for. */
    virtual void Close(bool completed) = 0;
};

CreationSource *CreationSourceNow();
CreationSource *SetCreationSource(CreationSource *s);   /* returns the old */
CreationSource &CreationLiveSource();
CreationSource &CreationReplaySource();

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

/* The halves the primitives are built from. Answer returns false for
   NOT_RECORDED; a successful Answer or a Note advances the ordinal. */
bool CreationAnswerRoll(CreationKey k, const char *sub, int32 &v);
void CreationNoteRoll(CreationKey k, const char *sub, int32 v);
bool CreationAnswerPick(CreationKey k, const char *sub,
    const CreationPickList &list, int32 &value, std::string &text, bool &inList);
void CreationNotePick(CreationKey k, const char *sub, const std::string &text);
bool CreationAnswerItem(CreationKey k, const char *sub, CreationItem &it);
void CreationNoteItem(CreationKey k, const char *sub, const CreationItem &it);
/* The retained perk set: the one set the player kept from the five offered. */
bool CreationAnswerPerks(PerkSet &out);
void CreationNotePerks(const PerkSet &set);

template<class Live>
int32 SourcedRoll(CreationKey k, Live live, const char *sub = NULL)
{
    int32 v;
    if (CreationAnswerRoll(k, sub, v))
        return v;
    v = (int32)live();
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
    v = (int32)live();
    for (size_t i = 0; i != list.values.size(); i++)
        if (list.values[i] == v) {
            CreationNotePick(k, sub, list.names[i]);
            break;
        }
    return v;
}

/* `live` fills `io` with the item it generated. */
template<class Live>
void SourcedItem(CreationKey k, CreationItem &io, Live live, const char *sub = NULL)
{
    if (CreationAnswerItem(k, sub, io))
        return;
    {
        CreationItemDepth inside;
        live(io);
    }
    CreationNoteItem(k, sub, io);
}

#endif
