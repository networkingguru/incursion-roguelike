/* inc-5lval: opt-in log of Thing::Remove's EV_FIELDOFF sweep, off unless
   INCURSION_REMOVE_PROBE is set (1 logs every throw; "scene" also runs the
   fixed scenes behind tools/check_remove_field_event.sh). Logs to
   logs/remove-probe.log. */
#include "Incursion.h"

static FILE *Log = NULL;
static bool Tried = false, SceneMode = false;
static Thing *Handler = NULL;   /* the thing a field event removes, once */
static int Delivered = 0;

static bool Open()
{
    if (!Tried) {
        Tried = true;
        const char *mode = getenv("INCURSION_REMOVE_PROBE");
        if (mode) {
            SceneMode = !strcmp(mode, "scene");
            char path[1024];
            snprintf(path, sizeof(path), "%slogs/remove-probe.log",
                (const char*)T1->IncursionDirectory);
            Log = fopen(path, "a");
            if (Log) setvbuf(Log, NULL, _IONBF, 0);
        }
    }
    return Log != NULL;
}

/* Called from Thing::Remove around each EV_FIELDOFF it throws; the field's
   resource and creator are passed by value because the throw can unseat the
   field. after is false before the throw, true after it. */
void RemoveProbe(Thing *t, rID eID, hObj creator, bool after)
{
    if (!Open()) return;
    if (!SceneMode)
        fprintf(Log, "%s thing=%s type=%d mID=%d mounted=%d field=%s creator=%s map=%s\n",
            after ? "after " : "before", (const char*)t->Name(0), (int)t->Type,
            t->isCreature() ? (int)((Creature*)t)->mID : 0,
            t->HasStati(MOUNTED) ? 1 : 0, NAME(eID),
            theRegistry->Exists(creator) ?
                (const char*)oThing(creator)->Name(0) : "{gone}",
            t->m ? "set" : "NULL");
    /* The scene's stand-in for a field handler that kills its subject: the
       real chain (seed 22) is FieldOff -> EV_EFFECT -> Blast -> Damage ->
       Death -> Remove. */
    if (after && SceneMode && t == Handler && t->m) {
        Handler = NULL;
        t->Remove(false);
    }
}

/* Called at the top of Creature::FieldOff: one count per delivered event. */
void RemoveProbeDelivered(Thing *t)
{
    if (!Open()) return;
    (void)t;
    Delivered++;
}

static void Scene(Player *pl, const char *name, bool handler)
{
    Map *mp = pl->m;
    Monster *k = new Monster(FIND("kobold"));
    k->CalcValues();
    k->PlaceAt(mp, 10, 10);
    mp->NewField(FI_OBVIOUS, 10, 10, 1, GLYPH_VALUE(GLYPH_FLOOR2, WHITE), -1, 0, NULL);
    mp->NewField(FI_OBVIOUS, 10, 10, 1, GLYPH_VALUE(GLYPH_FLOOR2, WHITE), -1, 0, NULL);
    Delivered = 0;
    Handler = handler ? k : NULL;
    fprintf(Log, "scene=%s begin\n", name);
    k->Remove(false);
    fprintf(Log, "scene=%s returned=1 offmap=%d delivered=%d\n", name,
        k->m == NULL ? 1 : 0, Delivered);
    Handler = NULL;
    for (int i = 0; mp->Fields[i]; ) mp->RemoveField(mp->Fields[i]);
    delete k;
}

/* inc-5lval: the scenes behind tools/check_remove_field_event.sh. */
void RemoveFieldScenes(Player *pl)
{
    if (!Open() || !SceneMode) return;
    rID floor = FIND("floor"), region = FIND("Winding Corridor");
    if (!pl || !pl->m || !floor || !region ||
        pl->m->SizeX() <= 26 || pl->m->SizeY() <= 26) {
        fprintf(Log, "INCONCLUSIVE: missing player, map or resource\n");
        return;
    }
    Map *mp = pl->m;
    Thing *obj; int index;
    for (;;) {
        Thing *gone = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { gone = obj; break; }
        if (!gone) break;
        gone->Remove(true);
    }
    Rect rect(0, 0, mp->SizeX()-1, mp->SizeY()-1);
    for (int y = 5; y <= 25; ++y)
        for (int x = 5; x <= 25; ++x) {
            mp->RemoveTerraXY(x, y);
            mp->WriteAt(rect, x, y, floor, region, PRIO_MAX, true);
        }
    pl->PlaceAt(mp, 20, 20);
    Scene(pl, "control", false);
    Scene(pl, "handler", true);
    fprintf(Log, "DONE\n");
}
