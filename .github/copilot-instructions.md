# Copilot Instructions for GAMEJAM

## Project snapshot
- Engine: Godot 4.6 (`project.godot`, `config/features=PackedStringArray("4.6", "Forward Plus")`).
- Main scene: `res://scenes/mekanik_gelistirme.tscn` (`run/main_scene` in `project.godot`).
- Core gameplay is currently a single-level 2D platformer prototype.

## Code and scene boundaries
- `scripts/gelistirme_karakteri.gd`: player movement, jump, dash state machine, animation switching.
- `scenes/gelistirme karakteri.tscn`: player prefab wiring (`AnimatedSprite2D`, `dash_stop_timer`, `dash_cooldown_timer`, embedded `HealthBar`).
- `scripts/killzone.gd` + `scenes/killzone.tscn`: death zone logic; scene reload after timer timeout.
- `scenes/healthbar.gd` + `scenes/healthbar.tscn`: delayed damage bar behavior (`DamageBar` follows after `Timer`).
- `scenes/mekanik_gelistirme.tscn`: level composition (`TileMap`, player instance, `Camera2D`, `Killzone` instance).

## High-impact project conventions
- Treat scene node names as API contracts: scripts use direct `$NodeName` lookups (for example `$AnimatedSprite2D`, `$dash_stop_timer`, `$dash_cooldown_timer`, `$Timer`, `$DamageBar`).
- When editing scene trees, keep connected signal method names stable (`_on_dash_stop_timer_timeout`, `_on_timer_timeout`, etc.) or update both `.tscn` connections and script method names together.
- Preserve Turkish file/scene naming already used in project (for example `gelistirme karakteri.tscn`, `mekanik_gelistirme.tscn`, `gelistirme_karakteri.gd`); avoid renaming unless explicitly requested.
- Keep gameplay constants near top-level script constants (`SPEED`, `JUMP_VELOCITY`, `DASH_SPEED`) rather than hardcoding in branches.

## Input and gameplay flow
- Input actions are defined in `project.godot`: `jump`, `move_left`, `move_right`, `dash`.
- Player update flow in `_physics_process(delta)` is: gravity -> jump -> dash state updates -> facing flip -> movement/animation -> `move_and_slide()`.
- Dash behavior depends on both timers in the player scene:
  - `dash_stop_timer` controls dash duration (`dashing = false` on timeout).
  - `dash_cooldown_timer` controls dash re-enable (`can_dash = true` on timeout).

## Working safely in this repo
- Prefer editing `.gd` scripts for behavior changes; avoid hand-editing large `.tscn` blocks unless necessary.
- If a behavior depends on scene wiring, verify both script path assumptions and scene node/signal wiring.
- This repo currently has no discovered automated test suite or build scripts; validate by running the main scene in Godot Editor.
- Keep changes minimal and localized; this project is small and tightly coupled via scene-node paths.

## Quick validation checklist for agents
- Did you keep required child node names used via `$...` unchanged?
- Did input action names still match `project.godot` entries?
- Did connected signal methods still exist with exact names?
- If touching player movement/dash, did both timers and animation transitions remain coherent?
