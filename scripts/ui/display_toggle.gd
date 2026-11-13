extends Node

# Tam ekran açma/kapama: F11 veya Alt+Enter.
# Görüntü ölçekleme project.godot [display] ayarlarinda (1152x648 taban, canvas_items + keep):
# pencere/tam ekran boyutu ne olursa olsun oyuncu ayni alani görür, sadece büyütülür.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var is_f11 := key.keycode == KEY_F11
	var is_alt_enter := key.alt_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
	if is_f11 or is_alt_enter:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
