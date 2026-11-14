# Trials: chapter authoring guide

Trials is the precision-platformer mode of this game. A chapter is a chain of small **rooms**
(screens). You die in one hit, respawn instantly at the room's spawn, and the room resets.
Movement centres on the dash. Collectibles ("embers") are optional. Each chapter is one plain-text
file. It is built into real Godot nodes at load time, using the existing tilesets and the existing
scenes (spikes, enemy, orbs, vines, lamps, portal, moving platform, the spreading darkness).

You only edit **two files per chapter**:

| File | What |
|---|---|
| `trials/chapters/chapterN.gd` | the chapter (text between `r"""` and `"""`) |
| `trials/chapters/chapterN.replay` | scripted inputs that prove every room is beatable |

Slots: `chapter1.gd` → menu "Trials I" (scene `trials/scenes/trials_chapter1.tscn`), `chapter2.gd` →
"Trials II", `chapter3.gd` → "Trials III". The menu shows the chapter's `title:`.
The chapter is wrapped in a GDScript raw string, so exported builds include it (a `.txt` would be
dropped by the export filter). Do not put `"""` inside the text. Nothing else in the `.gd` needs
changing.

## Quick start (run from the repo root)

```bash
tools/trials/validate.sh trials/chapters/chapter2.gd          # format + structure check (headless, ~3 s)
TRIALS_DISPLAY=93 tools/trials/render.sh trials/chapters/chapter2.gd /tmp/me/r   # PNG per room + overview
tools/trials/replay.sh trials/chapters/chapter2.gd             # play the .replay, per-room report
tools/trials/replay.sh trials/chapters/chapter2.gd --room b --trace 5   # one room, print state every 5 frames
TRIALS_DISPLAY=93 tools/trials/replay.sh trials/chapters/chapter2.gd --room b --shots /tmp/me/s --every 15  # frames as PNG
```

Then look at the PNGs with your image viewer / Read tool. **Use your own X display number** for
`TRIALS_DISPLAY` (render and `--shots` start a private Xvfb on that display; parallel agents
must not share one). Validate and replay are headless and need no display.
Play the real scene: `~/tools/godot/godot --path . res://trials/scenes/trials_chapter2.tscn`.

A finished chapter means: `validate.sh` shows 0 errors and no warnings you did not intend,
`replay.sh` ends with `RESULT: n/n rooms cleared`, and you have looked at every room render.

---

## 1. File format

```
title: Hollow Run                 // shown in the menu and on the complete screen
subtitle: optional text
theme: cave                       // forest | cave | deep
music: lantern                    // optional override: forest | lantern | menu | none

[room hollow]                     // id: letters, digits, _ and -
name: Vine Wall                   // optional display name
at: 0 0                           // position of the top-left cell, in tiles (see 1.3)
######################
#....................#
#..........|##........
#.P........|##........
######################

[room run]
at: hollow right bottom
chase: medium
...grid...
```

* `//` starts a comment (whole line, or after a space at the end of a line).
* Header lines (`key: value`) come before the first `[room ...]`.
* Inside a room, put all `key: value` lines **above** the grid. The grid is the contiguous block of
  rows that follows; blank lines inside a grid are an error.
* Every row of a room must have exactly the same length (no spaces; use `.` for air).
* **Room order in the file = room number** (HUD "ROOM 3/12", replay order). The first room is the start.

### 1.1 Legend

| Char | Element | Placement rule / notes |
|---|---|---|
| `.` | air | |
| `#` | solid ground | autotiled with the theme's edge and corner tiles. Out-of-room cells count as solid for tiling |
| `=` | one-way platform | thin ledge: jump up through it, stand on top. Collision = top 8 px of the cell. Runs of `=` get end caps |
| `^` | spike pointing up | on a floor: needs `#` below. Hitbox 24×7 px at the cell's bottom (lenient: the edges are safe) |
| `v` | spike pointing down | under a ceiling: needs `#` above |
| `<` | spike pointing left | on a wall face: needs `#` to its right |
| `>` | spike pointing right | needs `#` to its left |
| `o` | double-jump orb (green ring) | while touching it, pressing jump in mid-air gives a full new jump. The orb is used up and returns after `orb_respawn` s |
| `*` | dash orb (blue ring) | touching it while your dash is spent refills the dash. Used up, returns after `orb_respawn` s |
| `\|` | vine | climbable wall side: wall-jumps only work while touching a vine. Put it in the air cell next to a `#` wall (left or right), as a vertical run of `\|`. Vine top should reach the height you need to climb to |
| `e` | walking enemy | stands on the floor (`#`/`=` below). One touch kills |
| `x` | hazard cell (red crystal) | instant death. Drawn with red crystal tiles. Use for pits, hazard pools and thorn fields |
| `c` | collectible ("ember") | optional. Follows you once touched; banked when you leave the room or reach the exit. If you die first it goes back |
| `P` | spawn point | needs `#`/`=` below. ≥1 per room. On room entry the respawn point becomes the `P` **nearest to where you entered** |
| `E` | chapter exit portal | 2 tiles tall (this cell + the one above, which must not be `#`). Needs floor below. Exactly one per chapter |
| `L` | lamp (heal light) | mid-room checkpoint: touching it moves the respawn point to the lamp. Heals in `drain` rooms. The darkness can never enter its light. About 2.5 tiles tall, stands on floor |
| `D` | darkness origin | only in `chase:` rooms, exactly one |
| `M` | moving platform start | centre of a 3-tile-wide platform (art from `scenes/platforms.tscn`). Its top surface sits at the top of the `M` cell |
| `m` | moving platform end | in the same row or column as its `M`, with only non-`#` cells between. The platform ping-pongs M↔m |

A **pit** is any bottom-border cell that is not `#` with no room below it. Falling out of the room
bottom kills.

### 1.2 Room keys

| Key | Default | Meaning |
|---|---|---|
| `at:` | (required, except first room = `0 0`) | placement, see 1.3 |
| `name:` | id | display name |
| `dark:` | no | dark room: the world goes dark, the player's lantern switches on (no battery drain) and the ambient glow lights a small circle. Visibility is roughly 4–5 tiles around the player plus the lantern cone ahead |
| `drain:` | no | the ambient darkness slowly drains health (5 HP/s outside lamp light, 100 HP = 20 s; health bar shows). Lamps heal. Hazards still kill in one hit |
| `chase:` | no | `fast` / `medium` / `slow` (or a number = seconds per block wave, smaller = faster; story values 0.11/0.12/0.2). Starts the spreading darkness (`scripts/darkness/Manager_Darkness.gd`) at `D` when the room is entered. It restarts on every death |
| `chase_delay:` | 0.6 | seconds before the darkness starts moving |
| `platform_speed:` | 64 | moving platform speed, px/s (eased at both ends) |
| `platform_wait:` | 0.4 | seconds a platform waits at each end. Platforms restart from `M` on room entry and on death |
| `orb_respawn:` | 2.5 | seconds until a used orb returns (0 = only on death / room re-entry) |
| `note:` | | free text, ignored |

### 1.3 Placement and links between rooms

Rooms live on one world grid (1 tile = 32 px). `at:` is either absolute `at: X Y` (top-left cell,
negative allowed) or relative to an already placed room:

```
at: <room> right  [N | top | bottom]   // to the right; N = vertical offset in tiles (top-aligned = 0)
at: <room> left   [N | top | bottom]
at: <room> above  [N | left | right]   // N = horizontal offset
at: <room> below  [N | left | right]
```

`bottom` aligns bottom edges, `right` aligns right edges. **Rooms must not overlap.**
`tools/trials/validate.sh` prints every room's resolved position.

**A link is just a gap.** Any non-`#` cell on a room's border that touches a cell of a
neighbouring room is a doorway. Line the gaps up. The neighbouring cell must not be `#`, or
you get a warning. A gap with no room behind it gets an invisible wall on the left, right or
top, plus a warning. On the bottom it is a pit.
Walking through a doorway gives a quick camera slide (0.32 s, the game pauses), refills the dash,
banks carried embers and sets the respawn point. Entering a room **upwards** through its floor
gives a small boost (vertical speed at least 330 px/s up) so you can reach a ledge next to the
hole. Put that ledge within about 1 tile of the hole.

Every room must be reachable from the first room through doorways. Each room should also have
a doorway into the next room in file order, otherwise the validator warns.

### 1.4 Themes

| theme | tiles | background | music / ambience |
|---|---|---|---|
| `forest` | forest sheet (`assets/tileset-Sheet.png`) | demon-woods parallax | forest theme + forest ambience |
| `cave` | deep-cave sheet (`assets/DeepCaveTile-Sheet-export-export.png`) | DeepCave parallax | lantern-cave music + cave ambience |
| `deep` | forest edges + black cave fill (the Lantern Cave look) | DeepCave, dimmed world | lantern-cave music + cave ambience |

In chase rooms the theme music is muted and the darkness plays its own chase music.
Suggested: Trials I = forest, II = cave, III = deep. Any theme works in any slot.

---

## 2. Screen and room size

* Camera zoom is 2. One screen shows **576 × 324 px = 18 × 10.1 tiles**.
* A room can be any size ≥ 1 cell. Smaller than 18×10 gets a warning: the camera centres the room
  and shows void around it. Larger rooms scroll. The camera follows the player and clamps to the room rectangle.
* Recommended: single-screen rooms of **20–24 × 10–12** (edge walls included). Use 30–60 wide for
  runs and chases, 14–25 tall for climbs. Keep rooms short: a room should take 5–25 s for a
  player who knows it. Many small rooms beat one huge room, because death sends you back only to the room start.
* The outer ring of a room is normally `#`. Leave gaps only for doorways and pits.
* The player is **16 × 29 px** (fits a 1-tile corridor). The player node's origin is 17.5 px
  below the feet; the replay tools report feet and body-centre values for you.

---

## 3. Rules of the mode (what the runtime does)

* **One-hit death** from spikes, enemies, hazard cells `x`, the darkness, and pits. The death effect
  lasts 0.32 s, then you respawn at the room's current respawn point (entry `P` or last lamp).
  On respawn the room resets: enemies, moving platforms, orbs, darkness, and embers not yet banked.
  No scene reload, no slow motion.
* **Dash** (Shift / F) goes in 8 directions (arrows or WASD; W / Up = up, S / Down = down). With no
  direction held it goes the way you face. You get **one dash**, refilled on landing, by a dash orb,
  or on room transition. The sprite turns blue-grey while the dash is spent. Jump does not fire
  during a dash (it is buffered for 0.1 s).
* **Jump**: coyote time 0.1 s, jump buffer 0.1 s, variable height (releasing jump while rising
  cuts upward speed to 45%). Wall jumps only work on vines (`|`), and only while touching the wall.
  Holding toward the wall after a wall jump keeps you on it, so you climb the vine.
* The pause menu (Esc / gamepad Start) has Resume, Retry Room (counts a death) and Back to Menu.
* HUD: deaths, chapter time (it keeps running through deaths), embers carried + banked / total, room number.
* Chapter complete (touching `E`): a screen with time, deaths and embers, then the menu. Best results
  are saved in `user://trials_progress.cfg` and shown in the level select.
* Story mode is untouched. These rules come from `scripts/player/player_movement_rules.gd`, which only
  the Trials scene assigns.

---

## 4. Movement envelope (measured, Trials rules)

Measured by `tools/trials/envelope.sh` (headless, 60 fps, deterministic) on a flat arena. "Rise" =
how far the feet get above the take-off floor. 1 tile = 32 px.

| Move | Max rise above start (feet) | Horizontal takeoff→landing | Dash displacement (during dash) | Air time | Max fall speed px/s |
|---|---|---|---|---|---|
| Standing full jump (hold jump) | 57 px (1.77 t) | 0 px (0.0 t) | - | 40 f | 312 |
| Shortest hop (tap jump 1 frame) | 17 px (0.52 t) | 0 px (0.0 t) | - | 21 f | 171 |
| Running full jump | 57 px (1.77 t) | 120 px (3.7 t) | - | 40 f | 312 |
| Running short hop | 17 px (0.52 t) | 63 px (2.0 t) | - | 21 f | 171 |
| Ground dash right | 0 px (0.00 t) | - | (+106, +0) px | 0 f | 0 |
| Ground dash up | 116 px (3.61 t) | 0 px (0.0 t) | (+0, -102) px | 53 f | 464 |
| Ground dash up+right | 80 px (2.49 t) | 91 px (2.8 t) | (+75, -72) px | 45 f | 375 |
| Apex dash right (jump, dash at apex) | 57 px (1.77 t) | 144 px (4.5 t) | (+106, +0) px | 57 f | 310 |
| Apex dash up | 172 px (5.37 t) | 0 px (0.0 t) | (+0, -102) px | 82 f | 480 |
| Apex dash up+right | 136 px (4.25 t) | 95 px (3.0 t) | (+75, -72) px | 75 f | 480 |
| Apex dash down+right | 57 px (1.77 t) | 57 px (1.8 t) | (+57, +52) px | 33 f | 283 |
| Apex dash down | 57 px (1.77 t) | 0 px (0.0 t) | (+0, +50) px | 30 f | 400 |
| Running jump + apex dash right | 57 px (1.77 t) | 241 px (7.5 t) | (+106, +0) px | 57 f | 310 |
| Running jump + apex dash up+right | 136 px (4.25 t) | 255 px (8.0 t) | (+75, -72) px | 75 f | 480 |
| Running jump + apex dash down+right | 57 px (1.77 t) | 120 px (3.7 t) | (+57, +52) px | 33 f | 283 |
| Orb double jump (jump into orb at apex, jump again) | 113 px (3.53 t) | 0 px (0.0 t) | - | 71 f | 459 |
| Orb double jump + dash up | 228 px (7.13 t) | 0 px (0.0 t) | (+0, -102) px | 111 f | 480 |
| Vine climb: hold toward vine wall, 6 wall jumps | 337 px (10.54 t) | - | - | 236 f | 70 |
| Fall from vine top (max fall speed) | 337 px (10.54 t) | 19 px (0.6 t) | - | 268 f | 480 |

Constants: run speed 180 px/s (instant start and stop), jump velocity −325 px/s, gravity
980 px/s², dash 400 px/s for 0.26 s, coyote 0.10 s, jump buffer 0.10 s, jump-cut factor 0.45,
max fall 480 px/s, wall slide 70 px/s, vine wall jump ≈ +47 px per jump (≈ 0.65 s per jump).

**Design numbers to remember**

* Jump height is small: **a plain jump clears 1 tile of height, never 2.** Every 2+ tile step
  needs a dash, an orb, a vine or a platform.
* Gaps: plain running jump **3 tiles** (3.7 measured; 3 is comfortable, 4 is impossible).
  Jump + dash **6 tiles** comfortable (7.5 max). Jump + up-right dash reaches 4 tiles up / 8 across.
* Vertical: ground dash up ≈ 3.5 tiles. Jump then dash up ≈ 5 tiles. Orb + dash ≈ 7 tiles.
* Floor spikes: a running jump clears **2 spikes easily, 3 is tight** (takeoff window ≈ 24 px).
* An orb registers when the orb centre comes within ≈ 45 px horizontally / 41 px vertically of a
  point 17 px **below the feet**. Put orbs where the feet pass, not the head. An orb 1–2 tiles above
  the take-off floor, 2–3 tiles out, gets hit by a normal running jump.
* A vine must reach to within ≈ 1 tile of the top you want to climb onto. The last wall jump lifts
  the feet ≈ 50 px above the point where you leave the vine.
* The darkness (`chase:`): it moves through open cells at ≈ 230 px/s while far away and slows to
  ≈ 62 px/s once it is within ≈ 240 px of you. A running player (180 px/s) stays ahead. Standing
  still for ~2–4 s gets you caught. It never enters lamp light. Lamps placed along a chase give
  safe pauses and checkpoints. The darkness flows around walls (4-neighbour cells inside the room
  rectangle) and treats one-way platforms as open.

---

## 5. Design rules

1. **One idea per room.** Introduce a mechanic safely first (no death if you fail), then ask
   for it under pressure, then combine it with an earlier one.
2. **Fair deaths.** Every hazard must be visible before you commit to a jump. With rooms bigger
   than a screen, hazards may be off screen; reveal them before the jump that needs them.
   No blind drops into spikes. Pits should be visibly empty.
3. **Safe spawn.** `P` needs 2+ tiles of hazard-free floor around it, no enemy that reaches it within
   3 s, and in chase rooms the `D` at least ~6 tiles behind. The validator warns about hazards next to `P`.
4. **The main path is readable.** Doorways should sit where the eye goes. Mark them with a gap in the
   wall and the floor continuing into it.
5. **Collectibles off the main path.** An ember should ask for an extra skill (apex dash up, orb chain,
   risky detour) and must be reachable *and* returnable from: never strand the player.
6. **Respect the envelope.** Leave about 10–20 % margin on required jumps. Frame-perfect only for
   optional embers, and even then rarely.
7. **Keep rooms short and many.** Aim for 8–15 rooms per chapter. Difficulty rises across the
   chapter with a breather room every 3–4 rooms. End the chapter with `E` in a calm spot.
8. **Enemies** (`e`) walk and turn **only at ledges** (drops). They hop over 1-tile steps and walk
   into walls without turning. They chase the player on sight (150 px cone ahead) and then ignore
   ledges. Put them on floor segments that end in drops on both sides (islands). Do not let them
   wander through doorways.
9. **Dark rooms**: keep layouts simple and hazards dense near the floor you see. Don't require
   seeing more than ~5 tiles ahead.

---

## 6. Tools

All tools live in `tools/trials/`. Exit code 0 means success.

### validate.sh

```
tools/trials/validate.sh <chapter.gd> [more files] [--strict]
```

Parses the chapter, resolves room positions, prints a room summary (position, size, spawns, flags,
links), builds every room headless (catches broken scene references), and reports:
format errors with `file:line`, unknown legend chars, uneven rows, missing/unsupported `P`/`E`, spikes
without support, vines without a wall, `M` without `m`, `D` outside chase rooms, overlapping rooms,
doorways into `#` or into the void, unreachable rooms, dead ends, chase rooms without a goal.
`--strict` makes warnings fail too.

### render.sh

```
TRIALS_DISPLAY=<your display no.> tools/trials/render.sh <chapter.gd> <out_dir> [--room <id>] [--no-grid]
```

Writes `<out_dir>/<chapter>_<NN>_<id>.png` (1 tile = 32 px, 1-tile margin) and
`<chapter>_overview.png` (the whole map, scaled). The render uses real game graphics and adds:
a tile grid with column/row numbers every 5 cells (yellow), the room outline and label (number,
id, size, DARK/DRAIN/CHASE), green `P` boxes, a purple `D`, blue platform paths, red outlines on
`x` cells and red dashes under pits. Dark rooms are drawn fully lit.

### replay.sh (beatability proof)

```
tools/trials/replay.sh <chapter.gd> [--replay <file>] [--room <id>] [--trace N]
TRIALS_DISPLAY=<n> tools/trials/replay.sh <chapter.gd> [--room <id>] --shots <dir> [--every N]
```

Default replay file: `<chapter>.replay` next to the chapter. For each room in file order the
harness teleports the player to that room's **entry spawn** (the `P` nearest the doorway from
the previous room in file order, i.e. where a death in that room sends you), waits until
grounded, then runs that room's script at a fixed 60 fps. Output per room:

```
room start          CLEARED -> climb in 279 frames, collectibles +1
room gate           DIED at (1752,114) local cell (14,6) frame 129 [script line ~44]
room hollow         STALLED: line 7: wait_wall timed out at pos=... col,row=(10,9) x,y=(347.0,319.9) ...
room run            TIMEOUT: script ended without leaving the room; ...
RESULT: 2/3 rooms cleared
```

A room counts as cleared when the player enters a different room or touches `E`. Runs are
deterministic: the same script always gives the same result. `--trace N` prints the state every
N frames: room-local `col,row` (cell of the body centre) and `x,y` (px: x = body centre,
y = feet), velocity, floor/wall contact, dash available. `--shots` saves PNG frames (slow software
rendering, use it on one room).

#### Replay DSL

One command per line (or several separated by `;`). `//` comments. A file is a list of
`[room <id>]` sections. 1 frame = 1/60 s.

| Command | Effect |
|---|---|
| `hold right` / `hold left+up` | keep direction keys held (persist until released) |
| `release right` / `release` | release some / all held directions |
| `wait N` | advance N frames with the current holds |
| `run right N` | hold right for N frames, then return to the previous holds |
| `jump N` | hold jump for N frames (default 1). `jump 20` = full jump, `jump 1` = shortest hop. A fresh press is guaranteed (if jump was still down, a 1-frame release is inserted) |
| `dash [dir]` | 1-frame dash press. With `dir` (e.g. `up+right`, `down`) the direction keys are exactly `dir` on that frame, then the holds return. Without `dir` the current holds decide |
| `tap <action> [N]` | press any input action for N frames (e.g. `tap flashlight`) |
| `wait_floor [max]` | wait until standing (default max 240 frames). The others below work the same way |
| `wait_air` / `wait_fall` / `wait_wall` / `wait_room` | wait until airborne / moving down / touching a wall in the air / in another room |
| `until col >= 12 [max]` | wait until the condition holds. Variables: `col`, `row` (room cell of the body centre), `x` (room px, centre), `y` (room px, feet). Operators `>= <= > <`. Default max 300 |
| `repeat N` … `endrepeat` | repeat a block |
| `log` | print the current state |

A `wait_*`/`until` that hits its max is reported as **STALLED** (bad script, not necessarily a bad
room). Typical patterns:

```
hold right; until x >= 180; jump 20; wait_floor          // jump over spikes at cols 7-8
jump 20; wait_fall; dash up                               // apex dash up
until col >= 10; jump 30; repeat 4; wait_wall 60; jump 30; endrepeat   // climb a vine (holding right)
until x >= 296; jump 20                                   // orb jump while passing a green orb
```

Write scripts the way a player would play: they should pass with some slack. If one only works
at one exact frame, the room is too tight; move a tile.

### envelope.sh

```
tools/trials/envelope.sh
```

Re-measures section 4 and prints the Markdown table. Run it if the player rules change.

---

## 7. Gotchas and limitations

* Do **not** edit `trials/scripts/*`, the player scripts, or the scene files to make a chapter
  work. Everything a chapter needs is in the text format. If a mechanic is missing, note it in
  your report instead.
* `x` is cell-sized (hitbox inset 4 px). Spikes have small hitboxes (24×7). Players can stand
  between two spikes that have a gap cell between them.
* One-way platforms (`=`) and moving platforms do not block the darkness. Solid `#` and lamp
  light do.
* The darkness only lives inside its room rectangle. It is removed when you leave and restarts
  when you re-enter or die. Lamps in a chase room become checkpoints, and the darkness then
  restarts about 5 tiles behind that lamp.
* Moving platforms push the player but do not crush: never move a platform into a wall where the
  player can stand.
* Enemies inherit the story enemy's behaviour (see design rule 8). Their red vision cone is drawn
  in the game.
* `music:` picks from the existing tracks only. The chase music is fixed.
* Rooms are built once at load. 30 rooms of ~25×12 load in well under a second.
* The validator does not prove physical reachability. Only the replay does.
