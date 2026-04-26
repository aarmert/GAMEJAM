class_name CheckpointData

static var spawn_position: Vector2 = Vector2.ZERO
static var has_spawn: bool = false

static var darkness_origin_pos: Vector2 = Vector2.ZERO
static var has_darkness_origin: bool = false


static func save_checkpoint(player_pos: Vector2, origin: Node2D) -> void:
	spawn_position = player_pos
	has_spawn = true
	if origin != null:
		darkness_origin_pos = origin.global_position
		has_darkness_origin = true


static func clear() -> void:
	has_spawn = false
	has_darkness_origin = false
