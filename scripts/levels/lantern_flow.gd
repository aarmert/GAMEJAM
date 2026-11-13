extends Node

# Son bölümün sade fener akışı:
#  - Fener alındığı anda kendiliğinden yanar
#  - Pil bitmez (drain yok), istersen F ile kapatıp açabilirsin
#  - Rastgele karartma (blackout) yok
#
# Inspector'dan pil tüketimini geri açmak istersen drain_rate'i değiştir.

@export var player_path: NodePath
@export var drain_rate: float = 0.0
@export var auto_turn_on: bool = true

var _player: Node = null
var _lantern_ready := false


func _ready() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		for n in get_tree().get_nodes_in_group("player"):
			if n is CharacterBody2D:
				_player = n
				break


func _process(_delta: float) -> void:
	if _lantern_ready or _player == null:
		return
	if not _player.get("has_flashlight_skill"):
		return
	_lantern_ready = true
	var fc = _player.get("flashlight_component")
	if fc == null:
		return
	fc.drain_rate = drain_rate
	fc.battery = fc.max_battery
	if auto_turn_on and not fc.is_on:
		fc._turn_on()
	set_process(false)
