extends CanvasLayer

const Goat := preload("res://goats/goat.gd")
const NAMEPLATE_SCALE := Vector2(2, 2)

var _anchors: Dictionary[Goat, Vector2] = {}


func track_goat(goat: Goat) -> void:
	var plate := goat.nameplate
	var bottom_center := Vector2(plate.size.x * 0.5, plate.size.y)
	_anchors[goat] = plate.position + bottom_center
	plate.reparent(self, false)
	plate.scale = NAMEPLATE_SCALE
	goat.tree_exiting.connect(_remove_goat.bind(goat), CONNECT_ONE_SHOT)
	_position_nameplate(goat, _anchors[goat])


func _process(_delta: float) -> void:
	for goat in _anchors:
		_position_nameplate(goat, _anchors[goat])


func _position_nameplate(goat: Goat, anchor: Vector2) -> void:
	var plate := goat.nameplate
	var screen_anchor := goat.get_global_transform_with_canvas() * anchor
	var bottom_center := Vector2(plate.size.x * 0.5, plate.size.y)
	plate.position = (screen_anchor - bottom_center * plate.scale).round()


func _remove_goat(goat: Goat) -> void:
	_anchors.erase(goat)
	if is_instance_valid(goat.nameplate):
		goat.nameplate.queue_free()
