extends Node2D

# Mağara kristali süsü: zemini ve basılacak yeri hafifçe aydınlatır (gölgesiz ışık = ucuz).

@export var color: Color = Color(0.55, 0.75, 1.0)
@export var light_scale: float = 1.0
@export var flip: bool = false

var _light: PointLight2D


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_light = PointLight2D.new()
	_light.texture = _radial(96)
	_light.texture_scale = 2.4 * light_scale
	_light.energy = 0.75
	_light.color = color
	_light.position = Vector2(0, -8)
	_light.shadow_enabled = false
	add_child(_light)


func _draw() -> void:
	var s := -1.0 if flip else 1.0
	var dark := color.darkened(0.45)
	var mid := color
	var hi := color.lightened(0.55)
	# üç sivri kristal, 2 px "sanat pikseli"
	var shards := [[-6.0, 10.0, 4.0], [0.0, 16.0, 6.0], [6.0, 8.0, 4.0]]
	for sh in shards:
		var x: float = sh[0] * s
		var h: float = sh[1]
		var w: float = sh[2]
		var y := 0.0
		while y < h:
			var ww := maxf(2.0, floorf(w * (1.0 - y / h) / 2.0) * 2.0)
			draw_rect(Rect2(Vector2(x - ww * 0.5, -y - 2.0), Vector2(ww, 2)), mid if y > 2.0 else dark)
			if ww > 2.0:
				draw_rect(Rect2(Vector2(x - ww * 0.5, -y - 2.0), Vector2(2, 2)), hi)
			y += 2.0


static func _radial(sz: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = sz
	t.height = sz
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
