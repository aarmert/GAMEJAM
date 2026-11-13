extends Node2D

# Kovalamaca hız kademeleri (saniyede bir blok dalgası; küçük = hızlı).
# Müzik bölümü speed'e göre seçilir (bkz. _muzik_bolumu_sec): bu değerler eşiklerle uyumlu kalmalı.
const HIZ_HIZLI := 0.11
const HIZ_ORTA := 0.12
const HIZ_YAVAS := 0.2

@export var block_scene: PackedScene
@export var player: Node2D
@export var tile_map: TileMap
# Selin hızı: kaç saniyede bir yeni blok dalgası eklenir (küçük = hızlı).
# Değiştiği anda müzik de o hıza uygun bölüme geçer (bölüm değişmediyse müzik baştan başlamaz).
@export var speed: float = HIZ_HIZLI:
	set(value):
		speed = value
		if is_node_ready():
			muzik_degistir()
@export var spawn_count: int = 5 # Tek seferde eklenecek blok sayısı
# Kovalama: her dalgadaki blokların bir kısmı, oyuncuya YOL boyunca en yakın sınır
# bloklarından oyuncuya doğru büyür; geri kalanı rastgele (organik) yayılır.
# Kovalayan pay karanlığın oyuncuya yol mesafesine göre değişir: chase_near'dan yakında 0
# (yakındaki karanlık sadece organik yayılır, hareket eden oyuncu ondan kaçabilir),
# chase_far'dan uzakta chase_max (geride kalan karanlık arayı kapatır). İki mesafe de
# speed / HIZ_HIZLI ile ölçeklenir: yavaş kademede karanlık belirgin şekilde geride kalır.
@export var chase_max: float = 1.0
@export var chase_near: float = 150.0
@export var chase_far: float = 700.0
# Yakın mesafede (chase_near içinde) karanlık oyuncuya en fazla bu hızla (px/sn, hızlı
# kademede; yavaşta orantılı olarak daha az) yaklaşır. Duran oyuncu birkaç saniyede yakalanır,
# kısa bir duraksama ya da hata ise affedilir. Dar koridorlarda serbest yayılma çok daha hızlı olurdu.
@export var close_speed: float = 65.0
# Bölüm başında karanlık bu kadar saniye bekler (sahne geçiş fade'i sürerken geçen süre sayılmaz).
# 0 = bölüm oynanabilir olduğu anda canavar koşmaya başlar.
@export var start_delay: float = 0.0
# Checkpoint'te yeniden doğunca karanlığın bekleme süresi.
@export var respawn_delay: float = 1.5
# Işık (heal zone) karanlığı bu kadar saniye tutar, sonra karanlık ışığın içinden (blok
# bırakmadan) geçip yoluna devam eder. Işığın içindeki oyuncuya karanlık hiç değmez.
@export var heal_hold_time: float = 1.5
# Güvenlik sınırı: blok sayısı bunu aşarsa yayılma durur.
@export var max_blocks: int = 3000


const TILE_SIZE = 32
# Blok merkezinin heal zone kenarından en az bu kadar uzak olması gerekir (blok yarı boyu ~10 px)
const HEAL_MARGIN = 12.0
# Yol mesafesi haritası oyuncudan en fazla bu kadar hücre öteye hesaplanır
const FLOW_MAX_STEPS := 160
const FLOW_REFRESH := 0.15

var time_passed: float = 0.0
var _clock: float = 0.0
var _delay_left: float = 0.0
var _block_count: int = 0
var _bounds := Rect2()
var frontier_blocks = []
var occupied_blocks = {}
var _heal_touch := {} # heal zone -> karanlığın ona ilk değdiği an (_clock)
var _wall_cache := {} # Vector2i -> bool
var _flow := {} # Vector2i hücre -> oyuncuya yol mesafesi (hücre)
var _flow_cell := Vector2i(1 << 30, 0)
var _flow_age := INF
var lead_distance := INF # karanlığın oyuncuya yol mesafesi (px), hata ayıklama/test için
var _near_eff := 0.0
var _approach_budget := 0.0

# Sadece 4 ana yöne yayıl (Çaprazları es geç ki boşluk kalmasın)
var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const DIRS_I := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

@onready var muzik = $Muzik

# canavar_escape.wav içindeki hazır bölümler: [başlangıç, bitiş] saniye
const MUZIK_YAVAS := Vector2(0.0, 4.5)
const MUZIK_ORTA := Vector2(4.5, 9.5)
const MUZIK_HIZLI := Vector2(9.5, 14.35)

var loop_baslangic: float = MUZIK_ORTA.x
var loop_bitis: float = MUZIK_ORTA.y
var _aktif_bolum := Vector2(-1, -1)


func _muzik_bolumu_sec() -> Vector2:
	# speed aralıkla değerlendirilir (float eşitliği güvenilmez)
	if speed <= 0.115:
		return MUZIK_HIZLI
	elif speed < 0.16:
		return MUZIK_ORTA
	return MUZIK_YAVAS


func muzik_degistir() -> void:
	var bolum := _muzik_bolumu_sec()
	if bolum == _aktif_bolum:
		return
	_aktif_bolum = bolum
	loop_baslangic = bolum.x
	loop_bitis = bolum.y
	if muzik:
		muzik.play(loop_baslangic)


func _ready() -> void:
	add_to_group("darkness_manager")
	_delay_left = start_delay
	if CheckpointData.has_darkness_origin:
		global_position = CheckpointData.darkness_origin_pos
		# Checkpoint'te yeniden doğuş: kaydedilmiş hız (varsa) ve kısa bekleme
		var cd: Script = load("res://scripts/world/checkpoint_data.gd")
		var saved = cd.get("darkness_speed") if cd else null
		if saved != null and float(saved) > 0.0:
			speed = float(saved)
		_delay_left = respawn_delay

	if tile_map:
		# Başlangıcı karo merkezine hizala: bloklar (20x21) hücre ortasında durur ve
		# duvar karolarına hiç değmez.
		var cell := tile_map.local_to_map(tile_map.to_local(global_position))
		global_position = tile_map.to_global(tile_map.map_to_local(cell))
		# Bölüm sınırı: karoların kapladığı alanın dışına (boşluğa) yayılma
		var used := tile_map.get_used_rect()
		var tl := tile_map.to_global(tile_map.map_to_local(used.position)) - Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		_bounds = Rect2(tl, Vector2(used.size) * TILE_SIZE).grow(-1.0)

	frontier_blocks.append(global_position)
	occupied_blocks[global_position] = true
	muzik_degistir()


func _process(delta: float) -> void:
	# Müzik bittiyse ya da bölüm sonuna geldiyse aktif bölümün başına sar
	if not muzik.playing:
		muzik.play(loop_baslangic)
	elif muzik.get_playback_position() >= (loop_bitis - 0.05):
		muzik.seek(loop_baslangic)

	if not is_instance_valid(player) or frontier_blocks.is_empty():
		return
	# Oyuncu öldüyse yayılmaya gerek yok (yeniden yükleme sırasında boşuna blok üretme)
	if "health_component" in player and player.health_component and not player.health_component.can_receive_actions():
		return
	if _block_count >= max_blocks:
		return
	# Sahne geçiş fade'i sürerken karanlık hiç ilerlemez; ardından (varsa) bekleme süresi
	if _is_transitioning():
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return

	_clock += delta
	time_passed += delta
	_flow_age += delta
	if time_passed < speed:
		return
	# Artanı koru: 60 FPS'te 0.12 ile 0.13 aynı kare sayısına yuvarlanmasın
	time_passed = minf(time_passed - speed, speed)

	_update_flow()
	var chase_share := 0.0
	if tile_map:
		lead_distance = _lead_distance()
		# Yavaş kademede karanlık daha geriden kovalar, hızlıda daha yakından
		var k := speed / HIZ_HIZLI
		_near_eff = chase_near * k
		var far := chase_far * k
		chase_share = chase_max * clampf((lead_distance - _near_eff) / maxf(far - _near_eff, 1.0), 0.0, 1.0)
		# Yaklaşma bütçesi: dalga başına sabit (yavaş kademede dalgalar seyrek olduğundan daha yavaş)
		_approach_budget = minf(_approach_budget + close_speed * HIZ_HIZLI, TILE_SIZE * 1.5)

	for i in range(spawn_count):
		if frontier_blocks.is_empty():
			break
		if randf() < chase_share and _grow_chase():
			continue
		_grow_random()


# Oyuncuya yol boyunca en yakın sınır bloklarından birini, oyuncuya yaklaşan komşusuna büyüt.
func _grow_chase() -> bool:
	for _attempt in range(4):
		var best := FLOW_MAX_STEPS + 1
		var cands := []
		for b in frontier_blocks:
			var d: int = _flow.get(_cell(b), FLOW_MAX_STEPS + 1)
			if d < best:
				best = d
				cands = [b]
			elif d <= best + 1 and d <= FLOW_MAX_STEPS:
				cands.append(b)
		if best > FLOW_MAX_STEPS:
			return false
		# en iyi + 1 adım içindeki adaylardan rastgele biri (dalga koridoru doldursun)
		cands = cands.filter(func(c): return _flow.get(_cell(c), FLOW_MAX_STEPS + 1) <= best + 1)
		var base_pos: Vector2 = cands.pick_random()
		var base_d: int = _flow.get(_cell(base_pos), FLOW_MAX_STEPS + 1)
		var targets := []
		var held := false
		for dir in directions:
			var target_pos: Vector2 = base_pos + dir * TILE_SIZE
			var r := _check_target(target_pos)
			if r == 2:
				held = true
			if r != 1:
				continue
			var td: int = _flow.get(_cell(target_pos), FLOW_MAX_STEPS + 1)
			if td <= base_d:
				if not _approach_ok(target_pos):
					held = true
					continue
				targets.append(target_pos)
		if targets.is_empty():
			# Bu blok ileri gidemiyor: tamamen tıkalıysa sınırdan çıkar, değilse organik yayılsın
			if held:
				return true # yaklaşma bütçesi doldu / ışık tutuyor: bu blok hakkı beklesin
			if not _has_free_neighbour(base_pos):
				frontier_blocks.erase(base_pos)
				continue
			return false
		_place(targets.pick_random())
		return true
	return false


func _grow_random() -> void:
	# Sınır hattından rastgele bir blok seç
	var base_pos = frontier_blocks.pick_random()
	var current_distance = base_pos.distance_to(player.global_position)

	# Ölü Bölge: Oyuncuya çok yakınsa ezmesin
	if current_distance < 15.0:
		return

	var valid_targets = []
	var held := false

	# Bloğun etrafındaki 4 yöne bak
	for dir in directions:
		var target_pos = base_pos + (dir * TILE_SIZE)
		var r := _check_target(target_pos)
		if r == 2:
			held = true
		if r != 1:
			continue
		if not _approach_ok(target_pos):
			held = true
			continue

		# HİLELİ ZAR: Hedef oyuncuya daha mı yakın?
		var new_distance = target_pos.distance_to(player.global_position)
		if new_distance < current_distance:
			# Oyuncuya yaklaşıyorsa 3 kere ekle (yüksek şans)
			valid_targets.append(target_pos)
			valid_targets.append(target_pos)
			valid_targets.append(target_pos)
		else:
			# Uzaklaşıyorsa 1 kere ekle (düşük şans)
			valid_targets.append(target_pos)

	# OPTİMİZASYON: Gidecek yeri kalmayan bloğu sınır listesinden sil
	if valid_targets.is_empty():
		if not held:
			frontier_blocks.erase(base_pos)
		return

	_place(valid_targets.pick_random())


# 0 = geçersiz (dolu/duvar/sınır dışı), 1 = uygun, 2 = ışık şimdilik tutuyor
func _check_target(target_pos: Vector2) -> int:
	# 1. KONTROL: Kendi bloklarımızla zaten dolu mu?
	if occupied_blocks.has(target_pos):
		return 0
	# Bölüm sınırları dışı: boşluğa sonsuza dek yayılmasın
	if _bounds.has_area() and not _bounds.has_point(target_pos):
		occupied_blocks[target_pos] = true
		return 0
	# 2. KONTROL: TileMap üzerinde burada bir duvar var mı?
	if tile_map and _is_wall(_cell(target_pos)):
		occupied_blocks[target_pos] = true
		return 0
	# 3. KONTROL: Heal zone (ışık) içinde mi? Işık karanlığı bir süre tutar;
	# süre dolunca karanlık ışığın içinden blok bırakmadan geçer.
	var zone = _heal_zone_at(target_pos)
	if zone != null:
		if not _heal_touch.has(zone):
			_heal_touch[zone] = _clock
		if _clock - _heal_touch[zone] < heal_hold_time:
			return 2
	return 1


# Yakın mesafede oyuncuya yaklaştıran hücre ancak bütçe varsa kabul edilir
func _approach_ok(pos: Vector2) -> bool:
	if not tile_map or _flow.is_empty():
		return true
	var d: float = float(_flow.get(_cell(pos), FLOW_MAX_STEPS + 1)) * TILE_SIZE
	if d >= _near_eff or d >= lead_distance:
		return true
	return _approach_budget >= lead_distance - d


func _place(pos: Vector2) -> void:
	if tile_map and not _flow.is_empty():
		var d: float = float(_flow.get(_cell(pos), FLOW_MAX_STEPS + 1)) * TILE_SIZE
		if d < lead_distance:
			if d < _near_eff:
				_approach_budget -= lead_distance - d
			lead_distance = d
	frontier_blocks.append(pos)
	occupied_blocks[pos] = true
	if _heal_zone_at(pos) != null:
		return # ışığın içinden geçen karanlık: blok yok, oyuncuya değmez
	var new_block = block_scene.instantiate()
	new_block.global_position = pos
	add_sibling(new_block)
	_block_count += 1


func _has_free_neighbour(pos: Vector2) -> bool:
	for dir in directions:
		if _check_target(pos + dir * TILE_SIZE) != 0:
			return true
	return false


func _cell(pos: Vector2) -> Vector2i:
	return tile_map.local_to_map(tile_map.to_local(pos))


func _is_wall(map_pos: Vector2i) -> bool:
	if _wall_cache.has(map_pos):
		return _wall_cache[map_pos]
	# Sadece çarpışmalı karolar duvardır (çarpışmasız süs karoları karanlığı durdurmaz)
	var td := tile_map.get_cell_tile_data(0, map_pos)
	var wall := td != null and tile_map.tile_set.get_physics_layers_count() > 0 and td.get_collision_polygons_count(0) > 0
	_wall_cache[map_pos] = wall
	return wall


# Oyuncudan başlayarak geçilebilir hücrelerde yol mesafesi haritası (BFS)
func _update_flow() -> void:
	if not tile_map:
		return
	var pc := _cell(player.global_position + Vector2(0, -12))
	if pc == _flow_cell and _flow_age < FLOW_REFRESH:
		return
	_flow_cell = pc
	_flow_age = 0.0
	_flow = {}
	var queue: Array[Vector2i] = []
	if _is_wall(pc):
		for d in DIRS_I:
			if not _is_wall(pc + d):
				_flow[pc + d] = 0
				queue.append(pc + d)
	else:
		_flow[pc] = 0
		queue.append(pc)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var nd: int = _flow[c] + 1
		if nd > FLOW_MAX_STEPS:
			continue
		for d in DIRS_I:
			var n: Vector2i = c + d
			if _flow.has(n) or _is_wall(n):
				continue
			if _bounds.has_area() and not _bounds.has_point(tile_map.to_global(tile_map.map_to_local(n))):
				continue
			_flow[n] = nd
			queue.append(n)


func _lead_distance() -> float:
	var best := FLOW_MAX_STEPS + 1
	for b in frontier_blocks:
		var d: int = _flow.get(_cell(b), FLOW_MAX_STEPS + 1)
		if d < best:
			best = d
	return INF if best > FLOW_MAX_STEPS else float(best * TILE_SIZE)


func _is_transitioning() -> bool:
	var st := get_node_or_null("/root/SceneTransition")
	return st != null and st.has_method("is_transitioning") and st.is_transitioning()


func _heal_zone_at(pos: Vector2) -> Node:
	# Heal zone (checkpoint) içine karanlık bloğu girmez: içinde duran oyuncu güvende.
	# Dikdörtgen alanda tam şeklini, daire alanda yarıçapı kullan.
	for zone in get_tree().get_nodes_in_group("heal_zone"):
		for child in zone.get_children():
			if not child is CollisionShape2D or child.shape == null:
				continue
			var local: Vector2 = (child as CollisionShape2D).global_transform.affine_inverse() * pos
			if child.shape is RectangleShape2D:
				var half: Vector2 = child.shape.size * 0.5 + Vector2(HEAL_MARGIN, HEAL_MARGIN)
				if abs(local.x) <= half.x and abs(local.y) <= half.y:
					return zone
			elif child.shape is CircleShape2D:
				if local.length() <= child.shape.radius + HEAL_MARGIN:
					return zone
	return null
