extends Control
class_name DashBarUI

@onready var dash_icon: TextureRect = $DashIcon
@onready var dash_label: Label = $DashTextColumn/DashLabel
@onready var dash_bar: ProgressBar = $DashTextColumn/DashBar

var ready_color := Color(0.55, 1.0, 0.55, 1.0)
var cooldown_color := Color(1.0, 0.75, 0.45, 1.0)
var locked_color := Color(0.8, 0.35, 0.35, 1.0)


func init_dash(max_seconds: float) -> void:
	dash_bar.max_value = max_seconds
	dash_bar.value = max_seconds
	dash_label.text = "Dash: Ready"
	dash_label.modulate = ready_color


func update_dash(remaining: float, max_seconds: float) -> void:
	if remaining <= 0.0:
		dash_label.text = "Dash: Ready"
		dash_label.modulate = ready_color
		dash_bar.value = max_seconds
		return

	var clamped_max: float = max(max_seconds, 0.001)
	dash_label.text = "Dash: %.1f" % remaining
	dash_label.modulate = cooldown_color
	dash_bar.max_value = clamped_max
	dash_bar.value = remaining


func set_ready() -> void:
	dash_label.text = "Dash: Ready"
	dash_label.modulate = ready_color


func set_locked() -> void:
	dash_label.text = "Dash: Locked"
	dash_label.modulate = locked_color
	dash_bar.value = 0.0
