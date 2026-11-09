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

## Call after the sim carves terrain.
func carve(rect: Rect2i) -> void:
	terrain.erase_image_region(image, rect)
	(texture as ImageTexture).update(image)
