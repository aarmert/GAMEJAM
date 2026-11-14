extends Resource
class_name PlayerMovementRules
# Opt-in hareket/ölüm kuralları (Trials modu). Oyuncunun `movement_rules` alanı null ise
# (hikaye modu, varsayılan) player.gd eski kod yolunu birebir çalıştırır; bu dosyadaki hiçbir
# değer hikaye modunu etkilemez. Trials sahnesi oyuncuyu oluştururken bir örneğini atar.
#
# Opt-in movement/death rules used by Trials mode. When a player's `movement_rules` is null
# (story mode, the default) player.gd runs its original code path untouched.

## Coyote time: seconds after walking off a ledge during which a jump still counts as a floor jump.
@export var coyote_time := 0.1
## Jump buffer: a jump pressed this many seconds before landing fires on landing.
@export var jump_buffer_time := 0.1
## Variable jump height: releasing jump while rising multiplies vertical speed by this (1 = off).
@export var jump_cut_factor := 0.45
## Dash recharges when standing on the floor (instead of the 2.5 s cooldown timer).
@export var dash_refill_on_floor := true
## 8-direction dash (move_up / move_down + left/right). false = horizontal only, like story mode.
@export var dash_8way := true
## Seconds a dash lasts (story: dash_component.dash_duration = 0.26).
@export var dash_duration := 0.26
## When a dash ends, vertical speed becomes dash_dir.y * dash_speed * this (keeps a little lift).
@export var dash_end_vertical_factor := 0.35
## Terminal fall speed in px/s (0 = unlimited, as in story mode).
@export var max_fall_speed := 480.0
## Every double-jump orb gives one jump (orb is consumed) regardless of extra_jumps_left.
@export var orb_jump_ignores_extra_limit := true
## Hazards that call take_damage() kill in one hit. Ambient darkness drain is not affected.
@export var one_hit_kill := true
## die() does not reload the scene: the player emits `trials_died` and waits for trials_respawn().
@export var instant_retry := true
## Sound played on death in instant-retry mode ("death" also ducks the music for 2.5 s, too heavy
## for a game where you die a lot).
@export var death_sfx := "hurt"
## Tint of the sprite while the dash is spent (shows dash availability at a glance).
@export var no_dash_tint := Color(0.62, 0.72, 1.0, 1.0)
