extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@onready var flashlight_pivot: Node2D = $FlashlightPivot
@onready var animated_sprit: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var landing_light: PointLight2D = get_node_or_null("LandingLight")
@onready var floor_ray: RayCast2D = get_node_or_null("FloorRay")

var safe_zones = 0
var is_dead = false


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity += get_gravity() * delta
		move_and_slide()
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction > 0:
		animated_sprit.flip_h = false
		flashlight_pivot.scale.x = 1
	elif direction < 0:
		animated_sprit.flip_h = true
		flashlight_pivot.scale.x = -1

	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()



func _ready() -> void:
	health_bar.init_health(100)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	health_bar.health -= amount
	if health_bar.health <= 0:
		Engine.time_scale = 0.5
		die()


func heal(amount: int) -> void:
	if is_dead:
		return
	health_bar.health += amount


func die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	await get_tree().create_timer(0.7, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _on_darkness_damage_timer_timeout() -> void:
	if safe_zones == 0 and not is_dead:
		take_damage(5)
