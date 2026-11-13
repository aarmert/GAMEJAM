extends Node2D

# Orman bölümü (oyunun ilk gerçek bölümü).
#
# Önizleme kamerasi: bir checkpoint'e (heal lambasi) ulasinca kamera sakin bir sekilde
# bir sonrakine kayar, kisa bir süre orada bekler ve oyuncuya geri döner.
#  - Süre mesafeye göre hesaplanir (preview_pan_speed), [preview_min_time, preview_max_time] araliginda.
#  - Önizleme boyunca oyun durdurulur (get_tree().paused): oyuncu hareket edemez,
#    karanlik/düsman hasari islemez. Ziplama tusu önizlemeyi atlar.
#  - Önizleme kamerasi oyuncu kamerasinin zoom ve limit degerlerini kullanir,
#    böylece önizlemede de bölüm disi (bos alan) görünmez.
#  - Hedef zaten ekrandaysa önizleme yapilmaz. Ölüp checkpoint'ten dogunca ayni
#    önizleme tekrar gösterilmez.

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var background_modulate: CanvasModulate = get_node_or_null("ParallaxBackground/BackgroundModulate")
@onready var flashlight: PointLight2D = $MayaChar2/FlashlightPivot/PointLight2D

@export var checkpoints: Array[Area2D] = []
@export var player: CharacterBody2D
@export var preview_camera: Camera2D
@export var player_camera: Camera2D
@export var preview_enabled: bool = true
## Kameranin hedefe kayma hizi (piksel/sn). Süre bununla hesaplanir ve asagidaki sinirlara kirpilir.
@export var preview_pan_speed: float = 300.0
@export var preview_min_time: float = 1.2
@export var preview_max_time: float = 3.2
## Hedefin üzerinde bekleme süresi (sn)
@export var preview_hold_time: float = 1.1
## Geri dönüs gidisten bu kat kadar hizli
@export var preview_return_speedup: float = 1.6
## Atlaninca oyuncuya geri dönüs süresi (sn)
@export var preview_skip_return_time: float = 0.35
## Hedef ekran kenarina bu kadar pikselden yakinsa "görünmüyor" sayilir
@export var preview_visible_margin: float = 40.0

# Ölüp checkpoint'ten yeniden dogunca ayni önizlemeleri tekrar gösterme
static var _shown_previews: Dictionary = {}

var visited: Array[bool] = []
var is_previewing: bool = false

var _tween: Tween
var _ticker: _PreviewTicker
var _skipping: bool = false
var _pending_index: int = -1


# Oyun durdurulmusken (paused) de çalisan küçük yardimci: atlama tusunu dinler.
class _PreviewTicker extends Node:
	var on_tick: Callable

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if on_tick.is_valid():
			on_tick.call()


func _ready() -> void:
	canvas_modulate.color = Color(0.34, 0.32, 0.42)
	if background_modulate:
		background_modulate.color = Color(0.55, 0.52, 0.64)
	flashlight.enabled = true

	visited.resize(checkpoints.size())
	visited.fill(false)

	if not CheckpointData.has_spawn:
		_shown_previews.clear()

	_ticker = _PreviewTicker.new()
	_ticker.on_tick = _preview_tick
	add_child(_ticker)

	if preview_camera:
		# Durdurulmus oyunda da kamera güncellensin
		preview_camera.process_mode = Node.PROCESS_MODE_ALWAYS
		preview_camera.position_smoothing_enabled = false
	_sync_preview_camera()

	if player_camera:
		player_camera.reset_smoothing()

	if preview_enabled and checkpoints.size() > 0 and not CheckpointData.has_spawn:
		play_preview_to(0)


func _sync_preview_camera() -> void:
	if not (preview_camera and player_camera):
		return
	preview_camera.zoom = player_camera.zoom
	preview_camera.limit_left = player_camera.limit_left
	preview_camera.limit_right = player_camera.limit_right
	preview_camera.limit_top = player_camera.limit_top
	preview_camera.limit_bottom = player_camera.limit_bottom


func _view_half_size() -> Vector2:
	return get_viewport().get_visible_rect().size / player_camera.zoom / 2.0


# Kamera merkezini limitlerin izin verdigi alana kirp (yoksa kamera "bos" yere
# kayar gibi yapip bir süre yerinde durur).
func _clamp_center(p: Vector2) -> Vector2:
	var h := _view_half_size()
	var lo := Vector2(player_camera.limit_left, player_camera.limit_top) + h
	var hi := Vector2(player_camera.limit_right, player_camera.limit_bottom) - h
	return Vector2(
		clampf(p.x, lo.x, maxf(lo.x, hi.x)),
		clampf(p.y, lo.y, maxf(lo.y, hi.y)))


func _is_on_screen(p: Vector2) -> bool:
	var rect := Rect2(player_camera.get_screen_center_position() - _view_half_size(), _view_half_size() * 2.0)
	return rect.grow(-preview_visible_margin).has_point(p)


func _wait_for_scene_transition() -> void:
	var st := get_node_or_null("/root/SceneTransition")
	while st != null and st.has_method("is_transitioning") and st.is_transitioning():
		await get_tree().process_frame


func play_preview_to(index: int) -> void:
	if not preview_enabled:
		return
	if is_previewing:
		# Su anki önizleme bitince göster
		_pending_index = maxi(_pending_index, index)
		return
	if index < 0 or index >= checkpoints.size() or checkpoints[index] == null:
		return
	if _shown_previews.has(index):
		return
	is_previewing = true
	# Fade/hikaye ekrani bitmeden önizleme baslamasin
	await _wait_for_scene_transition()
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(player):
		is_previewing = false
		return

	var target_world: Vector2 = checkpoints[index].global_position
	if _is_on_screen(target_world):
		_end_preview()
		return
	_shown_previews[index] = true

	_sync_preview_camera()
	var start := player_camera.get_screen_center_position()
	var target := _clamp_center(target_world)
	var dist := start.distance_to(target)
	var go_time := clampf(dist / preview_pan_speed, preview_min_time, preview_max_time)
	var back_time := clampf(go_time / preview_return_speedup, preview_min_time * 0.75, preview_max_time)

	get_tree().paused = true
	preview_camera.global_position = start
	preview_camera.make_current()
	_skipping = false

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(0.25)
	_tween.tween_property(preview_camera, "global_position", target, go_time)
	_tween.tween_interval(preview_hold_time)
	_tween.tween_property(preview_camera, "global_position", start, back_time)
	_tween.tween_callback(_finish_preview)


func _preview_tick() -> void:
	if not is_previewing or _skipping or _tween == null:
		return
	if Input.is_action_just_pressed("jump"):
		_skip_preview()


func _skip_preview() -> void:
	_skipping = true
	if _tween:
		_tween.kill()
	var back := player_camera.get_screen_center_position()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(preview_camera, "global_position", back, preview_skip_return_time)
	_tween.tween_callback(_finish_preview)


func _finish_preview() -> void:
	_tween = null
	_skipping = false
	player_camera.make_current()
	player_camera.reset_smoothing()
	get_tree().paused = false
	_end_preview()


func _end_preview() -> void:
	is_previewing = false
	if _pending_index >= 0:
		var next := _pending_index
		_pending_index = -1
		play_preview_to(next)


func _exit_tree() -> void:
	# Önizleme sirasinda sahne degisirse oyun durdurulmus kalmasin
	if is_previewing and get_tree():
		get_tree().paused = false


func checkpoint_reached(index: int) -> void:
	if index < 0 or index >= visited.size() or visited[index]:
		return
	visited[index] = true
	var next_index := index + 1
	if preview_enabled and next_index < checkpoints.size():
		play_preview_to(next_index)
