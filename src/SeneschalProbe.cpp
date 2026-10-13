/* inc-e46n phase 5a: opt-in oracle for the Seneschal follower ladder
   (Player::PoolOf, Monster::PoolRefuses/SeneschalQualifies/SeneschalKill/
   SeneschalPromote). Off unless INCURSION_SENESCHAL_PROBE is set. It holds
   no rule of its own: it builds followers, sets the leader's SK_SENESCHAL
   rating and the follower's SENESCHAL_TALLY, calls the real functions, and
   logs what they did to <IncursionDirectory>logs/seneschal.log. A later
   phase writes the check script that asserts these lines. */
#include "Incursion.h"

static FILE *snLog;

static const char *Rungs[] = { "skilled", "experienced", "veteran", "elite",
    "master", "paragon", "legendary", NULL };

/* Highest ladder template the creature carries, or "none". */
static const char *rungOf(Monster *mn) {
    const char *r = "none";
    for (int i = 0; Rungs[i]; i++) {
        rID id = FIND(Rungs[i]);
        if (id && mn->HasEffStati(TEMPLATE, id))
            r = Rungs[i];
    }
    return r;
}

static int16 tallyMag(Monster *mn) {
    Status *st = mn->GetStati(SENESCHAL_TALLY);
    return st ? st->Mag : 0;
}

static int16 tallyVal(Monster *mn) {
    Status *st = mn->GetStati(SENESCHAL_TALLY);
    return st ? st->Val : 0;
}

/* Replace the follower's tally with one permitted SENESCHAL_TALLY stati. */
static void setTally(Monster *mn, int16 mag) {
    mn->RemoveStati(SENESCHAL_TALLY);
    if (mag)
        mn->GainPermStati(SENESCHAL_TALLY, NULL, SS_MISC, 0, mag);
}

/* Set pl's SK_SENESCHAL to wanted. SkillLevel sums the SS_CURS SKILL_BONUS
   bucket, so a signed adjustment reaches any value including a decrease. */
static void setRating(Player *pl, int16 wanted) {
    pl->RemoveStati(SKILL_BONUS, SS_CURS, SK_SENESCHAL, -1, NULL);
    int16 base = pl->SkillLevel(SK_SENESCHAL);
    int16 delta = (int16)(wanted - base);
    if (delta)
        pl->GainPermStati(SKILL_BONUS, NULL, SS_CURS, SK_SENESCHAL, delta);
}

/* A free floor square a short ring-distance from the player. */
static bool freeSquareNear(Map *mp, Creature *anchor, int16 &ox, int16 &oy) {
    for (int d = 2; d <= 80; d++)
        for (int dx = -d; dx <= d; dx++)
            for (int dy = -d; dy <= d; dy++) {
                if (max(abs(dx), abs(dy)) != d) continue;
                int16 x = (int16)(anchor->x + dx), y = (int16)(anchor->y + dy);
                if (!mp->InBounds(x, y) || mp->SolidAt(x, y)) continue;
                if (mp->FCreatureAt(x, y)) continue;
                ox = x; oy = y; return true;
            }
    return false;
}

/* Build, place and (optionally) join a follower. NULL on any failure. */
static Monster *spawn(Player *pl, const char *name, int16 compType, bool join) {
    rID id = FIND(name);
    if (!id || RES(id)->Type != T_TMONSTER) return NULL;
    Map *mp = pl->m;
    int16 x = -1, y = -1;
    if (!freeSquareNear(mp, pl, x, y)) return NULL;
    Monster *mn = new Monster(id);
    mn->CalcValues();
    mn->PlaceAt(mp, x, y, true);
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(true);
    theGame->PlayMode = wasPlay;
    if (join && !mn->MakeCompanion(pl, compType)) {
        mn->Remove(true);
        return NULL;
    }
    return mn;
}

/* One "case=" line: the fixed prefix, then this case's named extras. */
static void logCase(const char *name, Monster *mn, Player *pl,
    const char *extra) {
    fprintf(snLog, "case=%s rung=%s cr=%d tally=%d flag=%d rating=%d%s%s\n",
        name, rungOf(mn), (int)mn->ChallengeRating(true), (int)tallyMag(mn),
        (int)tallyVal(mn), (int)pl->SkillLevel(SK_SENESCHAL),
        extra && *extra ? " " : "", extra ? extra : "");
}

/* Make the party pool overflow using a high-CR sapient filler. Returns 1. */
static int fillPartyPool(Player *pl, Monster **fillerOut) {
    *fillerOut = NULL;
    Monster *f = spawn(pl, "hezrou", PHD_FREEBIE, true);
    if (!f) return 0;
    f->RemoveStati(NO_PHD, -1, -1, -1, pl);
    *fillerOut = f;
    for (int k = 0; k < 40 &&
        pl->GetGroupXCR(PHD_PARTY) <= pl->MaxGroupXCR(PHD_PARTY); k++) {
        Monster *g = spawn(pl, "hezrou", PHD_FREEBIE, true);
        if (!g) break;
        g->RemoveStati(NO_PHD, -1, -1, -1, pl);
    }
    return pl->GetGroupXCR(PHD_PARTY) > pl->MaxGroupXCR(PHD_PARTY) ? 1 : 0;
}

void SeneschalProbe(Player *pl) {
    if (!getenv("INCURSION_SENESCHAL_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/seneschal.log",
        (const char*)T1->IncursionDirectory);
    snLog = fopen(path, "w");
    if (!snLog) return;

    if (!pl || !pl->m) {
        fprintf(snLog, "INCONCLUSIVE: setup no live player and map\n");
        fprintf(snLog, "DONE\n");
        fclose(snLog);
        return;
    }
    if (!FIND("kobold") || RES(FIND("kobold"))->Type != T_TMONSTER) {
        fprintf(snLog, "INCONCLUSIVE: setup missing kobold\n");
        fprintf(snLog, "DONE\n");
        fclose(snLog);
        return;
    }

    Monster *mn;

    /* case 1: promote -- exact skilled threshold clears, tally reaches 0. */
    mn = spawn(pl, "kobold", PHD_PARTY, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: promote could not join a follower\n");
    } else {
        const int16 base = mn->ChallengeRating(true);
        const int32 need = 400 * max(1, (int32)base + 1);
        setRating(pl, 20);
        setTally(mn, (int16)need);
        mn->SeneschalPromote(pl);
        char extra[128];
        snprintf(extra, sizeof(extra), "base=%d need=%d", (int)base, (int)need);
        logCase("promote", mn, pl, extra);
        mn->Remove(true);
    }

    /* case 2: remainder -- one rung, remainder 123 left in the tally. */
    mn = spawn(pl, "kobold", PHD_PARTY, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: remainder could not join a follower\n");
    } else {
        const int32 need = 400 * max(1, (int32)mn->ChallengeRating(true) + 1);
        setRating(pl, 20);
        setTally(mn, (int16)(need + 123));
        mn->SeneschalPromote(pl);
        logCase("remainder", mn, pl, "");
        mn->Remove(true);
    }

    /* case 3: multi -- a full tally climbs several rungs in one call. */
    mn = spawn(pl, "kobold", PHD_PARTY, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: multi could not join a follower\n");
    } else {
        setRating(pl, 20);
        setTally(mn, 32767);
        mn->SeneschalPromote(pl);
        logCase("multi", mn, pl, "");
        mn->Remove(true);
    }

    /* case 4: ceiling -- rating equals the CR, so CR+1 exceeds it. */
    mn = spawn(pl, "kobold", PHD_PARTY, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: ceiling could not join a follower\n");
    } else {
        setRating(pl, mn->ChallengeRating(true));
        setTally(mn, 32767);
        mn->SeneschalPromote(pl);
        logCase("ceiling", mn, pl, "");
        mn->Remove(true);
    }

    /* case 5: budget -- the tested follower itself overflows the party pool. */
    mn = spawn(pl, "kobold", PHD_FREEBIE, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: budget could not join a follower\n");
    } else {
        mn->RemoveStati(NO_PHD, -1, -1, -1, pl);
        Monster *filler = NULL;
        const int over = fillPartyPool(pl, &filler);
        setRating(pl, 30);
        setTally(mn, 32767);
        const int32 pool = pl->GetGroupXCR(PHD_PARTY);
        const int32 maxx = pl->MaxGroupXCR(PHD_PARTY);
        mn->SeneschalPromote(pl);
        mn->SeneschalPromote(pl);
        char extra[160];
        snprintf(extra, sizeof(extra),
            "over=%d pool=%d max=%d", over, (int)pool, (int)maxx);
        logCase("budget", mn, pl, extra);
        mn->Remove(true);
        if (filler) filler->Remove(true);
    }

    /* case 6: freebie -- a NO_PHD companion ignores the full party pool. */
    {
        Monster *filler = NULL;
        fillPartyPool(pl, &filler);
        mn = spawn(pl, "kobold", PHD_FREEBIE, true);
        if (!mn) {
            fprintf(snLog, "INCONCLUSIVE: freebie could not join a follower\n");
        } else {
            setRating(pl, 30);
            setTally(mn, 32767);
            mn->SeneschalPromote(pl);
            logCase("freebie", mn, pl, "");
            mn->Remove(true);
        }
        if (filler) filler->Remove(true);
    }

    /* case 7: animal -- an animal is never Seneschal-eligible. */
    mn = spawn(pl, "wolf", PHD_ANIMAL, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: animal could not join a follower\n");
    } else {
        setRating(pl, 30);
        setTally(mn, 32767);
        mn->SeneschalPromote(pl);
        logCase("animal", mn, pl, "");
        mn->Remove(true);
    }

    /* case 8: dominated -- a dominated charme is not Seneschal-eligible. */
    mn = spawn(pl, "kobold", PHD_MAGIC, false);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: dominated could not build a monster\n");
    } else {
        mn->GainPermStati(CHARMED, pl, SS_ENCH, CH_DOMINATE, 0);
        if (!mn->MakeCompanion(pl, PHD_MAGIC)) {
            fprintf(snLog, "INCONCLUSIVE: dominated could not join\n");
            mn->Remove(true);
        } else {
            setRating(pl, 30);
            setTally(mn, 32767);
            mn->SeneschalPromote(pl);
            logCase("dominated", mn, pl, "");
            mn->Remove(true);
        }
    }

    /* case 9: undead -- a sapient undead follower still climbs the ladder. */
    mn = spawn(pl, "ghoul", PHD_UNDEAD, true);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: undead could not join a follower\n");
    } else {
        setRating(pl, 30);
        setTally(mn, 32767);
        mn->SeneschalPromote(pl);
        char extra[64];
        snprintf(extra, sizeof(extra), "int=%d", (int)mn->Attr[A_INT]);
        logCase("undead", mn, pl, extra);
        mn->Remove(true);
    }

    /* case 10: wild-undead -- no leader, so the rung template refuses it. */
    mn = spawn(pl, "ghoul", PHD_UNDEAD, false);
    if (!mn) {
        fprintf(snLog, "INCONCLUSIVE: wild-undead could not build a monster\n");
    } else {
        int accepted = 0;
        rID skilled = FIND("skilled");
        if (skilled) accepted = mn->CanAddTemplate(skilled) ? 1 : 0;
        char extra[64];
        snprintf(extra, sizeof(extra), "accepted=%d", accepted);
        logCase("wild-undead", mn, pl, extra);
        mn->Remove(true);
    }

    /* case 11: kill -- the Death hook credits a follower's killing blow. */
    {
        Monster *F = spawn(pl, "kobold", PHD_PARTY, true);
        Monster *V = NULL;
        if (!F) {
            fprintf(snLog, "INCONCLUSIVE: kill could not join a follower\n");
        } else {
            V = spawn(pl, "goblin", PHD_PARTY, false);
            if (!V) {
                fprintf(snLog, "INCONCLUSIVE: kill could not build a victim\n");
                F->Remove(true);
            } else {
                setRating(pl, 0);
                F->RemoveStati(SENESCHAL_TALLY);
                const int16 fcr = F->ChallengeRating(true);
                const int16 vcr = V->ChallengeRating(true);
                const bool wasPlay = theGame->PlayMode;
                theGame->PlayMode = true;
                ThrowDmg(EV_DAMAGE, AD_BLUNT, V->cHP + 50, "probe", F, V);
                theGame->PlayMode = wasPlay;
                const int dead = (V->Flags & F_DELETE) || !V->m;
                char extra[96];
                snprintf(extra, sizeof(extra), "vcr=%d fcr=%d dead=%d",
                    (int)vcr, (int)fcr, dead);
                logCase("kill", F, pl, extra);
                if (!dead) V->Remove(true);
                F->Remove(true);
            }
        }
    }

    pl->RemoveStati(SKILL_BONUS, SS_CURS, SK_SENESCHAL, -1, NULL);
    fprintf(snLog, "DONE\n");
    fclose(snLog);
    snLog = NULL;
}
