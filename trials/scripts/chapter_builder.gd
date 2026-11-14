extends RefCounted
# Ayrıştırılmış bölümden gerçek düğümleri kurar: oda başına bir TileMap (otomatik kenar/köşe),
# mevcut sahnelerin örnekleri (diken, düşman, küreler, sarmaşık, lamba, killzone, portal, platform).
# Builds real nodes from a parsed chapter. Each room is a Node2D with its own TileMap named
# "TileMap" (sarmasik.gd and Manager_Darkness look for that) placed at absolute world cells.

const Parser := preload("res://trials/scripts/chapter_parser.gd")
const Themes := preload("res://trials/scripts/trials_themes.gd")
const MovingPlatform := preload("res://trials/scripts/moving_platform.gd")
const Collectible := preload("res://trials/scripts/collectible.gd")

const SPIKE := preload("res://scenes/canavar.tscn")
const ENEMY := preload("res://scenes/enemy.tscn")
const ORB_JUMP := preload("res://scenes/orbit/double_jump_orbiti.tscn")
const ORB_DASH := preload("res://scenes/orbit/dash_orbiti.tscn")
const VINE := preload("res://scenes/levels/level1_Scene/sarmasik.tscn")
const KILLZONE := preload("res://scenes/killzone.tscn")
const LAMP := preload("res://scenes/levels/level1_Scene/heal_zone.tscn")
const EXIT := preload("res://scenes/level_exit.tscn")
const PLATFORM := preload("res://scenes/platforms.tscn")

const T := 32
# platforms.tscn: görünen ince kenarın üstü kökün 13.6 px yukarısında (bölge 32.7,123.25 / 95.8x36.75)
const PLATFORM_SURFACE := 13.6


# Bölümdeki tüm hücreler: Vector2i(dünya) -> karakter. Otomatik karo komşuluğu buradan okunur.
static func cell_map(ch: Dictionary) -> Dictionary:
	if ch.has("_cells"):
		return ch._cells
	var cells := {}
	for r in ch.rooms:
		for y in r.h:
			var row: String = r.rows[y]
			for x in r.w:
				cells[Vector2i(r.x + x, r.y + y)] = row[x]
	ch["_cells"] = cells
	return cells


static func room_rect_px(r: Dictionary) -> Rect2:
	return Rect2(r.x * T, r.y * T, r.w * T, r.h * T)


static func cell_center(r: Dictionary, x: int, y: int) -> Vector2:
	return Vector2((r.x + x) * T + T * 0.5, (r.y + y) * T + T * 0.5)


# Oyuncu kökü: asil_karakter.tscn'de kök, ayakların (çarpışma kutusunun altı) 17.5 px altında.
const PLAYER_FEET := 17.5

# Doğuş noktası (oyuncu kökü): ayaklar hücrenin alt kenarında.
static func spawn_world(r: Dictionary, s: Vector2i) -> Vector2:
	return Vector2((r.x + s.x) * T + T * 0.5, (r.y + s.y + 1) * T + PLAYER_FEET - 0.5)


## Odayı kurar (ağaca eklenmeden). Döner: info Dictionary (node, tilemap, spawns, orbs, exit, ...).
static func build_room(ch: Dictionary, r: Dictionary) -> Dictionary:
	var cells := cell_map(ch)
	var solid_at := func(wx: int, wy: int) -> bool:
		var c = cells.get(Vector2i(wx, wy))
		return c == null or c == "#"
	var rules := Themes.rules_for(ch.theme)

	var room := Node2D.new()
	room.name = "Room_%s" % r.id
	var tm := TileMap.new()
	tm.name = "TileMap"
	tm.tile_set = Themes.get_tileset()
	while tm.get_layers_count() < 3:
		tm.add_layer(-1)
	tm.set_layer_name(0, "solid")
	tm.set_layer_name(1, "oneway")
	tm.set_layer_name(2, "hazard_decor")
	room.add_child(tm)
	tm.owner = room

	var static_root := Node2D.new()
	static_root.name = "Static"
	room.add_child(static_root)
	var orbs_root := Node2D.new()
	orbs_root.name = "Orbs"
	room.add_child(orbs_root)
	var dyn := Node2D.new()
	dyn.name = "Dynamic"
	room.add_child(dyn)

	var info := {
		"room": r, "node": room, "tilemap": tm, "dynamic": dyn, "orbs": [], "exit": null,
		"spawns": [], "rect": room_rect_px(r), "enemies": [], "platforms": [], "collectibles": [],
		"lamps": [], "chase": {},
	}
	for s in r.spawns:
		info.spawns.append(spawn_world(r, s))

	var done_vine := {}
	for y in r.h:
		var row: String = r.rows[y]
		for x in r.w:
			var c := row[x]
			var wx: int = r.x + x
			var wy: int = r.y + y
			var center := cell_center(r, x, y)
			match c:
				"#":
					var t: Array = Themes.autotile(rules, wx, wy, solid_at)
					tm.set_cell(Themes.LAYER_SOLID, Vector2i(wx, wy), t[0], t[1])
				"=":
					var l := Parser.cell(r, x - 1, y) == "="
					var rr := Parser.cell(r, x + 1, y) == "="
					var a := Themes.ONEWAY_SINGLE
					if l and rr:
						a = Themes.ONEWAY_MID
					elif rr:
						a = Themes.ONEWAY_LEFT
					elif l:
						a = Themes.ONEWAY_RIGHT
					tm.set_cell(Themes.LAYER_ONEWAY, Vector2i(wx, wy), Themes.SRC_FOREST, a)
				"x":
					tm.set_cell(Themes.LAYER_DECOR, Vector2i(wx, wy), Themes.SRC_CAVE, Themes.HAZARD_A if posmod(wx, 2) == 0 else Themes.HAZARD_B)
				"^", "v", "<", ">":
					static_root.add_child(_make_spike(c, center))
				"|":
					if done_vine.has(Vector2i(x, y)):
						continue
					var y1: int = y
					while Parser.cell(r, x, y1 + 1) == "|":
						y1 += 1
					for yy in range(y, y1 + 1):
						done_vine[Vector2i(x, yy)] = true
					var side := -1 if Parser.cell(r, x - 1, y) == "#" else 1
					var v := VINE.instantiate()
					v.set("wall_side", side)
					var cs := v.get_node("CollisionShape2D") as CollisionShape2D
					var sh := RectangleShape2D.new()
					sh.size = Vector2(34, (y1 - y + 1) * T)
					cs.shape = sh
					cs.position = Vector2.ZERO
					var top: int = (r.y + y) * T
					v.position = Vector2(center.x, top + (y1 - y + 1) * T * 0.5)
					static_root.add_child(v)
					v.owner = room # sarmasik.gd duvar yüzeyini owner/TileMap'ten bulur
				"o", "*":
					var orb := (ORB_JUMP if c == "o" else ORB_DASH).instantiate()
					orb.position = center
					orb.add_child(_orb_ring(Color(0.35, 1.0, 0.5, 0.75) if c == "o" else Color(0.35, 0.65, 1.0, 0.85)))
					orbs_root.add_child(orb)
					info.orbs.append(orb)
				"L":
					var lamp := LAMP.instantiate()
					lamp.position = Vector2(center.x, center.y - T * 0.5)
					static_root.add_child(lamp)
					info.lamps.append(lamp)
				"E":
					var ex := EXIT.instantiate()
					ex.position = Vector2(center.x, center.y - T * 0.5)
					ex.set("_triggered", true) # kendi sahne geçişini kapat; Trials kendi sinyalini bağlar
					static_root.add_child(ex)
					info.exit = ex
				"e":
					info.enemies.append(Vector2(center.x, (r.y + y + 1) * T))
				"c":
					info.collectibles.append({"id": "%s:%d:%d" % [r.id, x, y], "pos": center})
				"M":
					var p := Parser.platform_partner(r, x, y)
					if p != Vector2i(-1, -1):
						var a2 := Vector2(center.x, (r.y + y) * T + PLATFORM_SURFACE)
						var b2 := Vector2(cell_center(r, p.x, p.y).x, (r.y + p.y) * T + PLATFORM_SURFACE)
						info.platforms.append({"a": a2, "b": b2, "speed": r.platform_speed, "wait": r.platform_wait})
				"D":
					info.chase["origin"] = center

	# killzone: yatay koşular (çarpışma karolarına değmesin diye 4 px içeride)
	for y in r.h:
		var x := 0
		while x < r.w:
			if Parser.cell(r, x, y) != "x":
				x += 1
				continue
			var x1 := x
			while Parser.cell(r, x1 + 1, y) == "x":
				x1 += 1
			var kz := KILLZONE.instantiate()
			var kcs := CollisionShape2D.new()
			var ksh := RectangleShape2D.new()
			ksh.size = Vector2((x1 - x + 1) * T - 8, T - 8)
			kcs.shape = ksh
			kz.add_child(kcs)
			kz.position = Vector2((r.x + x) * T + (x1 - x + 1) * T * 0.5, (r.y + y) * T + T * 0.5)
			kz.set_meta("trials_killzone", true)
			static_root.add_child(kz)
			x = x1 + 1

	if r.chase > 0.0:
		var g := Parser.chase_goal(ch, r)
		info.chase["speed"] = r.chase
		info.chase["delay"] = r.chase_delay
		if g != Vector2i(-1, -1):
			info.chase["goal"] = cell_center(r, g.x, g.y)

	_build_bounds(ch, r, static_root, cells)
	return info


# Küre okunurluğu: arkada renkli yumuşak halka (yeşil = çift zıplama, mavi = dash)
static func _orb_ring(col: Color) -> Sprite2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.75, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.25), Color(col, col.a), Color(col, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 48
	gt.height = 48
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var s := Sprite2D.new()
	s.name = "Ring"
	s.texture = gt
	s.z_index = -1
	return s


static func _make_spike(c: String, center: Vector2) -> Node2D:
	var s := SPIKE.instantiate() as Node2D
	var rot := 0.0
	match c:
		"v":
			rot = PI
		"<":
			rot = -PI * 0.5
		">":
			rot = PI * 0.5
	# canavar.tscn: diken pikselleri kökün -3..+4 px'inde; kök hücrenin dibinden 4 px yukarıda
	var offset := Vector2(0, T * 0.5 - 4.0).rotated(rot)
	s.position = center + offset
	s.rotation = rot
	var cs := s.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		var sh := RectangleShape2D.new()
		sh.size = Vector2(24, 7)
		cs.shape = sh
		cs.position = Vector2(0, 0.5)
	return s


# Oda kenarında komşu oda olmayan açıklıklara görünmez duvar (sol/sağ/üst). Alt açıklık = çukur (ölüm).
static func _build_bounds(ch: Dictionary, r: Dictionary, parent: Node2D, cells: Dictionary) -> void:
	var body := StaticBody2D.new()
	body.name = "Bounds"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	for side in ["left", "right", "top"]:
		var n: int = r.h if side != "top" else r.w
		var i := 0
		while i < n:
			if not _is_void_opening(r, side, i, cells):
				i += 1
				continue
			var j := i
			while j + 1 < n and _is_void_opening(r, side, j + 1, cells):
				j += 1
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			var len := (j - i + 1) * T
			match side:
				"left":
					sh.size = Vector2(T, len)
					cs.position = Vector2(r.x * T - T * 0.5, (r.y + i) * T + len * 0.5)
				"right":
					sh.size = Vector2(T, len)
					cs.position = Vector2((r.x + r.w) * T + T * 0.5, (r.y + i) * T + len * 0.5)
				"top":
					sh.size = Vector2(len, T)
					cs.position = Vector2((r.x + i) * T + len * 0.5, r.y * T - T * 0.5)
			cs.shape = sh
			body.add_child(cs)
			i = j + 1


static func _is_void_opening(r: Dictionary, side: String, i: int, cells: Dictionary) -> bool:
	var lx := 0
	var ly := 0
	var o := Vector2i.ZERO
	match side:
		"left":
			lx = 0; ly = i; o = Vector2i(-1, 0)
		"right":
			lx = r.w - 1; ly = i; o = Vector2i(1, 0)
		"top":
			lx = i; ly = 0; o = Vector2i(0, -1)
	if r.rows[ly][lx] == "#":
		return false
	return not cells.has(Vector2i(r.x + lx, r.y + ly) + o)


## Odanın sıfırlanan kısmını (düşman, hareketli platform, alınmamış toplanabilir) yeniden kurar.
static func build_dynamic(info: Dictionary, banked: Dictionary) -> Array:
	var dyn: Node2D = info.dynamic
	for c in dyn.get_children():
		dyn.remove_child(c)
		c.queue_free()
	var made := []
	for p in info.enemies:
		var e := ENEMY.instantiate()
		e.position = p
		dyn.add_child(e)
	for spec in info.platforms:
		var pl := PLATFORM.instantiate()
		pl.set_script(MovingPlatform)
		pl.a = spec.a
		pl.b = spec.b
		pl.speed = spec.speed
		pl.wait = spec.wait
		pl.position = spec.a
		var cs := pl.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs != null:
			cs.position.y = -PLATFORM_SURFACE + 9.5 # şekil 19 px; üstü görünen kenarla hizalı
		dyn.add_child(pl)
	for spec in info.collectibles:
		if banked.has(spec.id):
			continue
		var c := Collectible.new()
		c.cid = spec.id
		c.position = spec.pos
		dyn.add_child(c)
		made.append(c)
	return made
