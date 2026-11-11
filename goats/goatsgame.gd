extends "res://goats/goat_controller.gd"

const Goat := preload("res://goats/goat.gd")
const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const CloudLayer := preload("res://goats/wind_clouds.gd")
const DIRT_TEXTURE := preload("res://sprites/dirt.png")
const DIRT_GRAVITY := 400.0
const CAMERA_DRAG_THRESHOLD := 4.0
const CAPTURED_MOUSE_SENSITIVITY := 2.0

class CameraControls extends Node:
	signal input_received(event: InputEvent)

	func _input(event: InputEvent) -> void:
		input_received.emit(event)


class Team:
	var id: int
	var team_name: String
	var color: Color
	var goats: Array[Goat] = []

	func _init(team_id: int, display_name: String, team_color: Color) -> void:
		id = team_id
		team_name = display_name
		color = team_color


class DirtDrop extends Sprite2D:
	signal deposited(grains: Dictionary[Vector2i, Color])

	var terrain_view: TerrainView
	var gravity: float
	var max_spread_time: float
	var max_diagonal_steps: int
	var fall_speed := 0.0
	var grains: Dictionary[Vector2i, Color] = {}
	var sideways_steps: Dictionary[Vector2i, int] = {}
	var impact_x: int
	var settle_elapsed := 0.0
	var scan_left_to_right := true

	func _ready() -> void:
		set_process(false)

	func _physics_process(delta: float) -> void:
		fall_speed += gravity * delta
		var next_y := position.y + fall_speed * delta
		var terrain := terrain_view.terrain
		var x := floori(position.x)
		# Sweep only the center through each crossed row to catch thin terrain.
		var first_row := maxi(0, floori(position.y))
		var last_row := mini(terrain.height - 1, floori(next_y))
		for y in range(first_row, last_row + 1):
			if terrain.is_solid(x, y):
				_begin_settling(Vector2i(x, y))
				return
		position.y = next_y
		if position.y - texture.get_height() * 0.5 >= terrain.height:
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


const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 4.0
const WALK_HOLD_MSEC := 80
const RIGHT_AIM_ORIGIN := Vector2(-3, -6)
const LEFT_AIM_ORIGIN := Vector2(2, -6)
const wind_max := 12
const DEFAULT_EXPLOSION_RADIUS := 18.0
const MAX_STEP_UP := 2
const MAX_STEP_DOWN := 2
const TERRAIN_BURN_COLOR := Color("#4c4947")
const LEVELS_DIR := "res://levels/"
const DEFAULT_LEVEL := "level1.png"
const TUNING_PATH := "user://goats_newtest_tuning.cfg"
const TUNING_SECTION := "tuning"
const SPRITE_LAYERS_SECTION := "sprite_layers"
const TUNING_FLOORS := {
	"jump_minimum_x": 1.0,
	"jump_minimum": 1.0,
	"jump_maximum_x": 1.0,
	"jump_maximum": 1.0,
	"jump_charge_time": 0.1,
	"fire_charge_time": 0.1,
	"fire_min_amount": 0.1,
	"fire_max_amount": 0.1,
	"explosion_radius": 1.0,
	"knockback_speed_per_damage": 0.0,
	"scorch_radius_modifier": 0.0,
	"dirt_settle_time": 0.0,
	"dirt_diagonal_steps": 0.0,
	"gravity_scale": 0.05,
	"fall_control_loss_distance": 1.0,
	"wind_scale": 0.0,
	"cloud_count": 0.0,
}

@export var aim_speed := 90.0
@export var cursor_distance := 40.0
@export var knockback_speed_per_damage := 4.0
@export_range(1, 8, 1) var camera_max_zoom := 2

@onready var player_goat: Goat = $Goat
@onready var second_goat: Goat = $Goat2
@onready var aim_pose: Sprite2D = $Goat/AimPose
@onready var aim_cursor: Sprite2D = $Goat/AimCursor
@onready var jump_charge_meter: Sprite2D = $Goat/JumpChargeMeter
@onready var shot_charge_meter: Sprite2D = $Goat/ShotChargeMeter
@onready var shot_charge_meter_distance := absf(shot_charge_meter.position.x)
@onready var arena_camera: Camera2D = $ArenaCamera
@onready var terrain_view: TerrainView = $Terrain
@onready var cloud_layers := [$Sky/CloudsFar, $Sky/CloudsMiddle, $Sky/CloudsNear]
@onready var leaf_layers := [$Sky/LeavesFar, $Sky/LeavesMiddle, $Sky/LeavesNear]
@onready var sky_layers := cloud_layers + leaf_layers
@onready var max_cloud_count := cloud_layers.size() * CloudLayer.CLOUD_COUNT
@onready var camera_target := arena_camera.position
@onready var console: CanvasLayer = $Console
@onready var console_output: RichTextLabel = $Console/Panel/Margin/Rows/Output
@onready var console_input: LineEdit = $Console/Panel/Margin/Rows/Input

# Keep command history when reset or load replaces the scene.
static var console_history: Array[String] = []
var console_history_index := -1

var fire_charge_time := 2.0
var fire_min_amount := 0.25
var fire_max_amount := 3.0
var explosion_radius := DEFAULT_EXPLOSION_RADIUS
var dirt_settle_time := 1.0
var dirt_diagonal_steps := 2
var scorch_radius_modifier := 3.0
var level_filename := DEFAULT_LEVEL
var sprite_layers: Dictionary[String, bool] = {"goat": true, "backpack": true, "launcher": true}
var showing_aim_pose := false
var aim_degrees := 0.0
var walk_start_msec := 0
var shot_charge := 0.0
var is_charging_shot := false
var shot_released := false
var mouse_unlocked := true
var left_press_position := Vector2.INF
var camera_dragging := false
var arena_bounds: Rect2
var terrain: Terrain
var goat_body: Rect2i
var player_spawn_x: int
var wind_scale := 4.0
var wind_speed := 0
var wind_random := true
var cloud_count := 15
var teams: Dictionary[int, Team] = {}
var second_goat_bouncing := false


func _ready() -> void:
	super()
	_load_tuning()
	_setup_level()
	player_goat.damaged.connect(_knock_back_player)
	player_goat.mode_changed.connect(_on_player_mode_changed)
	second_goat.damaged.connect(_knock_back_second_goat)
	var player_team := Team.new(player_goat.team_id, "Blue", Color.CORNFLOWER_BLUE)
	player_team.goats.append(player_goat)
	teams[player_team.id] = player_team
	for layer in sky_layers:
		layer.setup(arena_bounds)
	_apply_cloud_count()
	_set_wind(randi_range(-wind_max, wind_max) if wind_random else wind_speed)
	arena_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	var camera_controls := CameraControls.new()
	camera_controls.input_received.connect(_handle_camera_input)
	arena_camera.add_child(camera_controls)
	_update_mouse_mode()
	get_viewport().size_changed.connect(_clamp_camera_position)
	camera_target = goat.global_position
	_zoom_camera(1)
	var font := console_output.get_theme_font("normal_font")
	var font_size := console_output.get_theme_font_size("normal_font_size")
	console_output.custom_minimum_size.y = ceilf(font.get_height(font_size)) * 10
	console_input.text_submitted.connect(_run_console_command)
	_update_aim_display(0.0)
	_apply_sprite_layers()


func _setup_level() -> void:
	var image := _read_level_image(level_filename)
	if image == null or image.is_empty():
		push_warning("Could not load level %s. Using %s." % [level_filename, DEFAULT_LEVEL])
		level_filename = DEFAULT_LEVEL
		image = terrain_view.texture.get_image().duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	terrain = Terrain.from_image(image)
	arena_bounds = Rect2(Vector2.ZERO, Vector2(image.get_size()) * terrain_view.scale)

	var sky: Polygon2D = $Sky
	sky.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(arena_bounds.size.x, 0), arena_bounds.end, Vector2(0, arena_bounds.size.y),
	])
	RenderingServer.set_default_clear_color(sky.color)
	arena_camera.limit_left = 0
	arena_camera.limit_top = 0
	arena_camera.limit_right = roundi(arena_bounds.end.x)
	arena_camera.limit_bottom = roundi(arena_bounds.end.y)

	terrain_view.setup(terrain, image)

	var collider: CollisionShape2D = $Goat/CollisionShape2D
	var body_size := Vector2i((collider.shape as RectangleShape2D).size)
	goat_body = Rect2i(Vector2i(collider.position) - Vector2i(body_size / 2), body_size)
	player_spawn_x = roundi(arena_bounds.size.x * 0.5)
	_reset_fall_state()


func _read_level_image(filename: String) -> Image:
	if not filename.is_valid_filename() or filename.get_extension().to_lower() != "png":
		return null
	var path := LEVELS_DIR + filename
	# Read the source PNG during development, including files the editor hasn't imported yet.
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			return image
		return null
	if ResourceLoader.exists(path, "Texture2D"):
		var level_texture := load(path) as Texture2D
		if level_texture:
			return level_texture.get_image().duplicate() as Image
	return null


func _spawn_at(preferred_x: int) -> Vector2:
	# Cast down through the mask across the goat's feet so slopes cannot bury its body.
	for offset in ceili(arena_bounds.size.x):
		for x in [preferred_x + offset, preferred_x - offset]:
			var footprint := _bitmap_body_rect(Vector2(x, 0))
			if footprint.position.x < 0 or footprint.end.x > terrain.width:
				continue
			var surface := terrain.height
			for column in range(footprint.position.x, footprint.end.x):
				surface = mini(surface, terrain.surface_y(column))
			if surface < terrain.height:
				return Vector2(x, surface * terrain_view.scale.y - goat_body.end.y)
	push_error("Level bitmap has no solid spawn surface.")
	return Vector2(preferred_x, 0)


func _bitmap_body_rect(at: Vector2) -> Rect2i:
	# Cover every source pixel touched by the goat's world-space collision box.
	var origin := at.round() + Vector2(goat_body.position)
	var pixel_start := Vector2i((origin / terrain_view.scale).floor())
	var pixel_end := Vector2i(((origin + Vector2(goat_body.size)) / terrain_view.scale).ceil())
	return Rect2i(pixel_start, pixel_end - pixel_start)


func _body_is_free(at: Vector2) -> bool:
	var rect := _bitmap_body_rect(at)
	return terrain.rect_is_free(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


func _is_grounded() -> bool:
	return goat.velocity.y >= 0.0 and not _body_is_free(goat.position + Vector2.DOWN)


func _move_goat(delta: float) -> float:
	var start := goat.position
	var grounded := _is_grounded()
	var impact_velocity := goat.velocity
	var motion := impact_velocity * delta
	var dy := 0.0 if grounded else _sweep_vertical(goat.position, motion.y)
	goat.position.y += dy
	if not is_equal_approx(dy, motion.y) or _is_grounded():
		goat.position.y = roundf(goat.position.y)
		goat.velocity.y = 0.0
		if motion.y > 0.0 and (not grounded or is_bouncing):
			_handle_ground_impact(impact_velocity, _estimate_ground_normal(goat.position))

	var target := goat.position + Vector2(goat.velocity.x * delta, 0.0)
	goat.position = _sweep_horizontal(goat.position, target.x, grounded and not is_bouncing)
	if goat.position.x != target.x:
		goat.velocity.x = -goat.velocity.x * bounce_restitution if is_bouncing else 0.0

	if goat.position.y > arena_bounds.end.y or goat.position.x < -goat_body.size.x \
			or goat.position.x > arena_bounds.end.x + goat_body.size.x:
		goat.position = _spawn_at(player_spawn_x)
		goat.velocity = Vector2.ZERO
		_reset_fall_state()
	return goat.position.x - start.x


func _estimate_ground_normal(at: Vector2) -> Vector2:
	var footprint := _bitmap_body_rect(at)
	var left := footprint.position.x
	var right := footprint.end.x - 1
	var feet := footprint.end.y
	var left_y := _nearby_surface_y(left, feet)
	var right_y := _nearby_surface_y(right, feet)
	if left_y == -1 or right_y == -1 or left == right:
		return Vector2.UP

	var run := (right - left) * terrain_view.scale.x
	var rise := (right_y - left_y) * terrain_view.scale.y
	if absf(rise) > run:
		return Vector2.UP
	var slope := clampf(rise / run, -0.65, 0.65)
	return Vector2(slope, -1.0).normalized()


func _knockback_velocity(at: Vector2, amount: int, hit_direction: Vector2) -> Vector2:
	var direction := hit_direction
	if direction.is_zero_approx():
		direction = _estimate_ground_normal(at)
	elif not _body_is_free(at + Vector2.DOWN):
		# Give grounded goats enough lift to move sideways on a level hit.
		direction.y = minf(direction.y, -0.35)
		direction = direction.normalized()
	return direction * (amount * knockback_speed_per_damage)


func _knock_back_player(amount: int, hit_direction: Vector2) -> void:
	if knockback_speed_per_damage == 0.0:
		return
	_reset_fall_state()
	goat.velocity = _knockback_velocity(goat.position, amount, hit_direction)
	is_bouncing = true
	is_charging_shot = false
	shot_released = false


func _knock_back_second_goat(amount: int, hit_direction: Vector2) -> void:
	if knockback_speed_per_damage == 0.0:
		return
	second_goat.velocity = _knockback_velocity(second_goat.position, amount, hit_direction)
	second_goat_bouncing = true


func _nearby_surface_y(x: int, feet: int) -> int:
	# Search around the feet so an overhang far above doesn't affect the rebound.
	for y in range(maxi(0, feet - 1), mini(terrain.height, feet + 9)):
		if terrain.is_solid(x, y) and not terrain.is_solid(x, y - 1):
			return y
	return -1


func _sweep_horizontal(at: Vector2, target_x: float, follow_slope: bool) -> Vector2:
	if at.x == target_x and not follow_slope:
		return at
	var start_x := at.x
	var steps := maxi(1, ceili(absf(target_x - start_x)))
	for i in range(1, steps + 1):
		# Reach the exact target on a clear path so rounding cannot look like a wall hit.
		var next := Vector2(lerpf(start_x, target_x, float(i) / steps), at.y)
		if follow_slope:
			next = _follow_slope(next)
		if not _body_is_free(next):
			break
		at = next
	return at


func _follow_slope(at: Vector2) -> Vector2:
	# The step limits are in bitmap pixels, while the goat moves in world pixels.
	var max_step_up := roundi(MAX_STEP_UP * terrain_view.scale.y)
	var max_step_down := roundi(MAX_STEP_DOWN * terrain_view.scale.y)
	for up in range(max_step_up + 1):
		var candidate := at - Vector2(0, up)
		if _body_is_free(candidate):
			for down in max_step_down:
				if not _body_is_free(candidate + Vector2.DOWN):
					break
				candidate.y += 1.0
			return candidate
	return at


func _sweep_vertical(at: Vector2, distance: float) -> float:
	var steps := maxi(1, ceili(absf(distance)))
	var step_y := distance / steps
	var moved := 0.0
	for i in steps:
		if not _body_is_free(at + Vector2(0, moved + step_y)):
			break
		moved += step_y
	return moved


func _apply_idle_goat_gravity(delta: float) -> void:
	var grounded := second_goat.velocity.y >= 0.0 and not _body_is_free(second_goat.position + Vector2.DOWN)
	if grounded and not second_goat_bouncing:
		second_goat.position.y = roundf(second_goat.position.y)
		second_goat.velocity.y = 0.0
		return
	second_goat.velocity.y += second_goat.get_gravity().y * gravity_scale * delta
	var distance := second_goat.velocity.y * delta
	var moved := 0.0 if grounded else _sweep_vertical(second_goat.position, distance)
	second_goat.position.y += moved
	var hit_ground := distance > 0.0 and not _body_is_free(second_goat.position + Vector2.DOWN)
	if hit_ground or not is_equal_approx(moved, distance):
		second_goat.position.y = roundf(second_goat.position.y)
		var impact_velocity: Vector2 = second_goat.velocity
		second_goat.velocity.y = 0.0
		if distance > 0.0 and second_goat_bouncing:
			var rebound := _ground_rebound(impact_velocity, _estimate_ground_normal(second_goat.position))
			if rebound.y < -bounce_stop_speed:
				second_goat.velocity = rebound
			else:
				second_goat.velocity = Vector2.ZERO
				second_goat_bouncing = false
	var target := second_goat.position + Vector2(second_goat.velocity.x * delta, 0.0)
	second_goat.position = _sweep_horizontal(second_goat.position, target.x, false)
	if second_goat.position.x != target.x:
		second_goat.velocity.x *= -bounce_restitution


func _load_tuning() -> void:
	var config := ConfigFile.new()
	var error := config.load(TUNING_PATH)
	if error != OK:
		if error != ERR_FILE_NOT_FOUND:
			push_warning("Could not load tuning settings: %s" % error_string(error))
		return

	for field: String in TUNING_FLOORS:
		var saved: Variant = config.get_value(TUNING_SECTION, field, get(field))
		if (saved is float or saved is int) and is_finite(float(saved)):
			if field == "cloud_count":
				cloud_count = roundi(clampf(float(saved), 0.0, max_cloud_count))
			elif field == "dirt_diagonal_steps":
				if saved is int:
					dirt_diagonal_steps = maxi(saved, 0)
			else:
				set(field, maxf(float(saved), TUNING_FLOORS[field]))
	var saved_level: Variant = config.get_value(TUNING_SECTION, "level_filename", DEFAULT_LEVEL)
	if saved_level is String:
		level_filename = saved_level
	var saved_wind_speed: Variant = config.get_value(TUNING_SECTION, "wind_speed", wind_speed)
	if saved_wind_speed is int:
		wind_speed = clampi(saved_wind_speed, -wind_max, wind_max)
	var saved_wind_random: Variant = config.get_value(TUNING_SECTION, "wind_random", wind_random)
	if saved_wind_random is bool:
		wind_random = saved_wind_random
	jump_maximum = maxf(jump_minimum, jump_maximum)
	fire_max_amount = maxf(fire_min_amount, fire_max_amount)
	for layer: String in sprite_layers:
		var saved: Variant = config.get_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
		if saved is bool:
			sprite_layers[layer] = saved


func _run_console_command(command: String) -> void:
	console_input.clear()
	console_history_index = -1
	var words := command.replace("\t", " ").split(" ", false)
	if words.is_empty():
		return

	console_history.append(command)
	var lines := PackedStringArray(["> " + command])
	match words[0]:
		"vars":
			if words.size() != 1:
				lines.append("Usage: vars")
			else:
				for field: String in TUNING_FLOORS:
					lines.append("%s = %s" % [field, get(field)])
				lines.append("wind_speed = %s" % wind_speed)
				lines.append("wind_random = %s" % wind_random)
				for layer: String in sprite_layers:
					lines.append("%s = %s" % [layer, sprite_layers[layer]])
				lines.append("level_filename = " + level_filename)
		"set":
			lines.append(_set_console_variable(words))
		"load":
			var filename := command.strip_edges().substr(4).strip_edges()
			if filename.is_empty():
				lines.append("Usage: load level.png")
			else:
				var image := _read_level_image(filename)
				if image == null or image.is_empty():
					lines.append("Could not load PNG from levels/: " + filename)
				else:
					var previous_level := level_filename
					level_filename = filename
					var error := _save_tuning()
					if error == OK:
						_reload_level.call_deferred()
						return
					level_filename = previous_level
					lines.append("Could not save level preference: " + error_string(error))
		"reset":
			if words.size() != 1:
				lines.append("Usage: reset")
			else:
				_reload_level.call_deferred()
				return
		_:
			lines.append("Unknown command: " + words[0])

	var first_line := 0
	if not console_output.text.is_empty():
		first_line = console_output.get_line_count()
		console_output.text += "\n"
	console_output.text += "\n".join(lines)
	console_output.scroll_to_line(first_line)


func _set_console_variable(words: PackedStringArray) -> String:
	if words.size() != 3:
		return "Usage: set varname value"

	var field := words[1]
	var value_text := words[2]
	if field == "wind_speed":
		if not value_text.is_valid_int():
			return "wind_speed expects a whole number."
		var speed := value_text.to_int()
		if speed < -wind_max or speed > wind_max:
			return "wind_speed must be between %s and %s." % [-wind_max, wind_max]
		_set_wind(speed)
		_save_tuning()
		return "wind_speed = %s" % wind_speed
	if field == "wind_random":
		if value_text != "true" and value_text != "false":
			return "wind_random expects true or false."
		wind_random = value_text == "true"
		_save_tuning()
		return "wind_random = %s" % wind_random
	if sprite_layers.has(field):
		if value_text != "true" and value_text != "false":
			return "%s expects true or false." % field
		sprite_layers[field] = value_text == "true"
		_apply_sprite_layers()
		_save_tuning()
		return "%s = %s" % [field, sprite_layers[field]]

	if not TUNING_FLOORS.has(field):
		return "Unknown variable: " + field
	if field == "dirt_diagonal_steps":
		if not value_text.is_valid_int() or value_text.to_int() < 0:
			return "dirt_diagonal_steps expects a nonnegative whole number."
		dirt_diagonal_steps = value_text.to_int()
		_save_tuning()
		return "dirt_diagonal_steps = %s" % dirt_diagonal_steps
	if not value_text.is_valid_float() or not is_finite(value_text.to_float()):
		return "%s expects a finite number." % field

	var value := value_text.to_float()
	var minimum: float = TUNING_FLOORS[field]
	var maximum := INF
	match field:
		"jump_minimum":
			maximum = jump_maximum
		"jump_maximum":
			minimum = jump_minimum
		"fire_min_amount":
			maximum = fire_max_amount
		"fire_max_amount":
			minimum = fire_min_amount
		"cloud_count":
			if value != floorf(value):
				return "%s expects a whole number." % field
			maximum = max_cloud_count
	if value < minimum:
		return "%s must be at least %s." % [field, minimum]
	if value > maximum:
		return "%s must be at most %s." % [field, maximum]

	if field == "cloud_count":
		cloud_count = int(value)
		_apply_cloud_count()
	else:
		set(field, value)
	_save_tuning()
	return "%s = %s" % [field, get(field)]


func _reload_level() -> void:
	var error := get_tree().reload_current_scene()
	if error != OK:
		console_output.text += "\nCould not reset level: " + error_string(error)
		console_output.scroll_to_line(console_output.get_line_count() - 1)


func _save_tuning() -> Error:
	var config := ConfigFile.new()
	for key: String in TUNING_FLOORS:
		config.set_value(TUNING_SECTION, key, get(key))
	for layer: String in sprite_layers:
		config.set_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
	config.set_value(TUNING_SECTION, "level_filename", level_filename)
	config.set_value(TUNING_SECTION, "wind_speed", wind_speed)
	config.set_value(TUNING_SECTION, "wind_random", wind_random)
	var error := config.save(TUNING_PATH)
	if error != OK:
		push_warning("Could not save tuning settings: %s" % error_string(error))
	return error


func _walk_direction() -> float:
	if console.visible or Time.get_ticks_msec() < walk_start_msec:
		return 0.0
	return float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))


func _physics_process(delta: float) -> void:
	super(delta)
	_apply_idle_goat_gravity(delta)

	var can_aim := (
		player_goat.mode == Goat.Mode.LAUNCHER
		and _can_control_movement()
		and is_zero_approx(_walk_direction())
	)
	if can_aim and not console.visible:
		var elevation := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		aim_degrees = clampf(aim_degrees + elevation * aim_speed * delta, -90.0, 90.0)

	# Let the layered sprite finish its short walk tail before switching poses.
	showing_aim_pose = can_aim and sprite.animation == &"idle"
	var snapped_aim := snappedf(aim_degrees, AIM_CURSOR_STEP) if showing_aim_pose else 0.0
	muzzle_right.rotation = -deg_to_rad(snapped_aim)
	muzzle_left.rotation = -muzzle_right.rotation
	if showing_aim_pose:
		_update_aim_display(snapped_aim)
	_apply_sprite_layers()
	_update_shot_charge(delta)
	_update_charge_meters()


func _update_charge_meters() -> void:
	jump_charge_meter.visible = is_charging_jump and not jump_released
	if jump_charge_meter.visible:
		var progress := clampf(jump_charge / jump_charge_time, 0.0, 1.0)
		if is_equal_approx(progress, 1.0):
			progress = 1.0
		jump_charge_meter.frame = floori(progress * (jump_charge_meter.vframes - 1))

	shot_charge_meter.visible = is_charging_shot
	if shot_charge_meter.visible:
		var progress := clampf(shot_charge / fire_charge_time, 0.0, 1.0)
		shot_charge_meter.frame = floori(progress * (shot_charge_meter.hframes - 1))
		shot_charge_meter.position.x = -facing * shot_charge_meter_distance


func _apply_sprite_layers() -> void:
	var show_backpack := player_goat.mode != Goat.Mode.GOAT_ONLY and sprite_layers["backpack"]
	var show_launcher := player_goat.mode == Goat.Mode.LAUNCHER and sprite_layers["launcher"]
	# The aiming atlas is composited. Use the layered idle pose for individual layer previews.
	aim_pose.visible = showing_aim_pose and sprite_layers["goat"] and show_backpack and show_launcher
	sprite.visible = not aim_pose.visible
	# Hide only the body texture so its child equipment can still draw.
	sprite.self_modulate.a = 1.0 if sprite_layers["goat"] else 0.0
	backpack.visible = show_backpack
	launcher.visible = show_launcher
	aim_cursor.visible = showing_aim_pose and show_launcher


func _on_player_mode_changed() -> void:
	walk_start_msec = 0
	if player_goat.mode == Goat.Mode.LAUNCHER:
		if is_charging_jump:
			jump_pause_remaining = 0.0
		is_charging_jump = false
		jump_released = false
	else:
		showing_aim_pose = false
		is_charging_shot = false
		shot_released = false
	_apply_sprite_layers()
	_update_charge_meters()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_F2:
		if event.pressed and not event.echo:
			_reload_level.call_deferred()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_QUOTELEFT:
		if event.pressed and not event.echo:
			_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if console.visible:
		if event is InputEventKey and event.pressed:
			if event.physical_keycode == KEY_ESCAPE:
				_toggle_console()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_UP and console_input.has_focus() and not console_history.is_empty():
				if console_history_index == -1:
					console_history_index = console_history.size()
				console_history_index = maxi(0, console_history_index - 1)
				console_input.text = console_history[console_history_index]
				console_input.caret_column = console_input.text.length()
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SHIFT and event.location == KEY_LOCATION_LEFT:
			player_goat.mode = ((player_goat.mode + 1) % Goat.Mode.size()) as Goat.Mode
			get_viewport().set_input_as_handled()
			return
		if (event.physical_keycode == KEY_A or event.physical_keycode == KEY_D) \
				and _can_control_movement() and not is_charging_jump:
			var direction := -1.0 if event.physical_keycode == KEY_A else 1.0
			if player_goat.mode == Goat.Mode.LAUNCHER and direction != facing:
				walk_start_msec = Time.get_ticks_msec() + WALK_HOLD_MSEC
			else:
				walk_start_msec = 0
			facing = direction
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _handle_camera_input(event: InputEvent) -> void:
	var tree := get_tree()
	if event is InputEventKey and event.physical_keycode == KEY_F1:
		if event.pressed and not event.echo:
			tree.paused = not tree.paused
			if not tree.paused:
				# A release during pause should cancel the charge instead of firing it.
				if not jump_released and not Input.is_physical_key_pressed(KEY_ENTER):
					is_charging_jump = false
				if not shot_released and not Input.is_physical_key_pressed(KEY_SPACE):
					is_charging_shot = false
			_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	if console.visible and not tree.paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		mouse_unlocked = not mouse_unlocked
		_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	# Handle zoom in both cursor modes before routing pointer input.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(1)
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-1)
				get_viewport().set_input_as_handled()
				return
	if mouse_unlocked:
		_handle_unlocked_pointer(event)
		return
	if event is InputEventMouseMotion:
		camera_target += event.relative * CAPTURED_MOUSE_SENSITIVITY / arena_camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _handle_unlocked_pointer(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			left_press_position = event.position
			camera_dragging = false
		else:
			if not camera_dragging and event.position.distance_to(left_press_position) < CAMERA_DRAG_THRESHOLD \
					and not get_tree().paused:
				var at: Vector2 = terrain_view.get_global_transform_with_canvas().affine_inverse() * event.position
				_drop_dirt(at)
			left_press_position = Vector2.INF
			camera_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
			and left_press_position.is_finite():
		var motion: Vector2 = event.relative if camera_dragging else event.position - left_press_position
		if camera_dragging or motion.length() >= CAMERA_DRAG_THRESHOLD:
			camera_dragging = true
			camera_target -= motion / arena_camera.zoom
			_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _drop_dirt(at: Vector2) -> void:
	var pixel := Vector2i(at.floor())
	if terrain.is_solid(pixel.x, pixel.y):
		return
	var dirt := DirtDrop.new()
	dirt.texture = DIRT_TEXTURE
	dirt.position = at
	dirt.terrain_view = terrain_view
	dirt.gravity = DIRT_GRAVITY / terrain_view.scale.y
	dirt.max_spread_time = dirt_settle_time
	dirt.max_diagonal_steps = dirt_diagonal_steps
	dirt.deposited.connect(_lift_goats_after_deposit)
	terrain_view.add_child(dirt)


func _lift_goats_after_deposit(grains: Dictionary[Vector2i, Color]) -> void:
	for target: CharacterBody2D in [goat, second_goat]:
		var body := _bitmap_body_rect(target.position)
		for pixel: Vector2i in grains:
			if body.has_point(pixel) and terrain.is_solid(pixel.x, pixel.y):
				var clear_position := target.position + Vector2.UP
				while not _body_is_free(clear_position):
					clear_position.y -= 1.0
				target.position = clear_position
				target.velocity.y = minf(target.velocity.y, 0.0)
				break


func _toggle_console() -> void:
	console.visible = not console.visible
	if console.visible:
		if is_charging_jump:
			is_charging_jump = false
			jump_released = false
			jump_pause_remaining = 0.0
		is_charging_shot = false
		shot_released = false
		console_input.grab_focus()
	else:
		console_input.release_focus()
	_update_mouse_mode()


func _unhandled_key_input(event: InputEvent) -> void:
	if not console.visible:
		super(event)


func _unhandled_input(event: InputEvent) -> void:
	if console.visible or is_bouncing or player_goat.mode != Goat.Mode.LAUNCHER:
		return
	if event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.echo:
		if event.pressed and not is_charging_shot:
			is_charging_shot = true
			shot_charge = 0.0
		elif not event.pressed and is_charging_shot:
			shot_released = true
		get_viewport().set_input_as_handled()


func _zoom_camera(amount: int) -> void:
	var zoom_level := clampi(int(arena_camera.zoom.x) + amount, 1, camera_max_zoom)
	arena_camera.zoom = Vector2.ONE * float(zoom_level)
	_clamp_camera_position()


func _update_mouse_mode() -> void:
	left_press_position = Vector2.INF
	camera_dragging = false
	var cursor_visible := mouse_unlocked or (console.visible and not get_tree().paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cursor_visible else Input.MOUSE_MODE_CAPTURED


func _clamp_camera_position() -> void:
	var half_view_pixels := get_viewport_rect().size * 0.5
	var camera_zoom := arena_camera.zoom
	var half_view := (half_view_pixels / camera_zoom).min(arena_bounds.size * 0.5)
	camera_target = camera_target.clamp(arena_bounds.position + half_view, arena_bounds.end - half_view)
	# Snap the viewport origin to a render pixel without discarding small mouse movements.
	var origin_pixels := (camera_target * camera_zoom - half_view_pixels).round()
	arena_camera.position = (origin_pixels + half_view_pixels) / camera_zoom
	var camera_offset := arena_camera.position - arena_bounds.get_center()
	for layer in sky_layers:
		layer.update_parallax(camera_offset)


func _update_shot_charge(delta: float) -> void:
	if is_bouncing:
		is_charging_shot = false
		shot_released = false
		return
	if not is_charging_shot:
		return
	if not shot_released and shot_charge < fire_charge_time:
		shot_charge = minf(shot_charge + delta, fire_charge_time)
		if is_equal_approx(shot_charge, fire_charge_time):
			shot_charge = fire_charge_time
		# Show the full meter for a physics tick before the automatic shot.
		return

	var muzzle := muzzle_left if facing < 0.0 else muzzle_right
	var direction := Vector2(facing, 0).rotated(muzzle.global_rotation)
	var charge_ratio := minf(shot_charge / fire_charge_time, 1.0)
	var power := lerpf(fire_min_amount, fire_max_amount, charge_ratio)
	_fire_rocket(muzzle, direction, power)
	is_charging_shot = false
	shot_released = false


func _fire_rocket(muzzle: Marker2D, direction: Vector2, power: float = 1.0) -> Rocket:
	var rocket := super(muzzle, direction, power)
	if rocket == null:
		return null
	rocket.terrain = terrain
	rocket.terrain_pixel_size = terrain_view.scale
	rocket.wind_acceleration = (float(wind_speed) / wind_max) * wind_scale
	rocket.exploded_at.connect(_apply_rocket_blast.bind(rocket.blast_damage))
	rocket.impacted.connect(_roll_wind)
	return rocket


func _apply_rocket_blast(
	world_pixel: Vector2i, direct_hit: GoatHurtbox, hit_direction: Vector2, peak_damage: int
) -> void:
	var pixel := Vector2i((Vector2(world_pixel) / terrain_view.scale).floor())
	var radius := roundi(explosion_radius)
	# Damage signals sample the surface synchronously, before the bitmap changes.
	var center := terrain_view.to_global(Vector2(pixel))
	if direct_hit:
		direct_hit.apply_damage(peak_damage, hit_direction)
	GoatHurtbox.apply_area_damage(self, center, radius * terrain_view.scale.x, peak_damage, direct_hit)
	var crater := terrain.carve_circle(pixel.x, pixel.y, radius, true)
	var scorch_width := roundi(scorch_radius_modifier)
	if scorch_width > 0:
		terrain_view.scorch_circle(pixel, radius + scorch_width, TERRAIN_BURN_COLOR)
	terrain_view.carve(crater)


func _roll_wind() -> void:
	if not wind_random:
		return
	var offset := randi_range(1, 2 * wind_max)
	_set_wind(wrapi(wind_speed + offset, -wind_max, wind_max + 1))


func _set_wind(speed: int) -> void:
	wind_speed = speed
	var strength := float(speed) / wind_max
	for layer in leaf_layers:
		layer.set_wind(strength)


func _apply_cloud_count() -> void:
	var layer_count := cloud_layers.size()
	var per_layer := floori(float(cloud_count) / layer_count)
	var remainder := cloud_count % layer_count
	for index in layer_count:
		cloud_layers[index].multimesh.visible_instance_count = per_layer + int(index < remainder)


func _update_aim_display(snapped_aim: float) -> void:
	var column := roundi((90.0 - snapped_aim) / AIM_POSE_STEP)
	var row := 1 if facing < 0.0 else 0
	aim_pose.frame_coords = Vector2i(column, row)

	var angle := deg_to_rad(snapped_aim)
	var direction := Vector2(facing * cos(angle), -sin(angle))
	var origin := LEFT_AIM_ORIGIN if facing < 0.0 else RIGHT_AIM_ORIGIN
	aim_cursor.global_position = (aim_pose.to_global(origin) + direction * cursor_distance).round()
