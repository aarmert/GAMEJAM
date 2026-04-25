extends Area2D

var player_in_area: Node2D = null

@onready var damage_timer: Timer = $damage_timer

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		player_in_area = body
		body.take_damage(20)
		damage_timer.start()
		print("-20 Health")


func _on_damage_timer_timeout() -> void:
	if player_in_area:
		player_in_area.take_damage(20)
		print("-20 Health")


func _on_body_exited(body: Node2D) -> void:
	if body == player_in_area:
		player_in_area = null
		damage_timer.stop()
