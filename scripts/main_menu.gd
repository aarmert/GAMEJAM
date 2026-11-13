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


# Oyun açilis hikayesiyle (cutscene1) dogrudan ilk gerçek bölüme (orman, level2) baslar.
# Eski 3_part.tscn ara sahnesi akistan çikarildi; cutscene2 artik level2 çikisinda,
# level1'deki kovalamacanin hemen öncesinde gösteriliyor.
const FIRST_LEVEL := "res://scenes/levels/level2.tscn"
const OPENING_STORY_IMAGES := ["res://assets/cutscene1.png"]


func _on_start_pressed() -> void:
	_ui_sound("ui_start")
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("transition_to"):
		st.transition_to(FIRST_LEVEL, PackedStringArray(), PackedStringArray(OPENING_STORY_IMAGES))
	else:
		get_tree().change_scene_to_file(FIRST_LEVEL)


func _on_exit_pressed() -> void:
	_ui_sound("ui_click")
	await get_tree().create_timer(0.08).timeout
	get_tree().quit() # Replace with function body.x
