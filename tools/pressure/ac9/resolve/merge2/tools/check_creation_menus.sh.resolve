for scenario in fixture roll-first emptyalign maeve semirath monk; do
    # Only the fixture, roll-first, emptyalign and semirath scenarios test the footer's overflow
    # ("...and N more."), so they cap footer space at 11. The monk scenario
    # overrides it to 24 below so its exact refused lines render; the maeve
    # scenario leaves it unset so all her refused alignments render.
    unset INCURSION_FOOTER_MAX_LINES
    case "$scenario" in
    fixture|roll-first|emptyalign|semirath) export INCURSION_FOOTER_MAX_LINES=11 ;;
    esac
