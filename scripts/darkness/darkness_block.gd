extends Area2D

@onready var timer: Timer = $Timer


func _on_darkness_block_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("take_damage"):
		timer.start()


func _on_timer_timeout() -> void:
	get_tree().reload_current_scene()
