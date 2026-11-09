extends MultiMeshInstance2D

const CLOUD_TEXTURE := preload("res://sprites/clouds64x32.png")
const CLOUD_SHADER := preload("res://goats_newtest/instanced_sprite_sheet.gdshader")
const CLOUD_SIZE := Vector2(64, 32)
const CLOUD_COUNT := 10

var cloud_positions := PackedVector2Array()
var speed_multipliers := PackedFloat32Array()
var left_edge := 0.0
var right_edge := 0.0
var drift_speed := 0.0


func setup(arena_bounds: Rect2) -> void:
	var half_size := CLOUD_SIZE * 0.5
	left_edge = arena_bounds.position.x - half_size.x
	right_edge = arena_bounds.end.x + half_size.x
	var top := arena_bounds.position.y + half_size.y
	var bottom := arena_bounds.position.y + arena_bounds.size.y / 3.0 - half_size.y

	texture = CLOUD_TEXTURE
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("sheet_grid", Vector2i(1, 6))
	# The first cell contains a dot. The five cloud sprites start in the second cell.
	cloud_material.set_shader_parameter("first_frame", 1)
	cloud_material.set_shader_parameter("frame_count", 5)
	material = cloud_material

	var quad := QuadMesh.new()
	quad.size = CLOUD_SIZE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = CLOUD_COUNT

	cloud_positions.resize(CLOUD_COUNT)
	speed_multipliers.resize(CLOUD_COUNT)
	for index in CLOUD_COUNT:
		var fraction := (index + 0.5) / CLOUD_COUNT
		var x := lerpf(arena_bounds.position.x, arena_bounds.end.x, fraction)
		cloud_positions[index] = Vector2(x, randf_range(top, bottom))
		speed_multipliers[index] = randf_range(0.9, 1.1)
		multimesh.set_instance_color(index, Color(1.0, 1.0, 1.0, randf_range(0.55, 0.75)))
		_update_instance_transform(index)
	set_wind(0.0, 0.0)


func set_wind(strength: float, leaf_drift_speed: float) -> void:
	drift_speed = leaf_drift_speed * 0.25
	multimesh.visible_instance_count = roundi(absf(strength) * CLOUD_COUNT)
	set_process(multimesh.visible_instance_count > 0)


func _process(delta: float) -> void:
	for index in multimesh.visible_instance_count:
		var position_next := cloud_positions[index]
		var distance := drift_speed * speed_multipliers[index] * delta
		position_next.x = wrapf(position_next.x + distance, left_edge, right_edge)
		cloud_positions[index] = position_next
		_update_instance_transform(index)


func _update_instance_transform(index: int) -> void:
	var origin := to_local(cloud_positions[index].round())
	multimesh.set_instance_transform_2d(index, Transform2D(0.0, origin))
