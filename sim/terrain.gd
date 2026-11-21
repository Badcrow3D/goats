class_name Terrain
extends RefCounted
## Terrain as a bitmap mask: one byte per pixel, 0 = air, 1 = solid.
## Integer-only, so it is fully deterministic.

var width: int
var height: int
var mask: PackedByteArray

class Crater:
	var bounds: Rect2i
	var erased_pixels := 0

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

## First solid pixel from the top of a column (height if the column is empty).
func surface_y(x: int) -> int:
	for y in height:
		if is_solid(x, y):
			return y
	return height

## Removes a filled circle and reports its bounds and the number of solid pixels erased.
func carve_circle(cx: int, cy: int, r: int, center_between_pixels := false) -> Crater:
	# Use doubled coordinates to sample half-pixel offsets with integer math.
	var offset := 1 if center_between_pixels else 0
	var r2 := 4 * r * r
	var diameter := 2 * r + 1 - offset
	var rect := Rect2i(cx - r, cy - r, diameter, diameter).intersection(Rect2i(0, 0, width, height))
	var crater := Crater.new()
	crater.bounds = rect
	for y in range(rect.position.y, rect.end.y):
		var dy := 2 * (y - cy) + offset
		for x in range(rect.position.x, rect.end.x):
			var dx := 2 * (x - cx) + offset
			var index := y * width + x
			if dx * dx + dy * dy <= r2 and mask[index] != 0:
				mask[index] = 0
				crater.erased_pixels += 1
	return crater

func rect_is_free(x: int, y: int, w: int, h: int) -> bool:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if is_solid(xx, yy):
				return false
	return true

## Builds the collision mask from an image: alpha >= threshold = solid.
## Integer compare on the raw alpha byte, so the same PNG always gives the same mask.
static func from_image(img: Image, alpha_threshold: int = 128) -> Terrain:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = img.duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
	var t := Terrain.new(src.get_width(), src.get_height())
	var data := src.get_data()   # RGBA8: alpha is every 4th byte
	for i in t.width * t.height:
		if data[i * 4 + 3] >= alpha_threshold:
			t.mask[i] = 1
	return t

## Rendering helper: makes every pixel in rect that is now air fully transparent,
## leaving the artwork of the remaining terrain untouched.
func erase_image_region(img: Image, rect: Rect2i) -> void:
	var clear := Color(0, 0, 0, 0)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if mask[y * width + x] == 0:
				img.set_pixel(x, y, clear)
