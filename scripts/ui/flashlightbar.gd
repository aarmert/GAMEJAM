extends Control
class_name FlashlightBarUI

# Fener pili göstergesi: mevcut 6 kareli simge + yanında 10 dilimli pil çubuğu.
# Fener açıkken çubuk parlar, pil azaldığında (<%25) kırmızı yanıp söner.

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

const FRAME_COUNT := 6
const SEGMENTS := 10
const BAR_POS := Vector2(274, 28)
const SEG_SIZE := Vector2(10, 22)
const SEG_GAP := 3.0
const C_FRAME := Color(0.07, 0.05, 0.12, 0.85)
const C_BORDER := Color(0.55, 0.45, 0.85, 1)
const C_ON := Color(1.0, 0.8, 0.35)
const C_OFF := Color(0.72, 0.55, 0.95)
const C_LOW := Color(1.0, 0.25, 0.3)
const C_EMPTY := Color(0.18, 0.13, 0.26)

var _percent := 1.0
var _is_on := false
var _t := 0.0


func _ready() -> void:
	set_process(false)


func update_battery(percent: float, is_on: bool) -> void:
	show()
	anim_sprite.stop()
	anim_sprite.frame = int(clamp(percent, 0.0, 1.0) * (FRAME_COUNT - 1))
	var changed := not is_equal_approx(percent, _percent) or is_on != _is_on
	_percent = clampf(percent, 0.0, 1.0)
	_is_on = is_on
	set_process(_percent < 0.25)
	if changed:
		queue_redraw()


func set_locked() -> void:
	hide()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := SEGMENTS * (SEG_SIZE.x + SEG_GAP) - SEG_GAP
	var frame := Rect2(BAR_POS - Vector2(6, 6), Vector2(w + 12, SEG_SIZE.y + 12))
	draw_rect(frame, C_FRAME)
	draw_rect(frame, C_BORDER, false, 3.0)
	var filled := _percent * SEGMENTS
	var low := _percent < 0.25
	var blink := low and int(_t * 4.0) % 2 == 0
	var col := C_ON if _is_on else C_OFF
	if low:
		col = C_LOW if not blink else C_LOW.darkened(0.5)
	for i in SEGMENTS:
		var r := Rect2(BAR_POS + Vector2(i * (SEG_SIZE.x + SEG_GAP), 0), SEG_SIZE)
		draw_rect(r, C_EMPTY)
		var part := clampf(filled - i, 0.0, 1.0)
		if part > 0.0:
			var h := roundf(SEG_SIZE.y * part / 2.0) * 2.0
			draw_rect(Rect2(r.position + Vector2(0, SEG_SIZE.y - h), Vector2(SEG_SIZE.x, h)), col)
			if part >= 1.0:
				draw_rect(Rect2(r.position, Vector2(SEG_SIZE.x, 2)), col.lightened(0.4))
