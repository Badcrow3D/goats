extends "res://goats/projectile.gd"

const BOUNCE_RESTITUTION := 0.55

var ground_response: Callable

@onready var collider: CollisionShape2D = $Area2D/CollisionShape2D
@export_range(1.0, 5.0, 0.1) var fuse_seconds := 4.0
@onready var time_remaining := clampf(fuse_seconds, 1.0, 5.0)


var contact_query := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	contact_query.shape = collider.shape
	contact_query.collision_mask = GoatHurtbox.COLLISION_MASK | LevelItem.COLLISION_MASK
	contact_query.collide_with_bodies = false
	contact_query.collide_with_areas = true
	if is_instance_valid(shooter_hurtbox):
		contact_query.exclude = [shooter_hurtbox.get_rid()]


func _physics_process(delta: float) -> void:
	var flight_time := minf(delta, time_remaining)
	velocity.y += gravity * flight_time
	var travel_pixels := velocity * flight_time / terrain_pixel_size
	var steps := maxi(1, ceili(travel_pixels.length()))
	var step_time := flight_time / steps
	for step in steps:
		if is_instance_valid(shooter_hurtbox) and not collider.shape.collide(
			collider.global_transform, shooter_hurtbox.collider.shape, shooter_hurtbox.collider.global_transform
		):
			contact_query.exclude = []
			shooter_hurtbox = null
		var next_y := position + Vector2.DOWN * velocity.y * step_time
		if _blocked(next_y):
			if velocity.y > 0.0 and ground_response.is_valid():
				velocity = ground_response.call(velocity, _footprint(position))
			else:
				velocity.y = 0.0
		else:
			position.y = next_y.y

		var next_x := position + Vector2.RIGHT * velocity.x * step_time
		if _blocked(next_x):
			velocity.x *= -BOUNCE_RESTITUTION
		else:
			position.x = next_x.x

	time_remaining -= flight_time
	if time_remaining <= 0.0:
		exploded_at.emit(Vector2i(position.floor()), null, velocity.normalized())
		impacted.emit()
		queue_free()


func _footprint(at: Vector2) -> Rect2i:
	# The destructible terrain is a bitmap. Test every pixel touched by the Area2D shape.
	var bounds := (global_transform.affine_inverse() * collider.global_transform) * collider.shape.get_rect()
	var shift := at
	var start := Vector2i(((bounds.position + shift) / terrain_pixel_size).floor())
	var end := Vector2i(((bounds.end + shift) / terrain_pixel_size).ceil())
	return Rect2i(start, end - start)


func _blocked(at: Vector2) -> bool:
	if terrain:
		var rect := _footprint(at)
		if not terrain.rect_is_free(rect.position.x, rect.position.y, rect.size.x, rect.size.y):
			return true
	var pose := collider.global_transform
	pose.origin += get_parent().to_global(at) - global_position
	contact_query.transform = pose
	return not get_world_2d().direct_space_state.intersect_shape(contact_query, 1).is_empty()
