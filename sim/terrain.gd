class_name Terrain
extends RefCounted

const CHUNK_SIZE := 128

class Chunk:
	var bounds: Rect2i
	var mask := PackedByteArray()
	var revision := 0

	func index_at(x: int, y: int) -> int:
		return (y - bounds.position.y) * bounds.size.x + x - bounds.position.x

class Crater:
	var bounds: Rect2i
	var erased_pixels := 0
	var changed: Dictionary[Vector2i, bool] = {}

var width: int
var height: int
var columns: int
var rows: int
var chunks: Array[Chunk] = []

func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	columns = ceili(float(width) / CHUNK_SIZE)
	rows = ceili(float(height) / CHUNK_SIZE)
	for cy in rows:
		for cx in columns:
			var chunk := Chunk.new()
			var origin := Vector2i(cx, cy) * CHUNK_SIZE
			var size := Vector2i(mini(CHUNK_SIZE, width - origin.x), mini(CHUNK_SIZE, height - origin.y))
			chunk.bounds = Rect2i(origin, size)
			chunk.mask.resize(chunk.bounds.get_area())
			chunks.append(chunk)

func chunk_at(id: Vector2i) -> Chunk:
	return chunks[id.y * columns + id.x]

## Returns chunk coordinates covering the in-bounds portion of a pixel rectangle.
func chunk_range(rect: Rect2i) -> Rect2i:
	var clipped := rect.intersection(Rect2i(0, 0, width, height))
	if not clipped.has_area():
		return Rect2i()
	@warning_ignore("integer_division")
	var first := clipped.position / CHUNK_SIZE
	@warning_ignore("integer_division")
	var last := (clipped.end - Vector2i.ONE) / CHUNK_SIZE
	return Rect2i(first, last - first + Vector2i.ONE)

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func is_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	@warning_ignore("integer_division")
	var chunk := chunks[(y / CHUNK_SIZE) * columns + x / CHUNK_SIZE]
	return chunk.mask[(y % CHUNK_SIZE) * chunk.bounds.size.x + x % CHUNK_SIZE] != 0

func surface_y(x: int) -> int:
	if x < 0 or x >= width:
		return height
	for cy in rows:
		@warning_ignore("integer_division")
		var chunk := chunks[cy * columns + x / CHUNK_SIZE]
		var i := x % CHUNK_SIZE
		for y in chunk.bounds.size.y:
			if chunk.mask[i] != 0:
				return chunk.bounds.position.y + y
			i += chunk.bounds.size.x
	return height

func rect_is_free(x: int, y: int, w: int, h: int) -> bool:
	var rect := Rect2i(x, y, w, h)
	var span := chunk_range(rect)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var chunk := chunk_at(Vector2i(cx, cy))
			var region := chunk.bounds.intersection(rect)
			for yy in range(region.position.y, region.end.y):
				var start := chunk.index_at(region.position.x, yy)
				for i in range(start, start + region.size.x):
					if chunk.mask[i] != 0:
						return false
	return true

func carve_circle(cx: int, cy: int, r: int, center_between_pixels := false) -> Crater:
	var offset := 1 if center_between_pixels else 0
	var radius_squared := 4 * r * r
	var diameter := 2 * r + 1 - offset
	var crater := Crater.new()
	crater.bounds = Rect2i(cx - r, cy - r, diameter, diameter).intersection(Rect2i(0, 0, width, height))
	var span := chunk_range(crater.bounds)
	for y in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			var id := Vector2i(x, y)
			var chunk := chunk_at(id)
			var region := chunk.bounds.intersection(crater.bounds)
			var before := crater.erased_pixels
			for yy in range(region.position.y, region.end.y):
				var dy := 2 * (yy - cy) + offset
				var i := chunk.index_at(region.position.x, yy)
				for xx in range(region.position.x, region.end.x):
					var dx := 2 * (xx - cx) + offset
					if dx * dx + dy * dy <= radius_squared and chunk.mask[i] != 0:
						chunk.mask[i] = 0
						crater.erased_pixels += 1
					i += 1
			if before != crater.erased_pixels:
				crater.changed[id] = true
	return crater

func add_solid(pixel: Vector2i) -> bool:
	if not in_bounds(pixel.x, pixel.y):
		return false
	@warning_ignore("integer_division")
	var chunk := chunk_at(pixel / CHUNK_SIZE)
	var i := chunk.index_at(pixel.x, pixel.y)
	if chunk.mask[i] != 0:
		return false
	chunk.mask[i] = 1
	return true

func remove_solid(pixel: Vector2i) -> bool:
	if not in_bounds(pixel.x, pixel.y):
		return false
	@warning_ignore("integer_division")
	var chunk := chunk_at(pixel / CHUNK_SIZE)
	var i := chunk.index_at(pixel.x, pixel.y)
	if chunk.mask[i] == 0:
		return false
	chunk.mask[i] = 0
	return true


static func from_image(img: Image, alpha_threshold := 128) -> Terrain:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = img.duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
	var t := Terrain.new(src.get_width(), src.get_height())
	for chunk in t.chunks:
		var data := src.get_region(chunk.bounds).get_data()
		var mask := PackedByteArray()
		mask.resize(chunk.bounds.get_area())
		for i in mask.size():
			mask[i] = int(data[i * 4 + 3] >= alpha_threshold)
		chunk.mask = mask
	return t
