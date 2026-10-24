/* inc-w91w: deterministic fixture scene and state oracle, opt-in only. */
#include "Incursion.h"
#include <cstdlib>
#include <cstring>

extern void LOFSetForcedRoll(int8);
extern void LOFSetForcedSaveThrowRoll(int8);
static Trap *probeTrap;
static int initialHP, initialTimeout;
static uint32 initialXP;
static const char *probeMode;
static Monster *probeMon;       // staged creature (shot-under, shot-between)
static int probeMonHP;
static bool probeAttackRan;     // AttackTrap resolved the shot against the trap
static int probeShots;

/* Called at the end of every ranged shot, whatever it hit. */
void TrapAttackProbeShot(Creature *actor, EventInfo &e) {
    if (!probeTrap || !probeMode || actor != theGame->GetPlayer(0)) return;
    if (strncmp(probeMode,"shot-",5)) return;
    Player *p = (Player*)actor;
    ++probeShots;
    Error("TRAP_ATTACK shot mode=%s n=%d armed=%d hp_before=%d hp_after=%d blind=%d mon=%d mon_hp_before=%d mon_hp_after=%d mon_blind=%d trap_attacked=%d time=%d",
        probeMode,probeShots,!(probeTrap->TrapFlags & TS_DISARMED),initialHP,p->cHP,
        p->HasStati(BLIND),probeMon != NULL,probeMonHP,probeMon ? probeMon->cHP : 0,
        probeMon ? probeMon->HasStati(BLIND) : 0,probeAttackRan,p->Timeout-initialTimeout);
}

void TrapAttackProbeResult(Creature *actor, EventInfo &e) {
    if (!probeTrap || !probeMode || actor != theGame->GetPlayer(0)) return;
    Player *p = (Player*)actor;
    probeAttackRan = true;
    Error("TRAP_ATTACK mode=%s roll=%d confirm=%d bonus=%d defense=%d hit=%d fumble=%d armed=%d hp_before=%d hp_after=%d blind=%d lit=%d duration=%d pain=%d time=%d xp_before=%lu xp_after=%lu",
        probeMode, e.vRoll,e.vtRoll,e.vHit,e.vDef,e.isHit,e.isFumble,
        !(probeTrap->TrapFlags & TS_DISARMED),initialHP,p->cHP,
        p->HasStati(BLIND),p->HasEffStati(ILLUMINATED,FIND("faerie fire")),
        p->GetEffStatiDur(ILLUMINATED,FIND("faerie fire")),
        p->HasStati(ADJUST_PAIN) ? 1 : 0,
        p->Timeout-initialTimeout,(unsigned long)initialXP,(unsigned long)p->GetXP());
}

void TrapAttackProbe(Player *p) {
    /* inc-w91w: opt-in probe for tools/check_trap_attack.sh. */
    probeMode = getenv("INCURSION_TRAP_ATTACK_PROBE");
    if (!probeMode || !*probeMode || !p || !p->m) return;
    Map *m = p->m;
    // Fix the world independently of generation, including all possible AI.
    for (Thing *t = m->FirstThing(); t; ) {
        Thing *next = m->NextThing();
        if (t != p) t->Remove(true);
        t = next;
    }
    int px = m->SizeX()/2, py = m->SizeY()/2;
    for (int x=px-12; x<=px+12; ++x)
        for (int y=py-12; y<=py+12; ++y)
            if (m->InBounds(x,y)) {
                m->WriteTerra(x,y,FIND("Floor"));
                // A shot is aimed at a square the shooter can see (the prompt
                // refuses "unseen area"), so light the room for the shot modes.
                if (!strncmp(probeMode,"shot-",5)) m->At(x,y).Lit = 1;
            }
    // Arrival in an undescribed-before room opens a Box that eats the first scripted key.
    if (TREG(m->RegionAt(px,py))->Desc) REGMEM(m->RegionAt(px,py),p)->Seen = true;
    p->PlaceAt(m,px,py);
    p->CalcValues();
    bool area = strstr(probeMode,"area") || strstr(probeMode,"faerie");
    bool script = strstr(probeMode,"area-script") != NULL;
    bool shot = !strncmp(probeMode,"shot-",5);
    int distance = strstr(probeMode,"outside") ? 8 :
        (shot ? 3 : 1);
    const char *name = script ? "Symbol of Pain;trap" :
        (area ? "faerie fire trap" : "light trap");
    probeTrap = new Trap(FIND("trap"),FIND(name));
    probeTrap->PlaceAt(m,px+distance,py);
    probeTrap->TrapFlags |= TS_FOUND;
    probeTrap->SetImage();
    m->At(probeTrap->x,probeTrap->y).Memory = probeTrap->Image;
    m->At(probeTrap->x,probeTrap->y).Visibility = VI_DEFINED;
    initialHP = p->cHP; initialXP = p->GetXP(); initialTimeout = p->Timeout;
    Error("TRAP_ATTACK stage mode=%s class=%s armed=1 hp=%d blind=%d lit=%d distance=%d",
        probeMode,NAME(p->ClassID[0]),p->cHP,p->HasStati(BLIND),
        p->HasEffStati(ILLUMINATED,FIND("faerie fire")),distance);
    if (!strcmp(probeMode,"rogue")) {
        p->DisarmTrap(probeTrap,true);
        Error("TRAP_ATTACK rogue armed=%d",!(probeTrap->TrapFlags & TS_DISARMED));
    } else if (area) {
        EventInfo e; e.Clear();
        p->AttackTrap(e,probeTrap,p->EInSlot(SL_WEAPON));
    } else if (shot) {
        /* inc-w91w ranged: the player fires or throws through the real fire
           key; this only equips the shooter and stages a creature. A bow with
           arrows for the fire cases, a wielded dagger for shot-thrown. */
        EventInfo t;
        for (int sl = SL_WEAPON; sl >= SL_READY; sl--)
            if (Item *old = p->InSlot(sl)) {
                t.Clear(); t.EActor = p; t.EItem = old; p->TakeOff(t);
            }
        const bool thrown = !strcmp(probeMode,"shot-thrown");
        Item *wep = Item::Create(FIND(thrown ? "dagger" : "short bow"));
        wep->MakeKnown(0xFF);
        p->GainItem(wep, true);
        if (!thrown) {
            Item *ar = Item::Create(FIND("flight arrow"));
            ar->SetQuantity(20);
            ar->MakeKnown(0xFF);
            /* arrows must sit in a slot to be "ready" (Player.cpp fire key) */
            SetSilence();
            ThrowVal(EV_WIELD,SL_BELT1,p,NULL,ar);
            UnsetSilence();
            if (p->InSlot(SL_BELT1) != ar) p->GainItem(ar, true);
        }
        t.Clear(); t.EActor = p; t.EItem = wep; t.EParam = SL_WEAPON;
        p->Wield(t);
        if (!strcmp(probeMode,"shot-under") || !strcmp(probeMode,"shot-between")) {
            /* The creature never acts: ASLEEP for good (SS_MISC, no duration
               end), and a hit-point total no shot can exhaust. */
            int cx = !strcmp(probeMode,"shot-under") ? probeTrap->x : px+2;
            probeMon = new Monster(FIND("giant rat"));
            TMON(probeMon->tmID)->GrantGear(probeMon, probeMon->tmID, true);
            TMON(probeMon->tmID)->PEvent(EV_BIRTH, probeMon, probeMon->tmID);
            probeMon->PlaceAt(m,cx,py,true);
            probeMon->Initialize(true);
            m->At(cx,py).Lit = 1;
            probeMon->mHP = probeMon->cHP = 10000;
            probeMon->GainPermStati(ASLEEP,NULL,SS_MISC,SLEEP_MAGIC);
            probeMonHP = probeMon->cHP;
        }
        Error("TRAP_ATTACK equip weapon=%s hand=%d mon=%d ammo=%d",
            p->InSlot(SL_WEAPON) ? (const char*)p->InSlot(SL_WEAPON)->Name(0) : "none",
            p->InSlot(SL_WEAPON) == wep,probeMon != NULL,
            thrown || p->InSlot(SL_BELT1) != NULL);
    }
}
