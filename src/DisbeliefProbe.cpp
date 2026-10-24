/* inc-z1ba: test-only probe for the Spellcraft illusion-disbelief bonus. Off
   unless INCURSION_DISBELIEF_PROBE is set. Called from Thing::DisbeliefCheck and
   Map::TerrainDisbelief and the force save in Magic.cpp; appends one line per
   save to logs/disbelief-probe.log:
   DISBELIEF watcher=<name> illusion=<name or terrain> dc=<base> spotted=<0|1>
   used_dc=<dc> result=<pass|fail> removed=<0|1>. removed=1 when the illusion is
   gone after the save (inc-bvom); terrain and force lines write removed=0.
   No game effect. */
#include "Incursion.h"

/* The game chdir()s constantly, so a relative path lands wherever the working
   directory is at that moment; inc-yam9 found it missing in a session that
   fires a save before any menu runs. Name the run directory instead. */
static FILE *DisbeliefProbeOpen()
{
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/disbelief-probe.log",
        (const char*)T1->IncursionDirectory);
    return fopen(path, "a");
}

static void DisbeliefProbeLine(const char *watcherName, const char *illusName,
    int16 baseDC, bool spotted, int16 usedDC, bool pass, bool removed)
{
    FILE *f;
    if (!getenv("INCURSION_DISBELIEF_PROBE"))
        return;
    if (!(f = DisbeliefProbeOpen()))
        return;
    fprintf(f, "DISBELIEF watcher=%s illusion=%s dc=%d spotted=%d used_dc=%d "
        "result=%s removed=%d\n", watcherName, illusName, (int)baseDC,
        spotted ? 1 : 0, (int)usedDC, pass ? "pass" : "fail", removed ? 1 : 0);
    fclose(f);
}

void DisbeliefProbeThing(Creature *watcher, Thing *illusion, int16 baseDC,
    bool spotted, int16 usedDC, bool pass, bool removed)
{
    if (!watcher || !illusion)
        return;
    DisbeliefProbeLine((const char*)watcher->Name(),
        (const char*)illusion->Name(), baseDC, spotted, usedDC, pass, removed);
}

void DisbeliefProbeTerrain(Creature *watcher, int16 baseDC, bool spotted,
    int16 usedDC, bool pass)
{
    if (!watcher)
        return;
    DisbeliefProbeLine((const char*)watcher->Name(), "terrain", baseDC, spotted,
        usedDC, pass, false);
}

void DisbeliefProbeForce(Creature *watcher, int16 baseDC, bool spotted,
    int16 usedDC, bool pass)
{
    if (!watcher)
        return;
    DisbeliefProbeLine((const char*)watcher->Name(), "force", baseDC, spotted,
        usedDC, pass, false);
}

/* One line per perceiving watcher of a cast: did its Spellcraft check identify
   the spell. A watcher without the skill logs result=fail. */
void DisbeliefProbeIdentify(Creature *watcher, Creature *caster, rID eID,
    bool identified)
{
    FILE *f;
    if (!getenv("INCURSION_DISBELIEF_PROBE") || !watcher || !caster)
        return;
    if (!(f = DisbeliefProbeOpen()))
        return;
    fprintf(f, "IDENTIFY watcher=%s caster=%s spell=%s result=%s\n",
        (const char*)watcher->Name(), (const char*)caster->Name(),
        (const char*)NAME(eID), identified ? "pass" : "fail");
    fclose(f);
}
