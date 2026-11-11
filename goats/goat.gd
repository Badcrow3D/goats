@tool
extends CharacterBody2D

signal damaged(amount: int, hit_direction: Vector2)
signal mode_changed

enum Facing { LEFT = -1, RIGHT = 1 }
enum Status { ACTIVE, ALIVE, DEAD }
enum Mode { GOAT_ONLY = 0, BACKPACK = 1, LAUNCHER = 2 }

@export var team_id := 0
@export var goat_name := ""
@export var health := 100
@export var energy := 100
@export var facing_direction := Facing.RIGHT
@export var status := Status.ALIVE
@export var mode := Mode.LAUNCHER:
	set(value):
		if mode == value:
			return
		mode = value
		if is_node_ready():
			_apply_mode_layers()
		mode_changed.emit()


func _ready() -> void:
	_apply_mode_layers()


func _apply_mode_layers() -> void:
	$AnimatedSprite2D/Backpack.visible = mode != Mode.GOAT_ONLY
	$AnimatedSprite2D/Launcher.visible = mode == Mode.LAUNCHER


func take_damage(amount: int, hit_direction := Vector2.ZERO) -> void:
	if amount <= 0:
		return
	health = maxi(health - amount, 0)
	if health == 0:
		status = Status.DEAD
	damaged.emit(amount, hit_direction)
