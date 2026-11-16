/* inc-m2c6: opt-in probe for the script read of a thing's map. Off unless
   INCURSION_MAPREAD_PROBE is set to the varid of the member "m" (the number
   in the `case N:` just above the `->m` line of lib/dispatch.h; the check
   reads it from there). Called from Game::Play (src/Main.cpp); graded by
   tools/check_script_map_read.sh. It makes an item that is on no map, then
   runs the generated VMachine::GetMemberVar on it. One Error() line. */
#include "Incursion.h"

/* Public wrapper: GetMemberVar is private and generated into lib/dispatch.h. */
int32 VMachine::MapReadProbeRun(int16 varid, hObj h)
{
    Regs[0] = -12345;
    GetMemberVar(varid, h, 0);
    return Regs[0];
}

void MapReadProbe(Player *pl)
{
    const char *v = getenv("INCURSION_MAPREAD_PROBE");
    Item *it;
    VMachine vm;

    if (!v)
        return;
    if (!pl) {
        Error("MAPREAD_PROBE INCONCLUSIVE -- no live player");
        return;
    }
    it = Item::Create(FIND("long sword"));
    if (!it || it->m) {
        Error("MAPREAD_PROBE INCONCLUSIVE -- item missing or already on a map");
        return;
    }
    Error("MAPREAD_PROBE reading m of off-map item, varid=%d", atoi(v));
    Error("MAPREAD_PROBE result=%d", (int)vm.MapReadProbeRun(atoi(v), it->myHandle));
}
