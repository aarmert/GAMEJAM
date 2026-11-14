extends Node

# Son bölümün (fener mağarası) akışı:
#  - Fenerin pili SINIRLI: açıkken drain_rate/sn harcar, kapalıyken charge_rate/sn ile çok yavaş
#    dolar; ışıklı lambaların (heal zone) yanında zone_charge_rate/sn hızla dolar. Pil kristalleri +pil verir.
#  - Fener otomatik yanmaz; ne zaman yakacağına oyuncu karar verir (Z / "flashlight" eylemi).
#  - Ekranda kısa ipuçları (show_hint) gösterir: tema fontu, üst orta.
#  - Ölünce sahne yeniden yüklenir; checkpoint'ten doğulursa fener zaten alınmış sayılır.
#  - Oyuncunun çevresine gölgesiz, hafif bir "aura" ışığı ekler: fener kapalıyken de karakter ve
#    bastığı zemin görünür.

@export var player_path: NodePath
@export var max_battery: float = 100.0
@export var drain_rate: float = 25.0
@export var charge_rate: float = 4.0
@export var zone_charge_rate: float = 70.0
@export var auto_turn_on: bool = false
@export var aura_energy: float = 0.55
@export var aura_scale: float = 3.4
@export var pickup_hint: String = "Z: Feneri yak / kapat\nFener gölgeleri durdurur."

const THEME := preload("res://ui/game_theme.tres")

var _player: Node = null
var _fc = null
var _lantern_ready := false
var _empty_hint_shown := false
var _hint_layer: CanvasLayer
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_tween: Tween


func _ready() -> void:
	add_to_group("lantern_flow")
	_player = get_node_or_null(player_path)
	if _player == null:
		for n in get_tree().get_nodes_in_group("player"):
			if n is CharacterBody2D:
				_player = n
				break
	_build_hint_ui()
	if _player == null:
		return
	_add_aura()
	# Checkpoint'ten yeniden doğuş: fener zaten alınmıştı.
	if CheckpointData.has_spawn:
		call_deferred("_grant_on_respawn")


func _grant_on_respawn() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.get("has_flashlight_skill") and _player.has_method("unlock_flashlight_skill"):
		_player.unlock_flashlight_skill()
	var pk := get_parent().get_node_or_null("FlashlightPickup")
	if pk != null:
		pk.queue_free()
	_lantern_ready = true  # yeniden doğuşta "Z ile aç" ipucunu tekrar gösterme
	_configure()


func _configure() -> void:
	_fc = _player.get("flashlight_component")
	if _fc == null:
		return
	_fc.max_battery = max_battery
	_fc.drain_rate = drain_rate
	_fc.charge_rate = charge_rate
	_fc.battery = max_battery
	if auto_turn_on and not _fc.is_on:
		_fc._turn_on()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _lantern_ready:
		if not _player.get("has_flashlight_skill"):
			return
		_lantern_ready = true
		_configure()
		show_hint(pickup_hint, 5.0)
	if _fc == null:
		_configure()
		if _fc == null:
			return
	# Işıklı lambalarda hızlı şarj
	if int(_player.get("safe_zones")) > 0 and _fc.battery < _fc.max_battery:
		_fc.battery = minf(_fc.battery + zone_charge_rate * delta, _fc.max_battery)
		_fc.battery_changed.emit(_fc.battery / _fc.max_battery)
	if _fc.battery <= 0.0 and not _empty_hint_shown:
		_empty_hint_shown = true
		show_hint("Pil bitti! Lambaların yanında dolar.", 3.5)


# ---------------- ipucu etiketi ----------------

func _build_hint_ui() -> void:
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 20
	add_child(_hint_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = THEME
	_hint_layer.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 48
	center.offset_bottom = 140
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, 0.85)
	sb.border_color = Color(0.61, 0.25, 0.85, 1)
	sb.set_border_width_all(3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_hint_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_hint_panel)
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", Color(0.97, 0.92, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.16))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_panel.add_child(_hint_label)
	_hint_panel.modulate.a = 0.0
	_hint_panel.visible = false


func show_hint(text: String, duration: float = 4.0) -> void:
	if _hint_label == null:
		return
	print("[LanternFlow] ipucu: ", text.replace("\n", " / "))
	_hint_label.text = text
	_hint_panel.visible = true
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_panel, "modulate:a", 1.0, 0.25)
	_hint_tween.tween_interval(maxf(duration, 0.5))
	_hint_tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.5)
	_hint_tween.tween_callback(func(): _hint_panel.visible = false)


func current_hint() -> String:
	return _hint_label.text if _hint_panel != null and _hint_panel.visible else ""


# ---------------- oyuncu aurası ----------------

func _add_aura() -> void:
	if aura_energy <= 0.0 or _player.get_node_or_null("LanternAura") != null:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var l := PointLight2D.new()
	l.name = "LanternAura"
	l.texture = t
	l.texture_scale = aura_scale
	l.energy = aura_energy
	l.color = Color(0.8, 0.78, 1.0)
	l.position = Vector2(0, -30)
	l.shadow_enabled = false
	_player.add_child(l)
