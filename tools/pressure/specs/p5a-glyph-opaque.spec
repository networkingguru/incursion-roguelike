# 9f-pre P5a: one value per glyph-word and opaque-byte family, planted BY NAME (inc-cjos0).
# glyph, colour: a feature, a door and a field carry a named glyph word. col: a field spell's COL_ value, packed as
# Magic.cpp:2032 packs it, so it overflows into the back nibble. hostility_*: the Hostility inside a Target's why.
monster kobold
feature dangling rope
set feature Image GLYPH_FLOOR2/RED/BLUE
door oak door
set door SecretSavedGlyph GLYPH_FLOOR2/YELLOW/GREEN
set door Image GLYPH_FLOOR2/COL_LIGHT
set field FType FI_OBVIOUS
set field Image GLYPH_FOG/SKYBLUE/PURPLE
set field Color EMERALD
target TargetWasSeenAndHostile quality=Enemy quantity=Strong hostility=HostilityFeud @ kobold
