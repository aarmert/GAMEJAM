extends Area2D


var player_in_area: Node2D = null
@onready var heal_timer: Timer = $HealTimer


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("heal"):
		player_in_area = body
		body.heal(20)
		heal_timer.start()
		print("+20 Health")
		



	


func _on_body_exited(body: Node2D) -> void:
	if body == player_in_area:
		player_in_area = null
		heal_timer.stop()
	



func _on_heal_timer_timeout() -> void:
	if player_in_area:
		player_in_area.heal(20)
		print("+20 Health")
