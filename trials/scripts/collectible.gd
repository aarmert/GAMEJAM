extends Area2D
# Trials toplanabilir "kor" (assets/red_coin.png). Alınınca oyuncuyu izler; oda geçişinde ya da
# çıkışta "bankaya" yatar. Oda içinde ölünce yerine döner (oda sıfırlanır).
# Collectible ember: follows the player once touched, is banked on room exit / chapter exit,
# returns to its spot if the player dies before banking.

signal picked(c: Area2D)

const TEX := preload("res://assets/red_coin.png")

var cid := ""
var state := "idle" # idle | following | banked
var target: Node2D = null
var home := Vector2.ZERO
var _t := 0.0
var _sprite: AnimatedSprite2D


func _init() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	frames.set_animation_speed("spin", 10.0)
	frames.set_animation_loop("spin", true)
	for i in 8:
		var at := AtlasTexture.new()
		at.atlas = TEX
		at.region = Rect2(i * 16, 0, 16, 16)
		frames.add_frame("spin", at)
	if frames.has_animation("default"):
		frames.remove_animation("default")
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.animation = "spin"
	_sprite.scale = Vector2(1.25, 1.25)
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 11.0
	cs.shape = sh
	add_child(cs)
	var light := PointLight2D.new()
	light.color = Color(1.0, 0.35, 0.3)
	light.energy = 0.9
	light.texture_scale = 0.35
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	light.texture = gt
	add_child(light)


func _ready() -> void:
	home = position
	_sprite.play("spin")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if state != "idle" or not body.is_in_group("player"):
		return
	if body.has_method("trials_is_dead") and body.trials_is_dead():
		return
	state = "following"
	target = body as Node2D
	picked.emit(self)


func _physics_process(delta: float) -> void:
	_t += delta
	if state == "idle":
		position = home + Vector2(0, sin(_t * 3.0) * 2.0)
	elif state == "following" and is_instance_valid(target):
		var facing := -1.0 if (target.has_node("AnimatedSprite2D") and target.get_node("AnimatedSprite2D").flip_h) else 1.0
		var goal := target.global_position + Vector2(-20.0 * facing, -58.0 + sin(_t * 4.0) * 3.0)
		global_position = global_position.lerp(goal, 1.0 - exp(-7.0 * delta))


func bank() -> void:
	state = "banked"
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.15)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
