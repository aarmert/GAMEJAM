extends CharacterBody2D


@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var dash_bar_ui: DashBarUI = $UI/DashBar
@onready var dash_stop_timer: Timer = $dash_stop_timer
@onready var dash_cooldown_timer: Timer = $dash_cooldown_timer
@onready var movement_component: Node = $Components/MovementComponent
@onready var jump_component: Node = $Components/JumpComponent
@onready var jump_wall_component: Node = $Components/JumpWallComponent
@onready var dash_component: Node = $Components/DashComponent
@onready var health_component: Node = $Components/HealthComponent

@export var starts_with_dash_skill := false
@export var starts_with_flashlight_skill := false

var safe_zones := 0
var double_jump_orbit_overlap_count := 0
var dash_orbit_overlap_count := 0
var has_dash_skill := false
var has_flashlight_skill := false
var flashlight_is_on := false
var flashlight_light: PointLight2D = null


func _ready() -> void:
	health_component.init_health(health_bar)
	has_dash_skill = starts_with_dash_skill
	has_flashlight_skill = starts_with_flashlight_skill
	if not has_dash_skill:
		dash_component.can_dash = false

	flashlight_light = get_node_or_null("FlashlightPivot/PointLight2D") as PointLight2D
	if has_flashlight_skill:
		_ensure_flashlight_light()
		_set_flashlight_enabled(true)
	else:
		_set_flashlight_enabled(false)

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
			jump_component.try_extra_jump(self, double_jump_orbit_overlap_count > 0)

	if has_dash_skill and Input.is_action_just_pressed("dash"):
		if dash_orbit_overlap_count > 0:
			dash_component.try_start_dash_forced(dash_stop_timer, dash_cooldown_timer)
		else:
			dash_component.try_start_dash(dash_stop_timer, dash_cooldown_timer)

	movement_component.apply_facing(animated_sprite, direction)

	if dash_component.dashing:
		dash_component.apply_dash_velocity(self, direction, animated_sprite.flip_h)
		dash_component.spawn_dash_trail(self, animated_sprite, delta)
		animated_sprite.play("dash")
	else:
		if not dash_component.apply_recovery_movement(self, direction, movement_component.speed, delta):
			movement_component.apply_horizontal_movement(self, direction)

		if is_on_floor():
			if direction == 0:
				animated_sprite.play("idle")
			else:
				animated_sprite.play("run")
		elif touching_wall:
			animated_sprite.play("wall_slide")
		else:
			animated_sprite.play("jump")

	dash_component.update_cooldown_display(delta)
	move_and_slide()
	_update_dash_cooldown_ui()


func _update_dash_cooldown_ui() -> void:
	if dash_bar_ui == null:
		return

	if not has_dash_skill:
		dash_bar_ui.set_locked()
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
		double_jump_orbit_overlap_count += 1
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count += 1


func _on_orbit_detector_area_exited(area: Area2D) -> void:
	if area.is_in_group("double_jump_orbit"):
		double_jump_orbit_overlap_count = max(double_jump_orbit_overlap_count - 1, 0)
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count = max(dash_orbit_overlap_count - 1, 0)


func _on_darkness_damage_timer_timeout() -> void:
	if safe_zones == 0 and health_component.can_receive_actions():
		take_damage(5)


func _unhandled_input(event: InputEvent) -> void:
	if not has_flashlight_skill:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_set_flashlight_enabled(not flashlight_is_on)


func unlock_skill(skill_name: String) -> bool:
	match skill_name:
		"dash":
			return unlock_dash_skill()
		"flashlight":
			return unlock_flashlight_skill()
		_:
			return false


func unlock_dash_skill() -> bool:
	if has_dash_skill:
		return false
	has_dash_skill = true
	dash_component.can_dash = true
	dash_component.cooldown_time_left = 0.0
	_update_dash_cooldown_ui()
	return true


func unlock_flashlight_skill() -> bool:
	if has_flashlight_skill:
		return false
	has_flashlight_skill = true
	_ensure_flashlight_light()
	_set_flashlight_enabled(true)
	return true


func _set_flashlight_enabled(is_enabled: bool) -> void:
	flashlight_is_on = is_enabled and has_flashlight_skill
	if flashlight_light:
		flashlight_light.enabled = flashlight_is_on


func _ensure_flashlight_light() -> void:
	if flashlight_light and is_instance_valid(flashlight_light):
		return

	var pivot := get_node_or_null("FlashlightPivot") as Node2D
	if pivot == null:
		pivot = Node2D.new()
		pivot.name = "FlashlightPivot"
		add_child(pivot)

	flashlight_light = PointLight2D.new()
	flashlight_light.name = "PointLight2D"
	flashlight_light.position = Vector2(0, -24)
	flashlight_light.energy = 1.3
	flashlight_light.texture_scale = 0.2
	flashlight_light.range_z_min = -4096
	flashlight_light.range_z_max = 4096
	flashlight_light.range_layer_min = -128
	flashlight_light.range_layer_max = 128

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0)
	])

	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256
	gradient_texture.height = 256
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.5, 0.5)
	gradient_texture.fill_to = Vector2(1, 0.5)
	flashlight_light.texture = gradient_texture

	pivot.add_child(flashlight_light)
