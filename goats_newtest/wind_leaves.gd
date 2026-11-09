extends MultiMeshInstance2D

const LEAF_TEXTURE := preload("res://sprites/leaf16.png")
const LEAF_SHADER := preload("res://goats_newtest/instanced_sprite_sheet.gdshader")
const LEAF_SIZE := 16
const MAX_LEAVES := 20
const MAX_DRIFT_SPEED := 60.0
const FALL_SPEED := 16.0

@export_range(0.0, 1.0, 0.00125) var scroll_factor := 0.2275

var leaf_positions := PackedVector2Array()
var bounds: Rect2
var drift_speed := 0.0
var elapsed := 0.0


func setup(arena_bounds: Rect2) -> void:
	bounds = arena_bounds.grow(LEAF_SIZE)
	# Leave room for parallax so leaves still wrap beyond the level edges.
	var parallax_padding := arena_bounds.size * (scroll_factor * 0.5)
	bounds.position = to_local(bounds.position) - parallax_padding
	bounds.size += parallax_padding * 2.0
	# Include the entire wrap area and the sprite extents in the canvas bounds.
	var draw_bounds := bounds.grow(LEAF_SIZE)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, draw_bounds)
	texture = LEAF_TEXTURE
	var leaf_material := ShaderMaterial.new()
	leaf_material.shader = LEAF_SHADER
	material = leaf_material
	var quad := QuadMesh.new()
	quad.size = Vector2(LEAF_SIZE, LEAF_SIZE)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = quad
	multimesh.instance_count = MAX_LEAVES
	leaf_positions.resize(MAX_LEAVES)
	for index in MAX_LEAVES:
		leaf_positions[index] = Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)
		)
		_update_instance_transform(index)
	set_wind(0.0)


func set_wind(strength: float) -> void:
	drift_speed = strength * MAX_DRIFT_SPEED
	multimesh.visible_instance_count = roundi(absf(strength) * MAX_LEAVES)
	set_process(multimesh.visible_instance_count > 0)


func update_parallax(camera_offset: Vector2) -> void:
	position = -camera_offset * scroll_factor


func _process(delta: float) -> void:
	elapsed += delta
	for index in multimesh.visible_instance_count:
		var phase := index * 2.4
		var flutter := Vector2(sin(elapsed * 2.3 + phase) * 8.0, cos(elapsed * 1.7 + phase) * 5.0)
		var position_next := leaf_positions[index] + (Vector2(drift_speed, FALL_SPEED) + flutter) * delta
		leaf_positions[index] = Vector2(
			wrapf(position_next.x, bounds.position.x, bounds.end.x),
			wrapf(position_next.y, bounds.position.y, bounds.end.y)
		)
		_update_instance_transform(index)


func _update_instance_transform(index: int) -> void:
	var origin := leaf_positions[index].round()
	multimesh.set_instance_transform_2d(index, Transform2D(0.0, origin))
