extends Node2D

@export var block_scene: PackedScene
@export var player: Node2D
@export var tile_map: TileMap
# Selin hızı: kaç saniyede bir yeni blok dalgası eklenir (küçük = hızlı).
# Değiştiği anda müzik de o hıza uygun bölüme geçer.
@export var speed: float = 0.12:
	set(value):
		speed = value
		if is_node_ready():
			muzik_degistir()
@export var spawn_count: int = 5 # Tek seferde eklenecek blok sayısı
# Bölüm başında / checkpoint'te yeniden doğunca karanlık bu kadar saniye bekler
# (sahne geçiş fade'i sürerken geçen süre sayılmaz).
@export var start_delay: float = 4.0
# Güvenlik sınırı: blok sayısı bunu aşarsa yayılma durur.
@export var max_blocks: int = 3000


const TILE_SIZE = 32
# Blok merkezinin heal zone kenarından en az bu kadar uzak olması gerekir (blok yarı boyu ~10 px)
const HEAL_MARGIN = 12.0

var time_passed: float = 0.0
var _delay_left: float = 0.0
var _block_count: int = 0
var _bounds := Rect2()
var frontier_blocks = []
var occupied_blocks = {}

# Sadece 4 ana yöne yayıl (Çaprazları es geç ki boşluk kalmasın)
var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

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
	if CheckpointData.has_darkness_origin:
		global_position = CheckpointData.darkness_origin_pos
	_delay_left = start_delay

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
	if _delay_left > 0.0:
		if not _is_transitioning():
			_delay_left -= delta
		return

	time_passed += delta 

	if time_passed >= speed:
		time_passed = 0.0 
		
		for i in range(spawn_count):
			# Döngü içindeyken liste tamamen boşalırsa hata vermemesi için güvenlik kontrolü
			if frontier_blocks.is_empty():
				break

			# Sınır hattından rastgele bir blok seç
			var base_pos = frontier_blocks.pick_random()
			var current_distance = base_pos.distance_to(player.global_position)

			# Ölü Bölge: Oyuncuya çok yakınsa ezmesin
			if current_distance < 15.0:
				continue 

			var valid_targets = []
			
			# Bloğun etrafındaki 4 yöne bak
			for dir in directions:
				var target_pos = base_pos + (dir * TILE_SIZE)
				
				# 1. KONTROL: Kendi bloklarımızla zaten dolu mu?
				if occupied_blocks.has(target_pos):
					continue

				# Bölüm sınırları dışı: boşluğa sonsuza dek yayılmasın
				if _bounds.has_area() and not _bounds.has_point(target_pos):
					occupied_blocks[target_pos] = true
					continue
					
				# 2. KONTROL: TileMap üzerinde burada bir duvar var mı?
				if tile_map:
					# Hedef pikseli TileMap gridine çevir
					var map_pos = tile_map.local_to_map(tile_map.to_local(target_pos))
					# 0. katmanda (layer) duvar var mı bak (-1 boş demektir)
					if tile_map.get_cell_source_id(0, map_pos) != -1:
						# Duvar var! Burayı da dolu işaretle ve atla
						occupied_blocks[target_pos] = true
						continue

				# 3. KONTROL: Heal zone içinde mi?
				if _is_in_heal_zone(target_pos):
					occupied_blocks[target_pos] = true
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
				frontier_blocks.erase(base_pos)
				continue 

			# Havuzdan rastgele bir hedef seç
			var chosen_pos = valid_targets.pick_random()
			
			# Yeni bloğu yarat ve ekle
			var new_block = block_scene.instantiate()
			new_block.global_position = chosen_pos
			add_sibling(new_block)
			_block_count += 1
			
			# Yeni noktayı listelere kaydet
			frontier_blocks.append(chosen_pos)
			occupied_blocks[chosen_pos] = true


func _is_transitioning() -> bool:
	var st := get_node_or_null("/root/SceneTransition")
	return st != null and st.has_method("is_transitioning") and st.is_transitioning()


func _is_in_heal_zone(pos: Vector2) -> bool:
	# Heal zone (checkpoint) içine karanlık girmez: içinde duran oyuncu güvende.
	# Dikdörtgen alanda tam şeklini, daire alanda yarıçapı kullan.
	for zone in get_tree().get_nodes_in_group("heal_zone"):
		for child in zone.get_children():
			if not child is CollisionShape2D or child.shape == null:
				continue
			var local: Vector2 = (child as CollisionShape2D).global_transform.affine_inverse() * pos
			if child.shape is RectangleShape2D:
				var half: Vector2 = child.shape.size * 0.5 + Vector2(HEAL_MARGIN, HEAL_MARGIN)
				if abs(local.x) <= half.x and abs(local.y) <= half.y:
					return true
			elif child.shape is CircleShape2D:
				if local.length() <= child.shape.radius + HEAL_MARGIN:
					return true
	return false
