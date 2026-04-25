extends CharacterBody2D


@onready var animated_sprit: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var dash_bar_ui: Node = $UI/DashBar
@onready var dash_stop_timer: Timer = $dash_stop_timer
@onready var dash_cooldown_timer: Timer = $dash_cooldown_timer
@onready var movement_component: Node = $Components/MovementComponent
@onready var jump_component: Node = $Components/JumpComponent
@onready var jump_wall_component: Node = $Components/JumpWallComponent
@onready var dash_component: Node = $Components/DashComponent
@onready var health_component: Node = $Components/HealthComponent

var safe_zones := 0
var orbit_zone_overlap_count := 0
var dash_orbit_overlap_count := 0


func _ready() -> void:
	health_component.init_health(health_bar)
	dash_bar_ui.init_dash(dash_cooldown_timer.wait_time)
	_update_dash_cooldown_ui()


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
		if dash_orbit_overlap_count > 0:
			dash_component.try_start_dash_forced(dash_stop_timer, dash_cooldown_timer)
		else:
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

	dash_component.update_cooldown_display(delta)
	move_and_slide()
	_update_dash_cooldown_ui()


func _update_dash_cooldown_ui() -> void:
	if dash_bar_ui == null:
		return

	if dash_component.can_dash and dash_component.get_cooldown_remaining() <= 0.0:
		dash_bar_ui.set_ready()
		return

	var remaining: float = max(dash_component.get_cooldown_remaining(), 0.0)
	var cooldown_duration: float = max(dash_component.get_cooldown_duration(), 0.001)
	dash_bar_ui.update_dash(remaining, cooldown_duration)


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


func _on_dash_stop_timer_timeout() -> void:
	dash_component.on_dash_stop_timeout()


func _on_dash_cooldown_timer_timeout() -> void:
	dash_component.on_dash_cooldown_timeout()


func _on_orbit_detector_area_entered(area: Area2D) -> void:
	if area.is_in_group("double_jump_orbit"):
		orbit_zone_overlap_count += 1
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count += 1


func _on_orbit_detector_area_exited(area: Area2D) -> void:
	if area.is_in_group("double_jump_orbit"):
		orbit_zone_overlap_count = max(orbit_zone_overlap_count - 1, 0)
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count = max(dash_orbit_overlap_count - 1, 0)


func _on_darkness_damage_timer_timeout() -> void:
	if safe_zones == 0 and health_component.can_receive_actions():
		take_damage(5)
