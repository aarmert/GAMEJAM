extends Node2D

# Mağara kovalamacasının "canavarı": 32 px'lik ızgarada sürekli (kesintisiz) yayılan karanlık.
#
# Kurallar:
# - Yeni blok YALNIZCA mevcut bir bloğun 4 komşusundan birine konur: karanlık hiç atlamaz,
#   kopuk parça bırakmaz. Arkada kalan boşluklar (karanlığın çevrelediği hücreler) hemen doldurulur.
# - Çarpışmalı karolar (duvar) ve heal zone (ışık) dikdörtgenleri karanlığı tamamen durdurur.
#   Işığın içindeki oyuncuya karanlık asla değmez; karanlık ışığın etrafından, tasarımcının
#   açtığı alt tünellerden dolaşmak zorundadır.
# - Yön: oyuncudan başlayan yol mesafesi haritası (duvar + ışık geçilmez). Karanlığın ön cephesi
#   bu haritanın eş-mesafe çizgisi gibi ilerler (tüneli bütün kesitiyle doldurarak); yan cepler ve
#   cephenin gerisi "arka dolgu" ile kısa sürede doldurulur. Böylece karanlık tek, katı bir kütle
#   olarak oyuncuya giden en kısa yolu (ışık kapalıysa alt tüneli) izler.
# - Sollamaz: "ilerleme" = bölüm çıkışına (LevelExit) yol mesafesi. Karanlık, ilerlemesi oyuncununkinden
#   en az chase_gap kadar geride olan hücrelere girebilir; bu pay oyuncu yavaşlarsa close_speed ile
#   kapanır (duran/yavaş oyuncu yakalanır). Alt tünel oyuncunun önünden yukarı açılıyorsa karanlık
#   tünelde oyuncunun altında/biraz gerisinde onu izler, açıklıktan ancak oyuncu geçtikten sonra,
#   arkasından çıkar (koşan oyuncunun önünü kesmez). Uzun süre duran oyuncuyu ise (overtake) sonunda
#   önden dolaşarak da yakalar.
# - Tempo: karanlık oyuncuya yol mesafesi chase_gap'ten uzaktaysa catch_speed ile yetişir,
#   yakındaysa close_speed ile yaklaşır (duran oyuncu birkaç saniyede yakalanır, koşan kaçar).
#   Oyuncu ışıktayken karanlık light_gap'ten fazla yaklaşmaz (ışıktan çıkınca kaçma şansı olsun).

# Kovalamaca hız kademeleri (eski adıyla "saniyede bir blok dalgası"; küçük = hızlı).
# Müzik bölümü speed'e göre seçilir (bkz. _muzik_bolumu_sec): bu değerler eşiklerle uyumlu kalmalı.
const HIZ_HIZLI := 0.11
const HIZ_ORTA := 0.12
const HIZ_YAVAS := 0.2

@export var block_scene: PackedScene
@export var player: Node2D
@export var tile_map: TileMap
# Kademe: hızlar HIZ_HIZLI / speed ile, mesafeler speed / HIZ_HIZLI ile ölçeklenir
# (yavaş kademede karanlık hem daha yavaş hem daha geriden gelir).
# Değiştiği anda müzik de o hıza uygun bölüme geçer (bölüm değişmediyse müzik baştan başlamaz).
@export var speed: float = HIZ_HIZLI:
	set(value):
		speed = value
		if is_node_ready():
			muzik_degistir()
# Hedef takip mesafesi (px, yol boyunca, hızlı kademe). Bundan uzaktaysa karanlık yetişir.
@export var chase_gap: float = 160.0
# Uzaktayken ön cephenin yol boyunca ilerleme hızı (px/sn). Oyuncudan (180) hızlı olmalı.
@export var catch_speed: float = 230.0
# Yakındayken (chase_gap içinde) yaklaşma hızı (px/sn). Duran oyuncu ~chase_gap/close_speed sn'de yakalanır.
@export var close_speed: float = 45.0
# Oyuncu ışıktayken karanlık bundan fazla yaklaşmaz (px, yol boyunca).
@export var light_gap: float = 400.0
# Işık dikdörtgenini oyuncunun terk edeceği yön (seviye soldan sağa akar). Oyuncu ışıktayken
# mesafe haritası ışığın bu yöndeki kenarından başlar: karanlık ışığın arkasına (geldiği tarafa)
# yığılmaz, alt tünelden dolaşıp oyuncunun gideceği tarafa yönelir.
@export var heal_exit_dir: Vector2i = Vector2i.RIGHT
# Sollamama kuralının ölçüsü: bölüm çıkışı (boşsa sahnedeki "LevelExit" düğümü aranır).
@export var progress_target: Node2D
# Karanlık, çıkışa oyuncudan en fazla bu kadar hücre daha yakın olabilir (0 = hiç öne geçmez).
@export var progress_slack: int = 0
# Oyuncu bu kadar saniye ilerlemezse (ışık dışında) karanlık her saniye overtake_rate hücre daha
# öne geçebilir: duran oyuncuyu, tünel önden dolaşsa bile, sonunda yakalar. İlerleyince sıfırlanır.
@export var overtake_after: float = 1.5
@export var overtake_rate: float = 8.0
# Arka dolgu: cephenin gerisinde kalan boş hücreleri doldurma hızı (hücre/sn) ve derinliği (hücre).
@export var fill_rate: float = 90.0
@export var fill_depth: int = 36
# Cephe kenarı pürüzü (hücre, 0..1): ön cephe dümdüz bir çizgi gibi görünmesin.
@export var edge_jitter: float = 0.8
# Bölüm başında karanlık bu kadar saniye bekler (sahne geçiş fade'i sürerken geçen süre sayılmaz).
# 0 = bölüm oynanabilir olduğu anda canavar koşmaya başlar.
@export var start_delay: float = 0.0
# Checkpoint'te yeniden doğunca karanlığın bekleme süresi.
@export var respawn_delay: float = 1.5
# Güvenlik sınırı: blok sayısı bunu aşarsa yayılma durur.
@export var max_blocks: int = 6000


const TILE_SIZE = 32
# Blok merkezinin heal zone kenarından en az bu kadar uzak olması gerekir (blok yarı boyu ~10 px)
const HEAL_MARGIN = 12.0
const DIRS_I: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const INF_D := 1 << 20

var _clock: float = 0.0
var _delay_left: float = 0.0
var _block_count: int = 0
var _cell_bounds := Rect2i()
var _dark := {} # Vector2i -> true : karanlık hücreleri
var _shell := {} # Vector2i -> true : karanlığa komşu, boş ve geçilebilir hücreler (büyüme adayları)
var _wall_cache := {} # Vector2i -> bool
var _heal_cache := {} # Vector2i -> heal zone düğümü ya da null
var _flow := {} # Vector2i -> oyuncuya yol mesafesi (hücre)
var _flow_key := Vector3i(1 << 30, 0, 0)
var _player_in_light := false
var _exit_dist := {} # Vector2i -> bölüm çıkışına yol mesafesi (ışıklar geçilir: oyuncunun yolu)
var _player_progress := INF_D
var _pockets := {} # Vector2i -> true : karanlığın çevrelediği küçük boş bölgeler (önce doldurulur)
var _pocket_age := 0.0
var _best_progress := INF_D
var _idle_time := 0.0
var _allow_prog := float(INF_D) # karanlığın girebileceği en küçük ilerleme (çıkış mesafesi, hücre)
var _advance_acc := 0.0
var _fill_acc := 0.0
var lead_distance := INF # karanlık ön cephesinin oyuncuya yol mesafesi (px); test/hata ayıklama için
var contiguity_violations := 0 # komşusu olmadan konan blok sayısı (her zaman 0 olmalı)

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
	muzik_degistir()
	if not tile_map:
		push_warning("Manager_Darkness: tile_map atanmamış, karanlık yayılmaz")
		return
	# Bölüm sınırı: karoların kapladığı alanın dışına (boşluğa) yayılma
	_cell_bounds = tile_map.get_used_rect()
	var start := _cell(global_position)
	if _blocked(start):
		start = _nearest_open(start)
	global_position = _pos(start)
	_build_exit_field()
	_add_dark(start, true)


func _process(delta: float) -> void:
	# Müzik bittiyse ya da bölüm sonuna geldiyse aktif bölümün başına sar
	if not muzik.playing:
		muzik.play(loop_baslangic)
	elif muzik.get_playback_position() >= (loop_bitis - 0.05):
		muzik.seek(loop_baslangic)

	if not tile_map or not is_instance_valid(player) or _shell.is_empty():
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
	_update_flow()

	# Kademe çarpanı (yavaş kademede < 1). Karekök: yavaş kademe belirgin ama duran oyuncu yine
	# makul sürede yakalanır.
	var k := sqrt(HIZ_HIZLI / maxf(speed, 0.01))
	_update_progress_limit(k, delta)
	var front := _front_metric()
	var reachable: bool = front.x < INF_D
	if reachable:
		lead_distance = (front.x + 1.0) * TILE_SIZE
		var gap := (light_gap if _player_in_light else chase_gap) / k
		var v := 0.0
		if lead_distance > gap:
			# Yetişme hızı yavaş kademede de oyuncudan hızlı kalır (yoksa dolambaçtan sonra hiç yetişemez)
			v = catch_speed * clampf(k, 0.9, 1.0)
		elif not _player_in_light:
			v = close_speed * k
		else:
			_advance_acc = 0.0
		# Yakındayken tek seferde en fazla bir hücre (birikmiş hız oyuncuya sıçratmasın)
		var cap := TILE_SIZE * (2.0 if lead_distance > gap else 1.0)
		_advance_acc = minf(_advance_acc + v * delta, cap)
	else:
		# Oyuncuya geçilebilir yol yok (ışık kapatıyor, alt tünel yok): karanlık oyuncuya kuş uçuşu
		# yakın tarafta yavaşça birikir ama ışığı aşamaz.
		lead_distance = INF
		_advance_acc = minf(_advance_acc + close_speed * k * delta, TILE_SIZE * 2.0)

	_pocket_age += delta
	if _pocket_age >= 0.2:
		_pocket_age = 0.0
		_scan_pockets()

	var layers := 0
	while _advance_acc >= TILE_SIZE and layers < 2 and not _shell.is_empty():
		_advance_acc -= TILE_SIZE
		layers += 1
		_advance_layer()

	_fill_acc = minf(_fill_acc + fill_rate * clampf(k, 0.6, 1.0) * delta, 6.0)
	while _fill_acc >= 1.0 and not _shell.is_empty():
		_fill_acc -= 1.0
		if not _fill_one():
			_fill_acc = 0.0
			break


# --- büyüme -------------------------------------------------------------------------------

# Bir hücrenin "oyuncuya uzaklığı" (hücre). Mesafe haritası ulaşamıyorsa kuş uçuşu kullanılır.
func _metric(c: Vector2i) -> float:
	if not _allowed(c):
		return INF_D
	var d = _flow.get(c)
	if d != null:
		return float(d) + _jitter(c)
	return INF_D


func _euclid(c: Vector2i) -> float:
	return _pos(c).distance_to(player.global_position) / TILE_SIZE


# İlerleme sınırını güncelle (bkz. dosya başı "Sollamaz")
func _update_progress_limit(k: float, delta: float) -> void:
	if _player_progress >= INF_D:
		_allow_prog = -INF
		return
	var p := float(_player_progress)
	# Işıktayken de aynı pay: karanlık ışığın altındaki tünele dolar (görünür), ama oyuncunun
	# önüne geçmez; yol boyunca light_gap'ten fazla yaklaşmaz (_process).
	var gap := chase_gap / k / TILE_SIZE
	if _player_progress < _best_progress:
		_best_progress = _player_progress
		_idle_time = 0.0
		# Uzun bekleyişte verilen sollama izni oyuncu yeniden ilerleyince geri alınır
		_allow_prog = maxf(_allow_prog, p - progress_slack)
	elif not _player_in_light:
		_idle_time += delta
	if _allow_prog > p + gap or _player_in_light:
		_allow_prog = p + gap
		return
	_allow_prog -= close_speed * k * delta / TILE_SIZE
	if _idle_time > overtake_after:
		_allow_prog -= overtake_rate * delta
	elif _allow_prog < p - progress_slack:
		_allow_prog = p - progress_slack


# Sollamama: hücre bölüm çıkışına oyuncudan daha yakın olmamalı
func _allowed(c: Vector2i) -> bool:
	if _player_progress >= INF_D:
		return true
	return float(_exit_dist.get(c, INF_D)) >= _allow_prog


# x = ön cephe (en yakın aday hücre) metrik değeri; y = kuş uçuşu en yakın aday (ulaşılamazken)
func _front_metric() -> Vector2:
	var best := float(INF_D)
	var best_e := float(INF_D)
	for c in _shell:
		var m := _metric(c)
		if m < best:
			best = m
		if m >= INF_D:
			best_e = minf(best_e, _euclid(c))
	return Vector2(best, best_e)


# Ön cepheyi bir hücre ilerlet: oyuncuya en yakın aday hücreler (ve aynı şeritteki komşuları) dolar.
func _advance_layer() -> void:
	var best := float(INF_D)
	for c in _shell:
		best = minf(best, _metric(c))
	var picks: Array[Vector2i] = []
	if best < INF_D:
		for c in _shell:
			if _metric(c) <= best + 1.0:
				picks.append(c)
	else:
		# Ulaşılamaz: kuş uçuşu oyuncuya en yakın adayı doldur
		var be := float(INF_D)
		var bc := Vector2i.ZERO
		for c in _shell:
			if not _allowed(c):
				continue
			var e := _euclid(c)
			if e < be:
				be = e
				bc = c
		if be < INF_D:
			picks.append(bc)
	for c in picks:
		if _shell.has(c):
			_add_dark(c)


# Arka dolgu: cephenin gerisinde kalan (oyuncudan daha uzak) en yakın boş hücreyi doldur.
# Çevrelenmiş (hiç boş komşusu kalmamış) hücreler önce doldurulur.
func _fill_one() -> bool:
	var front := float(INF_D)
	for c in _shell:
		front = minf(front, _metric(c))
	var limit := front + float(fill_depth)
	var best := float(INF_D)
	var pick := Vector2i.ZERO
	var found := false
	for c in _shell:
		var free_n := 0
		for d in DIRS_I:
			var n: Vector2i = c + d
			if not _dark.has(n) and not _blocked(n):
				free_n += 1
		var m := _metric(c)
		var score: float
		if free_n == 0 or _pockets.has(c):
			score = -1.0 - float(4 - free_n) # delik / çevrelenmiş cep: hemen doldur
		elif m < INF_D:
			if front < INF_D and m <= front + 1.0:
				continue # cephenin kendisi: ilerleme hızına tabi
			if m > limit:
				continue
			score = m
		else:
			# Mesafe haritasının ulaşmadığı (ışıkla kapalı) bölge: oyuncuya kuş uçuşu yakın kısmı
			# doldur, böylece orada da delik kalmaz
			var e := _euclid(c)
			if e > 45.0 or not _allowed(c):
				continue
			score = float(fill_depth) + e
		if score < best:
			best = score
			pick = c
			found = true
	if not found:
		return false
	_add_dark(pick)
	return true


# Karanlığın (duvar/ışıkla birlikte) tamamen çevrelediği, oyuncunun bulunmadığı küçük boş
# bölgeleri bul: bunlar ilerleme kuralından bağımsız olarak hemen doldurulur.
func _scan_pockets() -> void:
	_pockets = {}
	var pc := _cell(player.global_position + Vector2(0, -32))
	var visited := {}
	for s in _shell:
		if visited.has(s):
			continue
		var comp: Array[Vector2i] = [s]
		visited[s] = true
		var head := 0
		var closed := true
		while head < comp.size():
			var c: Vector2i = comp[head]
			head += 1
			if c == pc or _flow.get(c, -1) == 0:
				closed = false
			for d in DIRS_I:
				var n: Vector2i = c + d
				if visited.has(n) or _dark.has(n) or _blocked(n):
					continue
				visited[n] = true
				comp.append(n)
			if comp.size() > 40:
				closed = false
				break
		if closed:
			for c in comp:
				_pockets[c] = true


func _add_dark(c: Vector2i, origin := false) -> void:
	if not origin:
		var ok := false
		for d in DIRS_I:
			if _dark.has(c + d):
				ok = true
				break
		if not ok:
			contiguity_violations += 1
			push_error("Manager_Darkness: komşusuz blok engellendi %s" % str(c))
			_shell.erase(c)
			return
	_dark[c] = true
	_shell.erase(c)
	for d in DIRS_I:
		var n: Vector2i = c + d
		if not _dark.has(n) and not _blocked(n):
			_shell[n] = true
	var new_block = block_scene.instantiate()
	new_block.global_position = _pos(c)
	if get_parent().is_node_ready():
		add_sibling(new_block)
	else:
		add_sibling.call_deferred(new_block) # _ready sırasında ebeveyn meşgul
	_block_count += 1


# --- harita -------------------------------------------------------------------------------

func _cell(pos: Vector2) -> Vector2i:
	return tile_map.local_to_map(tile_map.to_local(pos))


func _pos(c: Vector2i) -> Vector2:
	return tile_map.to_global(tile_map.map_to_local(c))


# Karanlık bu hücreye giremez: duvar, ışık ya da bölüm sınırı dışı
func _blocked(c: Vector2i) -> bool:
	if _cell_bounds.has_area() and not _cell_bounds.has_point(c):
		return true
	return _is_wall(c) or _heal_zone_of(c) != null


func _is_wall(map_pos: Vector2i) -> bool:
	if _wall_cache.has(map_pos):
		return _wall_cache[map_pos]
	# Sadece çarpışmalı karolar duvardır (çarpışmasız süs karoları karanlığı durdurmaz)
	var td := tile_map.get_cell_tile_data(0, map_pos)
	var wall := td != null and tile_map.tile_set.get_physics_layers_count() > 0 and td.get_collision_polygons_count(0) > 0
	_wall_cache[map_pos] = wall
	return wall


func _heal_zone_of(c: Vector2i) -> Node:
	if _heal_cache.has(c):
		return _heal_cache[c]
	var z := _heal_zone_at(_pos(c))
	_heal_cache[c] = z
	return z


func _nearest_open(from: Vector2i) -> Vector2i:
	for r in range(1, 8):
		var best := from
		var bd := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := from + Vector2i(dx, dy)
				if not _blocked(c):
					var d := Vector2(dx, dy).length()
					if d < bd:
						bd = d
						best = c
		if bd < INF:
			return best
	return from


# Oyuncudan başlayan yol mesafesi haritası (BFS; duvar ve ışık geçilmez, karanlık geçilir).
# Sadece oyuncunun hücresi değişince yeniden hesaplanır.
func _update_flow() -> void:
	var pc := _cell(player.global_position + Vector2(0, -32))
	var zone := _heal_zone_of(pc)
	var key := Vector3i(pc.x, pc.y, 1 if zone != null else 0)
	if key == _flow_key:
		return
	_flow_key = key
	_player_in_light = zone != null
	_player_progress = INF_D
	if not _exit_dist.is_empty():
		var best: int = _exit_dist.get(pc, INF_D)
		if best >= INF_D:
			for d in DIRS_I:
				best = mini(best, int(_exit_dist.get(pc + d, INF_D)))
		_player_progress = best
	_flow = {}
	var queue: Array[Vector2i] = []
	if zone != null:
		# Işığın çıkış tarafındaki kenarından başla
		for c in _zone_cells(zone, pc):
			var n: Vector2i = c + heal_exit_dir
			if not _blocked(n) and not _flow.has(n):
				_flow[n] = 0
				queue.append(n)
		if queue.is_empty():
			for c in _zone_cells(zone, pc):
				for d in DIRS_I:
					var n: Vector2i = c + d
					if not _blocked(n) and not _flow.has(n):
						_flow[n] = 0
						queue.append(n)
	elif _blocked(pc):
		for d in DIRS_I:
			if not _blocked(pc + d):
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
		for d in DIRS_I:
			var n: Vector2i = c + d
			if _flow.has(n) or _blocked(n):
				continue
			_flow[n] = nd
			queue.append(n)


# Bölüm çıkışından yol mesafesi (duvarlar geçilmez, ışıklar geçilir). Bir kez hesaplanır.
func _build_exit_field() -> void:
	var target := progress_target
	if target == null and owner != null:
		target = owner.find_child("LevelExit", true, false) as Node2D
	if target == null:
		return
	var start := _cell(target.global_position)
	if _is_wall(start):
		start = _nearest_open(start)
	var queue: Array[Vector2i] = [start]
	_exit_dist[start] = 0
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var nd: int = _exit_dist[c] + 1
		for d in DIRS_I:
			var n: Vector2i = c + d
			if _exit_dist.has(n) or _is_wall(n):
				continue
			if _cell_bounds.has_area() and not _cell_bounds.has_point(n):
				continue
			_exit_dist[n] = nd
			queue.append(n)


# Bir ışığın kapladığı hücreler (pc'nin çevresinde)
func _zone_cells(zone: Node, pc: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-6, 7):
		for dy in range(-6, 7):
			var c := pc + Vector2i(dx, dy)
			if _heal_zone_of(c) == zone:
				out.append(c)
	return out


# Hücreye özgü sabit pürüz (0..edge_jitter)
func _jitter(c: Vector2i) -> float:
	var h := (c.x * 73856093) ^ (c.y * 19349663)
	return float(posmod(h, 1000)) / 1000.0 * edge_jitter


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
