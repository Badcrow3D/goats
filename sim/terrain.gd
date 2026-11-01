class_name Terrain
extends RefCounted
## Terrain as a bitmap mask: one byte per pixel, 0 = air, 1 = solid.
## Integer-only, so it is fully deterministic.

var width: int
var height: int
var mask: PackedByteArray

func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	mask = PackedByteArray()
	mask.resize(width * height)   # zero-filled

## Out of bounds counts as air; the projectile handles leaving the world itself.
func is_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	return mask[y * width + x] != 0

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Simple seeded rolling hills (RandomNumberGenerator is deterministic per seed).
func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	@warning_ignore("integer_division")
	var lo: int = height / 3
	@warning_ignore("integer_division")
	var hi: int = height * 5 / 6
	@warning_ignore("integer_division")
	var h: int = height * 6 / 10
	var slope: int = 0
	for x in width:
		if rng.randi_range(0, 3) == 0:
			slope = clampi(slope + rng.randi_range(-1, 1), -2, 2)
		h = clampi(h + slope, lo, hi)
		if h == lo or h == hi:
			slope = -slope
		for y in range(h, height):
			mask[y * width + x] = 1

## First solid pixel from the top of a column (height if the column is empty).
func surface_y(x: int) -> int:
	for y in height:
		if is_solid(x, y):
			return y
	return height

## Removes a filled circle. Returns the affected rect (for partial redraws).
func carve_circle(cx: int, cy: int, r: int) -> Rect2i:
	var r2: int = r * r
	for y in range(maxi(cy - r, 0), mini(cy + r + 1, height)):
		for x in range(maxi(cx - r, 0), mini(cx + r + 1, width)):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r2:
				mask[y * width + x] = 0
	return Rect2i(cx - r, cy - r, r * 2 + 1, r * 2 + 1).intersection(Rect2i(0, 0, width, height))

## Rendering helpers (not part of the simulation).
func make_image(terrain_color: Color, background_color: Color) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(background_color)
	update_image_region(img, Rect2i(0, 0, width, height), terrain_color, background_color)
	return img

func update_image_region(img: Image, rect: Rect2i, terrain_color: Color, background_color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			img.set_pixel(x, y, terrain_color if mask[y * width + x] != 0 else background_color)
			
func rect_is_free(x: int, y: int, w: int, h: int) -> bool:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if is_solid(xx, yy):
				return false
	return true
	
				
