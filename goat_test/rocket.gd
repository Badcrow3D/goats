extends CharacterBody2D

const ANGLE_FRAMES := 40
const GoatHurtbox := preload("res://goat_test/goat_hurtbox.gd")

@export var speed := 220.0
@export var gravity := 400.0
@export var direct_damage := 10

@onready var sprite: Sprite2D = $Sprite2D
@onready var collider: CollisionShape2D = $CollisionShape2D
@onready var impact_cast: ShapeCast2D = $ImpactCast

var shooter_hurtbox: Area2D
var lifetime := 4.0


func _ready() -> void:
	if is_instance_valid(shooter_hurtbox):
		impact_cast.add_exception(shooter_hurtbox)
	_update_sprite_angle()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	velocity.y += gravity * delta
	_update_sprite_angle()
	var motion := velocity * delta
	impact_cast.target_position = impact_cast.global_transform.basis_xform_inv(motion)
	impact_cast.force_shapecast_update()
	if impact_cast.is_colliding():
		for index in impact_cast.get_collision_count():
			var hurtbox := impact_cast.get_collider(index) as GoatHurtbox
			if hurtbox:
				hurtbox.apply_damage(direct_damage)
				break
		queue_free()
	elif move_and_collide(motion) or lifetime <= 0.0:
		queue_free()


func _update_sprite_angle() -> void:
	if velocity.is_zero_approx():
		return
	# Frame 0 points up. The remaining frames rotate clockwise in 9° steps.
	var turns := (velocity.angle() + PI / 2.0) / TAU
	sprite.frame = posmod(roundi(turns * ANGLE_FRAMES), ANGLE_FRAMES)
	collider.rotation = TAU * sprite.frame / ANGLE_FRAMES
	impact_cast.rotation = collider.rotation
