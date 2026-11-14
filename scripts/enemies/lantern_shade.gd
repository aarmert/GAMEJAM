extends Node2D
class_name LanternShade

# Fener mağarasının gölge yaratığı (mağara kovalamacasındaki karanlık canavarla aynı mor görünüm).
#
# KURALLAR (oyuncu için okunur olsun diye basit):
#  - Dokunursa öldürür.
#  - CHASER: karanlıkta oyuncuya doğru süzülür. Fenerin ışık konisine girince DONAR, küçülür,
#    geri itilir; toplam `dissolve_time` saniye ışıkta kalırsa dağılıp yok olur.
#  - GUARD: geçidi tıkayan, ölmeyen gölge. Işıkta saklanma noktasına (tavana) çekilir ve küçülür;
#    ışık kesildikten `recover_time` sonra geri gelip geçidi yeniden tıkar.
# Her şey sahne yeniden yüklenince sıfırlanır (ölüm = sahne yeniden yükleme).
#
# Performans: fizik gövdesi/Area yok. Oyuncuya çarpışma basit daire-dikdörtgen testi; ışık testi
# önce ucuz açı/mesafe kontrolü, yalnızca konideyse tek bir ışın (duvar arkası ışık almaz).
# Çizim adım adım (10 fps) yenilenir.

enum Behavior { CHASER, GUARD }

@export var behavior: Behavior = Behavior.CHASER
@export var radius: float = 13.0
@export var speed: float = 80.0
## CHASER: oyuncu bu dünya dikdörtgenine girince uyanır (boyut 0 ise mesafe ile: wake_distance).
@export var wake_rect: Rect2 = Rect2()
@export var wake_distance: float = 260.0
## Gölgenin çıkamayacağı dünya dikdörtgeni (boyut 0 = sınırsız).
@export var leash_rect: Rect2 = Rect2()
@export var dissolve_time: float = 1.2
@export var push_back_speed: float = 55.0
## GUARD: ışıkta çekildiği nokta (yerel ofset) ve ışık kesildikten sonra geri dönüş gecikmesi.
@export var hide_offset: Vector2 = Vector2(0, -96)
@export var recover_time: float = 1.2
@export var start_hidden_in_wall: bool = true

const LIGHT_RANGE := 235.0
const LIGHT_HALF_ANGLE := deg_to_rad(31.0)
const PX := 2.0

const C_BODY := Color("2a0b3d")
const C_BODY2 := Color("3d1260")
const C_RIM := [Color("9b3fd8"), Color("c255f0"), Color("e46cff")]
const C_HOT := Color("f6b8ff")
const C_EYE := Color("f8ecff")
const C_PUPIL := Color("12041c")
const C_SPORE := [Color("f0a8ff"), Color("c768ff"), Color("8a44c8")]

enum State { DORMANT, EMERGING, ACTIVE, DISSOLVING, GONE }

var state: State = State.DORMANT
var lit := false
var lit_total := 0.0
var size_k := 1.0          # görsel ve vuruş ölçeği
var _player: CharacterBody2D = null
var _home := Vector2.ZERO
var _t := 0.0
var _tick := -1
var _emerge_t := 0.0
var _unlit_for := 99.0
var _dissolve_t := 0.0
var _spores: Array = []    # [pos, vel, life, max]
var _rng := RandomNumberGenerator.new()
var _hiss_cd := 0.0
var _grace := 0.6          # sahne açılışında kısa bekleme (yeniden doğuşta anında saldırı yok)


func _ready() -> void:
	add_to_group("lantern_shade")
	_home = global_position
	_rng.seed = int(absf(global_position.x) * 13.0 + absf(global_position.y) * 7.0) + 1
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED # karanlıkta da görünsün: kör ölüm yok
	material = mat
	z_index = 2
	if behavior == Behavior.GUARD:
		state = State.ACTIVE
	elif not start_hidden_in_wall:
		state = State.ACTIVE
	for n in get_tree().get_nodes_in_group("player"):
		if n is CharacterBody2D:
			_player = n
			break


func is_threat() -> bool:
	return state == State.ACTIVE or state == State.EMERGING


func _physics_process(delta: float) -> void:
	_t += delta
	_hiss_cd = maxf(_hiss_cd - delta, 0.0)
	if _grace > 0.0:
		_grace -= delta
	if _player == null or not is_instance_valid(_player):
		_redraw_stepped()
		return
	match state:
		State.DORMANT:
			if _should_wake():
				state = State.EMERGING
				_emerge_t = 0.0
				_burst(10, 40.0)
				_sfx("whoosh")
		State.EMERGING:
			_emerge_t += delta
			lit = _is_lit()
			if _emerge_t >= 0.6:
				state = State.ACTIVE
		State.ACTIVE:
			lit = _is_lit()
			if behavior == Behavior.CHASER:
				_chaser_step(delta)
			else:
				_guard_step(delta)
			_check_hit()
		State.DISSOLVING:
			_dissolve_t += delta
			size_k = maxf(size_k - delta * 1.6, 0.0)
			if _dissolve_t > 0.7:
				state = State.GONE
				visible = false
	_update_spores(delta)
	_redraw_stepped()


func _should_wake() -> bool:
	if _grace > 0.0:
		return false
	var pp := _player.global_position
	if wake_rect.size != Vector2.ZERO:
		return wake_rect.has_point(pp)
	return pp.distance_to(global_position) < wake_distance


func _player_center() -> Vector2:
	return _player.global_position + Vector2(0, -32)


func _chaser_step(delta: float) -> void:
	var to_p := _player_center() - global_position
	if lit:
		lit_total += delta
		size_k = move_toward(size_k, 0.55, delta * 1.5)
		var away := -to_p.normalized() if to_p.length() > 0.1 else Vector2.RIGHT
		global_position += away * push_back_speed * delta
		if _hiss_cd <= 0.0:
			_burst(3, 70.0)
			_hiss_cd = 0.12
		if lit_total >= dissolve_time:
			state = State.DISSOLVING
			_dissolve_t = 0.0
			_burst(26, 110.0)
			_sfx("whoosh")
	else:
		size_k = move_toward(size_k, 1.0, delta * 0.8)
		if to_p.length() > 2.0:
			# Önce oyuncunun yüksekliğine iner, sonra yatay yaklaşır: fener (yatay koni) ona hep
			# yetişebilsin, tepeden gelip "ışık tutamadım" ölümü olmasın. Hafif dalgalı süzülme.
			var vx := signf(to_p.x) * speed if absf(to_p.x) > 3.0 else 0.0
			var vy := clampf(to_p.y * 2.5, -speed * 1.3, speed * 1.3) + sin(_t * 3.1) * 14.0
			global_position += Vector2(vx, vy) * delta
	_apply_leash()


func _guard_step(delta: float) -> void:
	var hide_pos := _home + hide_offset
	if lit:
		_unlit_for = 0.0
		lit_total += delta
		if _hiss_cd <= 0.0:
			_burst(3, 70.0)
			_hiss_cd = 0.12
	else:
		_unlit_for += delta
	var retreat := _unlit_for < recover_time
	if retreat:
		global_position = global_position.move_toward(hide_pos, 260.0 * delta)
		size_k = move_toward(size_k, 0.35, delta * 2.5)
	else:
		global_position = global_position.move_toward(_home, speed * delta)
		size_k = move_toward(size_k, 1.0, delta * 1.2)


func _apply_leash() -> void:
	if leash_rect.size == Vector2.ZERO:
		return
	global_position = global_position.clamp(leash_rect.position, leash_rect.end)


# Fener konisinde mi? (açı + mesafe + duvar arkasında değil)
func _is_lit() -> bool:
	var fc = _player.get("flashlight_component")
	if fc == null or not fc.is_on or not _player.get("has_flashlight_skill"):
		return false
	var pivot := _player.get_node_or_null("FlashlightPivot") as Node2D
	var origin: Vector2 = pivot.global_position if pivot else _player.global_position + Vector2(0, -28)
	var facing := -1.0 if _player.animated_sprite.flip_h else 1.0
	var v := global_position - origin
	var d := v.length()
	if d > LIGHT_RANGE + radius:
		return false
	if d > radius + 6.0:
		if v.x * facing <= 0.0:
			return false
		var ang := absf(atan2(v.y, absf(v.x)))
		# yakın mesafede gövdenin kenarı koniye girse de yeter
		var slack := atan2(radius * size_k, d)
		if ang > LIGHT_HALF_ANGLE + slack:
			return false
	var q := PhysicsRayQueryParameters2D.create(origin, global_position, 1)
	q.exclude = [_player.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _check_hit() -> void:
	if _grace > 0.0 or state != State.ACTIVE:
		return
	if behavior == Behavior.GUARD and size_k < 0.6:
		return
	if not _player.health_component.can_receive_actions():
		return
	var r := radius * 0.8 * size_k
	var c := _player_center()
	var half := Vector2(8, 14.5)
	var dx := maxf(absf(global_position.x - c.x) - half.x, 0.0)
	var dy := maxf(absf(global_position.y - c.y) - half.y, 0.0)
	if dx * dx + dy * dy < r * r:
		_player.die()


# ---------------- görsel ----------------

func _burst(n: int, spd: float) -> void:
	for i in n:
		if _spores.size() > 48:
			break
		var a := _rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * _rng.randf_range(spd * 0.4, spd)
		_spores.append([Vector2(cos(a), sin(a)) * radius * size_k * 0.8, v, 0.0, _rng.randf_range(0.35, 0.8)])


func _update_spores(delta: float) -> void:
	if _spores.is_empty():
		return
	var alive: Array = []
	for s in _spores:
		s[2] += delta
		if s[2] < s[3]:
			s[0] += s[1] * delta
			s[1] *= 0.94
			s[1].y -= 20.0 * delta
			alive.append(s)
	_spores = alive


func _redraw_stepped() -> void:
	var tk := int(_t * 10.0)
	if tk != _tick or lit:
		_tick = tk
		queue_redraw()


func _snap(v: Vector2) -> Vector2:
	return (v / PX).floor() * PX


func _draw() -> void:
	if state == State.GONE:
		return
	var tick := int(_t * 10.0)
	var k := size_k
	if state == State.DORMANT:
		# duvardaki çatlak: iki sönük göz (yaklaşınca uyanacağını ima eder)
		var blink := (tick % 37) < 2
		if not blink:
			draw_rect(Rect2(Vector2(-6, -2), Vector2(4, 2)), Color(C_RIM[0], 0.7))
			draw_rect(Rect2(Vector2(2, -2), Vector2(4, 2)), Color(C_RIM[0], 0.7))
		_draw_spores()
		return
	if state == State.EMERGING:
		k *= clampf(_emerge_t / 0.6, 0.1, 1.0)
	var r := radius * k
	var lvl: int = [0, 1, 2, 1][tick % 4]
	var rim: Color = C_HOT if lit and tick % 2 == 0 else C_RIM[lvl]
	var body: Color = C_BODY2 if lit else C_BODY
	if state == State.DISSOLVING:
		var a := clampf(1.0 - _dissolve_t / 0.7, 0.0, 1.0)
		rim = Color(C_HOT, a)
		body = Color(body, a)
	# dış parıltı
	var glow := Color(C_RIM[1], 0.18 if not lit else 0.32)
	_draw_blob(r + 4.0, glow, tick, 2.0)
	# kenar + gövde
	_draw_blob(r + 2.0, rim, tick, 3.0)
	_draw_blob(r, body, tick, 3.0)
	# alttan sarkan kuyruk / alev pikselleri
	for i in range(-2, 3):
		var h := 4.0 + float((tick + i * 3) % 4) * 2.0 * k
		var x := float(i) * r * 0.4
		draw_rect(Rect2(_snap(Vector2(x - 2, r * 0.7)), Vector2(4, h)), body)
		draw_rect(Rect2(_snap(Vector2(x - 1, r * 0.7 + h)), Vector2(2, 2)), Color(rim, rim.a * 0.6))
	# gözler: karanlıkta açık ve oyuncuya bakar; ışıkta kısılır (tıslama)
	var look := Vector2.ZERO
	if _player and is_instance_valid(_player):
		look = (_player_center() - global_position).normalized() * 2.0
	var ey := -r * 0.2
	var ex := maxf(r * 0.38, 4.0)
	if lit or state == State.DISSOLVING:
		for sx in [-1.0, 1.0]:
			var c := Vector2(sx * ex, ey)
			draw_rect(Rect2(_snap(c + Vector2(-4, -1)), Vector2(8, 2)), C_HOT)
			draw_rect(Rect2(_snap(c + Vector2(-2, -3) + Vector2(sx * -1, 0)), Vector2(4, 2)), C_EYE)
		# ağız: tıslayan dişler
		var my := r * 0.35
		draw_rect(Rect2(_snap(Vector2(-r * 0.4, my)), Vector2(r * 0.8, 2)), C_HOT)
		for i in 3:
			draw_rect(Rect2(_snap(Vector2(-r * 0.3 + i * r * 0.3, my + 2)), Vector2(2, 2)), C_EYE)
	else:
		var blink := (tick % 41) < 1
		for sx in [-1.0, 1.0]:
			var c := Vector2(sx * ex, ey)
			if blink:
				draw_rect(Rect2(_snap(c + Vector2(-3, 0)), Vector2(6, 2)), C_EYE)
			else:
				draw_rect(Rect2(_snap(c + Vector2(-3, -3)), Vector2(6, 6)), C_EYE)
				draw_rect(Rect2(_snap(c + look + Vector2(-1, -1)), Vector2(2, 2)), C_PUPIL)
	_draw_spores()


func _draw_blob(r: float, col: Color, tick: int, wobble: float) -> void:
	if r <= 1.0:
		return
	var y := -r
	while y <= r:
		var w := sqrt(maxf(r * r - y * y, 0.0))
		var n := float(((int(y) * 7 + tick * 3) % 5)) / 4.0 # 0..1 adımlı dalga
		w = maxf(w + (n - 0.5) * wobble, 1.0)
		var rect := Rect2(_snap(Vector2(-w, y)), Vector2(_snap(Vector2(w * 2.0, 0)).x + PX, PX))
		draw_rect(rect, col)
		y += PX


func _draw_spores() -> void:
	for s in _spores:
		var kk := float(s[2]) / float(s[3])
		var col: Color = C_SPORE[mini(int(kk * 3.0), 2)]
		draw_rect(Rect2(_snap(s[0]), Vector2(2, 2)), col)


func _sfx(n: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(n, 0.1)
