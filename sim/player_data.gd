class_name PlayerData
extends RefCounted

var id: int
var name: String
var location: Vector2i   # pixel position (feet), in terrain coordinates
var health: int

func _init(p_id: int, p_name: String, p_location: Vector2i, p_health: int = 100) -> void:
	id = p_id
	name = p_name
	location = p_location
	health = p_health
