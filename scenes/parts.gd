extends Node2D

@onready var darkness_timer: Timer = $DarknessTimer
@onready var flashlight: PointLight2D = $MayaChar2/FlashlightPivot/PointLight2D
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var is_dark = false

func _on_darkness_timer_timeout() -> void:
	is_dark = !is_dark
	if is_dark:
		canvas_modulate.color = Color.BLACK
		flashlight.enabled = true
		darkness_timer.wait_time = randf_range(3.0,6.0)
	else:
		canvas_modulate.color = Color.WHITE
		flashlight.enabled = false
		darkness_timer.wait_time = randf_range(8.0,15.0)
	darkness_timer.start()
	
