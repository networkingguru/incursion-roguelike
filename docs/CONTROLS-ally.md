<!-- AI-assisted; see the commit trailer. Documents the ROG Ally X control
     scheme as shipped. This is now a HYBRID: the two analog sticks are read
     game-side by the binary (SDL_GameController, src/Wlibtcod.cpp), while the
     d-pad and every button are Steam Input bindings that live on the device.
     Verified on-device 2026-08-29. -->

# Incursion — ROG Ally X controls

The analog sticks are read by the game itself (native `SDL_GameController`
support in the SDL/libtcod build). The d-pad and all buttons are Steam Input
key bindings. Movement no longer uses a Steam-synthesised numpad — the game
reads the stick angle directly.

## Movement and view (game-side, analog sticks)

| Control | Action |
|---|---|
| **Left stick** | 8-way movement. The game snaps the stick angle to one of eight directions. One flick = one step; **hold a direction to autorun** (repeats after ~0.5 s until you recentre or change direction). |
| **Right stick** | Pan the view (look) in eight directions. Sends ALT+direction, which nudges the map view from normal play. |

## Commands (Steam Input → keyboard keys)

| Control | Press | Hold | Double-tap |
|---|---|---|---|
| **D-pad Up** | Kick (`K`) | Jump (`J`) | — |
| **D-pad Down** | Pray (`P`) | Hide (`H`) | — |
| **D-pad Left** | Legend (`/`) | Exchange (`-`) | — |
| **D-pad Right** | Run (`,`) | Tab | — |
| **A** | Yes / YUse | Confirm | Activate |
| **B** | No / Name | Cancel | Blast |
| **X** | Get | Open | — |
| **Y** | Inventory | Use | — |
| **LB** | Look | Eat | Talk |
| **RB** | Attack | Quaff | — |
| **LT** | Magic | Read | — |
| **RT** | More | Search | — |
| **M2 · left back** | Fire | Messages | Sheet |
| **M1 · right back** | **On-screen keyboard** | Rest | Sleep |
| **☰ Menu** | Help | — | — |
| **⊟ View** | Options | — | — |
| **L3 · left stick click** | Up stairs | — | — |
| **R3 · right stick click** | Down stairs | — | — |

## Notes

- **Sticks are game-side; d-pad and buttons are Steam Input.** Only the two
  analog sticks go to the game as raw gamepad. Everything else is a Steam Input
  key binding.
- **The d-pad MUST stay on keyboard keys — do not move it to gamepad output.**
  Steam's virtual pad on this device (`28de:11ff`) exposes the d-pad ONLY as a
  hat axis, it has no d-pad buttons, and SDL ships no mapping entry for that pad,
  so any game-side d-pad button read returns nothing forever. This was proven by
  an on-device evdev capture (36 hat events, zero key events). Binding the d-pad
  to keyboard keys sidesteps it entirely. The d-pad is four cardinal commands,
  which needs no diagonals, so the keyboard-key route loses nothing.
- **Press / hold / double-tap** are separate Steam Input bindings on the same
  control. Hold is ~1/3 second.
- **A and B have press and hold swapped** from the obvious arrangement: a press
  sends `y`/`n`, a hold sends Enter/Esc. On the map a press of A opens the YUse
  menu and a press of B opens the Name prompt — those are real commands, not
  misfires. Backing out of a menu is a **hold** of B.
- Anything unbound — page-by-letter item lists and the rest of the command set —
  is reachable via the **on-screen keyboard** on M1.
- `W` (wizmode) is deliberately unbound.
