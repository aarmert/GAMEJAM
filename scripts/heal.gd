extends Area2D


var player_in_area: Node2D = null
@onready var heal_timer: Timer = $HealTimer


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("heal"):
		body.heal(20)
	print("Entered heal zone" + " +20 Health")# Replace with function body.
