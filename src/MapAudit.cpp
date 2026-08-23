/* MAPAUDIT.CPP -- See the Incursion LICENSE file for copyright information.

     bool MapAuditEnabled()
     void AuditMap(Map *m, const char *when)

     Three checks over a map's two views of itself. See inc/MapAudit.h for why
   this looks at state rather than at the rendered screen.

     Diagnostic only. It reports and never repairs: a check that quietly fixes
   what it finds destroys the evidence it exists to collect.
*/

#include "Incursion.h"
#include "MapAudit.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <ctime>

/* A chain longer than this is a cycle, not a crowd. The largest legitimate
   stack is a square holding a creature, its mount, and everything dropped
   there; a hundred is far past any of that. */
#define CHAIN_LIMIT 100

/* Report each distinct kind of violation once per audit, with a count, so a
   cascade does not bury the first occurrence -- which is the one that says
   what went wrong. */
#define MAX_KINDS 16

bool MapAuditEnabled() {
    static int on = -1;
    if (on < 0) {
        /* The VALUE decides, not the mere presence of the variable. This used
           to be `getenv(...) ? 1 : 0`, so INCURSION_MAP_AUDIT=0 switched the
           audit ON, and a caller who wrote 0 to turn it off got it anyway.
           That matters because the audit is not free: a sample of a headless
           run on 2026-08-15 put 75% of the process inside AuditMap, so a
           timing run that could not turn it off was measuring the audit. */
        const char *s = getenv("INCURSION_MAP_AUDIT");
        on = (s && *s && strcmp(s, "0")) ? 1 : 0;
    }
    return on != 0;
}

/* Opening the log on the first audit rather than on the first finding matters:
   a silent log then means "audited, nothing wrong", and an absent log means
   "never ran". Without that distinction a clean run and a broken switch look
   identical, and the check proves nothing. */
static FILE *auditLog() {
    static FILE *f = NULL;
    if (!f) {
        char path[1024];
        time_t now;
        char stamp[32];

        snprintf(path, sizeof(path), "%slogs/mapaudit.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
        if (!f)
            return NULL;
        time(&now);
        strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
        fprintf(f, "=== map audit armed %s  Incursion %s  built %s %s ===\n",
            stamp, VERSION_STRING, __DATE__, __TIME__);
        fflush(f);
    }
    return f;
}

/* Reachable by walking the Contents chain of (x,y)? Bounded, because a cycle
   here would hang the game inside a diagnostic, which is worse than the bug. */
static bool inContentsChain(Map *m, int16 x, int16 y, hObj h) {
    hObj cur = m->At(x, y).Contents;
    int steps = 0;

    while (cur && steps++ < CHAIN_LIMIT) {
        if (cur == h)
            return true;
        if (!theRegistry->Exists(cur))
            return false;
        cur = oThing(cur)->Next;
    }
    return false;
}

static bool inThingsArray(Map *m, hObj h) {
    int32 i;
    for (i = 0; m->Things[i]; i++)
        if (m->Things[i] == h)
            return true;
    return false;
}

void AuditMap(Map *m, const char *when) {
    char kinds[MAX_KINDS][96];
    int counts[MAX_KINDS];
    char first[MAX_KINDS][256];
    int nkinds = 0;
    int32 i;
    int16 x, y;
    FILE *f;
    time_t now;
    char stamp[32];

    if (!m || !MapAuditEnabled())
        return;

    /* Open now, so the log records that an audit happened even when it finds
       nothing. See auditLog(). */
    if (!auditLog())
        return;

    /* Record one exemplar per kind, then a tally. */
    #define REPORT(kind, detailfmt, ...) do {                                 \
        int k_;                                                               \
        for (k_ = 0; k_ < nkinds; k_++)                                       \
            if (!strcmp(kinds[k_], kind))                                     \
                break;                                                        \
        if (k_ == nkinds && nkinds < MAX_KINDS) {                             \
            snprintf(kinds[nkinds], sizeof(kinds[0]), "%s", kind);            \
            snprintf(first[nkinds], sizeof(first[0]), detailfmt, __VA_ARGS__);\
            counts[nkinds] = 0;                                               \
            nkinds++;                                                         \
        }                                                                     \
        if (k_ < MAX_KINDS && k_ < nkinds)                                    \
            counts[k_]++;                                                     \
    } while (0)

    /* --- 1. every Thing in the array agrees with where it says it stands --- */
    for (i = 0; m->Things[i]; i++) {
        hObj h = m->Things[i];
        Thing *t;

        if (!theRegistry->Exists(h)) {
            REPORT("dead handle in Things[]", "Things[%d] = %d, no such object", (int)i, (int)h);
            continue;
        }
        t = oThing(h);
        if (t->Flags & F_DELETE)
            REPORT("deleted Thing still in Things[]", "%s/%d still listed",
                (const char*)t->Name(0), (int)h);
        if (t->m != m) {
            REPORT("Thing in Things[] belongs to another map", "%s/%d has m=%p, audited map is %p",
                (const char*)t->Name(0), (int)h, (void*)t->m, (void*)m);
            continue;
        }
        if (!m->InBounds(t->x, t->y)) {
            REPORT("Thing outside the map", "%s/%d at (%d,%d)",
                (const char*)t->Name(0), (int)h, (int)t->x, (int)t->y);
            continue;
        }
        /* A mounted or engulfed creature is deliberately absent from Contents:
           it is on the map, but nothing can interact with it there. Both are
           by design -- see Creature::DoEngulf in src/Display.cpp. */
        if (t->HasStati(MOUNT) || t->HasStati(ENGULFED))
            continue;
        if (!inContentsChain(m, t->x, t->y, h))
            REPORT("Thing not in the Contents chain of its own square",
                "%s/%d claims (%d,%d) but is not linked there",
                (const char*)t->Name(0), (int)h, (int)t->x, (int)t->y);
    }

    /* --- 2. every Contents chain is well formed and agrees with the array --- */
    for (y = 0; y < m->SizeY(); y++)
        for (x = 0; x < m->SizeX(); x++) {
            hObj cur = m->At(x, y).Contents;
            int steps = 0;

            while (cur) {
                Thing *t;
                if (steps++ >= CHAIN_LIMIT) {
                    REPORT("Contents chain too long, probably a cycle",
                        "square (%d,%d) still linking after %d hops", (int)x, (int)y, CHAIN_LIMIT);
                    break;
                }
                if (!theRegistry->Exists(cur)) {
                    REPORT("dead handle in a Contents chain",
                        "square (%d,%d) links to %d, no such object", (int)x, (int)y, (int)cur);
                    break;
                }
                t = oThing(cur);
                if (t->x != x || t->y != y)
                    REPORT("Thing linked at a square it does not claim",
                        "%s/%d linked at (%d,%d) but claims (%d,%d)",
                        (const char*)t->Name(0), (int)cur, (int)x, (int)y, (int)t->x, (int)t->y);
                if (t->m != m)
                    REPORT("Thing linked into the wrong map's square",
                        "%s/%d linked at (%d,%d) with m=%p",
                        (const char*)t->Name(0), (int)cur, (int)x, (int)y, (void*)t->m);
                if (!inThingsArray(m, cur))
                    REPORT("Thing in Contents but missing from Things[]",
                        "%s/%d linked at (%d,%d)", (const char*)t->Name(0), (int)cur, (int)x, (int)y);
                cur = t->Next;
            }
        }

    /* --- 3. zombies: still pointing at this map, in neither list -----------
       This is the signature Thing::Remove leaves behind when it returns early.
       The object has already been dropped from Things[], was never in the
       Contents chain, keeps its map pointer and coordinates, and is never
       marked deleted. Sweeping by handle uses only the Registry's public
       interface, so it costs a lookup per handle rather than access to its
       internals. */
    for (hObj h = 128; h <= theRegistry->LastUsedHandle; h++) {
        Object *o;
        Thing *t;

        if (!theRegistry->Exists(h))
            continue;
        o = theRegistry->Get(h);
        if (!o || !(o->isCreature() || o->isItem() || o->isFeature()))
            continue;
        t = (Thing*)o;
        if (t->m != m)
            continue;
        /* A mounted or engulfed creature is deliberately absent from both
           Things[] and the Contents chain -- see check 1's exemption above
           and Creature::DoEngulf in src/Display.cpp. */
        if (t->HasStati(MOUNT) || t->HasStati(ENGULFED))
            continue;
        if (inThingsArray(m, h))
            continue;
        REPORT("orphan: claims this map but is in neither list",
            "%s/%d claims (%d,%d), F_DELETE=%d",
            (const char*)t->Name(0), (int)h, (int)t->x, (int)t->y,
            (t->Flags & F_DELETE) ? 1 : 0);
    }

    if (!nkinds)
        return;

    f = auditLog();
    if (!f)
        return;
    time(&now);
    strftime(stamp, sizeof(stamp), "%H:%M:%S", localtime(&now));
    fprintf(f, "%s  turn %u  %s  -- %d kind(s)\n",
        stamp, (unsigned)theGame->Turn, when, nkinds);
    for (i = 0; i < nkinds; i++)
        fprintf(f, "    %-52s x%-5d %s\n", kinds[i], counts[i], first[i]);
    fflush(f);

    #undef REPORT
}
