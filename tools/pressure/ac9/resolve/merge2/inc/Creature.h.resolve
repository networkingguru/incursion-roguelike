      FIELD_SKIP(LightAverseWasBright);   /* derived; never saved */
@@@ next hunk
      FIELD_H  ("defReach", defReach);
      FIELD_H  ("defReachOff", defReachOff);
      FIELD_H  ("defShort", defShort);
      FIELD_H  ("defShortOff", defShortOff);
      FIELD_ARRAY("BAttr", BAttr, sizeof(int16), 7);
      FIELD_ARRAY("KAttr", KAttr, sizeof(int16), ATTR_LAST);
      FIELD_ARRAY("SkillRanks", SkillRanks, sizeof(int8), SK_COUNT);
      FIELD_ARRAY("Feats", Feats, sizeof(uint16), (FEATBITS_LAST/8)+1);
@@@ next hunk
      /* The row length travels beside each array of rows (spec section 6.1,
         inc-cjos0). A file written before the field existed has rows of the
         length then in force: 11, 11, 15 here. */
      uint16 hpRollsRow = isSave ? MAX_CHAR_LEVEL : 11;
      uint16 manaRollsRow = isSave ? MAX_CHAR_LEVEL : 11;
      uint16 GainAttrRow = 15;
      FIELD_U16("hpRollsRow", hpRollsRow);
      FIELD_U16("manaRollsRow", manaRollsRow);
      FIELD_U16("GainAttrRow", GainAttrRow);
      FIELD_ARRAY_ROWS("hpRolls", hpRolls, sizeof(int8), 3, MAX_CHAR_LEVEL, hpRollsRow, 0);
      FIELD_ARRAY_ROWS("manaRolls", manaRolls, sizeof(int8), 3, MAX_CHAR_LEVEL, manaRollsRow, 0);
      FIELD_ARRAY("SaveBonus", SaveBonus, sizeof(int8), 16);
      FIELD_ARRAY_ROWS("GainAttr", GainAttr, sizeof(int16), 7, 15, GainAttrRow, 0);
@@@ next hunk
      FIELD_ARRAY("Spells", Spells, sizeof(uint32), MAX_SPELLS+1);
@@@ next hunk
      /* The last two columns of a SacVals row are the total and the maximum
         (src/Prayer.cpp), so the reader keeps them last (tail 2). */
      uint16 SacValsRow = isSave ? MAX_SAC_CATS + 2 : 12;
      FIELD_U16("SacValsRow", SacValsRow);
      FIELD_ARRAY_ROWS("SacVals", SacVals, sizeof(int32), MAX_GODS, MAX_SAC_CATS + 2, SacValsRow, 2);
@@@ next hunk
      FIELD_ARRAY("JournalInfo_numMonOfType", JournalInfo.numMonOfType, sizeof(int), MA_COUNT);
