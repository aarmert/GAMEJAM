extends Node2D


func _ready() -> void:
	# UI sesleri: üzerine gelince kısa "blip"
	for path in ["Control/CanvasLayer/start", "Control/CanvasLayer/exit"]:
		var b := get_node_or_null(path) as BaseButton
		if b != null:
			b.mouse_entered.connect(_ui_sound.bind("ui_hover"))
			b.focus_entered.connect(_ui_sound.bind("ui_hover"))


func _ui_sound(sfx_name: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(sfx_name, 0.0)


func _on_start_pressed() -> void:
	_ui_sound("ui_start")
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("transition_to"):
		st.transition_to(
			"res://scenes/levels/3_part.tscn",
			PackedStringArray(),
			PackedStringArray(["res://assets/cutscene1.png"])
		)
	else:
		get_tree().change_scene_to_file("res://scenes/levels/3_part.tscn")

func _on_exit_pressed() -> void:
	_ui_sound("ui_click")
	await get_tree().create_timer(0.08).timeout
	get_tree().quit() # Replace with function body.x
