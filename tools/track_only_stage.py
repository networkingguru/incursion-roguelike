#!/usr/bin/env python3
"""Build inc-8c3k's isolated arena/observer in a scratch module only."""
import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve()
assert 'logs' in root.parts
variant = sys.argv[2]
assert variant in ('armed', 'unarmed')
p = root / 'lib/dungeon.irh'
s = p.read_text()
pos = s.index('    Constants:')
driver = r'''
    hObj trackSubject;
    int16 trackSample, trackAttempts, trackBad, trackFirst, trackDist, trackVis, trackEvent;
    rID trackSpell;
    On Event EV_PRAY {
      rect arena; int16 ax, ay;
      if (trackSubject && !isValidHandle(trackSubject)) {
        EActor->IPrint("Track subject missing");
        EActor->ChoicePrompt("Track read?","x",'x');
        return DONE;
      }
      if (!trackSubject) {
        arena@x1 = 1; arena@y1 = 1;
        arena@x2 = EMap->SizeX()-2; arena@y2 = EMap->SizeY()-2;
        for (ax = 1; ax < EMap->SizeX()-1; ax++)
          for (ay = 1; ay < EMap->SizeY()-1; ay++)
            EMap->WriteAt(arena,ax,ay,$"Floor",EMap->RegionAt(ax,ay),100,true);
        EActor->PlaceAt(EMap,10,10);
        EActor->GainPermStati(ADJUST,NULL,SS_MISC,A_THP,127);
        trackSubject = CreateMonster($"narzugon");
        trackSubject->Initialize(true);
        trackSubject->mMana = 75;
        trackSubject->PlaceAt(EMap,44,10);
        trackSubject->TurnHostileTo(EActor);
        trackSubject->GainPermStati(TRACKING,EActor,SS_MISC,0,125);
      }
      EActor->cHP = EActor->mHP + EActor->GetAttr(A_THP);
      trackSubject->GainMana(1000);
      EActor->IPrint("Track <Num>: d <Num> per <Num> lof <Num> mana <Num>",
        trackSample,dist(EActor->x,EActor->y,trackSubject->x,trackSubject->y),
        trackSubject->Perceives(EActor),
        EMap->LineOfFire(trackSubject->x,trackSubject->y,EActor->x,EActor->y,trackSubject),
        trackSubject->cMana());
      EActor->IPrint("Attempts <Num> forbidden <Num> first <Num> d <Num> per <Num> event <Num>",
        trackAttempts,trackBad,trackFirst,trackDist,trackVis,trackEvent);
      if (trackSpell) EActor->IPrint("Attempted spell: <Res>",trackSpell);
      trackAttempts = 0;
      trackSample++;
      EActor->ChoicePrompt("Track read?","x",'x');
      return DONE;
    },
    PRE(EV_CAST), PRE(EV_INVOKE), PRE(EV_RATTACK), PRE(EV_SATTACK) {
      hObj player;
      player = theGame->GetPlayer(0);
      if (EActor && GetHandle(EActor) == trackSubject &&
          ((EVictim && GetHandle(EVictim) == player) ||
           (e.isLoc && e.EXVal == player->x && e.EYVal == player->y))) {
        trackAttempts++;
        if (EActor->Perceives(player) == PER_TRACK) {
          if (!trackBad) {
            trackFirst = trackSample;
            trackDist = dist(EActor->x,EActor->y,player->x,player->y);
            trackVis = EActor->Perceives(player);
            trackEvent = e.Event;
            trackSpell = e.eID;
          }
          trackBad++;
        }
      }
      return NOTHING;
    },
'''
s = s[:pos] + driver.rstrip().rstrip(',') + ';\n' + s[pos:]
p.write_text(s)
p = root / 'lib/mon4.irh'
s = p.read_text()
a = s.index('Monster "narzugon"')
b = s.index('\nMonster ', a + 1)
# A fixed loadout avoids random magic gear, mounts, summons and self-buffs.
monster = '''Monster "narzugon" : MA_DEVIL {
 Image: purple GLYPH_LDEVIL; Size: SZ_MEDIUM;
 CR: 11; HD: 10; Hit: +12; Def: 16; Mov: 50%; Spd: 150%;
 Str 18, Dex 14, Con 13, Int 12, Wis 13, Cha 19; 
 Attk: A_PUNC for 1d3 AD_BLUNT;
 ABILITY(CA_TRACKING,15);
 Flags: M_LAWFUL, M_EVIL, M_IALIGN, M_NO_CORPSE, M_HUMANOID, M_CLOSEID;
 SPELLS
 Desc: "Tracking-only invariant subject.";
}
'''.replace('SPELLS', 'Spells: $"unholy blight";' if variant == 'armed' else '')
p.write_text(s[:a] + monster + s[b:])
