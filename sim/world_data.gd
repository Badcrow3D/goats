class_name WorldData
extends RefCounted

var players: Array[PlayerData] = []
var current_level: LevelData

func get_player(id: int) -> PlayerData:
	for p in players:
		if p.id == id:
			return p
	return null
