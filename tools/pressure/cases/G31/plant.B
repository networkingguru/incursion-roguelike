# G31: every addition of side B in one save
item grw-b flask
monster grw-b leucrotta
feature grw-b door
spell Grw B Bolt
god Grw B Deity favour 4
god Grw B Deity anger 1
god Grw B Deity flags 1
dungeon Grw B Cellar 1
class Grw B Class
race Grw B Race
varrid grw-b carrier grw_b_ref @ Grw B Domain
monster dragon
template grw-b hatchling @ dragon
terrain grw-b ooze
region Grw B Run
varrid grw-b carrier grw_b_ref2 @ help::grw-b
flavor Fury @ grw-b puce
varrid grw-b carrier grw_b_ref3 @ Grw B Pack
varrid grw-b carrier grw_b_ref4 @ Grw B Blade
varrid grw-b carrier grw_b_ref5 @ Grw B Behaviour
status GRW_B_AURA 29 0
status HESITATION 4 0 src=SS_GRWB
feat FT_LUCUBRATION
feat FT_GRWB
option OPT_GRWB 1
resave
item flask;retired
known flask;retired KN_MAGIC|KN_GRWB
iflags flask;retired IF_MASTERWORK|IF_GRWB
monster kobold
target TargetGrwB @ kobold
var barbazu claw_hits 11
var barbazu grw_b_time 29
var Grw B Bolt grw_state 6
roll hp 1 10 31
roll mana 2 10 42
roll hp 1 11 61
