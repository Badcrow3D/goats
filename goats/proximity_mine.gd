extends "res://goats/level_item.gd"

const TRIGGER_RADIUS := 24.0 # Terrain pixels
const FRAME_SECONDS := 0.08
const PEAK_DAMAGE := 35
enum Row { IDLE, ARMED, RIGHT, LEFT, ARMED_RIGHT, ARMED_LEFT }

@onready var sprite: Sprite2D = $Sprite2D

var fuse_duration := 0.0
var fuse_elapsed := 0.0
var velocity := Vector2.ZERO
var animation_elapsed := 0.0


func apply_damage(amount: int, hit_direction := Vector2.ZERO) -> void:
	if amount > 0:
		var speed := 30.0 + 3.0 * amount
		velocity = Vector2(hit_direction.normalized().x * speed, -speed)


func _physics_process(delta: float) -> void:
	if terrain_view == null or is_queued_for_deletion():
		return
	_move_mine(delta)
	if fuse_duration == 0.0 and _goat_in_range():
		fuse_duration = randi_range(1, 12) * 0.25
		add_to_group(DETONATING_GROUP)
	if fuse_duration > 0.0:
		fuse_elapsed += delta
		if fuse_elapsed >= fuse_duration:
			queue_free()
			exploded.emit(global_position, PEAK_DAMAGE)
			return
	_update_animation(delta)


func _update_animation(delta: float) -> void:
	var armed := fuse_duration > 0.0
	var row := Row.ARMED if armed else Row.IDLE
	if velocity.x > 0.0:
		row = Row.ARMED_RIGHT if armed else Row.RIGHT
	elif velocity.x < 0.0:
		row = Row.ARMED_LEFT if armed else Row.LEFT
	if row != sprite.frame_coords.y or row == Row.IDLE:
		animation_elapsed = 0.0
	else:
		animation_elapsed += delta
	sprite.frame_coords = Vector2i(floori(animation_elapsed / FRAME_SECONDS) % sprite.hframes, row)


func _goat_in_range() -> bool:
	for hurtbox in get_tree().get_nodes_in_group(&"goat_hurtboxes"):
		if hurtbox.get_parent().health <= 0:
			continue
		var shape_node: CollisionShape2D = hurtbox.collider
		var bounds := shape_node.shape.get_rect()
		var nearest := shape_node.to_local(global_position).clamp(bounds.position, bounds.end)
		var offset := terrain_view.to_local(shape_node.to_global(nearest)) - terrain_view.to_local(global_position)
		if offset.length_squared() <= TRIGGER_RADIUS * TRIGGER_RADIUS:
			return true
	return false


func _move_mine(delta: float) -> void:
	velocity.y += FALL_GRAVITY * delta
	var bounds := collision_bounds_in(terrain_view)
	var foot := Vector2(bounds.get_center().x, bounds.end.y)
	var travel := velocity * delta / terrain_view.global_scale
	var steps := maxi(1, ceili(maxf(absf(travel.x), absf(travel.y))))
	var step := travel / steps
	var start := foot
	for i in steps:
		var next := foot + step
		if terrain_view.terrain.is_solid(floori(next.x), floori(next.y)):
			if step.y >= 0 and floori(next.y) >= floori(foot.y):
				foot.y = floorf(next.y)
			velocity = Vector2.ZERO
			break
		foot = next
	global_position = terrain_view.to_global(terrain_view.to_local(global_position) + foot - start)
	if foot.y - bounds.size.y >= terrain_view.terrain.height and fuse_duration == 0.0:
		queue_free()
