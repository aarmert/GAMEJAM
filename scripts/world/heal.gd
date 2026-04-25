extends Area2D

@export var checkpoint_index: int = 0


var player_in_area: Node2D = null
var notified: bool = false

@onready var heal_timer: Timer = $HealTimer

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("heal"):
		player_in_area = body
		if "safe_zones" in body:
			body.safe_zones += 1
		body.heal(20)
		heal_timer.start()
		print("girilen area index: ", checkpoint_index)

		if not notified:
			notified = true
			var manager = get_tree().current_scene
			if manager.has_method("checkpoint_reached"):
				manager.checkpoint_reached(checkpoint_index)


func _on_body_exited(body: Node2D) -> void:
	if body == player_in_area:
		if "safe_zones" in body:
			body.safe_zones -= 1
		player_in_area = null
		heal_timer.stop()

func _on_heal_timer_timeout() -> void:
	if player_in_area:
		player_in_area.heal(20)
		
