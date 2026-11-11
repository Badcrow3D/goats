extends Area2D

const COLLISION_MASK := 1 << 2

@onready var collider: CollisionShape2D = $CollisionShape2D

func apply_damage(amount: int) -> void:
	var goat := get_parent()
	if amount > 0 and goat.has_method("take_damage"):
		goat.take_damage(amount)

## Call from a physics tick with a world-space radius and peak damage.
static func apply_area_damage(context: Node2D, center: Vector2, radius: float, peak_damage: int) -> void:
	var hurtbox_count := context.get_tree().get_node_count_in_group(&"goat_hurtboxes")
	if radius <= 0.0 or peak_damage <= 0 or hurtbox_count == 0:
		return
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = COLLISION_MASK
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hits := context.get_world_2d().direct_space_state.intersect_shape(query, hurtbox_count)
	for hit in hits:
		var hurtbox: Area2D = hit.collider
		var shape_node: CollisionShape2D = hurtbox.collider
		# Measure to the nearest point of the goat's hurtbox, so contact deals full damage.
		var bounds := shape_node.shape.get_rect()
		var nearest := shape_node.to_local(center).clamp(bounds.position, bounds.end)
		var distance := center.distance_to(shape_node.to_global(nearest))
		var falloff := clampf(1.0 - distance / radius, 0.0, 1.0)
		hurtbox.apply_damage(roundi(peak_damage * falloff))
