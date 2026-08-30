<!-- citations: this-port -->

<!-- AI-assisted; see the commit trailer. Documents the ROG Ally X control
     scheme as shipped and live on the device. HYBRID: the two analog sticks are
     read game-side by the binary (SDL_GameController, src/Wlibtcod.cpp); the
     d-pad and every button are Steam Input key bindings on the device.
     The exact working Steam Input config is checked in beside this file at
     docs/incursion-steam-input-ally.vdf. Verified on-device 2026-08-29. -->

# Incursion — ROG Ally X controls

The analog sticks are read by the game itself (native `SDL_GameController`
support in the SDL/libtcod build). The d-pad and all buttons are Steam Input
key bindings. **Hold LB** for a shift layer that reaches all 12 macro slots.
The exact config that produces this layout is checked in at
[`incursion-steam-input-ally.vdf`](incursion-steam-input-ally.vdf).

In play, `?` (RIGHT system button) shows this same table beside the keyboard
keys, as `Look  D-pad → (l)`, in as many columns as the screen is wide (three
on the Ally's 1600x1200 grid). The game shows the controller version when
it sees Steam's virtual pad (vendor `28de`) or the `SteamGameId` variable
Steam sets; `INCURSION_PAD_HELP=1` forces it on any machine, `=0` forces it
off. The table in `src/Help.cpp` (`PadHints`) is a copy of this layout and
must change with it.

**Naming the two system buttons.** On the ROG Ally the LEFT small system button
is Steam's `button_menu` and the RIGHT one is `button_escape` — the reverse of
what the glyphs suggest. This doc names them by **physical side** (LEFT / RIGHT),
not by the Steam token.

## Movement and view (game-side, analog sticks)

| Control | Action |
|---|---|
| **Left stick** | 8-way movement. One flick = one step; **hold a direction to autorun** (repeats after ~0.5 s until you recentre or change direction). |
| **Right stick** | Pan the view (look) in eight directions in play; out of play it scrolls (up/down = line, left/right = page). |
| **L3 · left stick click** | Up stairs (`<`) |
| **R3 · right stick click** | Down stairs (`>`) |
| **L3 hold · left stick click, hold** | Rest and Recover (`z`) |
| **R3 hold · right stick click, hold** | Exchange Weapons (`-`) |

The sticks are never mode-shifted, so movement and view pan are identical whether
or not you hold LB.

## Base commands (Steam Input → keyboard keys)

Press and hold are separate Steam Input bindings on the same control. Hold is
~350 ms. **There are no double-taps anywhere.**

| Control | Press | Hold |
|---|---|---|
| **D-pad Up** | Kick (`K`) | Pray (`P`) |
| **D-pad Down** | Jump (`J`) | Open (`o`) |
| **D-pad Left** | Hide (`H`) | Messages (`v`) |
| **D-pad Right** | Look (`l`) | Tab |
| **A** | Confirm (Enter) | Yes / YUse (`y`) |
| **B** | Cancel (Esc) | No / Name (`n`) |
| **X** | Examine (`x`) | Use (`u`) |
| **Y** | Get (`g`) | Inventory (`i`) |
| **LB** | **SHIFT** (hold — see below) | — |
| **RB** | Attack (`c`) | Quaff (`q`) |
| **LT** | Magic (`m`) | Read (`r`) |
| **RT** | Fire (`f`) | Target (`T`) |
| **LEFT system button** | SPACE (place item) | Eat (`e`) |
| **RIGHT system button** | Help (`?`) | Sheet (`d`) |

## Shift layer (hold LB)

Hold LB and use the control. This reaches all 12 of Incursion's macro slots
(F1–F12) plus the commands that used to be double-taps.

| Control | Press | Hold |
|---|---|---|
| **D-pad Up** | Macro F1 | Page Up |
| **D-pad Down** | Macro F2 | Page Down |
| **D-pad Left** | Macro F3 | Options (`=`) |
| **D-pad Right** | Macro F4 | On-screen keyboard |
| **A** | Macro F5 | Search (`s`) |
| **B** | Macro F6 | Rest (`.`) |
| **X** | Macro F7 | Activate (`A`) |
| **Y** | Macro F8 | Blast (`B`) |
| **LT** | Macro F10 | Macro F9 |
| **RT** | Macro F11 | Macro F12 |

The shift layer does **not** reach the bumpers or the two system buttons. Steam
will not mode-shift the group that contains the shift button itself (measured on
device); binding a shifted bumper or system button silently does nothing, with
no error. So F9 and F12 live on the trigger holds. Options landed on
shift+D-pad-Left-hold as a fallback after that retreat, not as a deliberate
choice — if the shift-group limitation is ever worked around, Options deserves a
better home. Sleep (`z`) is unbound; reach it via the on-screen keyboard. The
base layer is unchanged.

## Notes

- **SPACE is still bound (LEFT system button, press)** even though Confirm now
  does a full inventory swap. It costs nothing and is the native inventory key —
  it lifts/places an item in the In-Air slot directly.
- **The on-screen keyboard is on shift+D-pad-Right-hold.** Without it, typed prompts
  (Name, Journal, the "Some" quantity prompt), container digit picks, and
  inventory slot-letter selection are unreachable from the pad rather than merely
  awkward. Behind a modifier it costs nothing.
- **The back buttons M1/M2 cannot be bound at all on the Ally.** The pad reports
  them as keyboard keys (F16/F17/F18/PROG1), not as controller buttons, so no
  Steam Input binding name reaches them. Do not try `button_back_*` or
  `button_macro_*` again — they do nothing on this hardware. Every command is
  reachable without them, so this layout also works on a pad with no back
  buttons.
- **Deliberately unbound:** Run (`,`) — left-stick autorun replaced it; Legend
  (`/`); and More (space, as a -more- key). The full command set is
  reachable through the two tables above plus the on-screen keyboard.
- **Command keys are sent UNSHIFTED.** The keymap is case-insensitive (the game
  upper-cases the key before matching, `src/Wlibtcod.cpp:1800`), so lowercase
  keys resolve correctly. Only Help (`?`) and the stairs (`<` `>`) use
  `LEFT_SHIFT`.
- **Sticks are game-side; d-pad and buttons are Steam Input.** Only the two
  analog sticks go to the game as raw gamepad; everything else is a key binding.
- **The d-pad MUST stay on keyboard keys — do not move it to gamepad output.**
  Steam's virtual pad on this device (`28de:11ff`) exposes the d-pad ONLY as a
  hat axis, has no d-pad buttons, and SDL ships no mapping entry for that pad, so
  any game-side d-pad button read returns nothing forever. Proven by an on-device
  evdev capture (36 hat events, zero key events).
- `W` (wizmode) is deliberately unbound.

## How the shift layer works

The shift layer is a `mode_shift`: a second group bound to the same physical
source. LB carries four `mode_shift` bindings (button_diamond, dpad,
left_trigger, right_trigger — not the switch group, which holds LB itself and
Steam will not mode-shift), and each shifted group is qualified
`"<gid>" "<source> active modeshift"` in `group_source_bindings`. The qualifier
MUST be `active modeshift`, not a bare `modeshift` (a bare one works only by
tolerance, not by contract). The sticks are intentionally left out of the shift,
so the game keeps reading the raw analog for movement.

Valve's own worked examples of `mode_shift` live in
`~/.local/share/Steam/controller_base/*.vdf` (`basicui.vdf`,
`basicui_neptune.vdf`, `basicui_gamepad.vdf`, `desktop_neptune.vdf`) — one
directory ABOVE `controller_base/templates/`. None of the `templates/` files use
it, so searching only there wrongly suggests the feature is undocumented.

## Installing the Steam Input config

Import [`incursion-steam-input-ally.vdf`](incursion-steam-input-ally.vdf) as the
controller layout for Incursion. The file keeps its UTF-8 BOM — Steam wrote it
that way; leave it.

**You do not need to restart Steam after editing a controller template.** Steam
re-reads the template when the GAME LAUNCHES, so write the file, then launch the
game. Only a `shortcuts.vdf` change needs a client restart.
