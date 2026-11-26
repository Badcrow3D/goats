class_name TerrainView
extends Node2D

@onready var level_preview: Sprite2D = get_node_or_null("LevelPreview")

class Tile:
	var image: Image
	var texture: ImageTexture

class Snapshot:
	var level_hash: PackedByteArray
	var id: Vector2i
	var revision: int
	var mask: PackedByteArray
	var rgba: PackedByteArray

var terrain: Terrain
var _tiles: Dictionary[Vector2i, Tile] = {}
var _dirty: Dictionary[Vector2i, bool] = {}
var _art_layer: Node2D
var _level_hash: PackedByteArray

func _enter_tree() -> void:
	RenderingServer.frame_pre_draw.connect(flush_uploads)

func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(flush_uploads)

func setup(p_terrain: Terrain, art: Image) -> void:
	if level_preview:
		level_preview.hide()
	if _art_layer:
		_art_layer.free()
	_tiles.clear()
	_dirty.clear()
	terrain = p_terrain
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(PackedInt32Array([terrain.width, terrain.height]).to_byte_array())
	hash_context.update(art.get_data())
	_level_hash = hash_context.finish()
	_art_layer = Node2D.new()
	add_child(_art_layer)
	move_child(_art_layer, 0)
	for chunk in terrain.chunks:
		var tile := Tile.new()
		tile.image = art.get_region(chunk.bounds)
		tile.texture = ImageTexture.create_from_image(tile.image)
		_tiles[chunk.bounds.position / Terrain.CHUNK_SIZE] = tile
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position = chunk.bounds.position
		sprite.texture = tile.texture
		_art_layer.add_child(sprite)

func flush_uploads() -> void:
	for id in _dirty:
		var tile := _tiles[id]
		tile.texture.update(tile.image)
	_dirty.clear()

func _commit(id: Vector2i) -> void:
	terrain.chunk_at(id).revision += 1
	_dirty[id] = true

## Collision is carved first. Scorch and transparent-air cleanup share one commit.
func blast(center: Vector2i, radius: int, scorch_width: int, color: Color) -> Terrain.Crater:
	var crater := terrain.carve_circle(center.x, center.y, radius, true)
	var outer := radius + maxi(0, scorch_width)
	var extent := Vector2i.ONE * outer
	var rect := Rect2i(center - extent, extent * 2)
	var span := terrain.chunk_range(rect)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var id := Vector2i(cx, cy)
			var chunk := terrain.chunk_at(id)
			var region := chunk.bounds.intersection(rect)
			var image := _tiles[id].image
			var changed := crater.changed.has(id)
			for y in range(region.position.y, region.end.y):
				for x in range(region.position.x, region.end.x):
					var pixel := Vector2i(x, y)
					var local := pixel - chunk.bounds.position
					var existing := image.get_pixelv(local)
					var result := existing
					if chunk.mask[chunk.index_at(x, y)] == 0:
						if crater.bounds.has_point(pixel):
							result = Color(0, 0, 0, 0)
					elif scorch_width > 0:
						var offset := (pixel - center) * 2 + Vector2i.ONE
						if offset.length_squared() <= 4 * outer * outer:
							result = Color(color, existing.a)
					if result.to_rgba32() != existing.to_rgba32():
						image.set_pixelv(local, result)
						changed = true
			if changed:
				_commit(id)
	return crater

func deposit(grains: Dictionary[Vector2i, Color]) -> void:
	var changed: Dictionary[Vector2i, bool] = {}
	for pixel in grains:
		if not terrain.in_bounds(pixel.x, pixel.y):
			continue
		var id := pixel / Terrain.CHUNK_SIZE
		var local := pixel - id * Terrain.CHUNK_SIZE
		var image := _tiles[id].image
		var existing := image.get_pixelv(local)
		var added := terrain.add_solid(pixel)
		var blended := grains[pixel].blend(existing)
		if existing.to_rgba32() != blended.to_rgba32():
			image.set_pixelv(local, blended)
			changed[id] = true
		elif added:
			changed[id] = true
	for id in changed:
		_commit(id)

func snapshot(id: Vector2i) -> Snapshot:
	if not _tiles.has(id):
		return null
	var chunk := terrain.chunk_at(id)
	var state := Snapshot.new()
	state.level_hash = _level_hash.duplicate()
	state.id = id
	state.revision = chunk.revision
	state.mask = chunk.mask.duplicate()
	state.rgba = _tiles[id].image.get_data()
	return state

## Snapshots belong to the same base level. Accept only a newer complete revision.
func apply_snapshot(state: Snapshot) -> bool:
	if state == null or state.level_hash != _level_hash or not _tiles.has(state.id):
		return false
	var chunk := terrain.chunk_at(state.id)
	var size := chunk.bounds.size
	if state.revision <= chunk.revision or state.mask.size() != size.x * size.y or state.rgba.size() != size.x * size.y * 4:
		return false
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, state.rgba)
	chunk.mask = state.mask.duplicate()
	chunk.revision = state.revision
	_tiles[state.id].image = image
	_dirty[state.id] = true
	return true
