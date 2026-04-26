extends Node

@export var min_wait: float = 5.0
@export var max_wait: float = 15.0
@export var min_blackout: float = 3.0
@export var max_blackout: float = 5.0
@export var fade_duration: float = 0.6

@onready var _overlay: ColorRect = $BlackoutLayer/Overlay

var _mat: ShaderMaterial
var _is_blackout := false


func _ready() -> void:
	_mat = _overlay.material as ShaderMaterial
	var vp_size := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", vp_size.x / vp_size.y)
	_mat.set_shader_parameter("blackout_alpha", 0.0)
	_mat.set_shader_parameter("light_on", false)
	_loop()


func _process(_delta: float) -> void:
	if _is_blackout:
		_update_light()


func _update_light() -> void:
	var player := _get_player()
	if player == null:
		_mat.set_shader_parameter("light_on", false)
		return

	var fl: PlayerFlashlightComponent = player.get_node_or_null("Components/FlashlightComponent")
	var on := fl != null and fl.is_on
	_mat.set_shader_parameter("light_on", on)

	if not on:
		return

	var pivot := player.get_node_or_null("FlashlightPivot") as Node2D
	var origin := pivot.global_position if pivot else player.global_position

	var vp := get_viewport()
	var screen_px: Vector2 = vp.get_canvas_transform() * origin
	var vp_size := vp.get_visible_rect().size
	_mat.set_shader_parameter("light_uv", screen_px / vp_size)

	var spr := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_mat.set_shader_parameter("light_direction", -1.0 if (spr and spr.flip_h) else 1.0)


func _loop() -> void:
	while true:
		await get_tree().create_timer(randf_range(min_wait, max_wait)).timeout
		_is_blackout = true
		await _fade_to(1.0)
		await get_tree().create_timer(randf_range(min_blackout, max_blackout)).timeout
		await _fade_to(0.0)
		_is_blackout = false
		_mat.set_shader_parameter("light_on", false)


func _fade_to(target: float) -> void:
	var start: float = _mat.get_shader_parameter("blackout_alpha")
	var elapsed := 0.0
	while elapsed < fade_duration:
		elapsed += get_process_delta_time()
		_mat.set_shader_parameter("blackout_alpha", lerpf(start, target, minf(elapsed / fade_duration, 1.0)))
		await get_tree().process_frame
	_mat.set_shader_parameter("blackout_alpha", target)


func _get_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	return nodes[0] as Node2D if nodes.size() > 0 else null
