class_name CheckpointData

# Ölünce yeniden yükleme sonrası kullanılan, bölüme özel checkpoint durumu.
# Heal zone (ışık) oyuncu doğuş noktasını VE karanlığın (canavarın) yeniden doğacağı
# noktayı birlikte kaydeder: karanlık her zaman ulaşılan son ışığın hemen gerisinde başlar.

static var spawn_position: Vector2 = Vector2.ZERO
static var has_spawn: bool = false

static var darkness_origin_pos: Vector2 = Vector2.ZERO
static var has_darkness_origin: bool = false

# Checkpoint kaydedildiği andaki karanlık hızı (Manager_Darkness.speed); -1 = kayıt yok.
# Manager_Darkness yeniden doğuşta bunu uygular.
static var darkness_speed: float = -1.0

# DarknessCheckpoint'ten geçilince karanlığın yeni başlangıcı burada "bekler"; oyuncu
# bir sonraki heal zone'a ulaşınca kesinleşir (heal zone'un kendi DarknessOrigin'i varsa o geçerlidir).
static var pending_darkness_pos: Vector2 = Vector2.ZERO
static var has_pending_darkness: bool = false


# Oyuncu checkpoint'i + karanlık başlangıcını birlikte kaydeder.
static func commit_checkpoint(player_pos: Vector2, origin_pos: Vector2, tree: SceneTree) -> void:
	spawn_position = player_pos
	has_spawn = true
	darkness_origin_pos = origin_pos
	has_darkness_origin = true
	has_pending_darkness = false
	_store_darkness_speed(tree)


static func save_darkness_origin(origin_pos: Vector2, tree: SceneTree) -> void:
	darkness_origin_pos = origin_pos
	has_darkness_origin = true
	has_pending_darkness = false
	_store_darkness_speed(tree)


static func save_player_checkpoint(player_pos: Vector2) -> void:
	spawn_position = player_pos
	has_spawn = true
	if has_pending_darkness:
		darkness_origin_pos = pending_darkness_pos
		has_darkness_origin = true
		has_pending_darkness = false


static func save_darkness_checkpoint(origin: Node2D) -> void:
	if origin != null:
		darkness_origin_pos = origin.global_position
		has_darkness_origin = true
		has_pending_darkness = false
		if origin.is_inside_tree():
			_store_darkness_speed(origin.get_tree())


static func set_pending_darkness_origin(pos: Vector2) -> void:
	pending_darkness_pos = pos
	has_pending_darkness = true


static func save_checkpoint(player_pos: Vector2, origin: Node2D) -> void:
	save_player_checkpoint(player_pos)
	save_darkness_checkpoint(origin)


static func _store_darkness_speed(tree: SceneTree) -> void:
	if tree == null:
		return
	var m = tree.get_first_node_in_group("darkness_manager")
	if m != null and "speed" in m:
		darkness_speed = m.speed


static func clear() -> void:
	has_spawn = false
	has_darkness_origin = false
	has_pending_darkness = false
	darkness_speed = -1.0
