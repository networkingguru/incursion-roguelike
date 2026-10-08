/* inc-h22n probes: door generation, lock-picking and door kicking.
   Every entry point is a no-op unless its environment variable is set, and
   none changes play when it is unset. Callers: Map::MakeDoor (MakeLev.cpp),
   Creature::SkillCheck (Skills.cpp), Game::Play (Main.cpp). Readers:
   tools/check_door_lock_rate.sh, tools/check_door_pick_kick.sh. */
/* Character::SkillRanks is protected and the probe is a free function, so that
   one member is opened here rather than adding a probe method to Creature.h.
   This file is the only place that does it. */
#define protected public
#include "Incursion.h"
#undef protected

static bool probeOn(const char *name) {
    const char *s = getenv(name);
    return s && *s && strcmp(s, "0");
}

/* INCURSION_DOORGEN_PROBE=1: one line per random door placed by
   Map::MakeDoor, after the generator is finished with it:
     DOORGEN depth=D flags=0xFF
   to logs/doorgen.log. */
void DoorGenProbe(Map *m, Door *d) {
    static int on = -1;
    if (on < 0) on = probeOn("INCURSION_DOORGEN_PROBE") ? 1 : 0;
    if (!on || !m || !d) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/doorgen.log",
        (const char*)T1->IncursionDirectory);
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "DOORGEN depth=%d flags=0x%02x\n", (int)m->Depth,
        (unsigned)(unsigned char)d->DoorFlags);
    fclose(f);
}

/* INCURSION_DOORPICK_PROBE=1: drives the real open-door, pick-chest-lock and
   kick-door event paths on a door and a chest it places beside the player,
   and writes one line per case to logs/doorpick.log:
     <CASE> key=value ...
   Cases and keys are read by tools/check_door_pick_kick.sh, which says what
   each must hold. Nothing here advances game time or runs without the
   variable; the session it runs in is a throwaway test session. */
static int  gChecks, gLastDC, gModBad;
static int  gDC[64];
static bool gProbeOn() {
    static int on = -1;
    if (on < 0) on = probeOn("INCURSION_DOORPICK_PROBE") ? 1 : 0;
    return on != 0;
}
void LockPickCheckNote(int16 DC, int16 mod1) {
    if (!gProbeOn()) return;
    if (gChecks < 64) gDC[gChecks] = DC;
    gChecks++;
    gLastDC = DC;
    if (mod1 != 0) gModBad++;
}
static void noteReset() { gChecks = gLastDC = gModBad = 0; }

static FILE *gLog;
static void L(const char *fmt, ...) {
    if (!gLog) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(gLog, fmt, ap);
    va_end(ap);
    fputc('\n', gLog);
    fflush(gLog);
}
static void dcList(char *out, size_t n) {
    out[0] = 0;
    for (int i = 0; i < gChecks && i < 16; i++) {
        char b[16]; snprintf(b, sizeof b, "%s%d", i ? "," : "", gDC[i]);
        strncat(out, b, n - strlen(out) - 1);
    }
    if (!out[0]) strcpy(out, "-");
}

static bool freeSq(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FFeatureAt(x, y)
        && !mp->FCreatureAt(x, y);
}

/* inc-e3oo: intercept only the selected spell, before prompts or effects.
   Kick notes leave the real kick event running. Active only within a case. */
static Player *autoPlayer;
static Door *autoDoor;
static rID autoSpell;
static int autoKicks, autoAttempts;
bool AutoKnockProbeNote(Creature *actor, Thing *target, rID spell) {
    if (!probeOn("INCURSION_AUTOKNOCK_PROBE") || !autoPlayer ||
        actor != autoPlayer || target != autoDoor) return false;
    if (spell) { autoSpell = spell; ++autoAttempts; }
    else ++autoKicks;
    return spell != 0;
}

static void autoKnockCases(Player *pl, Door *door) {
    uint16 saved[MAX_SPELLS+1];
    memcpy(saved, pl->Spells, sizeof saved);
    const int8 knock = pl->Options[OPT_AUTOKNOCK], all = pl->Options[OPT_ALL_SPELLS];
    const int timeout = pl->Timeout;
    pl->Options[OPT_AUTOKNOCK] = 1;
    pl->Options[OPT_ALL_SPELLS] = 0;
    const char *names[] = {"levitation", "levitation-innate", "wizard-lock",
                          "knock", "warp-wood", "levitation-knock", "none"};
    rID lev = FIND("Levitation"), lock = FIND("Wizard Lock"),
        knockID = FIND("Knock"), wood = FIND("Warp Wood");
    if (!lev || !lock || !knockID || !wood) {
        L("INCONCLUSIVE reason=missing-spells");
    } else for (int c = 0; c < 7; ++c) {
        memset(pl->Spells, 0, sizeof pl->Spells);
        rID spell = c < 2 || c == 5 ? lev : c == 2 ? lock :
                    c == 3 ? knockID : c == 4 ? wood : 0;
        if (spell) pl->setSpellFlags(spell, c == 1 ? SP_INNATE : SP_KNOWN | SP_ARCANE);
        if (c == 5) pl->setSpellFlags(knockID, SP_KNOWN | SP_ARCANE);
        bool eligible = true;
        for (int i = 0; i < theGame->LastSpell(); ++i)
            if ((pl->Spells[i] != 0) != (pl->SpellRating(theGame->SpellID(i),0,true) != -1))
                eligible = false;
        door->DoorFlags = DF_LOCKED;
        door->Flags |= F_SOLID;
        door->cHP = door->mHP = TFEAT(door->fID)->hp;
        door->SetImage();
        pl->RemoveStati(ACTING);
        pl->Timeout = 0;
        autoPlayer = pl; autoDoor = door;
        autoSpell = 0; autoKicks = autoAttempts = 0;
        pl->TryToDestroyThing(door);
        autoPlayer = NULL; autoDoor = NULL;
        const char *selected = !autoSpell ? "none" : autoSpell == lev ? "levitation" :
            autoSpell == lock ? "wizard-lock" : autoSpell == knockID ? "knock" :
            autoSpell == wood ? "warp-wood" : "unexpected";
        L("AUTO case=%s eligible=%d spell=%s attempts=%d kicks=%d timeout=%d",
          names[c], eligible, selected, autoAttempts, autoKicks, (int)pl->Timeout);
        pl->RemoveStati(ACTING);
    }
    memcpy(pl->Spells, saved, sizeof saved);
    pl->Options[OPT_AUTOKNOCK] = knock; pl->Options[OPT_ALL_SPELLS] = all;
    pl->Timeout = timeout;
}

void DoorPickProbe(Player *pl) {
    const bool autoMode = probeOn("INCURSION_AUTOKNOCK_PROBE");
    if (!gProbeOn() && !autoMode) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/%s",
        (const char*)T1->IncursionDirectory, autoMode ? "autoknock.log" : "doorpick.log");
    gLog = fopen(path, "a");
    if (!gLog) return;
    if (!pl || !pl->m) { L("INCONCLUSIVE reason=no-live-player-or-map"); fclose(gLog); return; }
    Map *mp = pl->m;
    const rID oak = FIND("oak door"), chestID = FIND("large oak chest");
    if (!oak || !chestID) { L("INCONCLUSIVE reason=missing-resources"); fclose(gLog); return; }

    /* A door square beside the player, with solid walls either side so that
       Door::SetImage reads a frame and does not brand the door broken. */
    int dx = 0, dy = 0, X = -1, Y = -1;
    static const int dirs[4][2] = { {1,0}, {-1,0}, {0,1}, {0,-1} };
    for (int k = 0; k < 4 && X < 0; k++) {
        int x = pl->x + dirs[k][0], y = pl->y + dirs[k][1];
        int fx1 = x + dirs[k][1], fy1 = y + dirs[k][0];
        int fx2 = x - dirs[k][1], fy2 = y - dirs[k][0];
        if (!freeSq(mp, x, y) || !mp->InBounds(fx1, fy1) || !mp->InBounds(fx2, fy2)
            || mp->FCreatureAt(fx1, fy1) || mp->FCreatureAt(fx2, fy2)) continue;
        X = x; Y = y; dx = dirs[k][0]; dy = dirs[k][1];
        mp->At(fx1, fy1).Solid = mp->At(fx2, fy2).Solid = true;
        mp->At(fx1, fy1).Opaque = mp->At(fx2, fy2).Opaque = true;
    }
    int CX = -1, CY = -1;
    for (int ax = -1; ax <= 1 && CX < 0; ax++)
        for (int ay = -1; ay <= 1 && CX < 0; ay++)
            if ((ax || ay) && freeSq(mp, pl->x + ax, pl->y + ay)
                && !(pl->x + ax == X && pl->y + ay == Y)) {
                CX = pl->x + ax; CY = pl->y + ay;
            }
    if (X < 0 || CX < 0) { L("INCONCLUSIVE reason=no-free-squares"); fclose(gLog); return; }

    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const int8 o_open = pl->Options[OPT_AUTOOPEN], o_kick = pl->Options[OPT_AUTOKICK],
               o_rep = pl->Options[OPT_REPEAT_KICK], o_more = pl->Options[OPT_AUTOMORE];
    pl->Options[OPT_AUTOOPEN] = 1;   /* no "Pick the lock?" prompt */
    pl->Options[OPT_AUTOKICK] = 0;   /* a failed pick does not fall into a kick */
    pl->Options[OPT_REPEAT_KICK] = 1;
    pl->Options[OPT_AUTOMORE] = 1;   /* a --more-- prompt would wait for a key */
    const int8 o_ranks = pl->SkillRanks[SK_LOCKPICKING];
    const int depth = mp->Depth;
    L("RIG depth=%d str=%d size=%d std=%d", depth, (int)pl->Attr[A_STR],
        (int)pl->GetAttr(A_SIZ), 3000 / max(100 + pl->Attr[A_SPD_MELEE] * 5, 10));

    /* The chest also serves as the "caster" of every wizard lock: a Thing that
       is not the player, so HasStati(WIZLOCK,-1,player) reads false. */
    Container *chest = (Container*)Item::Create(chestID);
    chest->PlaceAt(mp, CX, CY);
    Door *door = NULL;
    auto newDoor = [&](rID fid) {
        if (door) door->Remove(true);
        door = new Door(fid);
        door->PlaceAt(mp, X, Y);
        door->SetImage();
    };
    /* Close the door and lock it (optionally wizard-locked by nobody the
       player knows), clear every attempt record, and restore its hit points. */
    auto arm = [&](bool wiz) {
        door->RemoveStati(WIZLOCK); door->RemoveStati(TRIED); door->RemoveStati(RETRY_BONUS);
        door->DoorFlags = DF_LOCKED;
        door->Flags |= F_SOLID;
        door->cHP = door->mHP = TFEAT(door->fID)->hp;
        if (wiz) door->GainPermStati(WIZLOCK, chest, SS_MISC, 0, 0);
        door->SetImage();
        if (!(door->DoorFlags & DF_LOCKED)) door->DoorFlags |= DF_LOCKED;
        pl->RemoveStati(ACTING); pl->RemoveStati(RETRY_BONUS); pl->RemoveStati(TRIED);
    };
    auto armChest = [&](bool wiz) {
        chest->RemoveStati(WIZLOCK); chest->RemoveStati(LOCKED); chest->RemoveStati(TRIED);
        chest->RemoveStati(RETRY_BONUS);
        chest->GainPermStati(LOCKED, chest, SS_MISC);
        if (wiz) chest->GainPermStati(WIZLOCK, chest, SS_MISC, 0, 0);
        pl->RemoveStati(RETRY_BONUS); pl->RemoveStati(TRIED);
    };
    auto setRanks = [&](int r) { pl->SkillRanks[SK_LOCKPICKING] = r; pl->CalcValues(); };
    auto openDoor = [&]() { pl->Timeout = 0; return Throw(EV_OPEN, pl, door); };
    auto pickChest = [&]() {
        EventInfo e; e.Clear(); e.EActor = pl; pl->Timeout = 0;
        return chest->PickLock(e);
    };
    char dcs[256];

    newDoor(oak);
    if (autoMode) {
        mp->At(X,Y).Lit = 1;
        pl->CalcVision();
        autoKnockCases(pl, door);
        door->Remove(true); chest->Remove(true);
        pl->Options[OPT_AUTOOPEN] = o_open; pl->Options[OPT_AUTOKICK] = o_kick;
        pl->Options[OPT_REPEAT_KICK] = o_rep; pl->Options[OPT_AUTOMORE] = o_more;
        theGame->PlayMode = wasInPlay;
        L("DONE"); fclose(gLog); gLog = NULL;
        return;
    }

    /* ---- lock-picking: doors ------------------------------------------ */
    setRanks(0);
    arm(false); noteReset(); openDoor();
    L("PICK door-untrained sr=%d checks=%d locked=%d", (int)pl->SkillLevel(SK_LOCKPICKING),
        gChecks, !!(door->DoorFlags & DF_LOCKED));

    setRanks(1);
    arm(false); noteReset(); openDoor();
    dcList(dcs, sizeof dcs);
    L("PICK door-trained sr=%d depth=%d checks=%d dcs=%s modbad=%d timeout=%d",
        (int)pl->SkillLevel(SK_LOCKPICKING), depth, gChecks, dcs, gModBad, (int)pl->Timeout);

    /* wizard-locked: DC is too high for rank 1, so every attempt fails. Three
       attempts in a row with no rest between them. */
    arm(true); noteReset();
    for (int i = 0; i < 3; i++) openDoor();
    dcList(dcs, sizeof dcs);
    L("PICK door-retry sr=%d depth=%d checks=%d dcs=%s modbad=%d locked=%d",
        (int)pl->SkillLevel(SK_LOCKPICKING), depth, gChecks, dcs, gModBad,
        !!(door->DoorFlags & DF_LOCKED));

    /* the same, out of combat, as ONE command: does the failure repeat itself? */
    arm(true); noteReset(); openDoor();
    const int first = gChecks;
    const bool acting = pl->HasStati(ACTING);
    for (int i = 0; i < 30 && pl->HasStati(ACTING) && gChecks < 15; i++) {
        pl->Timeout = 0; pl->ExtendedAction();
    }
    L("PICK door-repeat threatened=%d first=%d acting=%d total=%d", (int)pl->isThreatened(),
        first, (int)acting, gChecks);
    pl->RemoveStati(ACTING);

    setRanks(60);
    arm(false); noteReset(); openDoor();
    L("PICK door-skilled checks=%d locked=%d open=%d", gChecks,
        !!(door->DoorFlags & DF_LOCKED), !!(door->DoorFlags & DF_OPEN));

    /* ---- lock-picking: chests ------------------------------------------ */
    setRanks(0);
    armChest(false); noteReset(); pickChest();
    L("PICK chest-untrained checks=%d locked=%d", gChecks, (int)chest->HasStati(LOCKED));

    setRanks(1);
    armChest(false); noteReset(); pickChest();
    dcList(dcs, sizeof dcs);
    L("PICK chest-trained depth=%d checks=%d dcs=%s modbad=%d timeout=%d", depth,
        gChecks, dcs, gModBad, (int)pl->Timeout);

    armChest(true); noteReset();
    for (int i = 0; i < 3; i++) pickChest();
    dcList(dcs, sizeof dcs);
    L("PICK chest-retry depth=%d checks=%d dcs=%s modbad=%d locked=%d", depth,
        gChecks, dcs, gModBad, (int)chest->HasStati(LOCKED));

    setRanks(60);
    armChest(false); noteReset(); pickChest();
    L("PICK chest-skilled checks=%d locked=%d", gChecks, (int)chest->HasStati(LOCKED));
    setRanks(o_ranks);

    /* ---- kicking -------------------------------------------------------- */
    const int N = 400;
    const int origSize = pl->Attr[A_SIZ];
    auto kicks = [&](const char *label, int str, int size, bool wiz, int hpOverride) {
        int broke = 0, hpLost = 0, actingOnFail = 0, fails = 0, toFail = -1;
        for (int i = 0; i < N; i++) {
            PurgeStrings();  /* event strings queue until the next redraw */
            arm(wiz);
            if (hpOverride > 0) door->cHP = hpOverride;
            const int pre = door->cHP;
            pl->Attr[A_STR] = str; pl->Attr[A_SIZ] = size;
            pl->Timeout = 0;
            ThrowVal(EV_SATTACK, A_KICK, pl, door);
            if (door->DoorFlags & DF_BROKEN) { broke++; continue; }
            fails++;
            if (door->cHP < pre) hpLost++;
            if (pl->HasStati(ACTING)) actingOnFail++;
            if (toFail < 0) toFail = pl->Timeout;
        }
        pl->RemoveStati(ACTING);
        L("KICK label=%s feat=\"%s\" str=%d size=%d wiz=%d hp=%d n=%d broke=%d fails=%d "
          "hplost=%d acting=%d timeout=%d std=%d", label, (const char*)NAME(door->fID),
          str, size, (int)wiz, hpOverride, N, broke, fails, hpLost, actingOnFail, toFail,
          3000 / max(100 + pl->Attr[A_SPD_MELEE] * 5, 10));
    };
    newDoor(oak);
    kicks("base", 10, SZ_MEDIUM, false, 0);
    kicks("str18", 18, SZ_MEDIUM, false, 0);
    kicks("large", 10, SZ_LARGE, false, 0);
    kicks("small", 20, SZ_SMALL, false, 0);
    kicks("wizlock", 30, SZ_MEDIUM, true, 0);
    kicks("halfhp", 10, SZ_MEDIUM, false, 4);
    /* every door feature in the module, at two strengths */
    Module *mod = theGame->Modules[0];
    for (int i = 1; i < mod->szFea; i++) {
        rID fid = mod->FeatureID(i);
        if (TFEAT(fid)->FType != T_DOOR) continue;
        newDoor(fid);
        kicks("table20", 20, SZ_MEDIUM, false, 0);
        kicks("table40", 40, SZ_MEDIUM, false, 0);
    }
    pl->Attr[A_SIZ] = origSize;

    /* ---- repeated kicks: no limit, no resting -------------------------- */
    newDoor(FIND("vault door"));
    arm(false);
    int executed = 0;
    for (int i = 0; i < 60; i++) {
        PurgeStrings();
        pl->Attr[A_STR] = 10; pl->Timeout = 0;
        pl->RemoveStati(ACTING);   /* each kick is a new command */
        ThrowVal(EV_SATTACK, A_KICK, pl, door);
        if (pl->Timeout > 0) executed++;
    }
    pl->RemoveStati(ACTING);
    L("KICKRETRY n=60 executed=%d", executed);

    /* ---- weapon damage to a door: the door's own hardness arithmetic ---- */
    newDoor(oak);
    auto strike = [&](const char *label, const char *wname, int dtype, bool wiz) {
        Item *w = Item::Create(FIND(wname));
        arm(wiz);
        door->cHP = door->mHP = 1000;
        EventInfo e; e.Clear();
        e.Event = EV_DAMAGE; e.EActor = pl; e.EPActor = pl; e.ETarget = door;
        e.EMap = mp; e.EItem = w; e.AType = A_SWNG; e.DType = dtype; e.vDmg = 30;
        door->Event(e);
        L("AXE label=%s item=\"%s\" vdmg=30 hard=%d loss=%d", label, wname,
            (int)MaterialHardness(TFEAT(door->fID)->Material, dtype), 1000 - (int)door->cHP);
        delete w;
    };
    strike("axe", "battleaxe", AD_SLASH, false);
    strike("sword", "long sword", AD_SLASH, false);
    strike("blunt", "light mace", AD_BLUNT, false);
    strike("blunt-wiz", "light mace", AD_BLUNT, true);
    strike("axe-wiz", "battleaxe", AD_SLASH, true);

    /* ---- in combat: one attempt per command ----------------------------- */
    newDoor(oak);
    const rID kob = FIND("kobold");
    Monster *k = NULL;
    for (int ax = -2; ax <= 2 && !k; ax++)
        for (int ay = -2; ay <= 2 && !k; ay++) {
            int x = pl->x + ax, y = pl->y + ay;
            if ((ax || ay) && freeSq(mp, x, y) && !(x == CX && y == CY)) {
                k = new Monster(kob);
                TMON(kob)->GrantGear(k, kob, true);
                TMON(kob)->PEvent(EV_BIRTH, k, kob);
                k->PlaceAt(mp, x, y, true);
                k->Initialize(true);
                mp->At(x, y).Lit = 1;
            }
        }
    pl->CalcValues();
    setRanks(1);
    arm(true); noteReset(); openDoor();
    const int c1 = gChecks; const bool act1 = pl->HasStati(ACTING);
    openDoor();
    L("PICK door-combat threatened=%d first=%d acting=%d after2=%d", (int)pl->isThreatened(),
        c1, (int)act1, gChecks);
    pl->RemoveStati(ACTING);
    setRanks(o_ranks);
    if (k) k->Remove(true);
    if (door) door->Remove(true);
    chest->Remove(true);
    pl->Timeout = 0;

    pl->Options[OPT_AUTOOPEN] = o_open; pl->Options[OPT_AUTOKICK] = o_kick;
    pl->Options[OPT_REPEAT_KICK] = o_rep; pl->Options[OPT_AUTOMORE] = o_more;
    theGame->PlayMode = wasInPlay;
    L("DONE");
    fclose(gLog);
    gLog = NULL;
}
