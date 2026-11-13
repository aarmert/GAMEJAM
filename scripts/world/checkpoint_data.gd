class_name CheckpointData

static var spawn_position: Vector2 = Vector2.ZERO
static var has_spawn: bool = false

static var darkness_origin_pos: Vector2 = Vector2.ZERO
static var has_darkness_origin: bool = false

# DarknessCheckpoint'ten geçilince karanlığın yeni başlangıcı burada "bekler"; oyuncu
# bir sonraki checkpoint'e (heal zone) ulaşınca kesinleşir. Böylece DarknessCheckpoint'i
# geçip heal zone'a varmadan ölen oyuncu eski checkpoint'te doğarken karanlık önünde,
# ileride başlamaz.
static var pending_darkness_pos: Vector2 = Vector2.ZERO
static var has_pending_darkness: bool = false


static func save_player_checkpoint(player_pos: Vector2) -> void:
	spawn_position = player_pos
	has_spawn = true
	if has_pending_darkness:
		darkness_origin_pos = pending_darkness_pos
		has_darkness_origin = true
		has_pending_darkness = false


# Hemen geçerli olan karanlık başlangıcı (heal zone'un kendi darkness_origin'i vb.)
static func save_darkness_checkpoint(origin: Node2D) -> void:
	if origin != null:
		darkness_origin_pos = origin.global_position
		has_darkness_origin = true
		has_pending_darkness = false


# Oyuncu checkpoint'i kaydedilince geçerli olacak karanlık başlangıcı
static func set_pending_darkness_origin(pos: Vector2) -> void:
	pending_darkness_pos = pos
	has_pending_darkness = true


static func save_checkpoint(player_pos: Vector2, origin: Node2D) -> void:
	save_player_checkpoint(player_pos)
	save_darkness_checkpoint(origin)


static func clear() -> void:
	has_spawn = false
	has_darkness_origin = false
	has_pending_darkness = false
