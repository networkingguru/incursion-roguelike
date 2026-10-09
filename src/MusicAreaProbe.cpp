/* inc-ctee: opt-in probe for Music of the Spheres area and durations. Off
   unless INCURSION_MUSIC_AREA_PROBE is set. Called from Game::Play
   (src/Main.cpp); graded by tools/check_music_spheres_area.sh. Output goes to
   errors.log through Error(), one MUSIC_AREA_PROBE line per fact. */
#include "Incursion.h"

static Monster *MakeKobold(Map *mp, rID id, Player *pl, int16 x, int16 y, bool foe) {
    mp->At(x, y).Lit = 1;
    Monster *mn = new Monster(id);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, x, y, true);
    mn->Initialize(true);
    mn->mHP = mn->cHP = 10000;
    if (foe) {
        mn->ts.addCreatureTarget(pl, TargetEnemy);
        pl->ts.addCreatureTarget(mn, TargetEnemy);
    }
    return mn;
}

void MusicAreaProbe(Player *pl) {
    if (!getenv("INCURSION_MUSIC_AREA_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("MUSIC_AREA_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID musicID = FIND("Music of the Spheres"), koboldID = FIND("kobold"),
        jackalID = FIND("jackal");
    if (!musicID || !koboldID || !jackalID) {
        Error("MUSIC_AREA_PROBE: INCONCLUSIVE -- missing resource");
        return;
    }
    extern void LOFSetForcedSaveThrowRoll(int8 r);
    extern void LOFClearForcedSaveThrowRoll();

    /* Essiah's condition (NAUSEA, evil targets) is the one whose duration
       reaches the stati intact: the plain-stun branch passes SS_ATTK as the
       duration (src/Fight.cpp AD_STUN), so the fixture's own god cannot show
       10+2*CL. The god is borrowed for the probe and restored at the end. */
    const rID savedGod = pl->GodID, essiahID = FIND("Essiah");
    if (!essiahID) {
        Error("MUSIC_AREA_PROBE: INCONCLUSIVE -- missing Essiah");
        return;
    }
    pl->GodID = essiahID;
    const int16 targ = MA_EVIL, condStati = NAUSEA;
    /* Straight orthogonal line: squares 1..9 all open floor. */
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    Map *mp = pl->m;
    int dir = -1;
    for (int k = 0; k < 4 && dir < 0; ++k) {
        bool ok = true;
        for (int d = 1; d <= 9 && ok; ++d) {
            const int16 x = pl->x + DX[k]*d, y = pl->y + DY[k]*d;
            ok = mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
        }
        if (ok) dir = k;
    }
    if (dir < 0) {
        Error("MUSIC_AREA_PROBE: INCONCLUSIVE -- no open 9-square orthogonal line");
        pl->GodID = savedGod;
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->GainAbility(CA_SPELLCASTING, 8 - pl->CasterLev(), 0, SS_PERM);
    const int16 cl = pl->CasterLev();

    /* Damage ends hypnotic paralysis (src/Fight.cpp), so the paralysis
       targets are jackals, which targ does not name. The kobold takes the
       damage and the condition. */
    const int dists[4] = {2, 3, 8, 9};
    Monster *t[4];
    for (int i = 0; i < 4; ++i)
        t[i] = MakeKobold(mp, i == 1 ? koboldID : jackalID, pl, pl->x + DX[dir]*dists[i], pl->y + DY[dir]*dists[i], true);
    /* The ally stands off the line, within 8 of the caster. */
    Monster *ally = NULL;
    for (int k = 0; k < 4 && !ally; ++k) {
        const int16 ax = pl->x + DX[k], ay = pl->y + DY[k]*1;
        if (k != dir && mp->InBounds(ax, ay) && !mp->SolidAt(ax, ay) && !mp->FCreatureAt(ax, ay))
            ally = MakeKobold(mp, koboldID, pl, ax, ay, false);
    }
    bool ready = ally && t[1]->ChallengeRating() <= 5 && t[1]->isMType(targ) && !t[0]->isMType(targ) &&
        !t[2]->isMType(targ) && !t[3]->isMType(targ);
    if (ready) {
        pl->ts.addCreatureTarget(ally, TargetAlly);
        ally->ts.addCreatureTarget(pl, TargetLeader);
        ready = ally->isFriendlyTo(pl) && pl->isFriendlyTo(ally);
    }
    for (int i = 0; i < 4; ++i)
        ready = ready && t[i]->isHostileTo(pl);
    if (!ready) {
        Error("MUSIC_AREA_PROBE: INCONCLUSIVE -- setup incomplete (ally, alignment or hostility)");
    } else {
        bool pass = true;
        for (int c = 0; c < 2; ++c) {
            const int choir = c ? 3 : 0;      /* a level-6 bard adds 6/2 */
            if (c)
                ally->GainPermStati(EXTRA_ABILITY, NULL, SS_PERM, CA_BARDIC_MUSIC, 6, 0);
            for (int i = 0; i < 4; ++i) {
                t[i]->RemoveStati(PARALYSIS);
                t[i]->RemoveStati(condStati);
            }
            EventInfo xe; xe.Clear();
            xe.EActor = pl; xe.ETarget = pl; xe.EVictim = pl;
            xe.EMap = mp; xe.eID = musicID; xe.isSpell = true;
            LOFSetForcedSaveThrowRoll(1);
            ReThrow(EV_EFFECT, xe);
            LOFClearForcedSaveThrowRoll();
            const int wantCond = 10 + 2*cl + 2*choir;
            for (int i = 0; i < 4; ++i) {
                const int para = t[i]->HasStati(PARALYSIS) ? 1 : 0;
                const int pdur = para ? t[i]->GetStatiDur(PARALYSIS) : 0;
                const int cond = t[i]->HasStati(condStati) ? 1 : 0;
                const int cdur = cond ? t[i]->GetStatiDur(condStati) : 0;
                Error("MUSIC_AREA_PROBE: choir=%d dist=%d para=%d paradur=%d cond=%d conddur=%d loss=%d",
                    choir, dists[i], para, pdur, cond, cdur, (int)(10000 - t[i]->cHP));
                if (dists[i] == 8) pass = pass && para == 1;
                if (dists[i] == 9) pass = pass && para == 0;
                if (para) pass = pass && pdur >= 1 && pdur <= 4;
                if (dists[i] == 2) pass = pass && para == 1;
                if (dists[i] == 3) {
                    /* Hit by both parts: damage and condition land first,
                       so the paralysis must survive them. loss > 0 keeps
                       this from passing without the damage. */
                    const bool both = para == 1 && pdur >= 1 && pdur <= 4 &&
                        10000 - t[i]->cHP > 0;
                    Error("MUSIC_AREA_PROBE: choir=%d kobold both=%d cr=%d hostile=%d",
                        choir, both ? 1 : 0, (int)t[i]->ChallengeRating(),
                        (int)t[i]->isHostileTo(pl));
                    pass = pass && both && cond == 1 && cdur == wantCond;
                }
            }
            Error("MUSIC_AREA_PROBE: choir=%d caster_lev=%d want_conddur=%d want_paradur=1..4",
                choir, (int)cl, wantCond);
        }
        if (pass) Error("MUSIC_AREA_PROBE: PASS");
        else Error("MUSIC_AREA_PROBE: FAIL -- see choir/dist lines above");
    }
    for (int i = 0; i < 4; ++i) t[i]->Remove(true);
    if (ally) ally->Remove(true);
    pl->GodID = savedGod;
    theGame->PlayMode = wasInPlay;
}
