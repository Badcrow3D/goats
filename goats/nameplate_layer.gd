extends CanvasLayer

const Goat := preload("res://goats/goat.gd")
const MAX_PLATE_SCALE := 2
const PLATE_GAP := 4.0
const ACTIVE_GOAT_PLATE_MARGIN := 10.0
const PLATE_REAPPEAR_DELAY := 1.0
const ACTIVE_PLATE_BOTTOM_MARGIN := 12.0

var active_goat: Goat
var show_active_goat_hud := true

var _anchors: Dictionary[Goat, Vector2] = {}
var _clear_elapsed: Dictionary[Goat, float] = {}
var _last_rects: Dictionary[Goat, Rect2] = {}
var _last_view := Rect2()
var _last_hud_rect := Rect2()
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


func _process(delta: float) -> void:
	if not visible:
		_clear_elapsed.clear()
		return
	_layout_plates()
	if not is_instance_valid(active_goat):
		return
	var goat_to_screen := active_goat.get_global_transform_with_canvas()
	var nearby := (goat_to_screen * Rect2(active_goat.bitmap_body_rect())).grow(ACTIVE_GOAT_PLATE_MARGIN)
	for goat in _anchors:
		var plate := goat.nameplate
		if goat == active_goat or not plate.visible:
			plate.modulate.a = 1.0
			_clear_elapsed.erase(goat)
			continue
		var plate_rect := Rect2(plate.position, plate.size * plate.scale)
		if nearby.intersects(plate_rect):
			plate.modulate.a = 0.0
			_clear_elapsed.erase(goat)
			continue
		if plate.modulate.a != 0.0:
			continue
		var elapsed: float = _clear_elapsed.get(goat, -delta) + delta
		if elapsed >= PLATE_REAPPEAR_DELAY:
			plate.modulate.a = 1.0
			_clear_elapsed.erase(goat)
		else:
			_clear_elapsed[goat] = elapsed


func _layout_plates() -> void:
	var view := get_viewport().get_visible_rect()
	var occupied: Array[Rect2] = []
	if show_active_goat_hud and is_instance_valid(active_goat) and _anchors.has(active_goat):
		var plate := active_goat.nameplate
		var size := plate.size * plate.scale
		plate.position = Vector2(view.get_center().x - size.x * 0.5,
				view.end.y - ACTIVE_PLATE_BOTTOM_MARGIN - size.y).round()
		plate.show()
		occupied.append(Rect2(plate.position, size).grow(PLATE_GAP))
	var rects: Dictionary[Goat, Rect2] = {}
	for goat in _anchors:
		if show_active_goat_hud and goat == active_goat:
			continue
		if not goat.nameplate.visible:
			continue
		var rect := _preferred_rect(goat)
		if view.intersects(rect) or view.has_point(goat.get_global_transform_with_canvas().origin):
			rects[goat] = rect
		else:
			goat.nameplate.position = rect.position
	var hud_rect := occupied[0] if not occupied.is_empty() else Rect2()
	if rects == _last_rects and view == _last_view and hud_rect == _last_hud_rect:
		return
	_last_rects = rects
	_last_view = view
	_last_hud_rect = hud_rect
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
	# Keep the natural height even if the camera clips the plate at the top.
	var origin := Vector2(clampf(rect.position.x, view.position.x, limit.x), minf(rect.position.y, limit.y))
	var min_y := minf(view.position.y, origin.y)
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
		ys.append(clampf(obstacle.position.y - rect.size.y, min_y, origin.y))
		ys.append(clampf(obstacle.end.y, min_y, origin.y))
	if clear:
		return origin

	var best := origin
	var best_overlap := INF
	var best_cost := INF
	for y: float in ys:
		for x: float in xs:
			rect.position = Vector2(x, y)
			var rect_offset := rect.position - origin
			# Prefer raising a plate over an equally long sideways move.
			var cost := rect_offset.length_squared() + 0.5 * rect_offset.x ** 2
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
	_clear_elapsed.erase(goat)
	if is_instance_valid(goat.nameplate):
		goat.nameplate.queue_free()
