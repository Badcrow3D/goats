extends CanvasLayer

const Goat := preload("res://goats/goat.gd")
const MAX_PLATE_SCALE := 2
const PLATE_GAP := 4.0

var _anchors: Dictionary[Goat, Vector2] = {}
var _last_rects: Dictionary[Goat, Rect2] = {}
var _last_view := Rect2()
var _plate_scale := MAX_PLATE_SCALE


func track_goat(goat: Goat) -> void:
	var plate := goat.nameplate
	var bottom_center := Vector2(plate.size.x * 0.5, plate.size.y)
	_anchors[goat] = plate.position + bottom_center
	plate.reparent(self, false)
	plate.scale = Vector2.ONE * maxi(_plate_scale, 1)
	goat.tree_exiting.connect(_remove_goat.bind(goat), CONNECT_ONE_SHOT)
	plate.position = _preferred_rect(goat).position


func cycle_size() -> void:
	_plate_scale = wrapi(_plate_scale - 1, 0, MAX_PLATE_SCALE + 1)
	visible = _plate_scale > 0
	if visible:
		for goat in _anchors:
			goat.nameplate.scale = Vector2.ONE * _plate_scale


func _process(_delta: float) -> void:
	if not visible:
		return
	var view := get_viewport().get_visible_rect()
	var rects: Dictionary[Goat, Rect2] = {}
	for goat in _anchors:
		if not goat.nameplate.visible:
			continue
		var rect := _preferred_rect(goat)
		if view.intersects(rect) or view.has_point(goat.get_global_transform_with_canvas().origin):
			rects[goat] = rect
		else:
			goat.nameplate.position = rect.position
	if rects == _last_rects and view == _last_view:
		return
	_last_rects = rects
	_last_view = view

	var occupied: Array[Rect2] = []
	for goat in rects:
		var rect := rects[goat]
		rect.position = _place_plate(rect, view, occupied)
		goat.nameplate.position = rect.position
		occupied.append(rect.grow(PLATE_GAP))


func _preferred_rect(goat: Goat) -> Rect2:
	var plate := goat.nameplate
	var screen_anchor := goat.get_global_transform_with_canvas() * _anchors[goat]
	var size := plate.size * plate.scale
	return Rect2((screen_anchor - Vector2(size.x * 0.5, size.y)).round(), size)


func _place_plate(rect: Rect2, view: Rect2, occupied: Array[Rect2]) -> Vector2:
	var limit := (view.end - rect.size).max(view.position)
	var origin := rect.position.clamp(view.position, limit)
	rect.position = origin
	var xs := [origin.x]
	var ys := [origin.y]
	var clear := true
	for obstacle in occupied:
		if rect.intersects(obstacle):
			clear = false
		# A closest free position can sit flush against any earlier plate.
		xs.append(clampf(obstacle.position.x - rect.size.x, view.position.x, limit.x))
		xs.append(clampf(obstacle.end.x, view.position.x, limit.x))
		ys.append(clampf(obstacle.position.y - rect.size.y, view.position.y, limit.y))
		ys.append(clampf(obstacle.end.y, view.position.y, limit.y))
	if clear:
		return origin

	var best := origin
	var best_overlap := INF
	var best_cost := INF
	for y: float in ys:
		for x: float in xs:
			rect.position = Vector2(x, y)
			var offset := rect.position - origin
			# Prefer vertical separation and keep labels above their goats when possible.
			var cost := offset.length_squared() + 0.5 * offset.x ** 2 + maxf(offset.y, 0.0) ** 2
			if best_overlap == 0.0 and cost >= best_cost:
				continue
			var overlap := 0.0
			for obstacle in occupied:
				overlap += rect.intersection(obstacle).get_area()
			if overlap < best_overlap or (overlap == best_overlap and cost < best_cost):
				best = rect.position
				best_overlap = overlap
				best_cost = cost
	return best


func _remove_goat(goat: Goat) -> void:
	_anchors.erase(goat)
	if is_instance_valid(goat.nameplate):
		goat.nameplate.queue_free()
