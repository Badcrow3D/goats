class_name TerrainView
extends Node2D
## Draws the terrain artwork and keeps it in sync with the collision mask.
## All art handling lives here, so splitting the art into cells later
## only changes this file (the sim never sees it).

var terrain: Terrain
var image: Image          # RGBA8 artwork; air pixels are transparent
var texture: ImageTexture

func setup(p_terrain: Terrain, art: Image) -> void:
	terrain = p_terrain
	image = art
	texture = ImageTexture.create_from_image(image)
	queue_redraw()

## Call after the sim carves terrain.
func carve(rect: Rect2i) -> void:
	terrain.erase_image_region(image, rect)
	texture.update(image)
	queue_redraw()

func _draw() -> void:
	draw_texture(texture, Vector2.ZERO)
