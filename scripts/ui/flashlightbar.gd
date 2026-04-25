extends Control
class_name FlashlightBarUI

@onready var fl_label: Label = $Panel/HBoxContainer/FlTextColumn/FlLabel
@onready var fl_bar: ProgressBar = $Panel/HBoxContainer/FlTextColumn/FlBar

var on_color := Color(1.0, 0.95, 0.4, 1.0)
var charging_color := Color(0.55, 0.85, 0.55, 1.0)
var empty_color := Color(0.9, 0.3, 0.3, 1.0)
var locked_color := Color(0.8, 0.35, 0.35, 1.0)


func update_battery(percent: float, is_on: bool) -> void:
	fl_bar.value = percent * 100.0
	if percent <= 0.0:
		fl_label.text = "Fener: Boş"
		fl_label.modulate = empty_color
	elif is_on:
		fl_label.text = "Fener: %d%%" % int(percent * 100)
		fl_label.modulate = on_color
	else:
		fl_label.text = "Şarjda %d%%" % int(percent * 100)
		fl_label.modulate = charging_color


func set_locked() -> void:
	fl_label.text = "Fener: Kilitli"
	fl_label.modulate = locked_color
	fl_bar.value = 0.0
