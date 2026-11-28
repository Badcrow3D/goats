extends "res://goats/projectile.gd"

signal hit_target(at: Vector2, target: Area2D, direction: Vector2)
signal carved_terrain

const PENETRATION_PIXELS := 35.0
const SWEEP_EPSILON := 0.00001

@onready var collider: CollisionShape2D = $Area2D/CollisionShape2D
@onready var impact_cast: ShapeCast2D = $Area2D/CollisionShape2D/ImpactCast

var terrain_view: TerrainView
var penetration_left := PENETRATION_PIXELS
# Keep charging distance through pixels erased by the previous tick until the front clears them.
var cleared_at_front: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	global_rotation = velocity.angle()
	impact_cast.shape = collider.shape
	if is_instance_valid(shooter_hurtbox):
		impact_cast.add_exception(shooter_hurtbox)


func _physics_process(delta: float) -> void:
	var motion := velocity * delta
	var direction := velocity.normalized()
	var target := _find_target(Vector2.ZERO)
	var travel := motion.length()
	if target:
		travel = 0.0
	else:
		target = _find_target(motion)
		if target:
			travel *= impact_cast.get_closest_collision_unsafe_fraction()

	var world_to_terrain := terrain_view.global_transform.affine_inverse()
	var local_direction := world_to_terrain.basis_xform(direction)
	var local_distance := travel * local_direction.length()
	var allowed := _carve_path(world_to_terrain * collider.global_transform, local_direction.normalized(), local_distance)
	global_position += direction * (allowed / local_direction.length())
	if allowed < local_distance:
		queue_free()
	elif target:
		hit_target.emit(impact_cast.get_collision_point(0), target, direction)
		queue_free()
	else:
		var level := terrain_view.terrain
		var level_bounds := Rect2(0, 0, level.width, level.height)
		var footprint := (world_to_terrain * collider.global_transform) * collider.shape.get_rect()
		if not level_bounds.intersects(footprint):
			queue_free()


func _find_target(motion: Vector2) -> Area2D:
	impact_cast.target_position = impact_cast.global_transform.basis_xform_inv(motion)
	impact_cast.force_shapecast_update()
	while impact_cast.is_colliding():
		var target := impact_cast.get_collider(0) as Area2D
		if not target.is_queued_for_deletion():
			return target
		impact_cast.add_exception(target)
		impact_cast.force_shapecast_update()
	return null


func _carve_path(to_terrain: Transform2D, direction: Vector2, distance: float) -> float:
	var shape_rect := collider.shape.get_rect()
	var front := to_terrain * Vector2(shape_rect.end.x, shape_rect.get_center().y)
	var half_span := to_terrain.basis_xform(Vector2(0.0, shape_rect.size.y * 0.5))
	var body_length := to_terrain.basis_xform(Vector2(shape_rect.size.x, 0.0)).length()
	var back := front - direction * body_length
	var end := front + direction * distance
	var bounds := Rect2(back - half_span, Vector2.ZERO).expand(back + half_span)
	bounds = bounds.expand(end - half_span).expand(end + half_span)
	var first := Vector2i(bounds.position.floor()).max(Vector2i.ZERO)
	var level := terrain_view.terrain
	var last := Vector2i(bounds.end.ceil()).min(Vector2i(level.width, level.height))

	var hits: Dictionary[Vector2i, Vector2] = {}
	var intervals: Array[Vector2] = []
	var axes: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, half_span.orthogonal().normalized()]
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			var pixel := Vector2i(x, y)
			if not level.is_solid(x, y) and not cleared_at_front.has(pixel):
				continue
			var hit := _front_interval(Vector2(pixel) + Vector2(0.5, 0.5) - front, direction, half_span, axes)
			if hit.y <= maxf(hit.x, -body_length) or hit.x >= distance:
				continue
			hits[pixel] = hit
			# Measure material at the leading edge so a wall's thickness is counted once.
			if hit.y > 0.0:
				intervals.append(Vector2(maxf(hit.x, 0.0), minf(hit.y, distance)))

	var allowed := _limit_penetration(intervals, distance)
	var carved: Array[Vector2i] = []
	cleared_at_front.clear()
	for pixel in hits:
		var hit := hits[pixel]
		if hit.x < allowed - SWEEP_EPSILON:
			if level.is_solid(pixel.x, pixel.y):
				carved.append(pixel)
			if hit.y > allowed:
				cleared_at_front[pixel] = true
	if not carved.is_empty():
		terrain_view.erase_pixels(carved)
		carved_terrain.emit()
	return allowed


func _front_interval(offset: Vector2, direction: Vector2, half_span: Vector2, axes: Array[Vector2]) -> Vector2:
	# Sweep the hitbox's front segment against a unit pixel square using separating axes.
	var interval := Vector2(-INF, INF)
	for axis: Vector2 in axes:
		var gap := offset.dot(axis)
		var radius := absf(half_span.dot(axis)) + 0.5 * (absf(axis.x) + absf(axis.y))
		var speed_on_axis := direction.dot(axis)
		if absf(speed_on_axis) < SWEEP_EPSILON:
			if absf(gap) >= radius:
				return Vector2.ZERO
			continue
		var a := (gap - radius) / speed_on_axis
		var b := (gap + radius) / speed_on_axis
		interval.x = maxf(interval.x, minf(a, b))
		interval.y = minf(interval.y, maxf(a, b))
	return interval


func _limit_penetration(intervals: Array[Vector2], distance: float) -> float:
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered_until := 0.0
	for interval in intervals:
		var start := maxf(interval.x, covered_until)
		var depth := maxf(0.0, interval.y - start)
		if depth > penetration_left + SWEEP_EPSILON:
			return start + penetration_left
		penetration_left = maxf(0.0, penetration_left - depth)
		covered_until = maxf(covered_until, interval.y)
	return distance
