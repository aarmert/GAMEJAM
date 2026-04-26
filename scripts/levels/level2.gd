extends Node2D

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var background_modulate: CanvasModulate = get_node_or_null("ParallaxBackground/BackgroundModulate")
@onready var flashlight: PointLight2D = $MayaChar2/FlashlightPivot/PointLight2D

@export var checkpoints: Array[Area2D] = []
@export var player: CharacterBody2D
@export var preview_camera: Camera2D
@export var player_camera: Camera2D
@export var preview_duration: float = 1.5

var visited: Array[bool] = []
var is_previewing: bool = false


func _ready() -> void:
	# Cok hafif aydinlatma: sadece siluetler zar zor seçilir
	canvas_modulate.color = Color(0.08, 0.08, 0.11)
	#background_modulate.color = Color(0.14, 0.14, 0.18)
	flashlight.enabled = true

	visited.resize(checkpoints.size())
	visited.fill(false)

	# Preview kameranın zoom'unu player kameranınkine eşitle
	if preview_camera and player_camera:
		preview_camera.zoom = player_camera.zoom

	if checkpoints.size() > 0:
		await get_tree().process_frame
		play_preview_to(0)


func play_preview_to(index: int) -> void:
	if is_previewing or index < 0 or index >= checkpoints.size():
		return
	is_previewing = true
	player.set_physics_process(false)

	# Her preview başında zoom'u tekrar eşitle (güvence)
	preview_camera.zoom = player_camera.zoom

	preview_camera.global_position = player.global_position
	preview_camera.make_current()

	var target_pos = checkpoints[index].global_position
	var tween = create_tween()
	tween.tween_property(preview_camera, "global_position", target_pos, preview_duration)
	tween.tween_property(preview_camera, "global_position", player.global_position, preview_duration)
	tween.tween_callback(_finish_preview)


func _finish_preview() -> void:
	player_camera.make_current()
	player.set_physics_process(true)
	is_previewing = false


func checkpoint_reached(index: int) -> void:
	if index >= visited.size() or visited[index]:
		return
	visited[index] = true
	var next_index = index + 1
	if next_index < checkpoints.size():
		play_preview_to(next_index)
