extends CharacterBody2D

signal impacted
signal exploded_at(pixel: Vector2i, direct_hit: Area2D, travel_direction: Vector2)
signal trail_sampled(at: Vector2)

const ANGLE_FRAMES := 40
const TRAIL_SPACING := 16.0
const FIRST_TRAIL_SAMPLE_DISTANCE := 8.0
const TRAIL_LAG_SAMPLES := 1
const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const LevelItem := preload("res://goats/level_item.gd")

@export var speed := 220.0
@export var gravity := 400.0
@export var blast_damage := 50

@onready var sprite: Sprite2D = $Sprite2D
@onready var collider: CollisionShape2D = $CollisionShape2D
@onready var impact_cast: ShapeCast2D = $ImpactCast

var shooter_hurtbox: GoatHurtbox
var terrain: Terrain
var terrain_pixel_size := Vector2.ONE
var wind_acceleration := 0.0
var lifetime := 4.0
var distance_to_next_trail := FIRST_TRAIL_SAMPLE_DISTANCE
var trail_positions: Array[Vector2] = []


func _ready() -> void:
	if is_instance_valid(shooter_hurtbox):
		impact_cast.add_exception(shooter_hurtbox)
	_update_sprite_angle()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	velocity.x += wind_acceleration * delta
	velocity.y += gravity * delta
	_update_sprite_angle()
	# Ignore the shooter only until the missile has cleared its hurtbox.
	if is_instance_valid(shooter_hurtbox) and not impact_cast.shape.collide(
		impact_cast.global_transform, shooter_hurtbox.collider.shape, shooter_hurtbox.collider.global_transform
	):
		impact_cast.remove_exception(shooter_hurtbox)
		shooter_hurtbox = null
	var motion := velocity * delta
	var bitmap_hit := false
	var hit_pixel := Vector2i.ZERO
	if terrain:
		# Sample the missile center at most one pixel apart, like the bitmap demo.
		var steps := maxi(1, ceili(motion.length()))
		for step in range(steps + 1):
			var fraction := float(step) / steps
			hit_pixel = Vector2i((position + motion * fraction).floor())
			var bitmap_pixel := Vector2i((Vector2(hit_pixel) / terrain_pixel_size).floor())
			if terrain.is_solid(bitmap_pixel.x, bitmap_pixel.y):
				bitmap_hit = true
				motion *= fraction
				break
	impact_cast.target_position = impact_cast.global_transform.basis_xform_inv(motion)
	impact_cast.force_shapecast_update()
	if impact_cast.is_colliding():
		for index in impact_cast.get_collision_count():
			var hurtbox := impact_cast.get_collider(index) as Area2D
			if hurtbox is GoatHurtbox or hurtbox is LevelItem:
				var contact := impact_cast.get_collision_point(index)
				exploded_at.emit(Vector2i(get_parent().to_local(contact).floor()), hurtbox, velocity.normalized())
				break
		impacted.emit()
		queue_free()
	elif bitmap_hit:
		exploded_at.emit(hit_pixel, null, velocity.normalized())
		impacted.emit()
		queue_free()
	else:
		var start := position
		var collision := move_and_collide(motion)
		_sample_trail(start, position - start)
		if collision:
			impacted.emit()
			queue_free()
		elif lifetime <= 0.0:
			queue_free()


func _sample_trail(start: Vector2, motion: Vector2) -> void:
	var distance := motion.length()
	while distance_to_next_trail <= distance:
		trail_positions.append(start + motion * (distance_to_next_trail / distance))
		if trail_positions.size() > TRAIL_LAG_SAMPLES:
			trail_sampled.emit(trail_positions.pop_front())
		distance_to_next_trail += TRAIL_SPACING
	distance_to_next_trail -= distance


func _update_sprite_angle() -> void:
	if velocity.is_zero_approx():
		return
	# Frame 0 points up. The remaining frames rotate clockwise in 9° steps.
	var turns := (velocity.angle() + PI / 2.0) / TAU
	sprite.frame = posmod(roundi(turns * ANGLE_FRAMES), ANGLE_FRAMES)
	collider.rotation = TAU * sprite.frame / ANGLE_FRAMES
	impact_cast.rotation = collider.rotation
