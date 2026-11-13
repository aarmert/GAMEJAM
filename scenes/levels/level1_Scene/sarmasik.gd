extends Area2D
# Sarmaşık: içindeyken oyuncu duvardan zıplayabilir (player.sarmasikta_mi).
# Görsel: duvar yüzeyine yapışık, dikey döşenen sarmaşık sprite'ı. Hangi duvarda
# olduğunu TileMap'ten kendisi bulur (wall_side = 0) ya da elle seçilir (-1 sol, 1 sağ).

@export_range(-1, 1) var wall_side: int = 0

const VINE_WIDTH := 16.0
const VINE_TILE_H := 48.0

@onready var _shape_node: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Vine


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_place_vine()


func _on_body_entered(body: Node2D) -> void:
	if not "sarmasikta_mi" in body:
		return
	# Üst üste binen sarmaşıklardan birinden çıkınca diğerinin içindeyken bayrak
	# düşmesin diye kaç sarmaşığın içinde olduğunu sayıyoruz.
	body.set_meta("sarmasik_sayisi", int(body.get_meta("sarmasik_sayisi", 0)) + 1)
	body.sarmasikta_mi = true


func _on_body_exited(body: Node2D) -> void:
	if not "sarmasikta_mi" in body or not is_instance_valid(body):
		return
	var count: int = max(int(body.get_meta("sarmasik_sayisi", 1)) - 1, 0)
	body.set_meta("sarmasik_sayisi", count)
	body.sarmasikta_mi = count > 0


func _place_vine() -> void:
	var rect := _shape_node.shape as RectangleShape2D
	if rect == null or _sprite == null:
		return
	var half := rect.size * 0.5
	var top := _shape_node.position.y - half.y
	var x := 0.0
	var side := wall_side
	var face := 0.0
	var tm := _find_tilemap()
	if tm != null:
		var found := _find_wall_face(tm, side)
		side = int(found.x)
		face = found.y
	if side != 0:
		# Sprite duvar yüzeyine 3 px gömülü dursun
		x = face - global_position.x + (VINE_WIDTH * 0.5 - 3.0) * (-side)
	_sprite.position = Vector2(x, top + rect.size.y * 0.5)
	_sprite.flip_h = side > 0
	# Dünya koordinatına hizalı döşeme: üst üste binen sarmaşıklar kesintisiz görünür
	var v := fposmod(global_position.y + top, VINE_TILE_H)
	_sprite.region_rect = Rect2(0.0, v, VINE_WIDTH, rect.size.y)


func _find_tilemap() -> TileMap:
	var scene := get_tree().current_scene if get_tree() else null
	var tm: Node = owner.get_node_or_null("TileMap") if owner else null
	if tm == null and scene != null:
		tm = scene.get_node_or_null("TileMap")
	return tm as TileMap


# x: duvar tarafı (-1 sol / 1 sağ / 0 yok), y: duvar yüzeyinin global x'i
func _find_wall_face(tm: TileMap, preferred: int) -> Vector2:
	var y := global_position.y + _shape_node.position.y
	var sides := [preferred] if preferred != 0 else [-1, 1]
	for s in sides:
		for d in range(4, 48, 2):
			var p := Vector2(global_position.x + s * d, y)
			var cell := tm.local_to_map(tm.to_local(p))
			if tm.get_cell_source_id(0, cell) != -1:
				var center := tm.to_global(tm.map_to_local(cell))
				var half_cell := tm.tile_set.tile_size.x * 0.5
				return Vector2(s, center.x - s * half_cell)
	return Vector2(preferred, global_position.x)
