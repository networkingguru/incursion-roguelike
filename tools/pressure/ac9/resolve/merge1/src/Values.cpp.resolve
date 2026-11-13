int16 Creature::WeaponSizeBonus()
{
    return (HasFeat(FT_MONKEY_GRIP) || HasStati(WEAPON_SIZE_UP)) ? 1 : 0;
}

/* this is the mount or the rider; throw the rider if the pair no longer
   fits. */
void Creature::CheckMountSize()
{
    Creature *mount, *rider;
    if (HasStati(MOUNT)) {
        mount = this;
        rider = (Creature*) GetStatiObj(MOUNT);
    } else if (HasStati(MOUNTED)) {
        mount = (Creature*) GetStatiObj(MOUNTED);
        rider = this;
    } else
        return;
    /* upstream: mount and recalculation size tests disagreed (Small-on-Small,
     * dwarf-on-Medium, quadruped-only upper limit; a typo compared the mount's
     * size with itself). Rule: a mount must be larger than its rider, no upper
     * limit. Plain type checks, same on Win32. Observed; inc-2mea; not sent. */
    if (rider->MountTooSmall(mount))
        ThrowVal(EV_DISMOUNT,DSM_THROWN,rider,mount);
}
static void ApplyAdjustRows(Creature *cr, int16 nature, int8 btype, bool KnownOnly);
static void BonusOrderProbeNote(Creature *c, bool KnownOnly);
@@@ next hunk
        /* Default-off probe (inc-pu6v.317): with INCURSION_DANCING_PROBE set,
           every real CalcValues logs the creature's handle, whether DANCING
           is on, and its final defense. */
        if (getenv("INCURSION_DANCING_PROBE") && !KnownOnly)
            Error("DANCING who=%d on=%d def=%d", myHandle,
                  HasStati(DANCING) ? 1 : 0, (int)Attr[A_DEF]);
        /* Default-off probe (inc-pu6v.325): with INCURSION_DENYAC_PROBE set,
           every real CalcValues logs the handle, DENY_AC_BONUS on or off,
           defense and noDexDefense(). */
        if (getenv("INCURSION_DENYAC_PROBE") && !KnownOnly)
            Error("DENYAC who=%d on=%d def=%d nodex=%d", myHandle,
                  HasStati(DENY_AC_BONUS) ? 1 : 0, (int)Attr[A_DEF],
                  noDexDefense() ? 1 : 0);
        BonusOrderProbeNote(this,KnownOnly);
