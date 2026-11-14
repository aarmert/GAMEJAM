extends Node2D

# Karanlık "canavarın" görünümü (yalnızca görsel; yayılma mantığına, zamanlamaya, çarpışmaya dokunmaz).
#
# - Gövde: her blok aynı 64x64 dokudan (4x4 hücre) kendi hücresine düşen parçayı gösterir; böylece desen
#   bloklar arasında kesintisiz akar, ızgara görünmez. İç bloklar statiktir, her karede iş yapılmaz.
# - Ön cephe: açık (henüz karanlık olmayan) bir komşusu olan bloklar burada tek bir _draw ile çizilir:
#   nabız gibi atan macenta kenar, titreşen piksel "alevler", doğarken kısa bir parlama, sporlar ve
#   arada bir kırpışan gözler. Yalnızca yeni doğmuş / cephedeki bloklar izlenir (toplam blok sayısıyla
#   ölçeklenen bir döngü yok).
# - Kendi RandomNumberGenerator'ı vardır: oyunun global rastgeleliğini tüketmez (determinizm).

@export var manager: Node2D
@export var block_parent: Node
@export var body_texture: Texture2D

const CELL := 32
const HALF := 16
const PX := 2 # bir sanat pikseli = 2 dünya pikseli (tileset ile aynı tıknazlık)
const BODY_CELLS := 4 # doku kaç hücrede bir tekrar eder
const MAX_ACTIVE := 1200
const MAX_EYES := 7
const SPORE_POOL := 56

const C_GLOW := [Color(0.42, 0.16, 0.66, 0.30), Color(0.50, 0.20, 0.76, 0.38), Color(0.58, 0.24, 0.84, 0.46)]
const C_RIM := [Color("9b3fd8"), Color("c255f0"), Color("e46cff")]
const C_RIM_OLD := Color("5b2a8c")
const C_TIP := Color("f6b8ff")
const C_BLOOM := [Color("ffffff"), Color("f4c6ff"), Color("d47aff"), Color("8f45d0")]
const C_EYE := Color("f8ecff")
const C_PUPIL := Color("2a0b3d")
const C_SPORE := [Color("f0a8ff"), Color("c768ff"), Color("8a44c8")]

# Cephe hücresi kaydı: [cell: Vector2i, born: float, open_mask: int, eye: bool, gone_at: float]
var _active: Array = []
var _known := {} # Vector2i -> true (aktif listede)
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _spores: Array = [] # [pos: Vector2, vel: Vector2, life: float, max_life: float, size: int]
var _spore_acc := 0.0

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


func _ready() -> void:
	_rng.seed = 7331
	if block_parent == null and manager != null:
		block_parent = manager.get_parent()
	if block_parent == null:
		return
	block_parent.child_entered_tree.connect(_on_block_added)
	for c in block_parent.get_children():
		if c is Area2D and c.has_node("Sprite2D"):
			_on_block_added(c)


func _on_block_added(node: Node) -> void:
	if not (node is Area2D) or node.get_script() == null:
		return
	if not str(node.get_script().resource_path).ends_with("darkness_block_1_1.gd"):
		return
	var spr := node.get_node_or_null("Sprite2D") as Sprite2D
	var cell := Vector2i(floori(node.global_position.x / CELL), floori(node.global_position.y / CELL))
	if manager != null and manager.has_method("_cell") and manager.get("tile_map") != null:
		cell = manager._cell(node.global_position)
	if spr != null:
		if body_texture != null:
			spr.texture = body_texture
		spr.region_enabled = true
		spr.region_rect = Rect2(posmod(cell.x, BODY_CELLS) * 16, posmod(cell.y, BODY_CELLS) * 16, 16, 16)
	if _known.has(cell):
		return
	var mask := _open_mask(cell)
	if mask == 0:
		return # arka dolgu bloğu: hemen statik gövde
	_known[cell] = true
	_active.append([cell, _t, mask, _hash(cell, 3) % 4 == 0, -1.0])
	if _active.size() > MAX_ACTIVE:
		var old = _active.pop_front()
		_known.erase(old[0])


func _open_mask(c: Vector2i) -> int:
	if manager == null:
		return 0
	var shell: Dictionary = manager.get("_shell")
	var m := 0
	for i in 4:
		if shell.has(c + DIRS[i]):
			m |= 1 << i
	return m


func _process(delta: float) -> void:
	_t += delta
	# cephe durumunu güncelle (yalnızca aktif hücreler)
	var keep: Array = []
	for e in _active:
		var m := _open_mask(e[0])
		e[2] = m
		if m == 0:
			if e[4] < 0.0:
				e[4] = _t
			if _t - e[4] > 0.35:
				_known.erase(e[0])
				continue
		else:
			e[4] = -1.0
		keep.append(e)
	_active = keep
	_update_spores(delta)
	queue_redraw()


func _update_spores(delta: float) -> void:
	var alive: Array = []
	for s in _spores:
		s[2] += delta
		if s[2] >= s[3]:
			continue
		s[0] += s[1] * delta
		s[1].x += sin(_t * 3.0 + s[3] * 17.0) * 18.0 * delta
		s[1].y -= 6.0 * delta
		alive.append(s)
	_spores = alive
	# yalnızca genç cephe hücrelerinden spor çıkar
	var young: Array = []
	for e in _active:
		if e[2] != 0 and _t - e[1] < 5.0:
			young.append(e)
	if young.is_empty():
		return
	_spore_acc += delta * clampf(young.size() * 2.5, 6.0, 34.0)
	while _spore_acc >= 1.0 and _spores.size() < SPORE_POOL:
		_spore_acc -= 1.0
		var e = young[_rng.randi() % young.size()]
		var sides: Array[int] = []
		for i in 4:
			if e[2] & (1 << i):
				sides.append(i)
		var d: Vector2 = Vector2(DIRS[sides[_rng.randi() % sides.size()]])
		var center := _center(e[0])
		var along := Vector2(-d.y, d.x) * _rng.randf_range(-HALF, HALF)
		var pos := center + d * (HALF - 2.0) + along
		var vel := d * _rng.randf_range(8.0, 26.0) + Vector2(0, -_rng.randf_range(4.0, 14.0))
		_spores.append([pos, vel, 0.0, _rng.randf_range(0.6, 1.4), 2 if _rng.randf() < 0.7 else 4])
	_spore_acc = minf(_spore_acc, 2.0)


func _center(c: Vector2i) -> Vector2:
	if manager != null and manager.has_method("_pos") and manager.get("tile_map") != null:
		return to_local(manager._pos(c))
	return Vector2(c * CELL) + Vector2(HALF, HALF)


func _hash(c: Vector2i, salt: int) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663) ^ (salt * 83492791))


func _snap(v: Vector2) -> Vector2:
	return (v / PX).floor() * PX


func _draw() -> void:
	var pulse := int(floor(_t * 6.0)) % 4 # 0,1,2,1 adım adım nabız (yumuşak geçiş yok)
	var lvl: int = [0, 1, 2, 1][pulse]
	var tick := int(floor(_t * 9.0))
	var eyes := 0
	for e in _active:
		var c: Vector2i = e[0]
		var age: float = _t - float(e[1])
		var mask: int = e[2]
		var tl := _snap(_center(c) - Vector2(HALF, HALF))
		var young := age < 4.0
		if mask != 0:
			for i in 4:
				if mask & (1 << i):
					_draw_glow(tl, i, young, lvl)
			for i in 4:
				if mask & (1 << i):
					_draw_edge(tl, i, c, young, lvl, tick)
		# doğuş parlaması: yalnızca cephede doğan hücrede kısa, yarı saydam bir "pop" (3 adım, küçülerek)
		if age < 0.21 and mask != 0:
			var step := int(age / 0.07)
			var inset: float = [6.0, 9.0, 12.0][mini(step, 2)]
			var col: Color = [Color(C_BLOOM[1], 0.38), Color(C_BLOOM[2], 0.26), Color(C_BLOOM[3], 0.16)][mini(step, 2)]
			# artı biçimli piksel kümesi (kare kutu gibi görünmesin)
			var w := CELL - inset * 2.0
			draw_rect(Rect2(tl + Vector2(inset + 4.0, inset), Vector2(w - 8.0, w)), col)
			draw_rect(Rect2(tl + Vector2(inset, inset + 4.0), Vector2(w, w - 8.0)), col)
		# gözler
		if e[3] and mask != 0 and age > 0.25 and age < 7.0 and eyes < MAX_EYES:
			eyes += 1
			_draw_eyes(tl, c, age)
	for s in _spores:
		var k := float(s[2]) / float(s[3])
		var col: Color = C_SPORE[mini(int(k * 3.0), 2)]
		var sz: int = s[4] if k < 0.6 else 2
		draw_rect(Rect2(_snap(s[0]), Vector2(sz, sz)), col)


# Açık kenarın iç tarafında iki kademeli mor parıltı (yumuşak gradyan değil, iki bant)
func _draw_glow(tl: Vector2, side: int, young: bool, lvl: int) -> void:
	var a: Color = C_GLOW[lvl] if young else Color(0.36, 0.14, 0.56, 0.22)
	var b := Color(a, a.a * 0.5)
	for k in 2:
		var w := 6.0 if k == 0 else 14.0
		var col: Color = a if k == 0 else b
		var r: Rect2
		match side:
			0: r = Rect2(tl, Vector2(CELL, w))
			1: r = Rect2(tl + Vector2(0, CELL - w), Vector2(CELL, w))
			2: r = Rect2(tl, Vector2(w, CELL))
			_: r = Rect2(tl + Vector2(CELL - w, 0), Vector2(w, CELL))
		draw_rect(r, col)


# Bir açık kenar: kalın macenta bant + açıklığa doğru titreşen piksel alevleri
func _draw_edge(tl: Vector2, side: int, c: Vector2i, young: bool, lvl: int, tick: int) -> void:
	var rim: Color = C_RIM[lvl] if young else C_RIM_OLD
	var band := 4.0
	var r: Rect2
	match side:
		0: r = Rect2(tl, Vector2(CELL, band))
		1: r = Rect2(tl + Vector2(0, CELL - band), Vector2(CELL, band))
		2: r = Rect2(tl, Vector2(band, CELL))
		_: r = Rect2(tl + Vector2(CELL - band, 0), Vector2(band, CELL))
	draw_rect(r, rim)
	if not young:
		return
	# 8 dilim x 4 px; her dilimin alev boyu hücreye, dilime ve zamana göre adım adım değişir
	for k in 8:
		# taban boy hücre/dilime sabit, üstüne zamanla adım adım dalgalanan kısım: kıpır kıpır dokunaçlar
		var base := (_hash(c + Vector2i(k * 7, side * 13), 1) >> 3) % 4
		var wave := (_hash(c + Vector2i(k * 5, side * 11), tick / 2 + k) >> 5) % 3
		var ln := float(base + wave) * PX # 0..10 px
		if ln <= 0.0:
			continue
		var off := float(k * 4)
		var fr: Rect2
		var tip: Rect2
		match side:
			0:
				fr = Rect2(tl + Vector2(off, -ln), Vector2(4, ln))
				tip = Rect2(tl + Vector2(off + 1, -ln), Vector2(2, 2))
			1:
				fr = Rect2(tl + Vector2(off, CELL), Vector2(4, ln))
				tip = Rect2(tl + Vector2(off + 1, CELL + ln - 2), Vector2(2, 2))
			2:
				fr = Rect2(tl + Vector2(-ln, off), Vector2(ln, 4))
				tip = Rect2(tl + Vector2(-ln, off + 1), Vector2(2, 2))
			_:
				fr = Rect2(tl + Vector2(CELL, off), Vector2(ln, 4))
				tip = Rect2(tl + Vector2(CELL + ln - 2, off + 1), Vector2(2, 2))
		draw_rect(fr, rim)
		if ln >= 4.0:
			draw_rect(tip, C_TIP)


func _draw_eyes(tl: Vector2, c: Vector2i, age: float) -> void:
	var phase := float(_hash(c, 9) % 1000) / 1000.0 * 3.0
	var cyc := fmod(_t + phase, 2.6)
	var closed := cyc < 0.14 or age < 0.4
	var y := tl.y + 12.0
	for ex in [tl.x + 6.0, tl.x + 20.0]:
		if closed:
			draw_rect(Rect2(Vector2(ex, y + 2.0), Vector2(6, 2)), C_EYE)
		else:
			draw_rect(Rect2(Vector2(ex, y), Vector2(6, 6)), C_EYE)
			# göz bebeği oyuncuya değil, ileriye (sağa) bakar; hafif titrer
			var look := 2.0 if int(_t * 1.5 + phase) % 3 != 0 else 0.0
			draw_rect(Rect2(Vector2(ex + 2.0 + look, y + 2.0), Vector2(2, 2)), C_PUPIL)
