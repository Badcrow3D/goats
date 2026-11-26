extends "res://goats/goat_controller.gd"

const Goat := preload("res://goats/goat.gd")
const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const LevelItem := preload("res://goats/level_item.gd")
const DirtDrop := preload("res://goats/dirt_drop.gd")
const WindLeaves := preload("res://goats/wind_leaves.gd")
const Crow := preload("res://goats/crow.gd")
const CROW_SPAWN_INTERVAL := 10.0
const DIRT_TEXTURE := preload("res://sprites/dirt.png")
const BLAST_DIRT_TEXTURE := preload("res://sprites/dirt-16x16.png")
const BLAST_DIRT_FRAME_SIZE := 16
# Opaque pixel counts in the sheet's seven frames, largest to smallest.
const BLAST_DIRT_PIXELS := [148, 112, 76, 52, 24, 12, 4]
const EXPLOSION_TEXTURE := preload("res://sprites/explosion-40x40.png")
const EXPLOSION_FRAME_SECONDS := 0.07
const SMOKE_TEXTURE := preload("res://sprites/smoke-16x16.png")
const SMOKE_FRAME_COUNT := 7
const SMOKE_FRAME_SECONDS := 0.04
const SMOKE_SPAWN_RADIUS := 24.0
const TRAIL_SMOKE_MIN_START_FRAME := 3
const TRAIL_SMOKE_MAX_START_FRAME := 4
const TRAIL_SMOKE_FRAME_SECONDS := 0.16
const TRAIL_SMOKE_JITTER := 4.0
const TRAIL_SMOKE_RISE_SPEED := 20.0
const TRAIL_SMOKE_WIND_SPEED := 20.0
const DIRT_GRAVITY := 400.0
const GRAPPLE_RANGE := 500.0
const GRAPPLE_CHUNK_PIXELS := 2.0
const GRAPPLE_MISS_SECONDS := 0.2
const GRAPPLE_REEL_SPEED := 80.0
const GRAPPLE_REEL_MOMENTUM_EXPONENT := 1.5
const GRAPPLE_SWING_ACCELERATION := 150.0
const GRAPPLE_SWING_DRAG := 0.18 # Per second, applied to tangential speed.
const GRAPPLE_MAX_SPEED := 360.0 # Six world pixels per 60 Hz tick.
const GRAPPLE_SWING_RESTITUTION := 0.75
const GRAPPLE_BOUNCE_HEIGHT := 24.0 # Standing sprite height in world pixels.
const GRAPPLE_BOUNCE_STRENGTH := 0.75
const GRAPPLE_BOUNCE_COOLDOWN := 2.0
const ACTIVE_GOAT_ARROW_TEXTURE := preload("res://sprites/arrow-16x16.png")
const ACTIVE_GOAT_ARROW_FRAME_SECONDS := 0.08
const OFFSCREEN_ARROW_MARGIN := 40.0
const CAMERA_DRAG_THRESHOLD := 4.0
const CAPTURED_MOUSE_SENSITIVITY := 2.0
const ZOOM_TRANSITION_SECONDS := 0.25
const CAMERA_MIN_ZOOM := 0.5
const GOAT_SWITCH_CAMERA_SECONDS := 0.3
const CAMERA_FOLLOW_IDLE_MSEC := 500
const CAMERA_FOLLOW_MOVE_PIXELS := 50.0
const ZOOM_PEAK_BLOCK_SIZE := 10.0

class CameraControls extends Node:
	signal input_received(event: InputEvent)

	func _input(event: InputEvent) -> void:
		input_received.emit(event)


# A straight run of pinned chunks only needs its last joint stored.
class RopeBend:
	var joint: Vector2
	var pinned_length: float
	var winding: float


class Team:
	var id: int
	var team_name: String
	var color: Color
	var goats: Array[Goat] = []

	func _init(team_id: int, display_name: String, team_color: Color) -> void:
		id = team_id
		team_name = display_name
		color = team_color


const WALK_HOLD_MSEC := 80
const wind_max := 12
const DEFAULT_EXPLOSION_RADIUS := 18.0
const EXPLOSION_SHAKE_DURATION := 0.25
const EXPLOSION_SHAKE_PIXELS := 5.0
const MAX_STEP_UP := 2
const MAX_STEP_DOWN := 2
const TERRAIN_BURN_COLOR := Color("#4c4947")
const LEVELS_DIR := "res://levels/"
const DEFAULT_LEVEL := "level2.png"
const LEVEL_SIZE := Vector2i(1920, 1080)
const TUNING_PATH := "user://goats_newtest_tuning.cfg"
const TUNING_SECTION := "tuning"
const TUNING_FLAGS := ["wind_random"]
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
	"gravity_scale": 0.05,
	"fall_control_loss_distance": 1.0,
	"fall_animation_distance": 0.0,
	"wind_scale": 0.0,
}

@export var aim_speed := 90.0
@export var cursor_distance := 40.0
@export var knockback_speed_per_damage := 1.0
@export_range(1, 8, 1) var camera_max_zoom := 2

@onready var goat_container: Node2D = $Goats
@onready var arena_camera: Camera2D = $ArenaCamera
@onready var offscreen_arrow: Sprite2D = $GoatIndicator/Arrow
@onready var zoom_pixelation: ColorRect = $ZoomEffect/Pixelation
@onready var zoom_material: ShaderMaterial = zoom_pixelation.material
@onready var camera_zoom_level := arena_camera.zoom.x
@onready var terrain_view: TerrainView = $Terrain
@onready var cloud_layers := [$Sky/CloudsFar, $Sky/CloudsMiddle, $Sky/CloudsNear]
@onready var leaf_layers := [$Sky/LeavesFar, $Sky/LeavesMiddle, $Sky/LeavesNear]
@onready var max_leaf_count := leaf_layers.size() * WindLeaves.MAX_LEAVES
@onready var sky_layers := cloud_layers + leaf_layers
@onready var camera_target := arena_camera.position
@onready var camera_rest_offset := arena_camera.offset
@onready var console: ArenaConsole = $Console

var fire_charge_time := 2.0
var fire_min_amount := 0.25
var fire_max_amount := 3.0
var explosion_radius := DEFAULT_EXPLOSION_RADIUS
var dirt_settle_time := 1.0
var dirt_diagonal_steps := 2
var scorch_radius_modifier := 3.0
var level_filename := DEFAULT_LEVEL
var walk_start_msec := 0
var shot_charge := 0.0
var is_charging_shot := false
var shot_released := false
var active_missile: Missile
var active_dirt_drops := 0
var pending_item_blasts: Array[Callable] = []
var mouse_unlocked := true
var pointer_press_position := Vector2.INF
var camera_dragging := false
var camera_shake: Tween
var camera_zoom_transition: Tween
var camera_goat_transition: Tween
var last_manual_camera_msec := -CAMERA_FOLLOW_IDLE_MSEC
var camera_follow_origin: Vector2
var camera_follow_armed := false
var camera_follows_goat := false
var active_goat_arrow: Sprite2D
var arena_bounds: Rect2
var terrain: Terrain
var crow: Crow
var grapple_line := Node2D.new()
var grapple_start_pixel := Vector2i.ZERO
var grapple_end_pixel := Vector2i.ZERO
var grapple_miss_time := 0.0
var grapple_attached := false
var grapple_anchor := Vector2.ZERO
var grapple_length := 0.0:
	set(value):
		grapple_length = clampf(value, 0.0, GRAPPLE_RANGE)
var grapple_bends: Array[RopeBend] = []
var goat_body: Rect2i
var player_spawn_x: int
var wind_scale := 4.0
var wind_speed := 0
var wind_random := true
var cloud_count := 15
var leaf_count := 30
var teams: Dictionary[int, Team] = {}
var goats: Array[Goat] = []


func _ready() -> void:
	for child in goat_container.get_children():
		if child is Goat:
			goats.append(child)
	active_goat = goats[0]
	_load_tuning()
	arena_camera.limit_enabled = false
	_setup_level()
	grapple_line.draw.connect(_draw_grapple_line)
	grapple_line.hide()
	grapple_line.z_as_relative = false
	grapple_line.z_index = 1
	terrain_view.add_child(grapple_line)
	var player_team := Team.new(active_goat.team_id, "Blue", Color.CORNFLOWER_BLUE)
	for target in goats:
		if target != active_goat:
			target.mode = Goat.Mode.GOAT_ONLY
		target.damaged.connect(_knock_back_goat.bind(target))
		target.mode_changed.connect(_on_goat_mode_changed.bind(target))
		if target.team_id == player_team.id:
			player_team.goats.append(target)
	teams[player_team.id] = player_team
	for layer in sky_layers:
		layer.setup(arena_bounds)
	_apply_cloud_count()
	_apply_leaf_count()
	_set_wind(randi_range(-wind_max, wind_max) if wind_random else wind_speed)
	arena_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	var camera_controls := CameraControls.new()
	camera_controls.input_received.connect(_handle_camera_input)
	arena_camera.add_child(camera_controls)
	_update_mouse_mode()
	get_viewport().size_changed.connect(func() -> void:
		if arena_camera.limit_enabled:
			_clamp_camera_position()
	)
	_update_camera_parallax()
	arena_camera.force_update_scroll()
	for target in goats:
		$Nameplates.track_goat(target)
	console.list_variables = _list_console_variables
	console.set_variable = _set_console_variable
	console.load_level = _load_console_level
	console.reset_level = _reload_level
	_show_active_goat_arrow()
	_try_spawn_crow()
	var crow_timer := Timer.new()
	crow_timer.wait_time = CROW_SPAWN_INTERVAL
	crow_timer.timeout.connect(_try_spawn_crow)
	add_child(crow_timer)
	crow_timer.start()
	var goat_idle_timer := Timer.new()
	goat_idle_timer.wait_time = 4.0
	goat_idle_timer.timeout.connect(_play_random_goat_idle)
	add_child(goat_idle_timer)
	goat_idle_timer.start()


func _play_random_goat_idle() -> void:
	var screen := get_viewport_rect()
	var inactive_goats: Array[Goat] = []
	var onscreen_goats: Array[Goat] = []
	for target in goats:
		if target == active_goat or not target.can_play_idle_animation() or not _is_grounded(target):
			continue
		inactive_goats.append(target)
		var body_on_screen := target.get_global_transform_with_canvas() * Rect2(target.bitmap_body_rect())
		if target.is_visible_in_tree() and screen.intersects(body_on_screen):
			onscreen_goats.append(target)
	if not onscreen_goats.is_empty():
		onscreen_goats.pick_random().play_idle_animation()
	elif not inactive_goats.is_empty():
		inactive_goats.pick_random().play_idle_animation()


func _try_spawn_crow() -> void:
	if is_instance_valid(crow):
		return

	arena_camera.force_update_scroll()
	var viewport_to_terrain := terrain_view.get_global_transform_with_canvas().affine_inverse()
	var visible_area := viewport_to_terrain * get_viewport_rect()
	var direction := 1 if randf() < 0.5 else -1
	var middle_x := visible_area.get_center().x
	var perches: Array[Vector2] = []
	var near_perches: Array[Vector2] = []
	var first_column := maxi(0, ceili(visible_area.position.x))
	var last_column := mini(terrain.width - 1, floori(visible_area.end.x))
	for x in range(first_column, last_column + 1):
		var surface_y := terrain.surface_y(x)
		var feet := Vector2(x, surface_y)
		if surface_y < terrain.height and visible_area.has_point(feet):
			perches.append(feet)
			if (feet.x - middle_x) * direction <= 0.0:
				near_perches.append(feet)
	if perches.is_empty():
		return

	var perch: Vector2 = (near_perches if not near_perches.is_empty() else perches).pick_random()
	var entry_x := visible_area.position.x if direction > 0 else visible_area.end.x
	var entry_y := visible_area.position.y + randf() * visible_area.size.y / 3.0
	var entry := Vector2(entry_x - direction * Crow.FRAME_SIZE, entry_y)
	crow = Crow.new()
	terrain_view.add_child(crow)
	crow.visit(entry, perch, terrain.width)


func _setup_level() -> void:
	var image := _read_level_image(level_filename)
	if image == null or image.get_size() != LEVEL_SIZE:
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
	var background: TextureRect = $Sky/Background
	background.size = arena_bounds.size
	RenderingServer.set_default_clear_color(sky.color)
	arena_camera.limit_left = 0
	arena_camera.limit_top = 0
	arena_camera.limit_right = roundi(arena_bounds.end.x)
	arena_camera.limit_bottom = roundi(arena_bounds.end.y)

	terrain_view.setup(terrain, image)
	for child in $Items.get_children():
		if child is LevelItem:
			child.terrain_view = terrain_view
			child.exploded.connect(_queue_item_blast)

	goat_body = active_goat.bitmap_body_rect()
	player_spawn_x = roundi(arena_bounds.size.x * 0.5)
	for target in goats:
		_reset_fall_state(target)


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


func _is_grounded(body: Goat) -> bool:
	if grapple_attached and body == active_goat:
		return _grapple_contact(body.position + Vector2.DOWN * 0.25).y < -0.001
	return body.velocity.y >= 0.0 and not _body_is_free(body.position + Vector2.DOWN)


func _move_goat(body: Goat, delta: float) -> float:
	var start := body.position
	var grounded := _is_grounded(body)
	var impact_velocity := body.velocity
	var motion := impact_velocity * delta
	var dy := 0.0 if grounded else _sweep_vertical(body.position, motion.y)
	body.position.y += dy
	if not is_equal_approx(dy, motion.y) or _is_grounded(body):
		body.position.y = roundf(body.position.y)
		body.velocity.y = 0.0
		if motion.y > 0.0 and (not grounded or body.is_bouncing):
			_handle_ground_impact(body, impact_velocity, _estimate_ground_normal(body.position))

	var target := body.position + Vector2(body.velocity.x * delta, 0.0)
	body.position = _sweep_horizontal(body.position, target.x, grounded and not body.is_bouncing)
	if body.position.x != target.x:
		body.velocity.x = -body.velocity.x * bounce_restitution if body.is_bouncing else 0.0

	if body.position.y > arena_bounds.end.y or body.position.x < -goat_body.size.x \
			or body.position.x > arena_bounds.end.x + goat_body.size.x:
		body.position = _spawn_at(player_spawn_x)
		body.velocity = Vector2.ZERO
		_reset_fall_state(body)
	return body.position.x - start.x


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


func _knock_back_goat(amount: int, hit_direction: Vector2, target: Goat) -> void:
	if target == active_goat and grapple_attached:
		_disconnect_grapple()
	if not target.is_bouncing:
		_reset_fall_state(target)
	if knockback_speed_per_damage != 0.0:
		target.velocity = _knockback_velocity(target.position, amount, hit_direction)
	target.is_bouncing = true
	target.show_bounce_pose()
	if target == active_goat:
		is_charging_shot = false
		shot_released = false


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
			set(field, maxf(float(saved), TUNING_FLOORS[field]))
	var saved_level: Variant = config.get_value(TUNING_SECTION, "selected_level_filename", DEFAULT_LEVEL)
	if saved_level is String:
		level_filename = saved_level
	var saved_wind_speed: Variant = config.get_value(TUNING_SECTION, "wind_speed", wind_speed)
	if saved_wind_speed is int:
		wind_speed = clampi(saved_wind_speed, -wind_max, wind_max)
	for field: String in TUNING_FLAGS:
		var saved: Variant = config.get_value(TUNING_SECTION, field, get(field))
		if saved is bool:
			set(field, saved)
	var saved_leaf_count: Variant = config.get_value(TUNING_SECTION, "leaf_count", leaf_count)
	if saved_leaf_count is int:
		leaf_count = clampi(saved_leaf_count, 0, max_leaf_count)
	jump_maximum = maxf(jump_minimum, jump_maximum)
	fire_max_amount = maxf(fire_min_amount, fire_max_amount)


func _list_console_variables() -> PackedStringArray:
	var lines := PackedStringArray()
	for field: String in TUNING_FLOORS:
		lines.append("%s = %s" % [field, get(field)])
	lines.append("wind_speed = %s" % wind_speed)
	for field: String in TUNING_FLAGS:
		lines.append("%s = %s" % [field, get(field)])
	lines.append("leaf_count = %s" % leaf_count)
	lines.append("level_filename = " + level_filename)
	return lines


func _load_console_level(filename: String) -> String:
	var image := _read_level_image(filename)
	if image == null or image.is_empty():
		return "Could not load PNG from levels/: " + filename
	if image.get_size() != LEVEL_SIZE:
		return "Level PNG must be %d×%d pixels." % [LEVEL_SIZE.x, LEVEL_SIZE.y]

	var previous_level := level_filename
	level_filename = filename
	var error := _save_tuning()
	if error != OK:
		level_filename = previous_level
		return "Could not save level preference: " + error_string(error)

	_reload_level.call_deferred()
	return ""


func _set_console_variable(field: String, value_text: String) -> String:
	if field == "wind_speed":
		if not value_text.is_valid_int():
			return "wind_speed expects a whole number."
		var speed := value_text.to_int()
		if speed < -wind_max or speed > wind_max:
			return "wind_speed must be between %s and %s." % [-wind_max, wind_max]
		_set_wind(speed)
		_save_tuning()
		return "wind_speed = %s" % wind_speed
	if field in TUNING_FLAGS:
		if value_text != "true" and value_text != "false":
			return "%s expects true or false." % field
		set(field, value_text == "true")
		_save_tuning()
		return "%s = %s" % [field, get(field)]
	if field == "leaf_count":
		if not value_text.is_valid_int():
			return "leaf_count expects a whole number."
		var count := value_text.to_int()
		if count < 0 or count > max_leaf_count:
			return "leaf_count must be between 0 and %s." % max_leaf_count
		leaf_count = count
		_apply_leaf_count()
		_save_tuning()
		return "leaf_count = %s" % leaf_count
	if not TUNING_FLOORS.has(field):
		return "Unknown variable: " + field
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
	if value < minimum:
		return "%s must be at least %s." % [field, minimum]
	if value > maximum:
		return "%s must be at most %s." % [field, maximum]

	set(field, value)
	_save_tuning()
	return "%s = %s" % [field, get(field)]


func _reload_level() -> void:
	var error := get_tree().reload_current_scene()
	if error != OK:
		console.show_message("Could not reset level: " + error_string(error))


func _save_tuning() -> Error:
	var config := ConfigFile.new()
	for key: String in TUNING_FLOORS:
		config.set_value(TUNING_SECTION, key, get(key))
	config.set_value(TUNING_SECTION, "selected_level_filename", level_filename)
	config.set_value(TUNING_SECTION, "wind_speed", wind_speed)
	for key: String in TUNING_FLAGS:
		config.set_value(TUNING_SECTION, key, get(key))
	config.set_value(TUNING_SECTION, "leaf_count", leaf_count)
	var error := config.save(TUNING_PATH)
	if error != OK:
		push_warning("Could not save tuning settings: %s" % error_string(error))
	return error


func _walk_direction() -> float:
	if grapple_attached or not _can_use_ground_controls() or console.visible or Time.get_ticks_msec() < walk_start_msec:
		return 0.0
	return Input.get_axis(&"walk_left", &"walk_right")


func _process(_delta: float) -> void:
	var screen := get_viewport_rect()
	var goat_to_screen := active_goat.get_global_transform_with_canvas()
	var body_on_screen := goat_to_screen * Rect2(active_goat.bitmap_body_rect())
	if screen.intersects(body_on_screen):
		offscreen_arrow.hide()
		return

	var angle := PI * 0.5 if body_on_screen.end.x <= screen.position.x else -PI * 0.5
	if body_on_screen.end.y <= screen.position.y:
		angle = PI
	elif body_on_screen.position.y >= screen.end.y:
		angle = 0.0
	var sprite_rect := offscreen_arrow.get_rect()
	var half_sprite := sprite_rect.position.abs().max(sprite_rect.end.abs()) * offscreen_arrow.scale
	var rotated_half_size := half_sprite.rotated(angle).abs().ceil()
	var inset := Vector2.ONE * OFFSCREEN_ARROW_MARGIN + rotated_half_size
	var minimum := screen.position + inset
	var maximum := screen.end - inset
	if minimum.x > maximum.x or minimum.y > maximum.y:
		offscreen_arrow.hide()
		return

	offscreen_arrow.position = body_on_screen.get_center().clamp(minimum, maximum)
	offscreen_arrow.rotation = angle
	offscreen_arrow.show()


func _physics_process(delta: float) -> void:
	while not pending_item_blasts.is_empty():
		var blast: Callable = pending_item_blasts.pop_front()
		blast.call()
	var previous_goat_position := active_goat.global_position
	var direction := _walk_direction()
	for target in goats:
		target.grapple_bounce_cooldown = maxf(0.0, target.grapple_bounce_cooldown - delta)
		if grapple_attached and target == active_goat:
			_step_grapple(delta)
		else:
			_step_goat(target, delta, direction if target == active_goat else 0.0)
	if not camera_follow_armed and (grapple_attached or not is_zero_approx(direction) or active_goat.jump_launch_speed > 0.0):
		camera_follow_armed = true
		camera_follow_origin = terrain_view.to_local(previous_goat_position)
	if camera_follows_goat:
		if not camera_goat_transition.is_running():
			_set_camera_target(active_goat.global_position)
	elif camera_follow_armed and active_goat.global_position != previous_goat_position \
			and Time.get_ticks_msec() - last_manual_camera_msec >= CAMERA_FOLLOW_IDLE_MSEC:
		var displacement := (terrain_view.to_local(active_goat.global_position) - camera_follow_origin).abs()
		if displacement.x >= CAMERA_FOLLOW_MOVE_PIXELS or displacement.y >= CAMERA_FOLLOW_MOVE_PIXELS:
			_pan_camera_to_active_goat()
	if grapple_line.visible:
		if grapple_miss_time > 0.0:
			grapple_miss_time = maxf(0.0, grapple_miss_time - delta)
			if grapple_miss_time == 0.0:
				grapple_line.hide()

	var can_aim := (
		active_goat.mode != Goat.Mode.GOAT_ONLY
		and _can_control_movement()
		and is_zero_approx(direction)
	)
	if can_aim and not grapple_attached and not console.visible:
		var elevation := Input.get_axis(&"aim_down", &"aim_up")
		active_goat.aim_degrees = clampf(active_goat.aim_degrees + elevation * aim_speed * delta, -90.0, 90.0)

	active_goat.update_aim_pose(can_aim or grapple_attached, active_goat.aim_degrees, cursor_distance)
	if grapple_attached:
		var start_pixel := Vector2i(terrain_view.to_local(active_goat.muzzle_origin()).floor())
		if start_pixel != grapple_start_pixel:
			grapple_start_pixel = start_pixel
			grapple_line.queue_redraw()
	_update_shot_charge(delta)
	_update_charge_meters()


func _update_charge_meters() -> void:
	active_goat.update_jump_meter(is_charging_jump and not jump_released, jump_charge / jump_charge_time)
	active_goat.update_shot_meter(is_charging_shot, shot_charge / fire_charge_time)


func _select_next_goat() -> void:
	var next_goat := goats[(goats.find(active_goat) + 1) % goats.size()]
	if next_goat == active_goat:
		return
	_cancel_jump()
	is_charging_shot = false
	shot_released = false
	walk_start_msec = 0
	_update_charge_meters()
	active_goat.update_aim_pose(false, active_goat.aim_degrees, cursor_distance)
	_disconnect_grapple()
	if active_goat.status == Goat.Status.ACTIVE:
		active_goat.status = Goat.Status.ALIVE
	active_goat = next_goat
	if active_goat.status == Goat.Status.ALIVE:
		active_goat.status = Goat.Status.ACTIVE
	_show_active_goat_arrow()
	_pan_camera_to_active_goat()


func _show_active_goat_arrow() -> void:
	if is_instance_valid(active_goat_arrow):
		active_goat_arrow.queue_free()

	var arrow := Sprite2D.new()
	arrow.texture = ACTIVE_GOAT_ARROW_TEXTURE
	arrow.hframes = roundi(arrow.texture.get_width() / float(arrow.texture.get_height()))
	arrow.position = Vector2(0, -34)
	arrow.scale = Vector2(2, 2)
	arrow.z_index = 1
	active_goat.add_child(arrow)
	active_goat_arrow = arrow

	var animation := arrow.create_tween()
	for frame in range(1, arrow.hframes):
		animation.tween_interval(ACTIVE_GOAT_ARROW_FRAME_SECONDS)
		animation.tween_callback(arrow.set_frame.bind(frame))
	animation.tween_interval(ACTIVE_GOAT_ARROW_FRAME_SECONDS)
	animation.tween_callback(arrow.queue_free)


func _on_goat_mode_changed(target: Goat) -> void:
	if target != active_goat:
		return
	if target.mode != Goat.Mode.GRAPPLE:
		_disconnect_grapple()
	walk_start_msec = 0
	if active_goat.mode == Goat.Mode.LAUNCHER:
		_cancel_jump()
	else:
		is_charging_shot = false
		shot_released = false
	_update_charge_meters()


func _input(event: InputEvent) -> void:
	if not _can_use_ground_controls():
		return
	if event.is_action(&"reload_level"):
		if event.is_action_pressed(&"reload_level"):
			_reload_level.call_deferred()
		get_viewport().set_input_as_handled()
		return
	if event.is_action(&"toggle_console"):
		if event.is_action_pressed(&"toggle_console"):
			_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if console.visible:
		if event.is_action_pressed(&"cancel"):
			_toggle_console()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"console_history_previous", true) and console.recall_previous_command():
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"select_next_goat"):
		_select_next_goat()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_launcher"):
		if grapple_attached:
			get_viewport().set_input_as_handled()
			return
		match active_goat.mode:
			Goat.Mode.GOAT_ONLY:
				active_goat.mode = Goat.Mode.GRAPPLE
			Goat.Mode.GRAPPLE:
				active_goat.mode = Goat.Mode.LAUNCHER
			Goat.Mode.LAUNCHER:
				active_goat.mode = Goat.Mode.GOAT_ONLY
		get_viewport().set_input_as_handled()
		return
	var walk_left := event.is_action_pressed(&"walk_left")
	if (walk_left or event.is_action_pressed(&"walk_right")) \
			and not grapple_attached and _can_control_movement() and not is_charging_jump:
		var direction := -1.0 if walk_left else 1.0
		if active_goat.mode == Goat.Mode.LAUNCHER and direction != facing:
			walk_start_msec = Time.get_ticks_msec() + WALK_HOLD_MSEC
		else:
			walk_start_msec = 0
		facing = direction
	if event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _handle_camera_input(event: InputEvent) -> void:
	if not _can_use_ground_controls() and not (
			event is InputEventMouseMotion
			or event.is_action(&"arena_pointer")
			or event.is_action(&"toggle_mouse_capture")
			or (grapple_attached and (
				event.is_action(&"fire_grapple")
				or event.is_action(&"camera_zoom_in")
				or event.is_action(&"camera_zoom_out")
			))
	):
		get_viewport().set_input_as_handled()
		return
	var tree := get_tree()
	if event.is_action(&"toggle_pause"):
		if event.is_action_pressed(&"toggle_pause"):
			tree.paused = not tree.paused
			if not tree.paused:
				# A release during pause should cancel the charge instead of firing it.
				if not jump_released and not Input.is_action_pressed(&"charge_jump"):
					is_charging_jump = false
				if not shot_released and not Input.is_action_pressed(&"charge_weapon"):
					is_charging_shot = false
			_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	if console.visible and not tree.paused:
		return
	if event.is_action_pressed(&"toggle_mouse_capture"):
		mouse_unlocked = not mouse_unlocked
		_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	# Handle zoom in both cursor modes before routing pointer input.
	var zoom_in := event.is_action_pressed(&"camera_zoom_in")
	if zoom_in or event.is_action_pressed(&"camera_zoom_out"):
		var anchor_offset := Vector2.ZERO
		if mouse_unlocked:
			anchor_offset = _pointer_position(event) - get_viewport_rect().get_center()
		_zoom_camera(1 if zoom_in else -1, anchor_offset)
		get_viewport().set_input_as_handled()
		return
	if mouse_unlocked:
		_handle_unlocked_pointer(event)
		return
	if event is InputEventMouseMotion and event.relative != Vector2.ZERO:
		_note_manual_camera_control()
		camera_target += event.relative * CAPTURED_MOUSE_SENSITIVITY / arena_camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _pointer_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport().get_mouse_position()


func _handle_unlocked_pointer(event: InputEvent) -> void:
	if event.is_action_pressed(&"arena_pointer"):
		if not pointer_press_position.is_finite():
			pointer_press_position = _pointer_position(event)
			camera_dragging = false
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"arena_pointer"):
		if not Input.is_action_pressed(&"arena_pointer"):
			var pointer := _pointer_position(event)
			if pointer_press_position.is_finite() and not camera_dragging \
					and pointer.distance_to(pointer_press_position) < CAMERA_DRAG_THRESHOLD and not get_tree().paused:
				var at: Vector2 = terrain_view.get_global_transform_with_canvas().affine_inverse() * pointer
				_drop_dirt(at)
			pointer_press_position = Vector2.INF
			camera_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and pointer_press_position.is_finite() \
			and Input.is_action_pressed(&"arena_pointer"):
		var motion: Vector2 = event.relative if camera_dragging else event.position - pointer_press_position
		if camera_dragging or motion.length() >= CAMERA_DRAG_THRESHOLD:
			camera_dragging = true
			if motion != Vector2.ZERO:
				_note_manual_camera_control()
				camera_target -= motion / arena_camera.zoom
				_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _drop_dirt(at: Vector2) -> void:
	var pixel := Vector2i(at.floor())
	if terrain.is_solid(pixel.x, pixel.y):
		return
	_spawn_dirt(at, DIRT_TEXTURE)


func _spawn_dirt(at: Vector2, stamp: Texture2D, launch_velocity := Vector2.ZERO) -> void:
	var dirt := DirtDrop.new()
	dirt.texture = stamp
	dirt.position = at
	dirt.velocity = launch_velocity / terrain_view.scale
	dirt.terrain_view = terrain_view
	dirt.gravity = DIRT_GRAVITY / terrain_view.scale.y
	dirt.max_spread_time = dirt_settle_time
	dirt.max_diagonal_steps = dirt_diagonal_steps
	dirt.deposited.connect(_lift_goats_after_deposit)
	dirt.tree_exited.connect(_on_dirt_drop_exited)
	active_dirt_drops += 1
	terrain_view.add_child(dirt)


func _on_dirt_drop_exited() -> void:
	active_dirt_drops -= 1


func _lift_goats_after_deposit(grains: Dictionary[Vector2i, Color]) -> void:
	for target in goats:
		var body := _bitmap_body_rect(target.position)
		for pixel: Vector2i in grains:
			if body.has_point(pixel) and terrain.is_solid(pixel.x, pixel.y):
				var clear_position := target.position + Vector2.UP
				while not _body_is_free(clear_position):
					clear_position.y -= 1.0
				target.position = clear_position
				target.velocity.y = minf(target.velocity.y, 0.0)
				if grapple_attached and target == active_goat:
					var pivot := _rope_pivot()
					var span := target.muzzle_origin() - pivot
					var remaining := GRAPPLE_RANGE - _pinned_length()
					if span.length() > remaining:
						var limited := target.position + (span.limit_length(remaining) - span)
						if not _body_is_free(limited):
							_disconnect_grapple()
							break
						target.position = limited
					grapple_length = _pinned_length() + target.muzzle_origin().distance_to(pivot)
				break


func _toggle_console() -> void:
	var is_open := not console.visible
	if is_open:
		_cancel_jump()
		is_charging_shot = false
		shot_released = false
	console.set_open(is_open)
	_update_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if console.visible:
		return
	if grapple_attached and event.is_action(&"fire_grapple"):
		if event.is_action_pressed(&"fire_grapple"):
			_disconnect_grapple()
		get_viewport().set_input_as_handled()
		return
	if not _can_use_ground_controls():
		return
	if event.is_action(&"fire_grapple") and active_goat.mode == Goat.Mode.GRAPPLE:
		if event.is_action_pressed(&"fire_grapple"):
			_fire_grapple()
		get_viewport().set_input_as_handled()
	elif event.is_action(&"charge_jump") and _mode_allows_jump():
		if grapple_attached:
			if event.is_action_pressed(&"charge_jump"):
				_bounce_on_grapple()
		else:
			super(event)
		get_viewport().set_input_as_handled()
	elif event.is_action(&"charge_weapon") and active_goat.mode == Goat.Mode.LAUNCHER:
		if event.is_action_pressed(&"charge_weapon") and not is_charging_shot and _shot_simulation_finished():
			is_charging_shot = true
			shot_charge = 0.0
		elif event.is_action_released(&"charge_weapon") and not Input.is_action_pressed(&"charge_weapon") and is_charging_shot:
			shot_released = true
		get_viewport().set_input_as_handled()


func _bounce_on_grapple() -> void:
	if not is_zero_approx(active_goat.grapple_bounce_cooldown):
		return
	var tangent := _rope_pivot().direction_to(active_goat.muzzle_origin()).orthogonal()
	if tangent == Vector2.ZERO:
		return
	if is_zero_approx(tangent.y):
		# Directly below the pivot, either side of the arc rises.
		var direction := Input.get_axis(&"walk_left", &"walk_right")
		if is_zero_approx(direction):
			direction = facing
		tangent = Vector2(direction, 0.0).normalized()
	elif tangent.y > 0.0:
		tangent = -tangent
	var gravity := active_goat.get_gravity().length() * gravity_scale
	var speed := sqrt(2.0 * gravity * GRAPPLE_BOUNCE_HEIGHT)
	active_goat.velocity = tangent * minf(speed, GRAPPLE_MAX_SPEED) * GRAPPLE_BOUNCE_STRENGTH
	active_goat.grapple_bounce_cooldown = GRAPPLE_BOUNCE_COOLDOWN


func _step_grapple(delta: float) -> void:
	var reel := Input.get_axis(&"aim_up", &"aim_down") if not console.visible else 0.0
	var steer := Input.get_axis(&"walk_left", &"walk_right") if not console.visible else 0.0
	var gravity := active_goat.get_gravity() * gravity_scale
	# Keep each sweep shorter than one terrain cell, even on a fast swing.
	var speed_bound := active_goat.velocity.length() + GRAPPLE_REEL_SPEED + (gravity.length() + GRAPPLE_SWING_ACCELERATION) * delta
	speed_bound = minf(speed_bound, GRAPPLE_MAX_SPEED)
	if reel < 0.0:
		speed_bound = GRAPPLE_MAX_SPEED
	var cell_size := minf(terrain_view.scale.x, terrain_view.scale.y)
	var steps := maxi(1, ceili(speed_bound * delta / (0.5 * cell_size)))
	var dt := delta / steps
	for i in steps:
		var grounded := _is_grounded(active_goat)
		var reel_speed := minf(reel, 0.0) if grounded else reel
		if grounded and is_zero_approx(reel_speed) and active_goat.velocity.length() < 1.0:
			break
		var origin := active_goat.muzzle_origin()
		var pivot := _rope_pivot()
		var pinned := _pinned_length()
		var free_length := maxf(0.0, grapple_length - pinned)
		var radial := pivot.direction_to(origin)
		if radial == Vector2.ZERO:
			radial = -active_goat.aim_direction()
		var tangent := radial.orthogonal()
		var acceleration := gravity
		if not grounded:
			acceleration.x += steer * GRAPPLE_SWING_ACCELERATION
		var speed := (active_goat.velocity + acceleration * dt).dot(tangent)
		var length_now := clampf(free_length + reel_speed * GRAPPLE_REEL_SPEED * dt, minf(free_length, 1.0), GRAPPLE_RANGE - pinned)
		if not grounded:
			speed *= exp(-GRAPPLE_SWING_DRAG * dt)
		# Reeling and swinging share the same travel budget for this collision step.
		var radial_speed := (length_now - free_length) / dt
		var max_tangent := sqrt(maxf(0.0, GRAPPLE_MAX_SPEED ** 2 - radial_speed ** 2))
		speed = clampf(speed, -max_tangent, max_tangent)
		var turn_radius := sqrt(free_length * length_now)
		var next_radial := (radial * maxf(turn_radius, 0.001) + tangent * speed * dt).normalized()
		var motion := pivot + next_radial * length_now - origin
		var start := active_goat.position
		var candidate := start + motion
		# Resolve corners and slopes along their contact normals so the circle can slide.
		for iteration in 4:
			var correction := _grapple_contact(candidate)
			if correction.is_zero_approx():
				break
			# The ground-control probe reaches slightly below the feet. A goat
			# crossing that gap is still airborne until it actually hits terrain.
			var airborne := not grounded or _grapple_contact(start + Vector2.DOWN * 0.001).is_zero_approx()
			if airborne and (tangent * speed).dot(correction) < 0.0:
				# A taut rope leaves one direction of travel along the arc.
				# Rebound from the last clear position, keeping its rope length.
				active_goat.velocity = -tangent * speed * GRAPPLE_SWING_RESTITUTION
				return
			candidate += correction
		var next_origin := origin + (candidate - start)
		var reached := next_origin.distance_to(pivot)
		# Contact can limit reeling. Only accept a length within this step's reel travel.
		var shortest := minf(free_length, length_now)
		var longest := maxf(free_length, length_now)
		if not _grapple_contact(candidate).is_zero_approx() or reached < shortest - 0.001 or reached > longest + 0.001:
			active_goat.velocity = Vector2.ZERO
			break
		if _update_rope_contacts(pivot, origin, next_origin):
			continue
		active_goat.position = candidate
		var velocity := (candidate - start) / dt
		var new_length := clampf(reached, shortest, longest)
		if not grounded and new_length > 0.0 and new_length != free_length and candidate == start + motion:
			# Amplify the speed change from reeling around the current pivot.
			var end_tangent := pivot.direction_to(next_origin).orthogonal()
			var end_speed := speed * pow(free_length / new_length, GRAPPLE_REEL_MOMENTUM_EXPONENT)
			velocity += end_tangent * (end_speed - velocity.dot(end_tangent))
		active_goat.velocity = velocity.limit_length(GRAPPLE_MAX_SPEED)
		grapple_length = pinned + new_length


func _rope_pivot() -> Vector2:
	return grapple_anchor if grapple_bends.is_empty() else grapple_bends.back().joint


func _pinned_length() -> float:
	return 0.0 if grapple_bends.is_empty() else grapple_bends.back().pinned_length


func _update_rope_contacts(pivot: Vector2, origin: Vector2, next_origin: Vector2) -> bool:
	if origin == next_origin:
		return false
	var local_pivot := terrain_view.to_local(pivot)
	var old_span := terrain_view.to_local(origin) - local_pivot
	var new_span := terrain_view.to_local(next_origin) - local_pivot
	if not grapple_bends.is_empty():
		var last := grapple_bends.size() - 1
		var previous := grapple_anchor if last == 0 else grapple_bends[last - 1].joint
		var incoming := pivot - previous
		# Lift the last joint when the free rope swings back through the pinned run.
		if incoming.normalized().cross(next_origin - pivot) * grapple_bends[last].winding < -0.0001:
			var previous_local := terrain_view.to_local(previous)
			if not _rope_span_blocked(previous_local, local_pivot + old_span) and not _rope_span_blocked(previous_local, local_pivot + new_span):
				grapple_bends.pop_back()
				grapple_line.queue_redraw()
				return true

	var old_length := old_span.length()
	var new_length := new_span.length()
	var old_direction := old_span.normalized()
	var new_direction := new_span.normalized()
	var chunk_start := local_pivot
	var distance := 0.0
	while distance < new_length:
		distance = minf(distance + GRAPPLE_CHUNK_PIXELS, new_length)
		var joint := local_pivot + new_direction * distance
		var old_joint := local_pivot + old_direction * minf(distance, old_length)
		# Test the entire chunk and the path swept by its distal joint.
		if _rope_span_blocked(chunk_start, joint) or _rope_span_blocked(old_joint, joint):
			var winding := signf(old_span.cross(new_span))
			if distance < minf(old_length, new_length) - 0.001 and winding != 0.0:
				var bend := RopeBend.new()
				bend.joint = terrain_view.to_global(old_joint)
				bend.pinned_length = _pinned_length() + pivot.distance_to(bend.joint)
				bend.winding = winding
				grapple_bends.append(bend)
				grapple_line.queue_redraw()
			else:
				# The final partial chunk has no free joint beyond it.
				active_goat.velocity = Vector2.ZERO
			return true
		chunk_start = joint
	return false


func _rope_span_blocked(from: Vector2, to: Vector2) -> bool:
	var motion := to - from
	if motion.length_squared() < 0.00000001:
		return false
	# The anchor can lie exactly on a solid cell's edge. Sample its outgoing side.
	var start := from + motion.limit_length(0.0005)
	return _grapple_hit_fraction(start, to - start) >= 0.0


func _grapple_contact(at: Vector2) -> Vector2:
	# Inscribe the circle at the feet so switching shapes keeps the same ground level.
	var radius := 0.5 * mini(goat_body.size.x, goat_body.size.y)
	var center := at + Vector2(goat_body.get_center().x, goat_body.end.y - radius)
	var cell := terrain_view.scale
	var first := Vector2i(((center - Vector2.ONE * radius) / cell).floor())
	var last := Vector2i(((center + Vector2.ONE * radius) / cell).floor())
	var correction := Vector2.ZERO
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not terrain.is_solid(x, y):
				continue
			var corner := Vector2(x, y) * cell
			var offset := center - center.clamp(corner, corner + cell)
			var distance := offset.length()
			if distance < radius and radius - distance > correction.length():
				correction = (offset / distance if distance > 0.0 else Vector2.UP) * (radius - distance)
	return correction


func _nearest_standing_position(at: Vector2) -> Vector2:
	if _body_is_free(at):
		return at
	var distance := 1
	while true:
		for offset in range(-distance, distance + 1):
			for step: Vector2 in [Vector2(offset, -distance), Vector2(offset, distance),
					Vector2(-distance, offset), Vector2(distance, offset)]:
				if _body_is_free(at + step):
					return at + step
		distance += 1
	return at


func _disconnect_grapple() -> void:
	if grapple_attached:
		active_goat.aim_locked = false
		# The standing rectangle can overlap a corner cleared by the circle.
		active_goat.position = _nearest_standing_position(active_goat.position)
		active_goat.last_ground_position = active_goat.position
	grapple_attached = false
	grapple_bends.clear()
	grapple_miss_time = 0.0
	grapple_line.hide()


func _fire_grapple() -> void:
	var origin := active_goat.muzzle_origin()
	var end := origin + active_goat.aim_direction() * GRAPPLE_RANGE
	var terrain_origin := terrain_view.to_local(origin)
	var terrain_end := terrain_view.to_local(end)
	var hit_fraction := _grapple_hit_fraction(terrain_origin, terrain_end - terrain_origin)
	grapple_miss_time = GRAPPLE_MISS_SECONDS if hit_fraction < 0.0 else 0.0
	if hit_fraction >= 0.0:
		grapple_attached = true
		active_goat.aim_locked = true
		_cancel_jump()
		terrain_end = terrain_origin.lerp(terrain_end, hit_fraction)
		grapple_anchor = terrain_view.to_global(terrain_end)
		grapple_length = origin.distance_to(grapple_anchor)
		active_goat.velocity = Vector2.ZERO
		active_goat.update_walk_pose(false)
	grapple_start_pixel = Vector2i(terrain_origin.floor())
	grapple_end_pixel = Vector2i(terrain_end.floor())
	grapple_line.show()
	grapple_line.queue_redraw()


func _draw_grapple_line() -> void:
	if grapple_bends.is_empty():
		_draw_rope_span(grapple_start_pixel, grapple_end_pixel)
		return
	var from := grapple_end_pixel
	for bend in grapple_bends:
		var joint := Vector2i(terrain_view.to_local(bend.joint).floor())
		_draw_rope_span(from, joint)
		from = joint
	_draw_rope_span(from, grapple_start_pixel)


func _draw_rope_span(from: Vector2i, to: Vector2i) -> void:
	# Each step fills one pixel on the terrain grid.
	var pixel := from
	var distance := (to - pixel).abs()
	var step := (to - pixel).sign()
	var error := distance.x - distance.y
	while true:
		grapple_line.draw_rect(Rect2(Vector2(pixel), Vector2.ONE), Color.WHITE)
		if pixel == to:
			break
		var doubled_error := 2 * error
		if doubled_error > -distance.y:
			error -= distance.y
			pixel.x += step.x
		if doubled_error < distance.x:
			error += distance.x
			pixel.y += step.y


func _grapple_hit_fraction(origin: Vector2, motion: Vector2) -> float:
	# Visit each bitmap cell in the order the shot enters it.
	var cell := Vector2i(origin.floor())
	var step := Vector2i(motion.sign())
	var edge_offset := Vector2i(maxi(step.x, 0), maxi(step.y, 0))

	var fraction := 0.0
	while fraction <= 1.0:
		if terrain.is_solid(cell.x, cell.y):
			return fraction
		var edge := cell + edge_offset
		var crossing_x := (edge.x - origin.x) / motion.x if step.x != 0 else INF
		var crossing_y := (edge.y - origin.y) / motion.y if step.y != 0 else INF
		fraction = minf(crossing_x, crossing_y)
		if crossing_x == fraction:
			cell.x += step.x
		if crossing_y == fraction:
			cell.y += step.y
	return -1.0


func _zoom_camera(amount: int, anchor_offset: Vector2 = Vector2.ZERO) -> void:
	# The half-scale stop sits below the whole-number zoom levels.
	var next_level := clampf(floorf(camera_zoom_level) + amount, CAMERA_MIN_ZOOM, camera_max_zoom)
	if next_level == camera_zoom_level:
		return
	_note_manual_camera_control()
	camera_zoom_level = next_level
	if camera_zoom_transition and camera_zoom_transition.is_valid():
		camera_zoom_transition.kill()

	var block_size: float = zoom_material.get_shader_parameter("block_size")
	zoom_pixelation.show()
	camera_zoom_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	camera_zoom_transition.tween_method(_apply_camera_zoom.bind(anchor_offset),
			arena_camera.zoom.x, camera_zoom_level, ZOOM_TRANSITION_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_zoom_transition.parallel().tween_method(_set_zoom_block_size,
			block_size, ZOOM_PEAK_BLOCK_SIZE, ZOOM_TRANSITION_SECONDS * 0.5)
	camera_zoom_transition.parallel().tween_method(_set_zoom_block_size,
			ZOOM_PEAK_BLOCK_SIZE, 1.0, ZOOM_TRANSITION_SECONDS * 0.5) \
			.set_delay(ZOOM_TRANSITION_SECONDS * 0.5)
	camera_zoom_transition.tween_callback(zoom_pixelation.hide)


func _apply_camera_zoom(zoom_level: float, anchor_offset: Vector2) -> void:
	last_manual_camera_msec = Time.get_ticks_msec()
	if not camera_follows_goat:
		camera_follow_origin = terrain_view.to_local(active_goat.global_position)
	var previous_zoom := arena_camera.zoom.x
	# Keep the same world point under the screen anchor across the zoom step.
	camera_target += anchor_offset / previous_zoom - anchor_offset / zoom_level
	arena_camera.zoom = Vector2.ONE * zoom_level
	_clamp_camera_position()


func _set_zoom_block_size(block_size: float) -> void:
	zoom_material.set_shader_parameter("block_size", block_size)


func _update_mouse_mode() -> void:
	pointer_press_position = Vector2.INF
	camera_dragging = false
	var cursor_visible := mouse_unlocked or (console.visible and not get_tree().paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cursor_visible else Input.MOUSE_MODE_CAPTURED


func _pan_camera_to_active_goat() -> void:
	_cancel_goat_camera_transition()
	camera_follows_goat = true
	camera_goat_transition = create_tween()
	camera_goat_transition.tween_method(_interpolate_goat_camera.bind(camera_target),
			0.0, 1.0, GOAT_SWITCH_CAMERA_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _interpolate_goat_camera(weight: float, start: Vector2) -> void:
	_set_camera_target(start.lerp(_camera_target_in_bounds(active_goat.global_position), weight))


func _note_manual_camera_control() -> void:
	last_manual_camera_msec = Time.get_ticks_msec()
	camera_follow_origin = terrain_view.to_local(active_goat.global_position)
	camera_follow_armed = true
	camera_follows_goat = false
	_cancel_goat_camera_transition()


func _cancel_goat_camera_transition() -> void:
	if camera_goat_transition and camera_goat_transition.is_valid():
		camera_goat_transition.kill()


func _set_camera_target(target: Vector2) -> void:
	camera_target = target
	_clamp_camera_position()


func _camera_target_in_bounds(target: Vector2) -> Vector2:
	var half_view := (get_viewport_rect().size * 0.5 / arena_camera.zoom).min(arena_bounds.size * 0.5)
	return target.clamp(arena_bounds.position + half_view, arena_bounds.end - half_view)


func _clamp_camera_position() -> void:
	var half_view_pixels := get_viewport_rect().size * 0.5
	var camera_zoom := arena_camera.zoom
	camera_target = _camera_target_in_bounds(camera_target)
	# Snap the viewport origin to a render pixel without discarding small mouse movements.
	var origin_pixels := (camera_target * camera_zoom - half_view_pixels).round()
	arena_camera.position = (origin_pixels + half_view_pixels) / camera_zoom
	arena_camera.limit_enabled = true
	_update_camera_parallax()


func _update_camera_parallax() -> void:
	var camera_offset := arena_camera.position - arena_bounds.get_center()
	for layer in sky_layers:
		layer.update_parallax(camera_offset)


func _shake_camera() -> void:
	if camera_shake and camera_shake.is_valid():
		camera_shake.kill()
	_apply_camera_shake(0.0)
	camera_shake = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	camera_shake.tween_method(_apply_camera_shake, 0.0, 1.0, EXPLOSION_SHAKE_DURATION)


func _apply_camera_shake(progress: float) -> void:
	var strength := EXPLOSION_SHAKE_PIXELS * camera_zoom_level * (1.0 - progress) ** 2
	var motion := Vector2(cos(progress * TAU * 2.0), sin(progress * TAU * 1.0)) * strength
	arena_camera.offset = camera_rest_offset + motion.round() / arena_camera.zoom


func _update_shot_charge(delta: float) -> void:
	if not _can_use_ground_controls() or not _shot_simulation_finished():
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

	var charge_ratio := minf(shot_charge / fire_charge_time, 1.0)
	var power := lerpf(fire_min_amount, fire_max_amount, charge_ratio)
	_fire_missile(active_goat.aim_direction(), power)
	is_charging_shot = false
	shot_released = false


func _shot_simulation_finished() -> bool:
	return (
		not is_instance_valid(active_missile)
		and active_dirt_drops == 0
		and pending_item_blasts.is_empty()
		and get_tree().get_node_count_in_group(LevelItem.DETONATING_GROUP) == 0
	)


func _fire_missile(direction: Vector2, power: float = 1.0) -> Missile:
	if not _shot_simulation_finished():
		return null
	var missile := super(direction, power)
	if missile == null:
		return null
	active_missile = missile
	missile.terrain = terrain
	missile.terrain_pixel_size = terrain_view.scale
	missile.wind_acceleration = (float(wind_speed) / wind_max) * wind_scale
	missile.exploded_at.connect(_apply_missile_blast.bind(missile.blast_damage))
	missile.impacted.connect(_roll_wind)
	missile.trail_sampled.connect(_spawn_trail_smoke)
	return missile


func _apply_missile_blast(
	world_pixel: Vector2i, direct_hit: Area2D, travel_direction: Vector2, peak_damage: int
) -> void:
	var at := to_global(Vector2(world_pixel))
	var damage_center := terrain_view.to_global(terrain_view.to_local(at).floor())
	_apply_blast(at, damage_center, direct_hit, travel_direction, peak_damage)


func _queue_item_blast(center: Vector2, damage: int) -> void:
	pending_item_blasts.append(_apply_blast.bind(center, center, null, Vector2.ZERO, damage))


func _apply_blast(
	at: Vector2, damage_center: Vector2, direct_hit: Area2D, travel_direction: Vector2, peak_damage: int
) -> void:
	_play_explosion(to_local(at))
	_shake_camera()
	var pixel := Vector2i(terrain_view.to_local(at).floor())
	var radius := roundi(explosion_radius)
	# Damage signals sample the surface synchronously, before the bitmap changes.
	if direct_hit:
		direct_hit.apply_damage(peak_damage, travel_direction)
	_apply_area_damage(damage_center, radius * terrain_view.scale.x, peak_damage, direct_hit)
	var surface_normal := _estimate_impact_normal(pixel, travel_direction)
	var crater := terrain.carve_circle(pixel.x, pixel.y, radius, true)
	var scorch_width := roundi(scorch_radius_modifier)
	if scorch_width > 0:
		terrain_view.scorch_circle(pixel, radius + scorch_width, TERRAIN_BURN_COLOR)
	terrain_view.carve(crater.bounds)
	if is_instance_valid(crow):
		crow.check_perch_after_blast(terrain)
	_throw_blast_dirt(pixel, crater.erased_pixels, surface_normal)


func _apply_area_damage(center: Vector2, radius: float, peak_damage: int, direct_hit: Area2D) -> void:
	var hurtbox_count := get_tree().get_node_count_in_group(&"goat_hurtboxes")
	hurtbox_count += get_tree().get_node_count_in_group(&"level_items")
	if radius <= 0.0 or peak_damage <= 0 or hurtbox_count == 0:
		return
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = GoatHurtbox.COLLISION_MASK | LevelItem.COLLISION_MASK
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hits := get_world_2d().direct_space_state.intersect_shape(query, hurtbox_count)
	for hit in hits:
		var hurtbox: Area2D = hit.collider
		if hurtbox == direct_hit or hurtbox.is_queued_for_deletion():
			continue
		var shape_node: CollisionShape2D = hurtbox.collider
		# Measure to the nearest point of the hitbox so the entire item can receive damage.
		var bounds := shape_node.shape.get_rect()
		var nearest := shape_node.to_local(center).clamp(bounds.position, bounds.end)
		var distance := center.distance_to(shape_node.to_global(nearest))
		var falloff := clampf((1.0 - distance / radius) / 0.9, 0.0, 1.0)
		hurtbox.apply_damage(roundi(peak_damage * falloff))


func _estimate_impact_normal(center: Vector2i, travel_direction: Vector2) -> Vector2:
	# Nearby solid pixels pull inward. Reverse that direction to point toward open air.
	var inward := Vector2.ZERO
	for y in range(-4, 5):
		for x in range(-4, 5):
			if terrain.is_solid(center.x + x, center.y + y):
				inward += Vector2(x, y)
	if inward.is_zero_approx():
		return Vector2.UP if travel_direction.is_zero_approx() else -travel_direction
	return (-inward / terrain_view.scale).normalized()


func _throw_blast_dirt(center: Vector2i, erased_pixels: int, surface_normal: Vector2) -> void:
	var budget := erased_pixels / 8.0
	var smallest: int = BLAST_DIRT_PIXELS.back()
	if budget < smallest * 0.5:
		return
	var largest: int = BLAST_DIRT_PIXELS.front()
	var max_chunks := clampi(floori(budget / smallest), 3, 5)
	var min_chunks := clampi(ceili(budget / largest), 3, max_chunks)
	var chunk_count := randi_range(min_chunks, max_chunks)

	# Keep one frame combination for each reachable pixel total.
	var combinations: Dictionary[int, PackedInt32Array] = {0: PackedInt32Array()}
	for chunk in chunk_count:
		var next: Dictionary[int, PackedInt32Array] = {}
		for total in combinations:
			for frame in BLAST_DIRT_PIXELS.size():
				var new_total: int = total + BLAST_DIRT_PIXELS[frame]
				if not next.has(new_total):
					var frames := combinations[total].duplicate()
					frames.append(frame)
					next[new_total] = frames
		combinations = next
	var best_total := 0
	for total in combinations:
		if absf(total - budget) < absf(best_total - budget) or best_total == 0:
			best_total = total

	var sheet := BLAST_DIRT_TEXTURE.get_image()
	var size := Vector2i.ONE * BLAST_DIRT_FRAME_SIZE
	var frames := combinations[best_total]
	for frame in frames:
		var region := Rect2i(Vector2i(frame * size.x, 0), size)
		var stamp := ImageTexture.create_from_image(sheet.get_region(region))
		var angle := randf_range(-PI * 0.42, PI * 0.42)
		var launch_velocity := surface_normal.rotated(angle) * randf_range(140.0, 220.0)
		_spawn_dirt(Vector2(center), stamp, launch_velocity)


func _play_explosion(hit_position: Vector2) -> void:
	var explosion := Sprite2D.new()
	explosion.texture = EXPLOSION_TEXTURE
	explosion.hframes = roundi(EXPLOSION_TEXTURE.get_width() / float(EXPLOSION_TEXTURE.get_height()))
	explosion.position = hit_position
	explosion.scale = terrain_view.scale
	explosion.z_index = 1
	add_child(explosion)

	var animation := explosion.create_tween()
	for frame in range(1, explosion.hframes):
		animation.tween_interval(EXPLOSION_FRAME_SECONDS)
		animation.tween_property(explosion, "frame", frame, 0.0)
	animation.tween_interval(EXPLOSION_FRAME_SECONDS)
	animation.tween_callback(explosion.queue_free)
	_spawn_explosion_smoke(hit_position)


func _spawn_explosion_smoke(center: Vector2) -> void:
	_spawn_smoke_burst(center, randi_range(6, 10), SMOKE_SPAWN_RADIUS)


func _on_goat_bounced(target: Goat) -> void:
	var impact_position := target.position + Vector2(0, goat_body.end.y)
	_spawn_smoke_burst(impact_position, randi_range(1, 2), 0.0)


func _spawn_smoke_burst(center: Vector2, count: int, radius: float) -> void:
	for particle in range(count):
		var direction := Vector2.from_angle(randf() * TAU)
		var spawn_position := center + direction * (sqrt(randf()) * radius)
		var first_frame := randi_range(0, SMOKE_FRAME_COUNT - 1)
		var velocity := direction * randf_range(6.0, 120.0)
		_spawn_smoke(spawn_position, first_frame, SMOKE_FRAME_SECONDS, velocity)


func _spawn_trail_smoke(at: Vector2) -> void:
	var offset := Vector2(
		randf_range(-TRAIL_SMOKE_JITTER, TRAIL_SMOKE_JITTER),
		randf_range(-TRAIL_SMOKE_JITTER, TRAIL_SMOKE_JITTER)
	)
	var first_frame := randi_range(TRAIL_SMOKE_MIN_START_FRAME, TRAIL_SMOKE_MAX_START_FRAME)
	var wind_drift := (float(wind_speed) / wind_max) * TRAIL_SMOKE_WIND_SPEED
	var velocity := Vector2(wind_drift, -TRAIL_SMOKE_RISE_SPEED)
	_spawn_smoke(at + offset, first_frame, TRAIL_SMOKE_FRAME_SECONDS, velocity)


func _spawn_smoke(at: Vector2, first_frame: int, frame_seconds: float, velocity: Vector2) -> void:
	var smoke := Sprite2D.new()
	smoke.texture = SMOKE_TEXTURE
	smoke.hframes = SMOKE_FRAME_COUNT
	smoke.frame = first_frame
	smoke.position = at
	smoke.scale = terrain_view.scale
	smoke.z_index = 1
	add_child(smoke)

	var lifetime := (SMOKE_FRAME_COUNT - first_frame) * frame_seconds
	smoke.create_tween().tween_property(smoke, "position", at + velocity * lifetime, lifetime)

	var animation := smoke.create_tween()
	for frame in range(first_frame + 1, SMOKE_FRAME_COUNT):
		animation.tween_interval(frame_seconds)
		animation.tween_callback(smoke.set_frame.bind(frame))
	animation.tween_interval(frame_seconds)
	animation.tween_callback(smoke.queue_free)


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


func _apply_leaf_count() -> void:
	var layer_count := leaf_layers.size()
	var per_layer := floori(float(leaf_count) / layer_count)
	var remainder := leaf_count % layer_count
	for index in layer_count:
		leaf_layers[index].set_leaf_count(per_layer + int(index < remainder))
