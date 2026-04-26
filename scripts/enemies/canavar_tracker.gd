extends CharacterBody2D

@export var speed: float = 85.0
@export var jump_velocity: float = -300.0
@export var stun_duration: float = 3.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var wall_check_low: RayCast2D = $WallCheckLow
@onready var wall_check_high: RayCast2D = $WallCheckHigh
@onready var ledge_check: RayCast2D = $LedgeCheck

var player: Node2D = null
var facing_direction: int = 1
var is_stunned: bool = false
var _stun_timer: float = 0.0


func _ready() -> void:
	add_to_group("Enemy")
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_unfreeze()
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		move_and_slide()
		return

	if player == null:
		move_and_slide()
		return

	var dir := sign(player.global_position.x - global_position.x)
	if dir != 0.0:
		facing_direction = int(dir)

	if is_on_floor():
		var low_blocked := wall_check_low.is_colliding()
		var high_blocked := wall_check_high.is_colliding()
		var no_ledge := not ledge_check.is_colliding()

		if low_blocked and not high_blocked:
			velocity.y = jump_velocity
		elif no_ledge:
			facing_direction *= -1

	velocity.x = facing_direction * speed
	animated_sprite.flip_h = facing_direction < 0
	_update_raycasts()
	animated_sprite.play("run")
	move_and_slide()


func stun() -> void:
	is_stunned = true
	_stun_timer = stun_duration
	velocity = Vector2.ZERO
	animated_sprite.modulate = Color(0.4, 0.85, 1.0)
	animated_sprite.pause()


func _unfreeze() -> void:
	is_stunned = false
	animated_sprite.modulate = Color.WHITE
	animated_sprite.play("run")


func _update_raycasts() -> void:
	wall_check_low.target_position.x = abs(wall_check_low.target_position.x) * facing_direction
	wall_check_high.target_position.x = abs(wall_check_high.target_position.x) * facing_direction
	ledge_check.position.x = abs(ledge_check.position.x) * facing_direction
