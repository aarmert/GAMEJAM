extends Area2D

@export var orbit_group_name := "double_jump_orbit"

# --- Görsel (oynanışı etkilemez) -------------------------------------------------
# Sprite sheet: assets/orbs/orb_*.png (tools/orbs/gen_orbs.py), 8x2 kare, 32px.
#   0-5 boşta parıltı, 8 harcanmış (sönük kabuk), 9-10 geri gelme "pop", 11-15 alma patlaması.
const IDLE_FRAMES := 6
const FRAME_SPENT := 8
const FRAME_POP := [9, 10]
const FRAME_BURST := [11, 12, 13, 14, 15]
const IDLE_FPS := 7.0
const FX_FPS := 20.0
const BOB_PERIOD := 1.8
const DASH_SPENT_MIN := 0.3

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var _burst: Sprite2D = get_node_or_null("Burst")

var _t := 0.0
var _phase := 0.0
var _spent := false
var _pop_t := -1.0
var _burst_t := -1.0
var _player: Node = null
var _detector: Area2D = null
var _pending_use := 0
var _dash_spent_t := 0.0
var _silent := false


func _ready() -> void:
	add_to_group(orbit_group_name)
	# Her küre farklı fazda titreşsin (konuma bağlı, deterministik).
	_phase = fposmod(global_position.x * 0.013 + global_position.y * 0.007, 1.0)
	if _burst != null:
		_burst.visible = false


func _process(delta: float) -> void:
	if _sprite == null:
		return
	_t += delta
	_update_state(delta)

	# Trials kodu kullanılmış küreyi Sprite2D.self_modulate ile soldurur; sönük hâli biz çiziyoruz.
	_sprite.self_modulate = Color.WHITE

	if _burst_t >= 0.0:
		_burst_t += delta
		var bi := int(_burst_t * FX_FPS)
		if bi >= FRAME_BURST.size():
			_burst_t = -1.0
			_burst.visible = false
		else:
			_burst.visible = true
			_burst.frame = FRAME_BURST[bi]

	if _spent:
		_sprite.frame = FRAME_SPENT
		_sprite.position.y = 0.0
		return

	if _pop_t >= 0.0:
		_pop_t += delta
		var pi := int(_pop_t * FX_FPS * 0.75)
		if pi < FRAME_POP.size():
			_sprite.frame = FRAME_POP[pi]
			_sprite.position.y = 0.0
			return
		_pop_t = -1.0

	var cyc := _t / BOB_PERIOD + _phase
	_sprite.frame = int(cyc * BOB_PERIOD * IDLE_FPS) % IDLE_FRAMES
	# 1 piksellik yüzme; tam sayı adımlar piksel ızgarasını korur.
	_sprite.position.y = round(sin(cyc * TAU) * 1.4)


func _update_state(delta: float) -> void:
	var was_spent := _spent
	var now_spent := false
	_silent = false

	_find_player()
	if has_meta("trials_active") or (_player != null and _player.get("movement_rules") != null):
		# Trials: küre gerçekten tüketiliyor ve yeniden doğuyor.
		now_spent = not bool(get_meta("trials_active", true))
	else:
		if _player != null and _detector != null:
			now_spent = _story_spent(delta)

	if now_spent and not was_spent and not _silent:
		_burst_t = 0.0
	elif was_spent and not now_spent:
		_pop_t = 0.0
	_spent = now_spent


# Hikâye modunda küreler tükenmez; "sönük" görüntü yalnızca gerçekten kullanılamadığı süreyi gösterir.
func _story_spent(delta: float) -> bool:
	var overlapping := _detector.overlaps_area(self)
	if orbit_group_name == "dash_orbit":
		var dc = _player.get("dash_component")
		var dashing: bool = dc != null and bool(dc.get("dashing"))
		if overlapping and Input.is_action_just_pressed("dash") and bool(_player.get("has_dash_skill")):
			_pending_use = 3
		if _pending_use > 0:
			_pending_use -= 1
			if dashing:
				_pending_use = 0
				_dash_spent_t = DASH_SPENT_MIN
				return true
		_dash_spent_t -= delta
		return _spent and (dashing or _dash_spent_t > 0.0)
	else:
		# Çift zıplama: ek zıplama hakkı bitince (yere/duvara değene kadar) hiçbir küre kullanılamaz.
		var jc = _player.get("jump_component")
		if jc == null:
			return false
		if overlapping and Input.is_action_just_pressed("jump"):
			_pending_use = 3
		var left = jc.get("extra_jumps_left")
		var used: bool = left != null and int(left) <= 0
		if used and not _spent:
			# Patlama yalnızca kullanılan kürede; diğer çift zıplama küreleri sessizce söner.
			_silent = _pending_use <= 0
		if _pending_use > 0:
			_pending_use -= 1
		return used


func _find_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		var cs := get_tree().current_scene
		if cs != null:
			for n in ["MayaChar2", "asil_karakter"]:
				_player = cs.get_node_or_null(n)
				if _player != null:
					break
	_detector = null
	if _player != null:
		_detector = _player.get_node_or_null("OrbitDetector") as Area2D
