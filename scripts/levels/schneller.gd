extends Area2D
@export var manager_darkness: Node2D
 

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or manager_darkness == null:
		return
	manager_darkness.speed = 0.12
