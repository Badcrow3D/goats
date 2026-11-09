class_name TerrainView
extends Sprite2D
## Draws the terrain artwork and keeps it in sync with the collision mask.
## All art handling lives here, so splitting the art into cells later
## only changes this file (the sim never sees it).

var terrain: Terrain
var image: Image          # RGBA8 artwork; air pixels are transparent

func setup(p_terrain: Terrain, art: Image) -> void:
	terrain = p_terrain
	image = art
	centered = false
	texture = ImageTexture.create_from_image(image)

## Recolors surviving terrain in a round stamp centered between pixels.
## The next carve call uploads both changes together.
func scorch_circle(center: Vector2i, radius: int, color: Color) -> void:
	var extent := Vector2i.ONE * radius
	var rect := Rect2i(center - extent, extent * 2).intersection(
		Rect2i(Vector2i.ZERO, image.get_size())
	)
	var radius_squared := 4 * radius * radius
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var offset := (Vector2i(x, y) - center) * 2 + Vector2i.ONE
			if offset.length_squared() <= radius_squared and terrain.is_solid(x, y):
				color.a = image.get_pixel(x, y).a
				image.set_pixel(x, y, color)

## Call after the sim carves terrain.
func carve(rect: Rect2i) -> void:
	terrain.erase_image_region(image, rect)
	(texture as ImageTexture).update(image)
