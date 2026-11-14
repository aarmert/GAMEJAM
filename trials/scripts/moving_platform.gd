extends AnimatableBody2D
# Trials: scenes/platforms.tscn örneğine takılan ileri-geri hareket. Konum her fizik karesinde
# zamandan hesaplanır (deterministik; reset_motion() ile başa döner).

var a := Vector2.ZERO
var b := Vector2.ZERO
var speed := 64.0
var wait := 0.4
var t := 0.0


func _ready() -> void:
	sync_to_physics = true
	position = a


func reset_motion() -> void:
	t = 0.0
	position = a


func _physics_process(delta: float) -> void:
	t += delta
	position = pos_at(t)


func pos_at(time: float) -> Vector2:
	var dist := a.distance_to(b)
	if dist < 0.5 or speed <= 0.0:
		return a
	var travel := dist / speed
	var period := 2.0 * (travel + wait)
	var u := fposmod(time, period)
	if u < wait:
		return a
	u -= wait
	if u < travel:
		return a.lerp(b, smoothstep(0.0, 1.0, u / travel))
	u -= travel
	if u < wait:
		return b
	u -= wait
	return b.lerp(a, smoothstep(0.0, 1.0, u / travel))
