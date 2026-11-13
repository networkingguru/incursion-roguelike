            if (NeedsBothHands(e.EItem)) {
@@@ next hunk
/* Wield set `pick` (a WSET_* index). The `-` key calls it after it has picked
   a set; the C menu calls it for the set the player chose. It has no range
   test and no grapple test. */
void Character::ChangeToSet(int pick)
  {
    Item *new1, *new2, *old1, *old2;
    int8 si, sl1, sl2;
    hObj *setMain[WSET_COUNT], *setOff[WSET_COUNT];
    bool configured[WSET_COUNT];
    int cur, k;

    new1 = new2 = old1 = old2 = NULL; sl1 = sl2 = 0;
    isExchange = true;
    WeaponSetRefs(setMain, setOff);
    WeaponSets(configured, cur);
    if (pick < 0 || pick >= WSET_COUNT || !configured[pick] || pick == cur)
      goto XAbortNoItem;
    if (CursedGrip())
      /* upstream: Exchange returned with isExchange still true (cursed
         grip, death mid-swap), so later Wield calls skipped their
         two-handed prompt. Plain control flow, no platform dependence,
         so Win32 misbehaves the same. Traced; inc-h5aql; not sent. */
      goto XAbortNoItem;
    if (!WeaponSetUsable(pick))
      { IPrint("That set's weapon is not in your hand, shoulder or belt slots.");
        goto XAbortNoItem; }

    new1 = oItem(*setMain[pick]);
    new2 = setOff[pick] ? oItem(*setOff[pick]) : NULL;
    for (si = 0; si != SL_LAST; si++) {
      if (Inv[si] == *setMain[pick]) sl1 = si;
      if (new2 && Inv[si] == *setOff[pick]) sl2 = si;
@@@ next hunk
    /* Before anything moves, check that each weapon put away has a slot. */
    {
      hObj occ[NUM_SLOTS];
      memcpy(occ, Inv, sizeof(occ));
      if (new1) occ[sl1] = 0;
      if (new2) occ[sl2] = 0;
      Item *away[2] = { old1, old2 };
      for (k = 0; k != 2; k++)
        if (away[k]) {
          if ((si = StowSlotFor(this, away[k], occ)) < 0) {
            IPrint("You have nowhere to put away the <Obj>.", away[k]);
            goto XAbortNoItem;
          }
          occ[si] = away[k]->myHandle;
