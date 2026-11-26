extends "res://goats/level_item.gd"

const DETONATION_DAMAGE := 3
const DETONATION_DELAY := 0.08
const BLAST_DAMAGE := 50

@onready var sprite: Sprite2D = $Sprite2D


func apply_damage(amount: int, _hit_direction := Vector2.ZERO) -> void:
	if amount < DETONATION_DAMAGE or is_queued_for_deletion() or is_in_group(DETONATING_GROUP):
		return
	add_to_group(DETONATING_GROUP)
	sprite.frame = 1
	await get_tree().create_timer(DETONATION_DELAY, false).timeout
	queue_free()
	exploded.emit(global_position, BLAST_DAMAGE)
