/* inc-2mea: opt-in reproduction only; real EV_MOUNT and size-changing
   CalcValues. Each case runs in a fresh fixture sandbox. */
// Diagnostic message access, as in BeltPotionProbe.cpp.
#define protected public
#include "Incursion.h"
#undef protected

static const char *MountSizeName(int size)
{
    switch (size) {
        case SZ_TINY: return "tiny";
        case SZ_SMALL: return "small";
        case SZ_MEDIUM: return "medium";
        case SZ_LARGE: return "large";
        case SZ_HUGE: return "huge";
        default: return "unexpected";
    }
}

void MountSizeProbe(Player *p)
{
    const char *mode = getenv("INCURSION_MOUNT_SIZE_PROBE");
    if (!mode) return;
    const int n = atoi(mode);
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/mount-size.log", (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "w");
    if (!log) return;
    const char *name = n == 2 ? "elephant" : (n == 3 || n == 4 ? "pony" : "tiger");
    rID mountID = FIND(name), floor = FIND("floor"), region = FIND("Winding Corridor"), dwarf = FIND("Dwarf;race");
    if (!p || !p->m || n < 1 || n > 6 || !mountID || !floor || !region || !dwarf ||
        p->m->SizeX() <= 26 || p->m->SizeY() <= 26) {
        fprintf(log, "INCONCLUSIVE: missing player/map/resource or invalid case\n");
        fclose(log); return;
    }
    Map *mp = p->m;
    if (p->HasStati(MOUNTED))
        ThrowVal(EV_DISMOUNT, 0, p, p->GetStatiObj(MOUNTED));
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != p) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    Rect rect(0, 0, mp->SizeX()-1, mp->SizeY()-1);
    for (int y = 5; y <= 25; ++y)
        for (int x = 5; x <= 25; ++x) {
            mp->RemoveTerraXY(x,y);
            mp->WriteAt(rect,x,y,floor,region,PRIO_MAX,true);
        }
    REGMEM(region,p)->Seen = true;
    p->PlaceAt(mp,15,15);
    if (n == 4) {
        // Match character creation: racial type reads tmID, not polymorph mID.
        p->RaceID = dwarf;
        p->mID = p->tmID = TRACE(dwarf)->mID;
    }
    p->GainPermStati(EXTRA_SKILL,NULL,SS_MISC,SK_RIDE);
    const int wanted = n <= 3 ? SZ_SMALL : SZ_MEDIUM;
    p->CalcValues();
    p->GainPermStati(ADJUST,NULL,SS_MISC,A_SIZ,wanted-p->GetAttr(A_SIZ));
    p->CalcValues();
    Monster *mt = new Monster(mountID);
    mt->CalcValues();
    if (n == 3) {
        mt->GainPermStati(ADJUST,NULL,SS_MISC,A_SIZ,-1);
        mt->CalcValues();
    }
    mt->GainPermStati(ANIMAL_COMPANION,p,SS_MISC);
    mt->PlaceAt(mp,16,15);
    const bool companion = mt->MakeCompanion(p,PHD_FREEBIE);
    const int before = p->GetAttr(A_SIZ), mountSize = mt->GetAttr(A_SIZ);
    bool setup = companion && before == wanted && p->HasSkill(SK_RIDE) &&
        p->HasMFlag(M_HUMANOID) && !p->HasMFlag(M_NOLIMBS) &&
        (n != 4 || p->isMType(MA_DWARF)) &&
        mt->m == mp && mt->x != -1 && mt->HasMFlag(M_MOUNTABLE) &&
        mt->isMType(MA_ANIMAL) && !mt->isHostileTo(p) &&
        mt->GetStatiObj(ANIMAL_COMPANION) == p &&
        (n != 2 || mt->isMType(MA_QUADRUPED)) &&
        (strcmp(name,"tiger") || !mt->isMType(MA_QUADRUPED));
    TextTerm *term = (TextTerm*)p->MyTerm;
    term->MsgHistory[0] = 0;
    EvReturn result = Throw(EV_MOUNT,p,mt);
    const bool admitted = p->GetStatiObj(MOUNTED) == mt;
    String message = admitted ? "admitted" : (const char*)term->MsgHistory;
    for (int i = 0; i < message.GetLength(); ++i)
        if ((unsigned char)message[i] < 32 || message[i] == '"') message.SetAt(i,' ');
    message = message.Trim();
    setup = setup && (admitted ? result == DONE : result == ABORT);
    term->MsgHistory[0] = 0;
    const int delta = n == 5 ? 1 : (n == 1 || n == 6 ? -1 : 0);
    if (delta) p->GainPermStati(ADJUST_SAC,NULL,SS_MISC,A_SIZ,delta);
    p->CalcValues();
    const int after = p->GetAttr(A_SIZ);
    setup = setup && after == before + delta && mt->GetAttr(A_SIZ) == mountSize;
    const bool mounted = p->GetStatiObj(MOUNTED) == mt;
    const bool thrown = strstr(term->MsgHistory,"You are thrown from your mount.") != NULL;
    const bool pair = mounted ? mt->GetStatiObj(MOUNT) == p : !mt->HasStati(MOUNT);
    const char *outcome = !admitted ? "refused" : !delta ? "unchanged" :
        mounted ? "stays" : thrown ? "thrown" : "unexplained";
    fprintf(log, "case=%d rider=%s->%s mount=%s(%s) mount_result=\"%s\" mounted_after_recalc=%s outcome=%s setup=%d pair=%d\n",
        n,MountSizeName(before),MountSizeName(after),name,MountSizeName(mountSize),
        (const char*)message,mounted ? "yes" : "no",outcome,(int)setup,(int)pair);
    fclose(log);
}
