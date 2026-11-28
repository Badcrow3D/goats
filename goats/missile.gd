extends "res://goats/projectile.gd"

signal trail_sampled(at: Vector2)

const TRAIL_SPACING := 16.0
const FIRST_TRAIL_SAMPLE_DISTANCE := 8.0
const TRAIL_LAG_SAMPLES := 1

@onready var collider: CollisionShape2D = $Area2D/CollisionShape2D
@onready var impact_cast: ShapeCast2D = $Area2D/CollisionShape2D/ImpactCast


var wind_acceleration := 0.0
@export var lifetime := 4.0
@export var explode_on_timeout := false
var distance_to_next_trail := FIRST_TRAIL_SAMPLE_DISTANCE
var trail_positions: Array[Vector2] = []


func _ready() -> void:
	impact_cast.shape = collider.shape
	if is_instance_valid(shooter_hurtbox):
		impact_cast.add_exception(shooter_hurtbox)
	_face_velocity()


func _physics_process(delta: float) -> void:
	delta = minf(lifetime, delta)
	lifetime -= delta
	velocity.x += wind_acceleration * delta
	velocity.y += gravity * delta
	_face_velocity()
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
		var contact := impact_cast.get_collision_point(0)
		var direct_hit: Area2D
		for index in impact_cast.get_collision_count():
			var target := impact_cast.get_collider(index)
			if target is GoatHurtbox or target is LevelItem:
				direct_hit = target
				contact = impact_cast.get_collision_point(index)
				break
		if direct_hit or explode_on_timeout:
			exploded_at.emit(Vector2i(get_parent().to_local(contact).floor()), direct_hit, velocity.normalized())
		impacted.emit()
		queue_free()
	elif bitmap_hit:
		exploded_at.emit(hit_pixel, null, velocity.normalized())
		impacted.emit()
		queue_free()
	else:
		var start := position
		position += motion
		_sample_trail(start, position - start)
		if lifetime <= 0.0:
			if explode_on_timeout:
				exploded_at.emit(Vector2i(position.floor()), null, velocity.normalized())
				impacted.emit()
			queue_free()


func _sample_trail(start: Vector2, motion: Vector2) -> void:
	var distance := motion.length()
	while distance_to_next_trail <= distance:
		trail_positions.append(start + motion * (distance_to_next_trail / distance))
		if trail_positions.size() > TRAIL_LAG_SAMPLES:
			trail_sampled.emit(trail_positions.pop_front())
		distance_to_next_trail += TRAIL_SPACING
	distance_to_next_trail -= distance


func _face_velocity() -> void:
	if velocity.is_zero_approx():
		return
	rotation = velocity.angle()
