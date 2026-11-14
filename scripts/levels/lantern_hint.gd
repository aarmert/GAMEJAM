extends Area2D

# Oyuncu girince ekranda kısa bir ipucu gösterir (bir kez). Metin LanternFlow'un etiketinde çıkar.

@export_multiline var text: String = ""
@export var duration: float = 4.5
## Yalnızca fener alınmışsa tetiklen (fener ipuçları için).
@export var needs_flashlight: bool = true

var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _done or not body.is_in_group("player"):
		return
	if needs_flashlight and not body.get("has_flashlight_skill"):
		return
	_done = true
	var flow := get_tree().get_first_node_in_group("lantern_flow")
	if flow != null and flow.has_method("show_hint"):
		flow.show_hint(text, duration)
