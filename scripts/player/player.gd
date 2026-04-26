extends CharacterBody2D


@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var dash_bar_ui: DashBarUI = get_node_or_null("UI/DashBar") as DashBarUI
@onready var flashlight_bar_ui: FlashlightBarUI = get_node_or_null("UI/FlashlightBar") as FlashlightBarUI
@onready var dash_stop_timer: Timer = $dash_stop_timer
@onready var dash_cooldown_timer: Timer = $dash_cooldown_timer
@onready var movement_component: Node = $Components/MovementComponent
@onready var jump_component: Node = $Components/JumpComponent
@onready var jump_wall_component: Node = $Components/JumpWallComponent
@onready var dash_component: Node = $Components/DashComponent
@onready var health_component: Node = $Components/HealthComponent
@onready var flashlight_component: PlayerFlashlightComponent = $Components/FlashlightComponent

@export var starts_with_dash_skill := false
@export var starts_with_flashlight_skill := false
@export var darkness_damage_enabled := false

var safe_zones := 0
var double_jump_orbit_overlap_count := 0
var dash_orbit_overlap_count := 0
var has_dash_skill := false
var has_flashlight_skill := false
var _flashlight_light: PointLight2D = null
var sarmasikta_mi: bool = false


func _ready() -> void:
	health_component.init_health(health_bar)
	has_dash_skill = starts_with_dash_skill
	if not has_dash_skill:
		dash_component.can_dash = false
	if dash_bar_ui != null:
		dash_bar_ui.init_dash(dash_cooldown_timer.wait_time)
	_update_dash_cooldown_ui()

	has_flashlight_skill = starts_with_flashlight_skill
	if has_flashlight_skill:
		_setup_flashlight()
	elif flashlight_bar_ui != null:
		flashlight_bar_ui.set_locked()


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
		elif touching_wall and sarmasikta_mi:			
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
			# Havada: yatay hareket varsa kosma-zipla, yoksa yerinde-zipla
			if direction == 0:
				animated_sprite.play("idle_jump")
			else:
				animated_sprite.play("jump")

	dash_component.update_cooldown_display(delta)
	move_and_slide()
	_update_dash_cooldown_ui()

	if has_flashlight_skill:
		flashlight_component.flashlight_update(delta)
		_update_flashlight_direction()


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
		die()


func heal(amount: int) -> void:
	health_component.apply_heal(health_bar, amount)


func die() -> void:
	health_component.mark_dead()

	# 1) Slow motion → düsüsü dramatik göster
	Engine.time_scale = 0.4

	# 2) Yukari zipla yok — direkt yerçekimiyle asagi düssün
	velocity = Vector2.ZERO

	# 3) Tüm çarpısmayi kapat → yerden gecip asagi düssün
	collision_layer = 0
	collision_mask = 0

	# 4) Düsme pozu (renk degismez)
	animated_sprite.play("idle_jump")

	# 5) Gercek 3 saniye bekle → yavas çekimde düstügü görünür
	await get_tree().create_timer(3.0, true, false, true).timeout

	# 6) Reset ve sahneyi yenile
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
	if not darkness_damage_enabled:
		return
	if safe_zones == 0 and health_component.can_receive_actions():
		take_damage(5)


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
	_setup_flashlight()
	return true


func _setup_flashlight() -> void:
	_ensure_flashlight_light()
	flashlight_component.init_flashlight(_flashlight_light, null)
	flashlight_component.battery_changed.connect(_on_flashlight_battery_changed)
	if flashlight_bar_ui != null:
		flashlight_bar_ui.update_battery(1.0, false)


func _on_flashlight_battery_changed(percent: float) -> void:
	if flashlight_bar_ui != null:
		flashlight_bar_ui.update_battery(percent, flashlight_component.is_on)


func _update_flashlight_direction() -> void:
	var pivot := get_node_or_null("FlashlightPivot") as Node2D
	if pivot == null:
		return
	pivot.scale.x = -1.0 if animated_sprite.flip_h else 1.0


func _ensure_flashlight_light() -> void:
	if _flashlight_light and is_instance_valid(_flashlight_light):
		return

	var pivot := get_node_or_null("FlashlightPivot") as Node2D
	if pivot == null:
		pivot = Node2D.new()
		pivot.name = "FlashlightPivot"
		pivot.position = Vector2(0, -28)
		add_child(pivot)

	_flashlight_light = PointLight2D.new()
	_flashlight_light.name = "PointLight2D"
	_flashlight_light.position = Vector2(0, 0)
	_flashlight_light.energy = 1.5
	_flashlight_light.texture_scale = 1.5
	_flashlight_light.range_z_min = -4096
	_flashlight_light.range_z_max = 4096
	_flashlight_light.range_layer_min = -128
	_flashlight_light.range_layer_max = 128
	_flashlight_light.enabled = false
	_flashlight_light.texture = _create_cone_texture()

	pivot.add_child(_flashlight_light)


func _create_cone_texture() -> ImageTexture:
	var size: int = 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: int = size >> 1
	var cx: float = float(half)
	var cy: float = float(half)
	var max_dist: float = float(half)
	var half_angle: float = deg_to_rad(35.0)
	for y in range(size):
		for x in range(size):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			if dx <= 0.0:
				continue
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist > max_dist:
				continue
			var angle: float = abs(atan2(dy, dx))
			if angle > half_angle:
				continue
			var dist_falloff: float = 1.0 - dist / max_dist
			var angle_falloff: float = 1.0 - angle / half_angle
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(dist_falloff * sqrt(angle_falloff), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
