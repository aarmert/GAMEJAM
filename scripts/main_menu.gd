extends Node2D

# Ana menü: Start (hikaye, level2 + açılış hikayesi), Level Select (3 hikaye bölümü + 3 Trials bölümü), Exit.
# Not: Test botu "Start" ile başlayan butonu metninden bulur; Start'ın metni "Start" ile başlamalı ve
# hikayeyi level2'den açılış hikayesiyle başlatmalı.

const TrialsParser := preload("res://trials/scripts/chapter_parser.gd")
const TrialsSave := preload("res://trials/scripts/trials_save.gd")

# Oyun açilis hikayesiyle (cutscene1) dogrudan ilk gerçek bölüme (orman, level2) baslar.
# Eski 3_part.tscn ara sahnesi akistan çikarildi; cutscene2 artik level2 çikisinda,
# level1'deki kovalamacanin hemen öncesinde gösteriliyor.
const FIRST_LEVEL := "res://scenes/levels/level2.tscn"
const OPENING_STORY_IMAGES := ["res://assets/cutscene1.png"]

# Bölüm seçimi. Hikaye bölümleri, hikaye modunda o bölüme gelirken gösterilen hikayeyle açılır
# (level2 çıkışı -> level1: cutscene2; level1 çıkışı -> level1_2: hikaye yok).
const STORY_LEVELS := [
	{"label": "Story 1  -  Forest", "scene": "res://scenes/levels/level2.tscn", "images": ["res://assets/cutscene1.png"]},
	{"label": "Story 2  -  Cave Chase", "scene": "res://scenes/levels/level1.tscn", "images": ["res://assets/cutscene2.png"]},
	{"label": "Story 3  -  Lantern Cave", "scene": "res://scenes/levels/level1_2.tscn", "images": []},
]
# Trials bolumleri henuz demo; hazir olunca true yap.
const SHOW_TRIALS := false
const TRIALS := [
	{"numeral": "I", "id": "chapter1", "scene": "res://trials/scenes/trials_chapter1.tscn", "file": "res://trials/chapters/chapter1.gd"},
	{"numeral": "II", "id": "chapter2", "scene": "res://trials/scenes/trials_chapter2.tscn", "file": "res://trials/chapters/chapter2.gd"},
	{"numeral": "III", "id": "chapter3", "scene": "res://trials/scenes/trials_chapter3.tscn", "file": "res://trials/chapters/chapter3.gd"},
]

var _main_buttons: Array[Control] = []
var _select: Control
var _select_first: Button
var _levels_button: Button
var _starting := false


func _ready() -> void:
	var start := get_node_or_null("Control/CanvasLayer/start") as Button
	var levels := get_node_or_null("Control/CanvasLayer/levels") as Button
	var exit := get_node_or_null("Control/CanvasLayer/exit") as Button
	_levels_button = levels
	for b in [start, levels, exit]:
		if b != null:
			_main_buttons.append(b)
			# UI sesleri: üzerine gelince kısa "blip"
			b.mouse_entered.connect(_ui_sound.bind("ui_hover"))
			b.focus_entered.connect(_ui_sound.bind("ui_hover"))
	if levels != null:
		levels.pressed.connect(_open_select)
	_build_select()
	if start != null:
		start.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _select != null and _select.visible and event.is_action_pressed("ui_cancel"):
		_close_select()
		get_viewport().set_input_as_handled()


func _ui_sound(sfx_name: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx(sfx_name, 0.0)


func _on_start_pressed() -> void:
	_ui_sound("ui_start")
	_go(FIRST_LEVEL, OPENING_STORY_IMAGES)


func _on_exit_pressed() -> void:
	_ui_sound("ui_click")
	await get_tree().create_timer(0.08).timeout
	get_tree().quit()


func _go(scene: String, images: Array = []) -> void:
	if _starting:
		return
	_starting = true
	# Bölüme doğrudan girmek, hikaye modunda oraya varmakla aynı olmalı: checkpoint'ler temiz
	CheckpointData.clear()
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("transition_to"):
		st.transition_to(scene, PackedStringArray(), PackedStringArray(images))
	else:
		get_tree().change_scene_to_file(scene)


# ------------------------------------------------------------------ bölüm seçimi

func _build_select() -> void:
	var layer := get_node("Control/CanvasLayer")
	_select = ColorRect.new()
	(_select as ColorRect).color = Color(0.02, 0.01, 0.05, 0.55)
	_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_select.visible = false
	layer.add_child(_select)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 150
	_select.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, 0.9)
	sb.border_color = Color(0.55, 0.45, 0.85, 1)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(_header("STORY"))
	for s in STORY_LEVELS:
		var b := _row(v, s.label, "")
		b.pressed.connect(_on_story_pressed.bind(s))
		if _select_first == null:
			_select_first = b
	if SHOW_TRIALS:
		v.add_child(_header("TRIALS"))
	for t in (TRIALS if SHOW_TRIALS else []):
		var title := ""
		if ResourceLoader.exists(t.file):
			title = TrialsParser.parse_file(t.file).title
		var best := TrialsSave.get_best(t.id)
		var info := "not cleared yet"
		if best.get("cleared", false):
			info = "best %s  |  %d deaths  |  %d/%d" % [TrialsSave.format_time(best.get("best_time", INF)), best.get("best_deaths", 0), best.get("best_collectibles", 0), best.get("collectibles_total", 0)]
		var b2 := _row(v, "Trials %s  -  %s" % [t.numeral, title if not title.is_empty() else "Chapter %s" % t.numeral], info)
		b2.pressed.connect(_on_trials_pressed.bind(t))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer)
	var back := _row(v, "Back", "")
	back.pressed.connect(_close_select)


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.75, 0.68, 1.0))
	return l


func _row(parent: Control, text: String, info: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(900, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_entered.connect(_ui_sound.bind("ui_hover"))
	b.mouse_entered.connect(_ui_sound.bind("ui_hover"))
	if not info.is_empty():
		var l := Label.new()
		l.text = info
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0, 0.85))
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		l.offset_left = -330
		l.offset_right = -16
		l.offset_top = -10
		l.offset_bottom = 10
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	parent.add_child(b)
	return b


func _open_select() -> void:
	_ui_sound("ui_click")
	for b in _main_buttons:
		b.visible = false
	_select.visible = true
	_select_first.grab_focus()


func _close_select() -> void:
	_ui_sound("ui_click")
	_select.visible = false
	for b in _main_buttons:
		b.visible = true
	if _levels_button != null:
		_levels_button.grab_focus()


func _on_story_pressed(s: Dictionary) -> void:
	_ui_sound("ui_start")
	_go(s.scene, s.images)


func _on_trials_pressed(t: Dictionary) -> void:
	_ui_sound("ui_start")
	_go(t.scene)
