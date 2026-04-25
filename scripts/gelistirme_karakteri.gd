extends CharacterBody2D


@onready var animated_sprit: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var dash_cooldown_label: Label = $UI/DashCooldownPanel/DashCooldownLabel
@onready var dash_cooldown_bar: ProgressBar = $UI/DashCooldownPanel/DashCooldownPanelBg/HBoxContainer/DashTextColumn/DashCooldownBar
@onready var dash_stop_timer: Timer = $dash_stop_timer
@onready var dash_cooldown_timer: Timer = $dash_cooldown_timer
@onready var movement_component: Node = $Components/MovementComponent
@onready var jump_component: Node = $Components/JumpComponent
@onready var jump_wall_component: Node = $Components/JumpWallComponent
@onready var dash_component: Node = $Components/DashComponent
@onready var health_component: Node = $Components/HealthComponent

var orbit_zone_overlap_count := 0

func _physics_process(delta: float) -> void:
	if not health_component.can_receive_actions():
		velocity += get_gravity() * delta
		move_and_slide()
		return

	if not dash_component.dashing:
		jump_wall_component.apply_gravity(self, delta)
	jump_component.reset_on_floor(self)

	var direction := Input.get_axis("move_left", "move_right")
	var touching_wall: bool = jump_wall_component.apply_wall_slide(self, not dash_component.dashing)

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			jump_component.jump_from_floor(self)
		elif touching_wall:
			jump_wall_component.wall_jump(self, jump_component.jump_velocity)
			jump_component.restore_extra_jumps()
		else:
			jump_component.try_extra_jump(self, orbit_zone_overlap_count > 0)

	if Input.is_action_just_pressed("dash"):
		dash_component.try_start_dash(dash_stop_timer, dash_cooldown_timer)

	movement_component.apply_facing(animated_sprit, direction)

	if dash_component.dashing:
		dash_component.apply_dash_velocity(self, direction, animated_sprit.flip_h)
		dash_component.spawn_dash_trail(self, animated_sprit, delta)
		animated_sprit.play("dash")
	else:
		if not dash_component.apply_recovery_movement(self, direction, movement_component.speed, delta):
			movement_component.apply_horizontal_movement(self, direction)

		if is_on_floor():
			if direction == 0:
				animated_sprit.play("idle")
			else:
				animated_sprit.play("run")
		elif touching_wall:
			animated_sprit.play("wall_slide")
		else:
			animated_sprit.play("jump")

	move_and_slide()
	_update_dash_cooldown_ui()


func _on_dash_stop_timer_timeout() -> void:
	dash_component.on_dash_stop_timeout()


func _on_dash_cooldown_timer_timeout() -> void:
	dash_component.on_dash_cooldown_timeout()


func _on_orbit_detector_area_entered(area: Area2D) -> void:
	if area.is_in_group("orbit_zone"):
		orbit_zone_overlap_count += 1


func _on_orbit_detector_area_exited(area: Area2D) -> void:
	if area.is_in_group("orbit_zone"):
		orbit_zone_overlap_count = max(orbit_zone_overlap_count - 1, 0)


func _ready() -> void:
	health_component.init_health(health_bar)
	_update_dash_cooldown_ui()


func _update_dash_cooldown_ui() -> void:
	if dash_cooldown_timer.is_stopped() and dash_component.can_dash:
		dash_cooldown_label.text = "Dash: Ready"
		dash_cooldown_label.modulate = Color(0.55, 1.0, 0.55, 1.0)
		dash_cooldown_bar.value = 100.0
		return

	var remaining: float = max(dash_cooldown_timer.time_left, 0.0)
	var total_time: float = max(dash_cooldown_timer.wait_time, 0.001)
	var percent_ready: float = clamp(1.0 - (remaining / total_time), 0.0, 1.0)
	dash_cooldown_label.text = "Dash: %.1f" % remaining
	dash_cooldown_label.modulate = Color(1.0, 0.75, 0.45, 1.0)
	dash_cooldown_bar.value = percent_ready * 100.0


func take_damage(amount: int) -> void:
	if health_component.apply_damage(health_bar, amount):
		Engine.time_scale = 0.5
		die()


func heal(amount: int) -> void:
	health_component.apply_heal(health_bar, amount)


func die() -> void:
	health_component.mark_dead()
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	await get_tree().create_timer(0.7, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
