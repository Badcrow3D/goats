extends CharacterBody2D

const ANGLE_FRAMES := 40

@export var speed := 220.0
@export var gravity := 400.0

@onready var sprite: Sprite2D = $Sprite2D

var lifetime := 4.0


func _ready() -> void:
	_update_sprite_angle()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	velocity.y += gravity * delta
	_update_sprite_angle()
	if move_and_collide(velocity * delta) or lifetime <= 0.0:
		queue_free()


func _update_sprite_angle() -> void:
	if velocity.is_zero_approx():
		return
	# Frame 0 points up. The remaining frames rotate clockwise in 9° steps.
	var turns := (velocity.angle() + PI / 2.0) / TAU
	sprite.frame = posmod(roundi(turns * ANGLE_FRAMES), ANGLE_FRAMES)
