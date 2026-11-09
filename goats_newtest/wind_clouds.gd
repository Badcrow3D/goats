extends MultiMeshInstance2D

const CLOUD_TEXTURE := preload("res://sprites/clouds64x32.png")
const CLOUD_SHADER := preload("res://goats_newtest/instanced_sprite_sheet.gdshader")
const CLOUD_SIZE := Vector2(128, 64)
const CLOUD_COUNT := 10

@export_range(0.0, 1.0, 0.0025) var scroll_factor := 0.175

func setup(arena_bounds: Rect2) -> void:
	var half_size := CLOUD_SIZE * 0.5
	var cloud_area := Rect2(arena_bounds.position, Vector2(arena_bounds.size.x, arena_bounds.size.y * (1.0 / 3.0)))
	var top := arena_bounds.position.y + half_size.y
	var bottom := cloud_area.end.y - half_size.y
	cloud_area.position = to_local(cloud_area.position)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, cloud_area.grow(1.0))

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
	multimesh.mesh = quad
	multimesh.instance_count = CLOUD_COUNT

	for index in CLOUD_COUNT:
		var x := randf_range(arena_bounds.position.x + half_size.x, arena_bounds.end.x - half_size.x)
		var origin := to_local(Vector2(x, randf_range(top, bottom)).round())
		multimesh.set_instance_transform_2d(index, Transform2D(0.0, origin))
	set_wind(0.0)


func set_wind(strength: float) -> void:
	multimesh.visible_instance_count = roundi(absf(strength) * CLOUD_COUNT)


func update_parallax(camera_offset: Vector2) -> void:
	position = -camera_offset * scroll_factor
