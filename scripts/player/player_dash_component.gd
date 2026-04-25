extends Node
class_name PlayerDashComponent


@export var dash_speed := 390.0
var dashing := false
var can_dash := true


func try_start_dash(dash_stop_timer: Timer, dash_cooldown_timer: Timer) -> bool:
	if not can_dash:
		return false
	if not dash_cooldown_timer.is_stopped():
		return false

	dashing = true
	can_dash = false
	dash_stop_timer.start()
	dash_cooldown_timer.start()
	return true


func apply_dash_velocity(player: CharacterBody2D, direction: float, facing_left: bool) -> void:
	var dash_dir := direction
	if dash_dir == 0:
		dash_dir = -1 if facing_left else 1
	player.velocity.x = dash_dir * dash_speed


func on_dash_stop_timeout() -> void:
	dashing = false


func on_dash_cooldown_timeout() -> void:
	can_dash = true
