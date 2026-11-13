extends Area2D

@export var checkpoint_index: int = 0
@export var darkness_origin: Node2D = null
@export var save_player_checkpoint: bool = true
@export var save_darkness_checkpoint: bool = false
@export var sync_darkness_with_player_checkpoint: bool = true
# darkness_origin atanmamışsa ve "DarknessOrigin" adlı çocuk yoksa karanlık ışığın bu kadar
# gerisinde yeniden doğar.
@export var default_darkness_offset: Vector2 = Vector2(-160, 0)
# true: oyuncu ışığın ortasında, zeminde doğar (girdiği kenarda değil). Mağara bölümünün
# heal_zone.tscn'inde açık; diğer bölümlerin doğuşu değişmesin diye varsayılan kapalı.
@export var spawn_at_zone_center: bool = false

var player_in_area: Node2D = null
var notified: bool = false

@onready var heal_timer: Timer = $HealTimer


func _on_body_entered(body: Node2D) -> void:
	# Aynı body zaten içerdeyse tekrar artırma
	if player_in_area == body:
		return

	if not body.has_method("heal"):
		return

	player_in_area = body

	if save_player_checkpoint and sync_darkness_with_player_checkpoint:
		# Doğuş noktası ve karanlık başlangıcı birlikte kesinleşir: canavar hep bu ışığın gerisinde doğar
		CheckpointData.commit_checkpoint(_spawn_point(body), _darkness_origin_pos(), get_tree())
	elif save_player_checkpoint:
		CheckpointData.save_player_checkpoint(_spawn_point(body))
	elif save_darkness_checkpoint:
		CheckpointData.save_darkness_origin(_darkness_origin_pos(), get_tree())

	if "safe_zones" in body:
		body.safe_zones += 1
	_play_sound("heal" if notified else "checkpoint")
	body.heal(20)
	heal_timer.start()

	if not notified:
		notified = true
		var manager = get_tree().current_scene
		if manager and manager.has_method("checkpoint_reached"):
			manager.checkpoint_reached(checkpoint_index)


func _on_body_exited(body: Node2D) -> void:
	if body == player_in_area:
		if "safe_zones" in body:
			body.safe_zones = max(body.safe_zones - 1, 0)
		player_in_area = null
		heal_timer.stop()


func _on_heal_timer_timeout() -> void:
	if player_in_area and player_in_area.has_method("heal"):
		if _needs_heal(player_in_area):
			_play_sound("heal")
		player_in_area.heal(20)


func _needs_heal(body: Node) -> bool:
	var bar = body.get("health_bar")
	return bar == null or not ("health" in bar) or bar.health < bar.max_value


func _play_sound(sfx_name: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(sfx_name, 0.03)


func _darkness_origin_pos() -> Vector2:
	var origin: Node2D = darkness_origin
	if origin == null:
		origin = get_node_or_null("DarknessOrigin") as Node2D
	if origin != null:
		return origin.global_position
	if CheckpointData.has_pending_darkness:
		return CheckpointData.pending_darkness_pos
	return global_position + default_darkness_offset


# Oyuncu ışığın ortasında, zeminin üstünde doğar. Girildiği noktayı (alanın kenarı) kaydetmek
# oyuncuyu ışığın sınırına koyuyordu; karanlık oradan oyuncuya değip yeniden doğar doğmaz öldürebiliyordu.
func _spawn_point(body: Node2D) -> Vector2:
	var fallback := body.global_position
	if not spawn_at_zone_center:
		return fallback
	var shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return fallback
	var half_h: float = (shape_node.shape as RectangleShape2D).size.y * 0.5 * absf(shape_node.global_scale.y)
	var feet_offset := body.global_position.y - (shape_node.global_position.y + half_h)
	var center := global_position
	for child in get_children():
		if child is CollisionShape2D:
			center = (child as CollisionShape2D).global_position
			break
	var q := PhysicsRayQueryParameters2D.create(center, center + Vector2(0, 256), 1)
	if body is CollisionObject2D:
		q.exclude = [(body as CollisionObject2D).get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return Vector2(center.x, hit.position.y + feet_offset - 1.0)
