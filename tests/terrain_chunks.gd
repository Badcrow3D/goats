extends SceneTree
## Run with Godot --headless --path . --script tests/terrain_chunks.gd.

var failed := false

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failed = true

func make_view(art: Image) -> TerrainView:
	var view := TerrainView.new()
	view.setup(Terrain.from_image(art), art)
	return view

func _initialize() -> void:
	var art := Image.create_empty(259, 184, false, Image.FORMAT_RGBA8)
	art.fill(Color.WHITE)
	var source := make_view(art)
	var replica := make_view(art)
	var corner := Vector2i(128, 128)
	var crater := source.blast(corner, 2, 0, Color.BLACK)
	check(crater.erased_pixels == 12, "Half-pixel-centered crater spans four chunks")
	check(source.terrain.rect_is_free(127, 127, 2, 2), "Body spans four carved chunks")
	check(not source.terrain.rect_is_free(125, 125, 3, 3), "Body encounters surviving terrain")
	check(source.terrain.rect_is_free(-2, -2, 2, 2), "Outside level counts as air")
	source.blast(Vector2i(254, 182), 1, 4, Color.BLACK)
	var edge := source.snapshot(Vector2i(2, 1))
	check(edge.mask.size() == 3 * 56 and edge.revision == 1, "Scorch-only partial chunk")
	check(edge.mask.count(1) == edge.mask.size(), "Scorch preserves solidity")
	check(edge.rgba.count(0) > 0, "Scorch changes artwork")
	var dirt: Dictionary[Vector2i, Color] = {corner: Color8(65, 95, 13, 17)}
	source.deposit(dirt)
	check(source.terrain.is_solid(128, 128), "Translucent dirt is immediately solid")
	var state := source.snapshot(Vector2i.ONE)
	check(state.mask[0] == 1 and state.rgba[3] == 17, "Snapshot preserves independent solidity")
	var opaque: Dictionary[Vector2i, Color] = {Vector2i(220, 170): Color.WHITE}
	source.deposit(opaque)
	source.blast(Vector2i(-100, -100), 4, 2, Color.BLACK)
	check(source.snapshot(Vector2i.ONE).revision == state.revision, "No-op edits preserve revision")
	source.flush_uploads()
	for y in source.terrain.rows:
		for x in source.terrain.columns:
			var id := Vector2i(x, y)
			var current := source.snapshot(id)
			if current.revision > 0:
				check(replica.apply_snapshot(current), "Apply newer snapshot")
				check(not replica.apply_snapshot(current), "Ignore duplicate snapshot")
			var copy := replica.snapshot(id)
			check(copy.rgba == current.rgba and copy.mask == current.mask, "Snapshot round trip")
	art.set_pixel(0, 0, Color.RED)
	var different := make_view(art)
	check(not different.apply_snapshot(state), "Reject snapshots from another level")
	different.free()
	source.free()
	replica.free()
	if not failed:
		print("Terrain chunk regressions passed")
	quit(1 if failed else 0)
