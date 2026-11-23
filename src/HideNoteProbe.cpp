/* inc-6lwjk: prove a watcher's spot-result notes stay bounded. A no-op unless
   INCURSION_HIDE_NOTE_PROBE is set. Caller: Game::Play (src/Main.cpp), beside
   the other hide probes. Reader: tools/check_hide_note_cap.sh.

   One watcher takes a real SpotCheck against every one of NOTE_HIDERS other
   creatures. Each check stores one HK_SPOT_RESULT note on the watcher, keyed by
   the hider. The probe prints the counts; the literal expectations live in the
   shell oracle. */
#include "Incursion.h"
#include "HideCheck.h"

// no-family
static const int NOTE_HIDERS = 100;
// end no-family

void HideNoteProbe(Player *pl) {
    if (!getenv("INCURSION_HIDE_NOTE_PROBE")) return;
    if (!pl || !pl->m) { Error("HIDE_NOTE INCONCLUSIVE no player"); return; }
    Map *mp = pl->m;
    const rID rat = FIND("giant rat");
    if (!rat) { Error("HIDE_NOTE INCONCLUSIVE no giant rat"); return; }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;

    Monster *watcher = new Monster(rat);
    watcher->PlaceAt(mp, pl->x, pl->y);
    hObj hiders[NOTE_HIDERS];
    int made = 0;
    /* Hiders go in squares of the watcher's own map, nearest the player first. */
    for (int r = 1; r < 40 && made < NOTE_HIDERS; r++)
        for (int dy = -r; dy <= r && made < NOTE_HIDERS; dy++)
            for (int dx = -r; dx <= r && made < NOTE_HIDERS; dx++) {
                if (max(abs(dx), abs(dy)) != r) continue;
                const int x = pl->x + dx, y = pl->y + dy;
                if (!mp->InBounds(x, y) || mp->SolidAt(x, y) ||
                    mp->FCreatureAt(x, y)) continue;
                Monster *h = new Monster(rat);
                h->PlaceAt(mp, x, y);
                hiders[made++] = h->myHandle;
            }
    if (made < NOTE_HIDERS) {
        Error("HIDE_NOTE INCONCLUSIVE only %d free squares", made);
        theGame->PlayMode = wasInPlay;
        return;
    }
    const hObj wHandle = watcher->myHandle;
    for (int k = 0; k < made; k++) {
        if (!isValidHandle(wHandle) || !isValidHandle(hiders[k])) continue;
        SpotCheck(oCreature(wHandle), oCreature(hiders[k]), 0);
    }
    int notes = 0, newest = 0;
    if (isValidHandle(wHandle)) {
        Creature *w = oCreature(wHandle);
        StatiIterNature(w, TRIED)
            if (S->Val == HK_SPOT_RESULT) notes++;
        StatiIterEnd(w)
        if (isValidHandle(hiders[made - 1]))
            newest = w->HasStati(TRIED, HK_SPOT_RESULT, oCreature(hiders[made - 1])) ? 1 : 0;
    }
    Error("HIDE_NOTE hiders=%d notes=%d newest=%d", made, notes, newest);

    /* Remove the rats: a hostile beside the player would halt the key script. */
    for (int k = 0; k < made; k++)
        if (isValidHandle(hiders[k])) oCreature(hiders[k])->Remove(true);
    if (isValidHandle(wHandle)) oCreature(wHandle)->Remove(true);
    theGame->PlayMode = wasInPlay;
    Error("HIDE_NOTE COMPLETE");
}
