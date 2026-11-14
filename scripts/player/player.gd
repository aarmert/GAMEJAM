extends CharacterBody2D


@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = _resolve_health_bar()
@onready var dash_bar_ui: DashBarUI = $UI/DashBar
@onready var flashlight_bar_ui: FlashlightBarUI = $UI/FlashlightBar
@onready var dash_stop_timer: Timer = $dash_stop_timer
@onready var dash_cooldown_timer: Timer = $dash_cooldown_timer
@onready var movement_component: Node = $Components/MovementComponent
@onready var jump_component: Node = $Components/JumpComponent
@onready var jump_wall_component: Node = $Components/JumpWallComponent
@onready var dash_component: Node = $Components/DashComponent
@onready var health_component: PlayerHealthComponent = $Components/HealthComponent
@onready var flashlight_component: PlayerFlashlightComponent = $Components/FlashlightComponent

@export var starts_with_dash_skill := true
@export var starts_with_flashlight_skill := false
@export var darkness_damage_enabled := false
@export var use_darkness_mechanics := false
## Trials modu (opt-in). null = hikaye modu: aşağıdaki "Trials" kodlarının hiçbiri çalışmaz,
## oyuncu eskisi gibi davranır. Trials sahnesi oyuncuyu oluştururken bir PlayerMovementRules atar.
## (scripts/player/player_movement_rules.gd). Tip bilerek Resource: global sınıf önbelleğine bağımlı olmasın.
@export var movement_rules: Resource = null

# Trials: anında yeniden deneme. die() sahneyi yeniden yüklemez, bu sinyali verir.
signal trials_died(at: Vector2)
# Trials: bir küre (çift zıplama / dash) kullanıldı; Trials sahnesi küreyi tüketir.
signal trials_orb_used(orb: Area2D)

const FLASHLIGHT_ENERGY := 1.35
const FLASHLIGHT_TEXTURE_SCALE := 2.45
const FLASHLIGHT_CONE_HALF_ANGLE_DEG := 28.0

var safe_zones := 0
var double_jump_orbit_overlap_count := 0
var dash_orbit_overlap_count := 0
var has_dash_skill := false
var has_flashlight_skill := false
var _flashlight_light: PointLight2D = null
var _ambient_light: PointLight2D = null
var _lantern_light: PointLight2D = null
var sarmasikta_mi: bool = false
var _dying := false

# --- Trials (yalnızca movement_rules != null iken kullanılır) ---
var trials_drain_enabled := false   # oda karanlık hasarına izin veriyorsa Trials sahnesi açar
var _t_coyote := 0.0
var _t_jump_buffer := 0.0
var _t_jump_rising := false
var _t_dash_dir := Vector2.RIGHT
var _t_dash_left := 0.0
var _t_orbs: Array[Area2D] = []
var _t_layer := 1
var _t_mask := 1
var _t_respawn_frames := 0   # yeniden doğuştan sonra katman (alanların bizi görmesi) birkaç kare kapalı


func _resolve_health_bar() -> ProgressBar:
	var direct := get_node_or_null("HealthBar") as ProgressBar
	if direct != null:
		return direct
	return get_node_or_null("UI/HealthBar") as ProgressBar


func _ready() -> void:
	if CheckpointData.has_spawn:
		global_position = CheckpointData.spawn_position

	if health_component == null:
		push_error("HealthComponent bulunamadı: Components/HealthComponent")
		return
	if health_bar == null:
		push_error("HealthBar bulunamadı: HealthBar veya UI/HealthBar")
		return

	health_component.init_health(health_bar)
	has_dash_skill = starts_with_dash_skill
	if not has_dash_skill:
		dash_component.can_dash = false
	dash_bar_ui.init_dash(dash_cooldown_timer.wait_time)
	_update_dash_cooldown_ui()

	has_flashlight_skill = starts_with_flashlight_skill
	if has_flashlight_skill:
		_setup_flashlight()
	else:
		flashlight_bar_ui.set_locked()

	if use_darkness_mechanics:
		_setup_ambient_light()

	if movement_rules != null:
		_trials_ready()


func _physics_process(delta: float) -> void:
	if movement_rules != null:
		_trials_physics_process(delta)
		return
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
			_sfx("jump")
		elif touching_wall and sarmasikta_mi:			
			jump_wall_component.wall_jump(self, jump_component.jump_velocity)
			jump_component.restore_extra_jumps()
			_sfx("jump")
		else:
			if jump_component.try_extra_jump(self, double_jump_orbit_overlap_count > 0):
				_sfx("orb_jump", 0.02)

	if has_dash_skill and Input.is_action_just_pressed("dash"):
		if dash_orbit_overlap_count > 0:
			if dash_component.try_start_dash_forced(dash_stop_timer, dash_cooldown_timer):
				_sfx("orb_dash", 0.02)
		else:
			if dash_component.try_start_dash(dash_stop_timer, dash_cooldown_timer):
				_sfx("dash")

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
				animated_sprite.play("idle_torch" if has_flashlight_skill else "idle")
			else:
				animated_sprite.play("run_torch" if has_flashlight_skill else "run")
		elif touching_wall:
			animated_sprite.play("wall_slide")
		else:
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
	if movement_rules != null and movement_rules.one_hit_kill:
		if health_component.can_receive_actions():
			die()
		return
	if health_component.apply_damage(health_bar, amount):
		die()
	elif health_component.can_receive_actions():
		_sfx("hurt", 0.08)


func heal(amount: int) -> void:
	health_component.apply_heal(health_bar, amount)


func die() -> void:
	# Aynı anda birden fazla kaynak (onlarca karanlık bloğu, killzone, diken) die()
	# çağırabilir; ölüm dizisi yalnızca bir kez çalışmalı.
	if movement_rules != null and movement_rules.instant_retry:
		_trials_die()
		return
	if _dying:
		return
	_dying = true
	health_component.mark_dead()
	_sfx("death", 0.0)
	set_physics_process(false)
	velocity = Vector2.ZERO
	# Fizik sinyali (body_entered) içinden çağrılabilir: çarpışma ayarlarını ertele
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	var tree := get_tree()
	Engine.time_scale = 0.4
	animated_sprite.play("death")
	# animation_finished hiç gelmezse (animasyon değişti vb.) en fazla 4 sn bekle
	var finished := [false]
	animated_sprite.animation_finished.connect(func(): finished[0] = true, CONNECT_ONE_SHOT)
	var start_ms := Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - start_ms < 4000:
		await tree.process_frame
		if not is_instance_valid(self) or not is_inside_tree():
			Engine.time_scale = 1.0
			return
	await tree.create_timer(0.8, true, false, true).timeout
	Engine.time_scale = 1.0
	_reload_after_death(tree)


func _reload_after_death(tree: SceneTree) -> void:
	# Sahne bu arada değiştiyse (bölüm çıkışı geçişi vb.) yeniden yükleme yapma
	if not is_inside_tree() or tree.current_scene == null or not tree.current_scene.is_ancestor_of(self):
		return
	var st := tree.root.get_node_or_null("SceneTransition")
	if st != null and st.has_method("is_transitioning") and st.is_transitioning():
		return
	tree.reload_current_scene()


# Ses kancası: AudioManager autoload'ı yoksa sessizce geçer.
func _sfx(sfx_name: String, pitch_jitter: float = 0.05) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(sfx_name, pitch_jitter)


func _on_dash_stop_timer_timeout() -> void:
	dash_component.on_dash_stop_timeout()


func _on_dash_cooldown_timer_timeout() -> void:
	dash_component.on_dash_cooldown_timeout()


func _on_orbit_detector_area_entered(area: Area2D) -> void:
	if area.is_in_group("double_jump_orbit"):
		double_jump_orbit_overlap_count += 1
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count += 1
	if movement_rules != null and not _t_orbs.has(area):
		_t_orbs.append(area)


func _on_orbit_detector_area_exited(area: Area2D) -> void:
	if area.is_in_group("double_jump_orbit"):
		double_jump_orbit_overlap_count = max(double_jump_orbit_overlap_count - 1, 0)
	if area.is_in_group("dash_orbit"):
		dash_orbit_overlap_count = max(dash_orbit_overlap_count - 1, 0)
	if movement_rules != null:
		_t_orbs.erase(area)


func _on_darkness_damage_timer_timeout() -> void:
	if movement_rules != null:
		# Trials: ortam karanlığı sadece oda izin verdiyse can eritir (tek vuruşta öldürmez)
		if trials_drain_enabled and safe_zones == 0 and health_component.can_receive_actions():
			if health_component.apply_damage(health_bar, 5):
				die()
			else:
				_sfx("hurt", 0.08)
		return
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
	flashlight_bar_ui.update_battery(1.0, false)
	if use_darkness_mechanics:
		flashlight_component.flashlight_toggled.connect(_on_flashlight_toggled)
		_setup_lantern_glow()


func _on_flashlight_battery_changed(percent: float) -> void:
	flashlight_bar_ui.update_battery(percent, flashlight_component.is_on)


func _update_flashlight_direction() -> void:
	var pivot := get_node_or_null("FlashlightPivot") as Node2D
	if pivot == null:
		return
	var facing_left := animated_sprite.flip_h
	pivot.scale.x = -1.0 if facing_left else 1.0
	if _lantern_light and is_instance_valid(_lantern_light):
		_lantern_light.position.x = -10.0 if facing_left else 10.0


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
	_flashlight_light.energy = FLASHLIGHT_ENERGY
	_flashlight_light.texture_scale = FLASHLIGHT_TEXTURE_SCALE
	_flashlight_light.range_z_min = -4096
	_flashlight_light.range_z_max = 4096
	_flashlight_light.range_layer_min = -128
	_flashlight_light.range_layer_max = 128
	_flashlight_light.color = Color(0.75, 0.5, 1.0)
	_flashlight_light.enabled = false
	_flashlight_light.shadow_enabled = true
	_flashlight_light.shadow_color = Color(0.0, 0.0, 0.0, 1.0)
	_flashlight_light.texture = _create_cone_texture()

	pivot.add_child(_flashlight_light)


func _setup_ambient_light() -> void:
	var light := PointLight2D.new()
	light.name = "AmbientLight"
	light.position = Vector2(0, -28.5)
	light.color = Color(1.0, 1.0, 1.0)
	light.energy = 3.2
	light.texture_scale = 0.45
	light.range_z_min = -4096
	light.range_z_max = 4096
	light.range_layer_min = -128
	light.range_layer_max = 128
	light.texture = _create_radial_texture(128)
	light.shadow_enabled = true
	light.shadow_color = Color(0.0, 0.0, 0.0, 1.0)
	_ambient_light = light
	add_child(light)


func _setup_lantern_glow() -> void:
	_lantern_light = PointLight2D.new()
	_lantern_light.name = "LanternGlow"
	_lantern_light.position = Vector2(10.0, -40.0)
	_lantern_light.color = Color(1.0, 0.72, 0.2)
	_lantern_light.energy = 1.4
	_lantern_light.texture_scale = 0.22
	_lantern_light.range_z_min = -4096
	_lantern_light.range_z_max = 4096
	_lantern_light.range_layer_min = -128
	_lantern_light.range_layer_max = 128
	_lantern_light.enabled = false
	_lantern_light.texture = _create_radial_texture(128)
	add_child(_lantern_light)


func _on_flashlight_toggled(is_on: bool) -> void:
	if _lantern_light and is_instance_valid(_lantern_light):
		_lantern_light.enabled = is_on





func _create_radial_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := size / 2.0
	var max_dist := center
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x) - center, float(y) - center).length()
			if dist < max_dist:
				var t := 1.0 - dist / max_dist
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t))
	return ImageTexture.create_from_image(img)


func _create_cone_texture() -> ImageTexture:
	var size: int = 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: int = size >> 1
	var cx: float = float(half)
	var cy: float = float(half)
	var max_dist: float = float(half)
	var half_angle: float = deg_to_rad(FLASHLIGHT_CONE_HALF_ANGLE_DEG)
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


# =====================================================================================
# Trials modu (opt-in). Buradaki fonksiyonlar yalnızca movement_rules != null iken çağrılır;
# hikaye modunun kod yolu yukarıda olduğu gibi kalır.
# =====================================================================================

func _trials_ready() -> void:
	_t_layer = collision_layer
	_t_mask = collision_mask
	if has_dash_skill:
		dash_component.can_dash = true
	if dash_bar_ui != null:
		dash_bar_ui.hide()
	if health_bar != null:
		health_bar.visible = false


func _trials_physics_process(delta: float) -> void:
	var r = movement_rules
	if not health_component.can_receive_actions():
		return # öldü: trials_respawn() gelene kadar donuk
	if _t_respawn_frames > 0:
		_t_respawn_frames -= 1
		if _t_respawn_frames == 0:
			collision_layer = _t_layer

	var on_floor := is_on_floor()
	var dashing: bool = dash_component.dashing
	if dashing:
		_t_dash_left -= delta
		if _t_dash_left <= 0.0:
			dash_component.on_dash_stop_timeout()
			velocity.y = _t_dash_dir.y * dash_component.dash_speed * r.dash_end_vertical_factor
			dashing = false

	if not dashing:
		jump_wall_component.apply_gravity(self, delta)
		if r.max_fall_speed > 0.0 and velocity.y > r.max_fall_speed:
			velocity.y = r.max_fall_speed

	if on_floor:
		_t_coyote = r.coyote_time
		jump_component.reset_on_floor(self)
		if r.dash_refill_on_floor and not dashing and has_dash_skill:
			dash_component.can_dash = true
	else:
		_t_coyote = maxf(_t_coyote - delta, 0.0)

	var direction := Input.get_axis("move_left", "move_right")
	var touching_wall: bool = jump_wall_component.apply_wall_slide(self, not dashing)

	if Input.is_action_just_pressed("jump"):
		_t_jump_buffer = r.jump_buffer_time + 0.0001
	if _t_jump_buffer > 0.0 and not dashing:
		if on_floor or _t_coyote > 0.0:
			jump_component.jump_from_floor(self)
			_t_coyote = 0.0
			_t_jump_buffer = 0.0
			_t_jump_rising = true
			_sfx("jump")
		elif touching_wall and sarmasikta_mi:
			jump_wall_component.wall_jump(self, jump_component.jump_velocity)
			jump_component.restore_extra_jumps()
			_t_jump_buffer = 0.0
			_t_jump_rising = true
			_sfx("jump")
		else:
			var orb := _t_active_orb("double_jump_orbit")
			if orb != null:
				var ok := false
				if r.orb_jump_ignores_extra_limit:
					velocity.y = jump_component.jump_velocity
					ok = true
				else:
					ok = jump_component.try_extra_jump(self, true)
				if ok:
					_t_jump_buffer = 0.0
					_t_jump_rising = true
					_sfx("orb_jump", 0.02)
					trials_orb_used.emit(orb)
	_t_jump_buffer = maxf(_t_jump_buffer - delta, 0.0)

	# Değişken zıplama yüksekliği: yükselirken tuş bırakılırsa hız kesilir
	if _t_jump_rising:
		if velocity.y >= 0.0 or dashing:
			_t_jump_rising = false
		elif not Input.is_action_pressed("jump"):
			velocity.y *= r.jump_cut_factor
			_t_jump_rising = false

	if has_dash_skill and not dashing:
		if not dash_component.can_dash:
			var dorb := _t_active_orb("dash_orbit")
			if dorb != null:
				dash_component.can_dash = true
				_sfx("orb_dash", 0.02)
				trials_orb_used.emit(dorb)
		if Input.is_action_just_pressed("dash") and dash_component.can_dash:
			dash_component.dashing = true
			dash_component.can_dash = false
			dash_component.recovery_time_left = 0.0
			dash_component.trail_time_accumulator = 0.0
			_t_dash_left = r.dash_duration
			_t_dash_dir = _trials_dash_direction(r)
			_t_jump_rising = false
			_t_jump_buffer = 0.0
			dashing = true
			_sfx("dash")

	movement_component.apply_facing(animated_sprite, direction)

	if dashing:
		velocity = _t_dash_dir * dash_component.dash_speed
		dash_component.spawn_dash_trail(self, animated_sprite, delta)
		animated_sprite.play("dash")
	else:
		if not dash_component.apply_recovery_movement(self, direction, movement_component.speed, delta):
			movement_component.apply_horizontal_movement(self, direction)
		if is_on_floor():
			if direction == 0:
				animated_sprite.play("idle_torch" if has_flashlight_skill else "idle")
			else:
				animated_sprite.play("run_torch" if has_flashlight_skill else "run")
		elif touching_wall:
			animated_sprite.play("wall_slide")
		else:
			animated_sprite.play("idle_jump" if direction == 0 else "jump")

	move_and_slide()
	animated_sprite.self_modulate = Color.WHITE if (dash_component.can_dash or not has_dash_skill) else r.no_dash_tint

	if has_flashlight_skill:
		flashlight_component.flashlight_update(delta)
		_update_flashlight_direction()


func _trials_dash_direction(r) -> Vector2:
	var x := Input.get_axis("move_left", "move_right")
	var y := 0.0
	if r.dash_8way and InputMap.has_action("move_up") and InputMap.has_action("move_down"):
		y = Input.get_axis("move_up", "move_down")
	var v := Vector2(signf(x), signf(y))
	if v == Vector2.ZERO:
		v = Vector2(-1.0 if animated_sprite.flip_h else 1.0, 0.0)
	return v.normalized()


func _t_active_orb(group: String) -> Area2D:
	for a in _t_orbs:
		if is_instance_valid(a) and a.is_inside_tree() and a.is_in_group(group) and bool(a.get_meta("trials_active", true)):
			return a
	return null


func _trials_die() -> void:
	if _dying or _t_respawn_frames > 0:
		return
	_dying = true
	health_component.mark_dead()
	_sfx(movement_rules.death_sfx, 0.05)
	velocity = Vector2.ZERO
	dash_component.dashing = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	trials_died.emit(global_position)


## Trials: oyuncuyu verilen noktada (ayak hizası) canlandırır; hız, dash, zıplama durumu sıfırlanır.
func trials_respawn(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_dying = false
	health_component.revive()
	if health_bar != null:
		health_bar.init_health(health_component.initial_health)
	# Maske hemen (zemine basalım), katman 2 fizik karesi sonra: ölümdeki eski konumdan kalan
	# alan çakışması (diken vb.) yeni doğan oyuncuyu bir daha öldürmesin.
	collision_mask = _t_mask
	collision_layer = 0
	_t_respawn_frames = 2
	dash_component.dashing = false
	dash_component.recovery_time_left = 0.0
	dash_component.can_dash = has_dash_skill
	jump_component.restore_extra_jumps()
	_t_coyote = 0.0
	_t_jump_buffer = 0.0
	_t_jump_rising = false
	_t_dash_left = 0.0
	animated_sprite.self_modulate = Color.WHITE
	animated_sprite.modulate = Color.WHITE
	animated_sprite.scale = Vector2.ONE
	animated_sprite.play("idle_torch" if has_flashlight_skill else "idle")


## Trials: oda geçişinde/küre ile dash yenile.
func trials_refill_dash() -> void:
	if has_dash_skill and not dash_component.dashing:
		dash_component.can_dash = true


func trials_is_dead() -> bool:
	return _dying
