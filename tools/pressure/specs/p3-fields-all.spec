# 9f-pre P3: one value per family whose value is the whole content of a saved member (1b) or rides in an array (1c),
# planted BY NAME (inc-cjos0). Reproduction for tools/pressure/plant.sh; see its header for the language.
# Names only. df_door and ms carry their top (sign) bit: DF_PICKED is 0x80 of an I8, MS_STILL_CAST 0x8000 of an I16.
monster kobold
set monster LastMoveDir EAST
set monster Flags F_SOLID
set monster StateFlags MS_PEACEFUL|MS_STILL_CAST
door oak door
set door DoorFlags DF_LOCKED|DF_PICKED
trap light trap
set trap TrapFlags TS_FOUND
feature dangling rope
set feature Flags F_INVIS
item long sword
set item Qualities WQ_HOLY
item chainmail
set item Qualities AQ_FIRE_RES
set field FType FI_OBVIOUS
set player Personality PA_ETERNAL_ROMANTIC
set player Proficiencies WG_LARMOUR
set player QuickKeys_Type[1] QKY_SPELL
set player QuickKeys_MM[1] MM_EXTEND|MM_STILL
set player MMArray[5] MM_EXTEND|MM_STILL
set player IntStudy[STUDY_BAB] 2
god Mara flags GS_INVOLVED|GS_CROWNED
spell Endure Fire SP_ARCANE|SP_MASTERED
# target_type needs no `set`: the target verb writes Target.type itself (TargetEnemy)
target TargetHitMe @ kobold
# 9f-pre P3 status links: DETECTING holds a monster type, ADJUST_DMG an attribute, CHARGING a direction
status DETECTING MA_REPTILE 18
status ADJUST_DMG A_STR 2
status CHARGING CENTER 3
