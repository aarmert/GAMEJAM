extends Area2D

# Pil kristali: fenerin pilini doldurur (bir kez). Sahne yeniden yüklenince geri gelir.

@export var amount: float = 40.0

var _t := 0.0
var _origin := Vector2.ZERO


func _ready() -> void:
	_origin = position
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	position.y = _origin.y + roundf(sin(_t * 3.0) * 2.0) * 2.0


func _on_body_entered(body: Node) -> void:
	var fc = body.get("flashlight_component")
	if fc == null or not body.get("has_flashlight_skill"):
		return
	fc.battery = minf(fc.battery + amount, fc.max_battery)
	fc.battery_changed.emit(fc.battery / fc.max_battery)
	var flow := get_tree().get_first_node_in_group("lantern_flow")
	if flow != null and flow.has_method("show_hint"):
		flow.show_hint("+Pil", 1.2)
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("pickup", 0.05)
	queue_free()
