extends Area2D

const COLLISION_MASK := 1 << 2

func apply_damage(amount: int) -> void:
	var goat := get_parent()
	if amount > 0 and goat.has_method("take_damage"):
		goat.take_damage(amount)

## Call from a physics tick with the blast radius and damage chosen by the caller.
static func apply_area_damage(context: Node2D, center: Vector2, radius: float, amount: int) -> void:
	var hurtbox_count := context.get_tree().get_node_count_in_group(&"goat_hurtboxes")
	if radius <= 0.0 or amount <= 0 or hurtbox_count == 0:
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
		hit.collider.apply_damage(amount)
