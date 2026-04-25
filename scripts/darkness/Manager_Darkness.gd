extends Node2D

@export var block_scene: PackedScene
@export var player: Node2D
@export var tile_map: TileMap
@export var speed: float = 0.18 # Selin hızı
@export var spawn_count: int = 5 # Tek seferde eklenecek blok sayısı


const TILE_SIZE = 32

var time_passed: float = 0.0
var frontier_blocks = []
var occupied_blocks = {}

# Sadece 4 ana yöne yayıl (Çaprazları es geç ki boşluk kalmasın)
var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

func _ready() -> void:
	# Başlangıç noktasını listelere ekle
	frontier_blocks.append(global_position)
	occupied_blocks[global_position] = true

func _process(delta: float) -> void:
	

	if not player or frontier_blocks.is_empty():
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
					
				# 2. KONTROL: TileMap üzerinde burada bir duvar var mı?
				if tile_map:
					# Hedef pikseli TileMap gridine çevir
					var map_pos = tile_map.local_to_map(tile_map.to_local(target_pos))
					# 0. katmanda (layer) duvar var mı bak (-1 boş demektir)
					if tile_map.get_cell_source_id(0, map_pos) != -1:
						# Duvar var! Burayı da dolu işaretle ve atla
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
			
			# Yeni noktayı listelere kaydet
			frontier_blocks.append(chosen_pos)
			occupied_blocks[chosen_pos] = true
