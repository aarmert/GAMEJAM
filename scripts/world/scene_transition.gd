extends Node

# Sahneler arasi fade-to-black geçislerini ve hikaye yazilarini yöneten singleton.
# Project Settings → AutoLoad'a "SceneTransition" adiyla eklenmis olmali.
#
# Kullanim:
#   SceneTransition.transition_to("res://scenes/levels/level2.tscn")
#   SceneTransition.transition_to("res://scenes/levels/level2.tscn", ["Maya karanliga adim atti...", "Geri dönüs yoktu."])

@export var fade_duration: float = 0.6
@export var story_line_duration: float = 3.0  # Her hikaye satiri kaç saniye ekranda kalsin

signal transition_started
signal transition_finished

var _is_transitioning: bool = false
var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect
var _story_label: Label


func _ready() -> void:
	# Pause olsa bile çalissin, oyun durdurulmus olsa da fade devam eder
	process_mode = Node.PROCESS_MODE_ALWAYS

	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100  # Her seyin üstünde
	add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_fade_rect)

	_story_label = Label.new()
	_story_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_story_label.offset_left = 80
	_story_label.offset_right = -80
	_story_label.offset_top = 80
	_story_label.offset_bottom = -80
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.add_theme_font_size_override("font_size", 28)
	_story_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_story_label.modulate = Color(1, 1, 1, 0)
	_story_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_story_label)


# Ana giris noktasi. story_lines bos olabilir.
func transition_to(scene_path: String, story_lines: PackedStringArray = PackedStringArray()) -> void:
	if _is_transitioning:
		return
	if scene_path.is_empty():
		push_warning("[SceneTransition] Bos scene_path verildi")
		return
	_is_transitioning = true
	transition_started.emit()
	_run_transition(scene_path, story_lines)


func is_transitioning() -> bool:
	return _is_transitioning


func _run_transition(scene_path: String, story_lines: PackedStringArray) -> void:
	# 1) Siyaha fade
	await _fade_to(1.0, fade_duration)

	# 2) Hikaye yazilari (varsa)
	if story_lines.size() > 0:
		await _show_story_lines(story_lines)

	# 3) Sahneyi degistir
	# Slow-motion'i sifirla (ölüm sirasinda kalmis olabilir)
	Engine.time_scale = 1.0
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[SceneTransition] Sahne yüklenemedi: %s (hata: %d)" % [scene_path, err])

	# Yeni sahnenin _ready'si bitsin diye bir frame bekle
	await get_tree().process_frame

	# 4) Geri fade
	await _fade_to(0.0, fade_duration)
	_is_transitioning = false
	transition_finished.emit()


func _fade_to(target_alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(_fade_rect, "color:a", target_alpha, duration)
	await tween.finished


# STUB: Hikaye yazi sistemi. Su an her satir sirayla ekranda kaliyor.
# GELISTIRME IPUCU: typewriter efekti, "devam et" tusu, ses, arkaplana gradient ekleme,
# sahne özel görseller — burada eklenecek. Level'lardan dokunmana gerek yok.
func _show_story_lines(lines: PackedStringArray) -> void:
	for line in lines:
		_story_label.text = line

		# Yaziyi belirginlestir
		var tw_in := create_tween()
		tw_in.set_ignore_time_scale(true)
		tw_in.tween_property(_story_label, "modulate:a", 1.0, 0.4)
		await tw_in.finished

		# Ekranda dur
		await get_tree().create_timer(story_line_duration, true, false, true).timeout

		# Solduruyor
		var tw_out := create_tween()
		tw_out.set_ignore_time_scale(true)
		tw_out.tween_property(_story_label, "modulate:a", 0.0, 0.4)
		await tw_out.finished

	_story_label.text = ""
