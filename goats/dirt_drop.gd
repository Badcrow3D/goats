extends Sprite2D

signal deposited(grains: Dictionary[Vector2i, Color])

var terrain_view: TerrainView
var gravity: float
var max_spread_time: float
var max_diagonal_steps: int
var velocity := Vector2.ZERO
var grains: Dictionary[Vector2i, Color] = {}
var sideways_steps: Dictionary[Vector2i, int] = {}
var impact_x: int
var settle_elapsed := 0.0
var scan_left_to_right := true

func _ready() -> void:
	set_process(false)

func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	var motion := velocity * delta
	var terrain := terrain_view.terrain
	# Sample the center at most one terrain pixel apart, as with missiles.
	var steps := maxi(1, ceili(motion.length()))
	for step in range(steps + 1):
		var pixel := Vector2i((position + motion * (float(step) / steps)).floor())
		if terrain.is_solid(pixel.x, pixel.y):
			_begin_settling(pixel)
			return
	position += motion
	var half_width := texture.get_width() * 0.5
	if (
		position.y - texture.get_height() * 0.5 >= terrain.height
		or (velocity.x < 0.0 and position.x + half_width <= 0.0)
		or (velocity.x > 0.0 and position.x - half_width >= terrain.width)
	):
		queue_free()

func _begin_settling(center: Vector2i) -> void:
	var stamp := texture.get_image()
	var top_left := center - stamp.get_size() / 2
	var terrain := terrain_view.terrain
	for y in stamp.get_height():
		for x in stamp.get_width():
			var pixel := top_left + Vector2i(x, y)
			var color := stamp.get_pixel(x, y)
			if color.a > 0.0 and pixel.x >= 0 and pixel.x < terrain.width and pixel.y < terrain.height:
				grains[pixel] = color
	impact_x = center.x
	position = Vector2.ZERO
	texture = null
	show_behind_parent = true
	set_physics_process(false)
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var first_frame := settle_elapsed == 0.0
	settle_elapsed += delta
	if first_frame:
		return
	# Give each grain at most one move per frame, starting with the bottom layer.
	var can_spread := settle_elapsed < max_spread_time
	var pixels := grains.keys()
	pixels.sort_custom(_settle_order)
	var terrain := terrain_view.terrain
	var blocked: Array[Vector2i] = []
	var moved := false
	for pixel: Vector2i in pixels:
		if terrain.is_solid(pixel.x, pixel.y):
			continue
		var target := pixel + Vector2i.DOWN
		if _cell_is_free(target):
			_move_grain(pixel, target)
			moved = true
		elif can_spread and sideways_steps.get(pixel, 0) < max_diagonal_steps:
			blocked.append(pixel)
	# Falling grains get first claim on each cell before sideways spreading.
	for pixel in blocked:
		var target := pixel + Vector2i.DOWN
		if _cell_is_free(target):
			continue # The grain below moved diagonally. Fall on the next pass.
		var outward := -1 if pixel.x < impact_x else 1
		target.x += outward
		if not _cell_is_free(target):
			target.x -= 2 * outward
			if not _cell_is_free(target):
				continue
		_move_grain(pixel, target)
		moved = true
	scan_left_to_right = not scan_left_to_right
	if not moved:
		terrain_view.deposit(grains)
		deposited.emit(grains)
		queue_free()
	elif moved:
		queue_redraw()

func _move_grain(from: Vector2i, to: Vector2i) -> void:
	if to.y < terrain_view.terrain.height:
		grains[to] = grains[from]
		sideways_steps[to] = sideways_steps.get(from, 0) + absi(to.x - from.x)
	grains.erase(from)
	sideways_steps.erase(from)

func _settle_order(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y > b.y
	return a.x < b.x if scan_left_to_right else a.x > b.x

func _cell_is_free(pixel: Vector2i) -> bool:
	var terrain := terrain_view.terrain
	return (
		pixel.x >= 0 and pixel.x < terrain.width
		and not terrain.is_solid(pixel.x, pixel.y)
		and not grains.has(pixel)
	)

func _draw() -> void:
	for pixel: Vector2i in grains:
		draw_rect(Rect2(Vector2(pixel), Vector2.ONE), grains[pixel])
