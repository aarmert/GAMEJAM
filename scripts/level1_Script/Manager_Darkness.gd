extends Node2D


@export var block_scene: Area2D
@export var player: Node2D
@export var tile_map: TileMap
@export var speed: float = 1.0
const TILE_SIZE = 32
var time_passed: float 0.0
var frontier_blocks = []
var occupied_blocks = []

func _process(delta):
	var distance = player.global_position - global_position
	var direction = distance.normalized()
	time_passed += delta 
