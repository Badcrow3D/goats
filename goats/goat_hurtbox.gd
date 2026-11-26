extends Area2D

const COLLISION_MASK := 1 << 2

@onready var collider: CollisionShape2D = $CollisionShape2D

func apply_damage(amount: int, hit_direction := Vector2.ZERO) -> void:
	var goat := get_parent()
	if amount > 0 and goat.has_method("take_damage"):
		goat.take_damage(amount, hit_direction)
