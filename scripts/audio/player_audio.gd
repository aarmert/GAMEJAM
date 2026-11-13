extends Node

# Oyuncuya AudioManager tarafından otomatik eklenir (player.gd'ye dokunmadan):
#  - ayak sesleri: koşu animasyonunun ayak-yere-basma karelerinde, zemin karosuna göre (çim / taş)
#  - iniş sesi: havada belli bir süre kaldıktan sonra yere değince
#  - fener aç/kapa/bitti sesleri (FlashlightComponent sinyalleri)

const RUN_ANIMATIONS := ["run", "run_torch"]
const STEP_FRAMES := [0, 5]          # Player_run-Sheet: 10 kare, bacaklar 0. ve 5. karede açık
const MIN_STEP_SPEED := 20.0
const FALLBACK_STEP_INTERVAL := 0.32  # koşu animasyonu yoksa zaman bazlı ritim
const MIN_AIR_TIME_FOR_LAND := 0.14

var _player: CharacterBody2D
var _sprite: AnimatedSprite2D
var _was_on_floor := true
var _air_time := 0.0
var _fallback_timer := 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	if _player == null:
		queue_free()
		return
	_sprite = _player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite != null:
		_sprite.frame_changed.connect(_on_frame_changed)
	_shape = _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var fl := _player.get_node_or_null("Components/FlashlightComponent")
	if fl != null:
		if fl.has_signal("flashlight_toggled"):
			fl.flashlight_toggled.connect(_on_flashlight_toggled)
		if fl.has_signal("battery_empty"):
			fl.battery_empty.connect(_on_battery_empty)
	_was_on_floor = _player.is_on_floor()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var on_floor := _player.is_on_floor()
	if on_floor:
		if not _was_on_floor and _air_time >= MIN_AIR_TIME_FOR_LAND and _is_alive():
			AudioManager.play_sfx("land", 0.06)
			AudioManager.play_footstep(_surface_under_feet(), -2.0)
		_air_time = 0.0
	else:
		_air_time += delta
	_was_on_floor = on_floor

	# Koşu animasyonu yoksa (ör. animasyon ismi değişirse) zaman bazlı ritme düş
	if _sprite == null or not _sprite.sprite_frames or not _sprite.sprite_frames.has_animation(&"run"):
		if on_floor and abs(_player.velocity.x) > MIN_STEP_SPEED:
			_fallback_timer -= delta
			if _fallback_timer <= 0.0:
				_fallback_timer = FALLBACK_STEP_INTERVAL
				AudioManager.play_footstep(_surface_under_feet())
		else:
			_fallback_timer = 0.0


func _on_frame_changed() -> void:
	if not String(_sprite.animation) in RUN_ANIMATIONS:
		return
	if not _sprite.frame in STEP_FRAMES:
		return
	if not _player.is_on_floor() or abs(_player.velocity.x) < MIN_STEP_SPEED or not _is_alive():
		return
	AudioManager.play_footstep(_surface_under_feet())


func _surface_under_feet() -> String:
	# 1) Yere temas noktası (move_and_slide çarpışması) — karonun içine birkaç piksel in
	for i in _player.get_slide_collision_count():
		var c := _player.get_slide_collision(i)
		if c.get_normal().y < -0.5:
			var s := AudioManager.find_surface_at(c.get_position() + Vector2(0, 3))
			if not s.is_empty():
				return s
	# 2) Çarpışma kutusunun alt kenarı (ortası ve iki yanı)
	var feet := _player.global_position
	if _shape != null and _shape.shape is RectangleShape2D:
		var half_h: float = (_shape.shape as RectangleShape2D).size.y * 0.5
		feet = _shape.global_transform * Vector2(0, half_h)
	for dx in [0.0, -6.0, 6.0]:
		var s := AudioManager.find_surface_at(feet + Vector2(dx, 4))
		if not s.is_empty():
			return s
	# 3) Sahne varsayılanı (orman: çim, mağara: taş)
	return AudioManager.get_scene_surface()


func _is_alive() -> bool:
	var hc := _player.get_node_or_null("Components/HealthComponent")
	return hc == null or not hc.has_method("can_receive_actions") or hc.can_receive_actions()


func _on_flashlight_toggled(is_on: bool) -> void:
	AudioManager.play_sfx("lantern_on" if is_on else "lantern_off", 0.04)


func _on_battery_empty() -> void:
	AudioManager.play_sfx("lantern_empty", 0.0)
