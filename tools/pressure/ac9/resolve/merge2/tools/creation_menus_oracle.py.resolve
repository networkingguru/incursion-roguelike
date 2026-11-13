    # fallback line for MenuQuietMonk. inc-pu6v.9: Maeve's own three-row
    # MSG_FORBIDDEN_CLASS line is asserted here too, for its own sake rather
    # than as an overflow driver; the footer is uncapped in this scenario. Aiswin
    # does not forbid Monk, stays offered, and creation finishes under him.
    block(god, GOD_HEADING, 'god menu')
    expect(white_heading(raw, GOD_HEADING), 'god heading is drawn in WHITE')
    maeve_line = ("Maeve -- \"That calling of yours has someone else's name "
                  "written all through it. I don't share my toys, darling. "
                  "I break them first.\"")
    expect(maeve_line in flat(god), "Maeve's own Forbidden-class line")
@@@ next hunk
    for forbidder in ('Ekliazeh', 'Erich', 'Khasrach', 'Maeve', 'Sabine',
                      'Semirath', 'Zurvash', 'Xel',
                      'MenuNoMonk', 'MenuQuietMonk'):
        expect(bool(re.search(r'^\s*\* ' + re.escape(forbidder) + r' -- \S', god, re.M)),
@@@ next hunk
    # inc-pu6v.9: a Human Priest hits Maeve's priest rule (MSG_CUSTOM5). Every
    # alignment but Chaotic Neutral and Chaotic Evil is refused, and in the
    # merged game (inc-pu6v.268) all seven share one reason, so they render as
    # a single grouped row with her spoken line in quotes -- never the engine's
    # fallback. The footer is uncapped here and the whole row fits (inc-pu6v.9).
    priest = ('"A priest? Of mine? With that orderly little soul? I would have to '
              'open you up to fit inside, pet, and you would never quite close again."')
    refused = ('Lawful Good', 'Neutral Good', 'Chaotic Good', 'Lawful Neutral',
               'Neutral', 'Lawful Evil', 'Neutral Evil')
    block(align, 'Maeve will not accept these alignments:', 'alignment menu (a god refuses some rows)')
    for alignment in refused:
