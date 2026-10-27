/* inc-4trf: opt-in monster-feat observation probe. Off unless
   INCURSION_MONSTER_FEAT_PROBE is set. Called from Game::Play (src/Main.cpp);
   read by tools/check_monster_feats_live.sh. Builds each named monster from
   its template on the player's map, calls CalcValues, and logs one
   MONSTER_FEAT line per monster to errors.log via Error(). */
#include "Incursion.h"

static Map *probeMap;
static Player *probePl;

/* Build a monster from a template name and place it on the player's map. */
static Monster *make_feat_monster(const char *name, int dx) {
    rID rid = FIND(name);
    if (!rid || RES(rid)->Type != T_TMONSTER) {
        Error("MONSTER_FEAT INCONCLUSIVE monster=%s missing=%d", name, (int)rid);
        return NULL;
    }
    int16 tx = -1, ty = -1;
    for (int d = 2; d <= 8 && tx < 0; ++d)
        for (int ddx = -d; ddx <= d && tx < 0; ++ddx)
            for (int ddy = -d; ddy <= d && tx < 0; ++ddy) {
                const int16 nx = probePl->x + ddx, ny = probePl->y + ddy;
                if (!probeMap->InBounds(nx, ny) || probeMap->SolidAt(nx, ny)) continue;
                if (probeMap->FCreatureAt(nx, ny)) continue;
                tx = nx; ty = ny;
            }
    if (tx < 0) {
        Error("MONSTER_FEAT INCONCLUSIVE monster=%s no_open_floor", name);
        return NULL;
    }
    Monster *mn = new Monster(rid);
    mn->CalcValues();
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(probeMap, tx, ty, true);
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(false);
    theGame->PlayMode = wasInPlay;
    (void)dx;
    return mn;
}

/* Copy a 16-entry feat list into saved, then remove ft from it. The list is
   zero-terminated, so the survivors are packed to the front. feats is a
   TMonster's Feats or a TTemplate's NewFeats, both uint16[16]. */
static void feats_without(uint16 *feats, int16 ft, uint16 saved[16]) {
    memcpy(saved, feats, 16 * sizeof(uint16));
    int j = 0;
    for (int i = 0; i < 16; ++i)
        if (feats[i] != (uint16)ft)
            feats[j++] = feats[i];
    for (; j < 16; ++j)
        feats[j] = 0;
}

static void log_feat_monster(const char *tag, const char *name, Monster *mn) {
    if (!mn) return;
    mn->CalcValues();
    /* focus = the BONUS_SKILL cell on A_HIT_BRAWL: 1 when Weapon Focus landed. */
    /* wep = a weapon in SL_WEAPON; melee = Creature::meleeWep set by CalcValues. */
    Error("MONSTER_FEAT name=%s tag=%s dash=%d mov=%d hit_brawl=%d focus=%d wep=%d melee=%d tracking=%d finesse=%d",
        name, tag, (int)mn->HasFeat(FT_DASH), (int)mn->Attr[A_MOV],
        (int)mn->Attr[A_HIT_BRAWL], (int)mn->AttrAdj[A_HIT_BRAWL][BONUS_SKILL],
        (int)(mn->InSlot(SL_WEAPON) != NULL), (int)(Creature::meleeWep != NULL),
        (int)mn->AbilityLevel(CA_TRACKING), (int)mn->HasFeat(FT_WEAPON_FINESSE));
}

/* A square beside the player that is open floor. */
static bool find_beside_pl(int16 *ox, int16 *oy) {
    static const int dirs[8][2] = { {1,0},{-1,0},{0,1},{0,-1},
                                    {1,1},{1,-1},{-1,1},{-1,-1} };
    for (int k = 0; k < 8; ++k) {
        int16 nx = probePl->x + dirs[k][0], ny = probePl->y + dirs[k][1];
        if (!probeMap->InBounds(nx, ny) || probeMap->SolidAt(nx, ny)) continue;
        if (probeMap->FCreatureAt(nx, ny)) continue;
        *ox = nx; *oy = ny; return true;
    }
    return false;
}

/* Build a monster from a template name, optionally under a template, beside
   the player. Used for the Great Blow adjacency and the vampire Persuasive. */
static Monster *make_monster_beside(const char *name, const char *tname) {
    rID rid = FIND(name);
    if (!rid || RES(rid)->Type != T_TMONSTER) {
        Error("MONSTER_FEAT INCONCLUSIVE monster=%s missing=%d", name, (int)rid);
        return NULL;
    }
    int16 tx = -1, ty = -1;
    if (!find_beside_pl(&tx, &ty)) {
        Error("MONSTER_FEAT INCONCLUSIVE monster=%s no_square_beside_player", name);
        return NULL;
    }
    Monster *mn = new Monster(rid);
    mn->CalcValues();
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    if (tname) {
        rID tid = FIND(tname);
        if (tid && RES(tid)->Type == T_TTEMPLATE)
            mn->AddTemplate(tid);
    }
    mn->PlaceAt(probeMap, tx, ty, true);
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(false);
    theGame->PlayMode = wasInPlay;
    return mn;
}

/* A free square beside an arbitrary creature. */
static bool find_beside_creature(Creature *c, int16 *ox, int16 *oy) {
    static const int dirs[8][2] = { {1,0},{-1,0},{0,1},{0,-1},
                                    {1,1},{1,-1},{-1,1},{-1,-1} };
    for (int k = 0; k < 8; ++k) {
        int16 nx = c->x + dirs[k][0], ny = c->y + dirs[k][1];
        if (!probeMap->InBounds(nx, ny) || probeMap->SolidAt(nx, ny)) continue;
        /* ponytail: a SZ_HUGE actor's footprint makes FCreatureAt return the actor
           on every square it covers, so only another creature blocks a square. */
        Creature *occ = probeMap->FCreatureAt(nx, ny);
        if (occ && occ != c) continue;
        *ox = nx; *oy = ny; return true;
    }
    return false;
}

/* Build a plain victim monster beside the actor, so the great blow resolves on
   a creature that is not the player (a probe must not kill the character). */
static Monster *make_victim_beside(Monster *actor) {
    rID rid = FIND("human");
    if (!rid || RES(rid)->Type != T_TMONSTER) {
        Error("MONSTER_FEAT INCONCLUSIVE victim=human missing=%d", (int)rid);
        return NULL;
    }
    int16 tx = -1, ty = -1;
    if (!find_beside_creature(actor, &tx, &ty)) {
        Error("MONSTER_FEAT INCONCLUSIVE victim=human no_square_beside_actor");
        return NULL;
    }
    Monster *mn = new Monster(rid);
    mn->CalcValues();
    mn->PlaceAt(probeMap, tx, ty, true);
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(false);
    theGame->PlayMode = wasInPlay;
    return mn;
}

/* Persuasive observation: log Bluff and Intimidate. */
static void log_skill_monster(const char *tag, const char *name, Monster *mn) {
    if (!mn) return;
    mn->CalcValues();
    Error("MONSTER_FEAT_SKILL name=%s tag=%s persuasive=%d bluff=%d intimidate=%d",
        name, tag, (int)mn->HasFeat(FT_PERSUASIVE),
        (int)mn->SkillLevel(SK_BLUFF), (int)mn->SkillLevel(SK_INTIMIDATE));
}

/* Great Blow observation. Places a fresh monster beside the player, optionally
   forces the AI's 25% roll with INCURSION_GREAT_BLOW_FORCE, calls the real
   action selection, reports whether ACT_SATTACK/A_GREA was offered, then
   directly resolves A_GREA and reports whether the maneuver ran (the actor
   gains EXPOSED, src/Fight.cpp A_GREA). */
static void log_great_blow(const char *tag, const char *name, Monster *mn) {
    if (!mn) return;
    mn->Timeout = 0;
    mn->RemoveStati(EXPOSED);
    mn->ChooseAction();
    int offered = mn->OfferedSpecial(ACT_SATTACK, A_GREA) ? 1 : 0;
    /* Resolve A_GREA directly, whether or not the weighted pick chose it, on a
       victim beside the actor -- never the player, whom a probe must not kill. */
    mn->Timeout = 0;
    mn->RemoveStati(EXPOSED);
    Monster *victim = make_victim_beside(mn);
    if (victim)
        ThrowVal(EV_SATTACK, A_GREA, mn, (Thing *)victim);
    int resolved = mn->HasStati(EXPOSED) ? 1 : 0;
    Error("MONSTER_FEAT_GREATBLOW name=%s tag=%s offered=%d resolved=%d "
        "feat=%d wep=%d natattk=%d",
        name, tag, offered, resolved, (int)mn->HasFeat(FT_GREAT_BLOW),
        (int)(mn->InSlot(SL_WEAPON) != NULL),
        (int)(TMON(mn->tmID)->Attk[0].AType != 0));
}

void MonsterFeatProbe(Player *pl) {
    if (!getenv("INCURSION_MONSTER_FEAT_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("MONSTER_FEAT INCONCLUSIVE no live player and map");
        return;
    }
    probeMap = pl->m;
    probePl = pl;
    static const char *names[] = {
        "cheetah", "juvenile arrowhawk", "plague of rats", "scarab swarm",
        "cave tyrannosaurus", "medium fire elemental", "water genasi", NULL };
    for (int i = 0; names[i]; ++i)
        log_feat_monster("base", names[i], make_feat_monster(names[i], 0));

    /* Control: a monster that HAS FT_WEAPON_FOCUS and hands, first unwielded
       (natural attacks get the +1) and then with a wielded melee weapon (the
       +1 must NOT land on A_HIT_BRAWL). The cave tyrannosaurus named in the
       brief cannot wield: M_NOHANDS makes TMonster::HasSlot(SL_WEAPON) false,
       so Monster::InSlot always returns NULL and meleeWep stays NULL. The
       bugbear (lib/mon2.irh, which A_SEEMs as "hobgoblin") carries FT_WEAPON_FOCUS and has hands. */
    Monster *hob = make_feat_monster("bugbear", 0);
    if (hob) {
        Item *held = hob->InSlot(SL_WEAPON);
        if (held) {
            EventInfo t; t.Clear();
            t.EActor = hob; t.EItem = held; t.EParam = SL_WEAPON;
            hob->TakeOff(t);
        }
        log_feat_monster("control-unwielded", "bugbear", hob);
        if (held) {
            EventInfo w; w.Clear();
            w.EActor = hob; w.EItem = held; w.EParam = SL_WEAPON;
            hob->Wield(w);
        }
        log_feat_monster("control-wielded", "bugbear", hob);
    }

    /* Counterfactual: drop one feat from the template's feat list, log, then
       restore the saved list. Off then on, same creature. */
    static const char *dash[] = {
        "cheetah", "juvenile arrowhawk", "plague of rats", "scarab swarm", NULL };
    for (int i = 0; dash[i]; ++i) {
        Monster *mn = make_feat_monster(dash[i], 0);
        if (!mn) continue;
        TMonster *t = TMON(mn->tmID);
        uint16 saved[16];
        feats_without(t->Feats, FT_DASH, saved);
        log_feat_monster("dash-off", dash[i], mn);
        memcpy(t->Feats, saved, sizeof saved);
        log_feat_monster("dash-on", dash[i], mn);
    }
    Monster *tyr = make_feat_monster("cave tyrannosaurus", 0);
    if (tyr) {
        TMonster *t = TMON(tyr->tmID);
        uint16 saved[16];
        feats_without(t->Feats, FT_WEAPON_FOCUS, saved);
        log_feat_monster("focus-off", "cave tyrannosaurus", tyr);
        memcpy(t->Feats, saved, sizeof saved);
        log_feat_monster("focus-on", "cave tyrannosaurus", tyr);
    }

    /* inc-4trf phase B1: Persuasive (FT_PERSUASIVE) gives +2 to Bluff and
       Intimidate. The feat is listed on the "vampire" template (lib/mon3.irh:4450),
       so build a human under it. Creature::HasFeat reads the feat from the
       template's NewFeats (via the TEMPLATE stati) and from the EXTRA_FEAT
       stati AddTemplate made, so "off" drops it from both and "on" restores
       both -- the template, its racial skills and all else stay in place, so
       the only difference between off and on is the feat. */
    {
        Monster *vamp = make_monster_beside("human", "vampire");
        if (vamp) {
            TTemplate *vt = TTEM(FIND("vampire"));
            uint16 saved[16];
            feats_without(vt->NewFeats, FT_PERSUASIVE, saved);
            vamp->RemoveStati(EXTRA_FEAT, -1, FT_PERSUASIVE);
            log_skill_monster("persuasive-off", "vampire human", vamp);
            memcpy(vt->NewFeats, saved, sizeof saved);
            /* Grant the EXTRA_FEAT copy only while the template still lists the
               feat, as AddTemplate does, so a template edit reaches "on" too. */
            bool listed = false;
            for (int i = 0; i < 16; ++i)
                if (vt->NewFeats[i] == FT_PERSUASIVE) listed = true;
            if (listed)
                vamp->GainPermStati(EXTRA_FEAT, NULL, SS_MISC, FT_PERSUASIVE, 1,
                    FIND("vampire"));
            log_skill_monster("persuasive-on", "vampire human", vamp);
        }
    }

    /* inc-4trf phase B1: Great Blow (FT_GREAT_BLOW). Murgash and the
       malebranche list it. Stage the monster beside the player, force the AI's
       25% roll (INCURSION_GREAT_BLOW_FORCE), and report whether the chosen
       action list offers ACT_SATTACK/A_GREA and whether it resolves. */
    static const char *gb[] = { "Murgash, the Goblin King", "malebranche", NULL };
    for (int i = 0; gb[i]; ++i) {
        Error("MONSTER_FEAT_GREATBLOW enter name=%s", gb[i]);
        Monster *mn = make_monster_beside(gb[i], NULL);
        if (!mn) continue;
        TMonster *t = TMON(mn->tmID);
        uint16 saved[16];
        feats_without(t->Feats, FT_GREAT_BLOW, saved);
        log_great_blow("greatblow-off", gb[i], mn);
        memcpy(t->Feats, saved, sizeof saved);
        log_great_blow("greatblow-on", gb[i], mn);
    }
    Error("MONSTER_FEAT DONE");
}