extends CanvasLayer
# Trials HUD: ölüm sayacı, süre, toplanabilir n/toplam, oda numarası; Esc duraklat menüsü
# (Resume / Retry Room / Back to Menu); bölüm sonu ekranı. Tema: ui/game_theme.tres (proje teması).

const Save := preload("res://trials/scripts/trials_save.gd")
const COIN := preload("res://assets/red_coin.png")

var game: Node = null

var _deaths: Label
var _time: Label
var _coins: Label
var _room: Label
var _pause: Control
var _pause_first: Button
var _complete: Control
var _complete_first: Button
var _errors: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var tl := _panel(root, Vector2(16, 14), Vector2(250, 66))
	_deaths = _label(tl, Vector2(14, 8), 16)
	_time = _label(tl, Vector2(14, 36), 16)
	var tr := _panel(root, Vector2(1152 - 16 - 150, 14), Vector2(150, 40))
	var icon := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = COIN
	at.region = Rect2(0, 0, 16, 16)
	icon.texture = at
	icon.position = Vector2(14, 8)
	icon.size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	tr.add_child(icon)
	_coins = _label(tr, Vector2(48, 9), 16)
	_room = _label(root, Vector2(18, 648 - 34), 12)
	_room.modulate = Color(1, 1, 1, 0.7)

	_pause = _overlay(root)
	var pv := _menu_box(_pause, "PAUSED")
	_pause_first = _button(pv, "Resume", _on_resume)
	_button(pv, "Retry Room", _on_retry)
	_button(pv, "Back to Menu", _on_menu)
	_pause.hide()

	_complete = _overlay(root)
	_complete.hide()


func _process(_delta: float) -> void:
	if game == null:
		return
	_deaths.text = "DEATHS  %d" % game.deaths
	_time.text = "TIME    %s" % Save.format_time(game.time)
	_coins.text = "%d/%d" % [game.banked.size() + game.pending.size(), game.chapter.get("collectible_total", 0)]
	_room.text = "ROOM %s" % game.room_label()


func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	var pause_pressed := event.is_action_pressed("ui_cancel")
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		pause_pressed = true
	if not pause_pressed:
		return
	if _complete.visible or (_errors != null and _errors.visible):
		return
	if _pause.visible:
		_on_resume()
	elif not game.transitioning and not game.complete:
		_open_pause()
	get_viewport().set_input_as_handled()


func _open_pause() -> void:
	get_tree().paused = true
	_pause.show()
	_pause_first.grab_focus()
	_ui("ui_click")


func _on_resume() -> void:
	_pause.hide()
	get_tree().paused = false
	_ui("ui_click")


func _on_retry() -> void:
	_pause.hide()
	get_tree().paused = false
	game.retry_room(true)
	_ui("ui_click")


func _on_menu() -> void:
	_pause.hide()
	_ui("ui_start")
	game.back_to_menu()


func show_complete(stats: Dictionary) -> void:
	await get_tree().create_timer(0.7).timeout
	var best: Dictionary = stats.get("best", {})
	var v := _menu_box(_complete, "CHAPTER COMPLETE")
	var sub := _label(v, Vector2.ZERO, 16)
	sub.text = stats.title
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.75, 1.0)
	v.add_child(_spacer(8))
	_stat_row(v, "Time", Save.format_time(stats.time), best.get("new_time", false) and not best.get("first_clear", false))
	_stat_row(v, "Deaths", str(stats.deaths), best.get("new_deaths", false) and not best.get("first_clear", false))
	_stat_row(v, "Embers", "%d/%d" % [stats.collectibles, stats.collectibles_total], best.get("new_collectibles", false))
	if not best.is_empty() and not best.get("first_clear", false):
		var b := _label(v, Vector2.ZERO, 12)
		b.text = "Best  %s  |  %d deaths  |  %d embers" % [Save.format_time(best.best_time), best.best_deaths, best.best_collectibles]
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.modulate = Color(1, 1, 1, 0.7)
	v.add_child(_spacer(8))
	_complete_first = _button(v, "Continue", _on_menu)
	_complete.modulate.a = 0.0
	_complete.show()
	var tw := create_tween()
	tw.tween_property(_complete, "modulate:a", 1.0, 0.3)
	_complete_first.grab_focus()


func show_errors(errors: PackedStringArray) -> void:
	var root := get_child(0) as Control
	_errors = _overlay(root)
	var v := _menu_box(_errors, "CHAPTER HAS ERRORS")
	var l := _label(v, Vector2.ZERO, 12)
	var shown := PackedStringArray()
	for i in mini(errors.size(), 8):
		shown.append(errors[i])
	l.text = "\n".join(shown) + ("\n..." if errors.size() > 8 else "")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(800, 0)
	_button(v, "Back to Menu", _on_menu).grab_focus()
	_errors.show()


# ------------------------------------------------------------------ küçük yapı yardımcıları

func _panel(parent: Control, pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, 0.62)
	sb.border_color = Color(0.55, 0.45, 0.85, 0.7)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _label(parent: Control, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _overlay(parent: Control) -> Control:
	var o := ColorRect.new()
	o.color = Color(0.02, 0.01, 0.05, 0.72)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(o)
	return o


func _menu_box(parent: Control, title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, 0.94)
	sb.border_color = Color(0.55, 0.45, 0.85, 1)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(420, 0)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	t.add_theme_constant_override("outline_size", 6)
	v.add_child(t)
	return v


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 52)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	b.focus_entered.connect(_ui.bind("ui_hover"))
	parent.add_child(b)
	return b


func _stat_row(parent: Control, name: String, value: String, is_new: bool) -> void:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = name
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_font_size_override("font_size", 20)
	var b := Label.new()
	b.text = value + ("  NEW BEST" if is_new else "")
	b.add_theme_font_size_override("font_size", 20)
	if is_new:
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	h.add_child(a)
	h.add_child(b)
	parent.add_child(h)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _ui(n: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(n, 0.0)
