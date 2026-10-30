class_name LevelData
extends RefCounted

var collision_map: Terrain
var terrain_color: Color
var background_color: Color

func _init(p_map: Terrain, p_terrain_color: Color = Color(0.55, 0.36, 0.2), p_background_color: Color = Color(0.45, 0.7, 0.95)) -> void:
	collision_map = p_map
	terrain_color = p_terrain_color
	background_color = p_background_color
