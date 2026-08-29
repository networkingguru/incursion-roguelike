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

## Movement and view (game-side, analog sticks)

| Control | Action |
|---|---|
| **Left stick** | 8-way movement. One flick = one step; **hold a direction to autorun** (repeats after ~0.5 s until you recentre or change direction). |
| **Right stick** | Pan the view (look) in eight directions. |
| **L3 · left stick click** | Up stairs (`<`) |
| **R3 · right stick click** | Down stairs (`>`) |

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
| **☰ Menu** | Help (`?`) | Eat (`e`) |
| **⊟ View** | Options (`=`) | Sheet (`d`) |

## Shift layer (hold LB)

Hold LB and use the control. This reaches all 12 of Incursion's macro slots
(F1–F12) plus the four commands that used to be double-taps.

| Control | Press | Hold |
|---|---|---|
| **D-pad Up / Down / Left / Right** | Macro F1 / F2 / F3 / F4 | — |
| **A** | Macro F5 | Search (`s`) |
| **B** | Macro F6 | Rest (`.`) |
| **X** | Macro F7 | Activate (`A`) |
| **Y** | Macro F8 | Blast (`B`) |
| **RB** | Macro F9 | — |
| **LT** | Macro F10 | — |
| **RT** | Macro F11 | — |
| **☰ Menu** | Macro F12 | — |
| **⊟ View** | Sleep (`z`) | — |

## Notes

- **The back buttons M1/M2 cannot be bound at all on the Ally.** The pad reports
  them as keyboard keys (F16/F17/F18/PROG1), not as controller buttons, so no
  Steam Input binding name reaches them. Do not try `button_back_*` or
  `button_macro_*` again — they do nothing on this hardware. Every command is
  reachable without them, so this layout also works on a pad with no back
  buttons.
- **Deliberately unbound:** Run (`,`) — left-stick autorun replaced it; Legend
  (`/`); Exchange (`-`); More (space); the on-screen keyboard. There is now NO
  way to type an arbitrary key, so the two tables above are the **complete**
  reachable command set.
- **Command keys are sent UNSHIFTED.** The keymap is case-insensitive (the game
  upper-cases the key before matching, `src/Wlibtcod.cpp:1770`), so lowercase
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
source. LB carries five `mode_shift` bindings (button_diamond, dpad,
left_trigger, right_trigger, switch), and each shifted group is qualified
`"<gid>" "<source> active modeshift"` in `group_source_bindings`. The qualifier
MUST be `active modeshift`, not a bare `modeshift` (a bare one works only by
tolerance, not by contract). The sticks are intentionally left out of the shift,
so the game keeps reading the raw analog for movement.

Valve's own worked examples of `mode_shift` live in
`~/.local/share/Steam/controller_base/*.vdf` (`basicui.vdf`,
`basicui_neptune.vdf`, `basicui_gamepad.vdf`, `desktop_neptune.vdf`) — one
directory ABOVE `controller_base/templates/`. None of the `templates/` files use
it, so searching only there wrongly suggests the feature is undocumented.

Steam also has a second mechanism, action layers (`action_layers`, activated by
`controller_action hold_layer`). This config does NOT use it: `mode_shift` is
simpler, and action layers have two reported bugs — a layer bound with a Toggle
activator never turns off, and spamming a hold-layer button can wedge the layer
on permanently.

## Installing the Steam Input config

Import [`incursion-steam-input-ally.vdf`](incursion-steam-input-ally.vdf) as the
controller layout for Incursion. The file keeps its UTF-8 BOM — Steam wrote it
that way; leave it.

**You do not need to restart Steam after editing a controller template.** Steam
re-reads the template when the GAME LAUNCHES, so write the file, then launch the
game. Only a `shortcuts.vdf` change needs a client restart.
