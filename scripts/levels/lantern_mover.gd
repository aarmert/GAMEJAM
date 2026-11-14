extends AnimatableBody2D

# Fener mağarasının hareketli taş platformu: iki nokta arasında gidip gelir, uçlarda bekler.
# Görsel: mağara karo sayfasındaki ince kaya platform parçaları (3 karo).

@export var travel: Vector2 = Vector2(256, 0)
@export var speed: float = 80.0
@export var end_wait: float = 0.8
@export var start_delay: float = 0.4

var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _to_b := true
var _wait := 0.0


func _ready() -> void:
	_a = global_position
	_b = _a + travel
	_wait = start_delay
	sync_to_physics = true


func _physics_process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	var target := _b if _to_b else _a
	global_position = global_position.move_toward(target, speed * delta)
	if global_position.is_equal_approx(target):
		_to_b = not _to_b
		_wait = end_wait
