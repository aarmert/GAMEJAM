extends Area2D

@onready var timer = $Timer

# YENİ EKLENEN VE ÇALIŞACAK OLAN FONKSİYON
func _on_darkness_block_body_entered(_body) -> void:
	print("you died")
	timer.start()

func _on_timer_timeout() -> void:
	get_tree().reload_current_scene()
