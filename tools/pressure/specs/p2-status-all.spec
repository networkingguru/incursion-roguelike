# 9f-pre P2: one status per family whose value rides in Status.val or Status.mag, planted BY NAME (inc-cjos0).
# Reproduction for tools/pressure/plant.sh; see its header for the language. Names only, no number names a family member.
status SAVE_BONUS SN_KNOCKDOWN 4
status IMMUNITY AD_FIRE
status RESIST AD_COLD 5
status HEAL_TIMEOUT AD_POIS
status SPEC_TIMEOUT A_BREA
status SUSPEND_ATTK A_CLAW
status NONDETECTION PER_TREMOR|PER_SCENT
status BONUS_SCHOOL_CASTING_LEVEL SC_EVO|SC_DIV 1
status SCHOOL_FOCUS 0 SC_ABJ
status ALIGNMENT AL_LAWFUL|AL_GOOD
status WEP_SKILL WS_FOCUSED 0 eid=short sword
status ANIMAL_COMPANION TA_LEADER
status HAS_ANIMAL TA_LEADER
status BLINDNESS BLIND_EYES_CLOSED
status PARALYSIS PARA_HELD
status AFRAID FEAR_COWED
status STUCK STUCK_WEB
status SINGING BARD_COURAGE 0
status ENGULFED EG_ENGULF
status INVIS INV_IMPROVED
status PHASED PHASE_ASTRAL
status CHARMED CH_ALLY
status MISS_CHANCE MISS_FULL 50
status GAZE_REFLECTION GR_IMMUNE
# SLEEPING, HIDING and ELEVATED come last: an earlier status of this spec (blind, paralysis, fear) ends them on the resave
status SLEEPING SLEEP_NATURAL
status HIDING HI_WATER
status ELEVATED ELEV_TREE
# ENGULFER (val_engulfed too) is not planted: it holds the engulfed creature as its object, and the planter has no object to give
