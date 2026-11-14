extends StaticBody2D
class_name LanternBarrier

# Yolu kapatan karanlık kütle. Fenerle toplam `burn_time` saniye aydınlatılınca yanıp yok olur.
# regrow_time > 0 ise o kadar saniye sonra yeniden büyür (oyuncu içindeyken asla büyümez,
# büyümeden önce 1 sn titreyerek uyarır). Konum = dikdörtgenin sol üst köşesi.

@export var size: Vector2 = Vector2(32, 128)
@export var burn_time: float = 1.0
@export var regrow_time: float = 0.0
@export var body_texture: Texture2D = preload("res://assets/darkness/darkness_body.png")

const LIGHT_RANGE := 235.0
const LIGHT_HALF_ANGLE := deg_to_rad(31.0)
const C_RIM := [Color("9b3fd8"), Color("c255f0"), Color("e46cff")]
const C_HOT := Color("f6b8ff")
const C_EYE := Color("f8ecff")
const C_PUPIL := Color("2a0b3d")
const C_SPORE := [Color("f0a8ff"), Color("c768ff"), Color("8a44c8")]

enum State { SOLID, BURNED, REGROWING }

var state: State = State.SOLID
var lit := false
var burn := 0.0            # 0..burn_time
var _player: CharacterBody2D = null
var _shape: CollisionShape2D
var _occ: LightOccluder2D
var _sprite: Sprite2D
var _t := 0.0
var _tick := -1
var _burned_for := 0.0
var _regrow_t := 0.0
var _spores: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("lantern_barrier")
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	_rng.seed = int(absf(global_position.x)) + 3
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	_shape.shape = rs
	_shape.position = size * 0.5
	add_child(_shape)
	_occ = LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	op.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	_occ.occluder = op
	add_child(_occ)
	_sprite = Sprite2D.new()
	_sprite.texture = body_texture
	_sprite.centered = false
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(posmod(int(global_position.x / 2.0), 64), posmod(int(global_position.y / 2.0), 64), size.x / 2.0, size.y / 2.0)
	_sprite.scale = Vector2(2, 2)
	_sprite.use_parent_material = true
	_sprite.show_behind_parent = true
	add_child(_sprite)
	for n in get_tree().get_nodes_in_group("player"):
		if n is CharacterBody2D:
			_player = n
			break


func is_blocking() -> bool:
	return state != State.BURNED


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.SOLID:
			lit = _is_lit()
			if lit:
				burn += delta
				if int(_t * 30.0) % 2 == 0:
					_spawn_spores(2)
				if burn >= burn_time:
					_set_burned()
			else:
				burn = maxf(burn - delta * 0.35, 0.0)
		State.BURNED:
			lit = false
			if regrow_time > 0.0:
				_burned_for += delta
				if _burned_for >= regrow_time and not _player_inside():
					state = State.REGROWING
					_regrow_t = 0.0
		State.REGROWING:
			_regrow_t += delta
			if _player_inside():
				state = State.BURNED
				_burned_for = regrow_time - 0.3
			elif _regrow_t >= 0.5:
				state = State.SOLID
				burn = 0.0
				_shape.set_deferred("disabled", false)
				_occ.visible = true
	_update_spores(delta)
	var tk := int(_t * 10.0)
	if tk != _tick or lit or state == State.REGROWING:
		_tick = tk
		queue_redraw()


func _set_burned() -> void:
	state = State.BURNED
	_burned_for = 0.0
	_shape.set_deferred("disabled", true)
	_occ.visible = false
	_spawn_spores(30)
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("whoosh", 0.1)


func _player_inside() -> bool:
	if _player == null:
		return false
	var r := Rect2(global_position - Vector2(10, 4), size + Vector2(20, 8))
	return r.intersects(Rect2(_player.global_position + Vector2(-8, -46.5), Vector2(16, 29)))


# Dikdörtgenin oyuncuya bakan kenarından birkaç nokta konide ve görüş hattında mı?
func _is_lit() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var fc = _player.get("flashlight_component")
	if fc == null or not fc.is_on or not _player.get("has_flashlight_skill"):
		return false
	var pivot := _player.get_node_or_null("FlashlightPivot") as Node2D
	var origin: Vector2 = pivot.global_position if pivot else _player.global_position + Vector2(0, -28)
	var facing := -1.0 if _player.animated_sprite.flip_h else 1.0
	var face_x := global_position.x if facing > 0.0 else global_position.x + size.x
	var n := maxi(int(size.y / 24.0), 2)
	var space := get_world_2d().direct_space_state
	for i in n + 1:
		var p := Vector2(face_x, global_position.y + 4.0 + (size.y - 8.0) * float(i) / float(n))
		var v := p - origin
		if v.x * facing <= -4.0:
			continue
		var d := v.length()
		if d > LIGHT_RANGE:
			continue
		if d > 14.0 and absf(atan2(v.y, absf(v.x))) > LIGHT_HALF_ANGLE:
			continue
		var q := PhysicsRayQueryParameters2D.create(origin, p - Vector2(facing * 2.0, 0), 1)
		q.exclude = [_player.get_rid(), get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _spawn_spores(n: int) -> void:
	for i in n:
		if _spores.size() > 60:
			return
		var p := Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y))
		var v := Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-70, -10))
		_spores.append([p, v, 0.0, _rng.randf_range(0.4, 1.0)])


func _update_spores(delta: float) -> void:
	if _spores.is_empty():
		return
	var alive: Array = []
	for s in _spores:
		s[2] += delta
		if s[2] < s[3]:
			s[0] += s[1] * delta
			s[1].x += sin(_t * 5.0 + s[3] * 11.0) * 30.0 * delta
			alive.append(s)
	_spores = alive


func _draw() -> void:
	var tick := int(_t * 10.0)
	var lvl: int = [0, 1, 2, 1][tick % 4]
	var visible_k := 1.0
	match state:
		State.BURNED:
			_sprite.visible = false
			# kalıntı: zeminde sönük kor pikselleri + yeniden büyümeden önce titreşim
			var warn := regrow_time > 0.0 and _burned_for > regrow_time - 1.0 and tick % 2 == 0
			for i in int(size.x / 4.0):
				var h := 2.0 + float((i * 5 + tick) % 3) * 2.0
				draw_rect(Rect2(Vector2(i * 4.0, size.y - h), Vector2(4, h)), Color(C_RIM[0], 0.55 if warn else 0.3))
			if warn:
				draw_rect(Rect2(Vector2.ZERO, size), Color(C_RIM[1], 0.12))
			_draw_spores()
			return
		State.REGROWING:
			visible_k = clampf(_regrow_t / 0.5, 0.0, 1.0)
	var heat := clampf(burn / maxf(burn_time, 0.01), 0.0, 1.0)
	_sprite.visible = true
	var h := size.y * visible_k
	var top := size.y - h
	_sprite.region_rect.size = Vector2(size.x / 2.0, h / 2.0)
	_sprite.position = Vector2(0, top)
	_sprite.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.1, 1.8), heat)
	# kenarlarda titreşen macenta alevler
	var rim: Color = C_HOT if lit and tick % 2 == 0 else C_RIM[lvl]
	for side in [0.0, size.x]:
		var dir := -1.0 if side == 0.0 else 1.0
		var y := top
		var j := 0
		while y < size.y:
			var w := 2.0 + float((j * 7 + tick * 3) % 4) * 2.0 * (1.0 + heat)
			draw_rect(Rect2(Vector2(side - (w if dir < 0.0 else 0.0), y), Vector2(w, 4)), Color(rim, 0.85))
			draw_rect(Rect2(Vector2(side + dir * (w + 1.0) - 1.0, y + 1), Vector2(2, 2)), Color(C_HOT, 0.5 + heat * 0.5))
			y += 4.0
			j += 1
	# tepe
	for i in int(size.x / 4.0):
		var hh := 2.0 + float((i * 3 + tick) % 4) * 2.0
		draw_rect(Rect2(Vector2(i * 4.0, top - hh), Vector2(4, hh)), Color(rim, 0.8))
	# gözler (birkaç tane, ışıkta kısılır)
	var eyes := maxi(int(size.y / 64.0), 1)
	for e in eyes:
		var c := Vector2(size.x * 0.5, top + (size.y - top) * (float(e) + 0.5) / float(eyes))
		if lit:
			draw_rect(Rect2(c + Vector2(-8, -1), Vector2(6, 2)), C_HOT)
			draw_rect(Rect2(c + Vector2(2, -1), Vector2(6, 2)), C_HOT)
		elif (tick + e * 13) % 47 > 1:
			draw_rect(Rect2(c + Vector2(-8, -3), Vector2(6, 6)), C_EYE)
			draw_rect(Rect2(c + Vector2(2, -3), Vector2(6, 6)), C_EYE)
			draw_rect(Rect2(c + Vector2(-6, -1), Vector2(2, 2)), C_PUPIL)
			draw_rect(Rect2(c + Vector2(4, -1), Vector2(2, 2)), C_PUPIL)
	# yanma ilerlemesi: ışık aldıkça içten beyazlaşan çizgiler
	if heat > 0.05:
		var n := int(heat * 10.0)
		for i in n:
			var yy := top + fposmod(float(i * 37 + tick * 5), maxf(size.y - top, 1.0))
			draw_rect(Rect2(Vector2(2, yy), Vector2(size.x - 4, 2)), Color(C_HOT, 0.35 * heat))
	_draw_spores()


func _draw_spores() -> void:
	for s in _spores:
		var kk := float(s[2]) / float(s[3])
		draw_rect(Rect2((s[0] / 2.0).floor() * 2.0, Vector2(2, 2)), C_SPORE[mini(int(kk * 3.0), 2)])
