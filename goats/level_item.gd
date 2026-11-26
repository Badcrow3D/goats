extends Area2D

signal exploded(center: Vector2, damage: int)

const COLLISION_MASK := 1 << 3
const DETONATING_GROUP := &"detonating_level_items"
const FALL_GRAVITY := 400.0

@onready var collider: CollisionShape2D = $CollisionShape2D

var terrain_view: TerrainView
var fall_speed := 0.0


func apply_damage(_amount: int, _hit_direction := Vector2.ZERO) -> void:
	pass


func _physics_process(delta: float) -> void:
	if terrain_view == null or is_queued_for_deletion():
		return
	var terrain := terrain_view.terrain
	var to_terrain := terrain_view.global_transform.affine_inverse() * collider.global_transform
	var bounds := collider.shape.get_rect()
	var foot := to_terrain * Vector2(bounds.get_center().x, bounds.end.y)
	fall_speed += FALL_GRAVITY * delta
	var fall_distance := fall_speed * delta / terrain_view.global_scale.y
	var x := floori(foot.x)
	var first_row := maxi(0, floori(foot.y))
	var last_row := mini(terrain.height - 1, floori(foot.y + fall_distance))
	# Check each crossed pixel in the bottom-center column to catch one-pixel ledges.
	for y in range(first_row, last_row + 1):
		if terrain.is_solid(x, y):
			_move_down(float(y) - foot.y)
			fall_speed = 0.0
			return
	_move_down(fall_distance)
	if (to_terrain * bounds).position.y + fall_distance >= terrain.height and not is_in_group(DETONATING_GROUP):
		queue_free()


func _move_down(distance: float) -> void:
	global_position = terrain_view.to_global(terrain_view.to_local(global_position) + Vector2(0.0, distance))
