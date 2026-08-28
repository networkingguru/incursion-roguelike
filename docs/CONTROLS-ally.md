<!-- Authored by the on-device Claude session during ROG Ally X controller
     setup on 2026-08-28, at Brian's request. AI-assisted; see the commit
     trailer. This documents a Steam Input layout that lives outside the repo
     (on the device); it changes no game code. -->

# Incursion — ROG Ally X controller mapping

Steam Input layout for the Linux/Steam Deck alpha, on an ASUS ROG Xbox Ally X (RC73XA) under SteamOS 3.8.16. Built against StandardKeySet (default; active whenever OPT_ROGUELIKE is off). The game is keyboard-only — no SDL_Joystick or SDL_GameController code at all — so every control is Steam Input synthesising a keystroke.

## Movement

  D-pad / left stick, up/down/left/right  -> Up/Down/Left/Right arrows  = N/S/W/E
  RIGHT STICK, pushed toward a corner     -> PgUp/PgDn/End/Home         = NE/SE/SW/NW

The right stick's regions are rotated 45 degrees, so pushing physically toward a corner emits that corner's key. Each diagonal is a single keypress = one game turn. This is why movement is split across two sticks (see Why below). Diagonals also work inside targeting prompts, which run in ARROW_MODE and accept exactly the eight direction keys.

## Commands — tap / hold (~1/3 sec) / double-tap

  A     tap y  (Yes / YUse)      hold Enter (confirm)   double  A  Activate magic item
  B     tap n  (No / Name)       hold Esc   (cancel)    double  B  Blast wand/staff
  X     tap G  Get               hold O  Open           --
  Y     tap I  Inventory         hold U  Use skill      --
  LB    tap L  Look              hold E  Eat            double  T  Talk
  RB    tap C  Attack            hold Q  Quaff          --
  LT    tap M  Magic             hold R  Read           --
  RT    tap Space (--more--)     hold S  Search         --
  M2    tap F  Fire/throw        hold V  Messages       double  D  Character sheet
  M1    tap ON-SCREEN KEYBOARD   hold .  Rest           double  Z  Sleep
  Menu  tap ?  Help
  View  tap =  Options
  L3    <  Up stairs             R3     >  Down stairs

W (wizmode) is deliberately unbound. Anything not listed — Pray, Kick, Jump, Hide, Run, Legend, letter-paged item lists — is reachable via the on-screen keyboard on M1. Free double-press slots remain on X, Y, RB, LT, RT.

## Two deliberate choices

A and B have tap and hold SWAPPED from the obvious arrangement. A taps y and B taps n; Enter and Esc are on the holds. Consequences: on the map a bare tap of A opens the YUse verb menu and a tap of B opens the Name prompt (both real commands, not misfires), and cancelling a menu requires a HOLD of B. Menu-cancel is one of the most frequent actions in play, so that is the first thing to revisit if menus feel sticky.

Why movement needs two sticks: Steam Input's dpad mode exposes only four inputs (dpad_north/south/east/west). There are no diagonal inputs anywhere in the config format; Steam's "8-way" option just fires two cardinal bindings at once, which for Incursion means Up then Right — two moves, two turns. Since StandardKeySet puts the diagonals on four distinct keys, the only way to get a true one-turn diagonal was to give them their own stick.

## Where it lives

  Layout      ~/.steam/steam/controller_base/templates/controller_rog_ally_incursion.vdf
  Copy        ~/Games/incursion-deck/incursion-steam-input.vdf
  Selection   ~/.local/share/Steam/steamapps/common/Steam Controller Configs/<userid>/config/configset_controller_rog_ally.vdf

Steam reads both only at startup. Reload with `systemctl --user restart steam-launcher.service` — restarts the Steam client alone (it is PartOf=graphical-session.target and gamescope-session does not depend on it), so Game Mode survives. ~20s black screen.

Steam identifies this device as controller_rog_ally and ships no templates for it, so left alone it falls back to another device's template — which is how a Switch Pro WASD layout ended up sending W/A/S/D to a game that reads arrow keys.
