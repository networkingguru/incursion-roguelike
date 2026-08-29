<!-- AI-assisted; see the commit trailer. Documents the ROG Ally X control
     scheme as shipped and live on the device. HYBRID: the two analog sticks are
     read game-side by the binary (SDL_GameController, src/Wlibtcod.cpp); the
     d-pad and every button are Steam Input key bindings on the device.
     Verified on-device 2026-08-29. -->

# Incursion — ROG Ally X controls

The analog sticks are read by the game itself (native `SDL_GameController`
support in the SDL/libtcod build). The d-pad and all buttons are Steam Input
key bindings.

## Movement and view (game-side, analog sticks)

| Control | Action |
|---|---|
| **Left stick** | 8-way movement. One flick = one step; **hold a direction to autorun** (repeats after ~0.5 s until you recentre or change direction). |
| **Right stick** | Pan the view (look) in eight directions. |
| **L3 · left stick click** | Up stairs (`<`) |
| **R3 · right stick click** | Down stairs (`>`) |

## Commands (Steam Input → keyboard keys)

Press / hold / double-tap are separate Steam Input bindings on the same control.
Hold is ~350 ms.

| Control | Press | Hold | Double-tap |
|---|---|---|---|
| **D-pad Up** | Kick (`K`) | Pray (`P`) | — |
| **D-pad Down** | Jump (`J`) | Open (`o`) | — |
| **D-pad Left** | Hide (`H`) | Legend (`/`) | — |
| **D-pad Right** | Tab | Exchange (`-`) | — |
| **A** | Yes / YUse (`y`) | Confirm (Enter) | Activate (`A`) |
| **B** | No / Name (`n`) | Cancel (Esc) | Blast (`B`) |
| **X** | Examine (`x`) | Use (`u`) | — |
| **Y** | Get (`g`) | Inventory (`i`) | — |
| **LB** | Look (`l`) | Eat (`e`) | — |
| **RB** | Attack (`c`) | Quaff (`q`) | Search (`s`) |
| **LT** | Magic (`m`) | Read (`r`) | — |
| **RT** | Fire (`f`) | Target (`T`) | — |
| **M2 · left back** | More (space) | Messages (`v`) | Sheet (`d`) |
| **M1 · right back** | **On-screen keyboard** | Rest (`.`) | Sleep (`z`) |
| **☰ Menu** | Help (`?`) | — | — |
| **⊟ View** | Options (`=`) | — | — |

## Notes

- **Run is gone on purpose.** Left-stick autorun replaced the old Run command
  (`,`), so there is no dedicated Run binding — hold a movement direction instead.
- **Command keys are sent UNSHIFTED.** The keymap is case-insensitive (the game
  upper-cases the key before matching, `src/Wlibtcod.cpp:1770`), so lowercase
  keys resolve correctly. Only genuinely shifted characters use shift: Help
  (`?`) and the stairs (`<` `>`).
- **Sticks are game-side; d-pad and buttons are Steam Input.** Only the two
  analog sticks go to the game as raw gamepad; everything else is a key binding.
- **The d-pad MUST stay on keyboard keys — do not move it to gamepad output.**
  Steam's virtual pad on this device (`28de:11ff`) exposes the d-pad ONLY as a
  hat axis, has no d-pad buttons, and SDL ships no mapping entry for that pad, so
  any game-side d-pad button read returns nothing forever. Proven by an on-device
  evdev capture (36 hat events, zero key events). The d-pad is four cardinal
  commands, which needs no diagonals, so the keyboard route loses nothing.
- **A and B have press and hold swapped** from the obvious arrangement: a press
  sends `y`/`n`, a hold sends Enter/Esc. On the map a press of A opens the YUse
  menu and a press of B opens the Name prompt — those are real commands, not
  misfires. Backing out of a menu is a **hold** of B.
- Anything unbound is reachable via the **on-screen keyboard** on M1.
- Free double-tap slots: X, Y, LB, LT, RT, and all four d-pad directions.
- `W` (wizmode) is deliberately unbound.
