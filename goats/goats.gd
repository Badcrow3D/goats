extends "res://goats/goat_controller.gd"

const Goat := preload("res://goats/goat.gd")

class Team:
	var id: int
	var team_name: String
	var color: Color
	var goats: Array[Goat] = []

	func _init(team_id: int, display_name: String, team_color: Color) -> void:
		id = team_id
		team_name = display_name
		color = team_color


const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 4.0
const WALK_HOLD_MSEC := 80
const FLAT_LAUNCHER_COLUMN := 10.0
const LAUNCHER_RETURN_SPEED := 30.0
const RIGHT_AIM_ORIGIN := Vector2(-3, -6)
const LEFT_AIM_ORIGIN := Vector2(2, -6)
const MAX_WIND_LEVEL := 5
const WIND_ACCELERATION_PER_LEVEL := 20.0
const DEFAULT_EXPLOSION_RADIUS := 18.0
const MAX_STEP_UP := 2
const MAX_STEP_DOWN := 2
const TERRAIN_BURN_COLOR := Color("#4c4947")
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
	"scorch_radius_modifier": 0.0,
	"gravity_scale": 0.05,
}

@export var aim_speed := 90.0
@export var cursor_distance := 40.0
@export_range(1, 8, 1) var camera_max_zoom := 2

@onready var player_goat: Goat = $Goat
@onready var standing_goat: Goat = $StandingGoat
@onready var aim_pose: Sprite2D = $Goat/AimPose
@onready var aim_cursor: Sprite2D = $Goat/AimCursor
@onready var arena_camera: Camera2D = $ArenaCamera
@onready var terrain_view: TerrainView = $Terrain
@onready var wind_layers := [
	$Sky/CloudsFar, $Sky/CloudsMiddle, $Sky/CloudsNear,
	$Sky/LeavesFar, $Sky/LeavesMiddle, $Sky/LeavesNear,
]
@onready var camera_target := arena_camera.position
@onready var console: CanvasLayer = $Console
@onready var console_output: RichTextLabel = $Console/Panel/Margin/Rows/Output
@onready var console_input: LineEdit = $Console/Panel/Margin/Rows/Input

var fire_charge_time := 2.0
var fire_min_amount := 0.25
var fire_max_amount := 3.0
var explosion_radius := DEFAULT_EXPLOSION_RADIUS
var scorch_radius_modifier := 3.0
var sprite_layers: Dictionary[String, bool] = {"goat": true, "backpack": true, "launcher": true}
var showing_aim_pose := false
var aim_degrees := 0.0
var walk_start_msec := 0
var shot_charge := 0.0
var is_charging_shot := false
var shot_released := false
var restoring_launcher := false
var launcher_column := FLAT_LAUNCHER_COLUMN
var mouse_unlocked := false
var arena_bounds: Rect2
var terrain: Terrain
var goat_body: Rect2i
var player_spawn_x: int
var standing_spawn_x: int
var standing_fall_speed := 0.0
var wind_level := 0
var teams: Dictionary[int, Team] = {}


func _ready() -> void:
	super()
	_setup_level()
	var player_team := Team.new(player_goat.team_id, "Blue", Color.CORNFLOWER_BLUE)
	player_team.goats.append(player_goat)
	teams[player_team.id] = player_team
	var opposing_team := Team.new(standing_goat.team_id, "Orange", Color.DARK_ORANGE)
	opposing_team.goats.append(standing_goat)
	teams[opposing_team.id] = opposing_team
	for layer in wind_layers:
		layer.setup(arena_bounds)
	_set_wind(randi_range(-MAX_WIND_LEVEL, MAX_WIND_LEVEL))
	_update_mouse_mode()
	get_viewport().size_changed.connect(_clamp_camera_position)
	camera_target = goat.global_position
	_zoom_camera(1)
	_load_tuning()
	var font := console_output.get_theme_font("normal_font")
	var font_size := console_output.get_theme_font_size("normal_font_size")
	console_output.custom_minimum_size.y = ceilf(font.get_height(font_size)) * 10
	console_input.text_submitted.connect(_run_console_command)
	_update_aim_display(0.0, 0.0)
	_apply_sprite_layers()


func _setup_level() -> void:
	var image := terrain_view.texture.get_image().duplicate() as Image
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
	standing_spawn_x = roundi(arena_bounds.size.x * 0.6)
	goat.position = _spawn_at(player_spawn_x)
	standing_goat.position = _spawn_at(standing_spawn_x)


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
	var motion := goat.velocity * delta
	var dy := 0.0 if grounded else _sweep_vertical(goat.position, motion.y)
	goat.position.y += dy
	if not is_equal_approx(dy, motion.y) or _is_grounded():
		goat.position.y = roundf(goat.position.y)
		goat.velocity.y = 0.0

	var steps := maxi(1, ceili(absf(motion.x)))
	var step_x := Vector2(motion.x / steps, 0.0)
	for i in steps:
		var next := goat.position + step_x
		if grounded:
			next = _follow_slope(next)
		if not _body_is_free(next):
			break
		goat.position = next

	if goat.position.y > arena_bounds.end.y or goat.position.x < -goat_body.size.x \
			or goat.position.x > arena_bounds.end.x + goat_body.size.x:
		goat.position = _spawn_at(player_spawn_x)
		goat.velocity = Vector2.ZERO
	return goat.position.x - start.x


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


func _settle_standing_goat(delta: float) -> void:
	if not _body_is_free(standing_goat.position + Vector2.DOWN):
		standing_goat.position.y = roundf(standing_goat.position.y)
		standing_fall_speed = 0.0
		return
	standing_fall_speed += goat.get_gravity().y * gravity_scale * delta
	var distance := standing_fall_speed * delta
	var moved := _sweep_vertical(standing_goat.position, distance)
	standing_goat.position.y += moved
	if not is_equal_approx(moved, distance):
		standing_fall_speed = 0.0
	if standing_goat.position.y > arena_bounds.end.y:
		standing_goat.position = _spawn_at(standing_spawn_x)
		standing_fall_speed = 0.0


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
	jump_maximum = maxf(jump_minimum, jump_maximum)
	fire_max_amount = maxf(fire_min_amount, fire_max_amount)
	for layer: String in sprite_layers:
		var saved: Variant = config.get_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
		if saved is bool:
			sprite_layers[layer] = saved


func _run_console_command(command: String) -> void:
	console_input.clear()
	var words := command.replace("\t", " ").split(" ", false)
	if words.is_empty():
		return

	var lines := PackedStringArray(["> " + command])
	match words[0]:
		"vars":
			if words.size() != 1:
				lines.append("Usage: vars")
			else:
				for field: String in TUNING_FLOORS:
					lines.append("%s = %s" % [field, get(field)])
				for layer: String in sprite_layers:
					lines.append("%s = %s" % [layer, sprite_layers[layer]])
		"set":
			lines.append(_set_console_variable(words))
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
	if sprite_layers.has(field):
		if value_text != "true" and value_text != "false":
			return "%s expects true or false." % field
		sprite_layers[field] = value_text == "true"
		_apply_sprite_layers()
		_save_tuning()
		return "%s = %s" % [field, sprite_layers[field]]

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
		console_output.text += "\nCould not reset level: " + error_string(error)
		console_output.scroll_to_line(console_output.get_line_count() - 1)


func _save_tuning() -> void:
	var config := ConfigFile.new()
	for key: String in TUNING_FLOORS:
		config.set_value(TUNING_SECTION, key, get(key))
	for layer: String in sprite_layers:
		config.set_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
	var error := config.save(TUNING_PATH)
	if error != OK:
		push_warning("Could not save tuning settings: %s" % error_string(error))


func _walk_direction() -> float:
	if console.visible or Time.get_ticks_msec() < walk_start_msec:
		return 0.0
	return float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))


func _physics_process(delta: float) -> void:
	super(delta)
	_settle_standing_goat(delta)
	player_goat.facing_direction = Goat.Facing.LEFT if facing < 0.0 else Goat.Facing.RIGHT
	if is_walking:
		restoring_launcher = true
		launcher_column = FLAT_LAUNCHER_COLUMN
	elif is_charging_jump or not _is_grounded():
		restoring_launcher = false

	var can_aim := (
		_is_grounded()
		and not is_charging_jump
		and jump_pause_remaining == 0.0
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
		_update_aim_display(snapped_aim, delta)
	_apply_sprite_layers()
	_update_shot_charge(delta)


func _apply_sprite_layers() -> void:
	# The aiming atlas is composited. Use the layered idle pose for individual layer previews.
	aim_pose.visible = showing_aim_pose and sprite_layers["goat"] and sprite_layers["backpack"] and sprite_layers["launcher"]
	sprite.visible = not aim_pose.visible
	# Hide only the body texture so its child equipment can still draw.
	sprite.self_modulate.a = 1.0 if sprite_layers["goat"] else 0.0
	backpack.visible = sprite_layers["backpack"]
	launcher.visible = sprite_layers["launcher"]
	aim_cursor.visible = showing_aim_pose and sprite_layers["launcher"]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_QUOTELEFT:
		if event.pressed and not event.echo:
			_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if console.visible:
		if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed:
			_toggle_console()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_A or event.physical_keycode == KEY_D:
			var direction := -1.0 if event.physical_keycode == KEY_A else 1.0
			walk_start_msec = Time.get_ticks_msec() + WALK_HOLD_MSEC if direction != facing else 0
			if _is_grounded() and not is_charging_jump and jump_pause_remaining == 0.0:
				facing = direction
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		get_tree().quit()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		mouse_unlocked = not mouse_unlocked
		_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	if mouse_unlocked:
		return
	if event is InputEventMouseMotion:
		camera_target += event.relative / arena_camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()
		return

	# Captured wheel events arrive at the window center, which may overlap UI.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-1)
				get_viewport().set_input_as_handled()


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
	if console.visible:
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mouse_unlocked or console.visible else Input.MOUSE_MODE_CAPTURED


func _clamp_camera_position() -> void:
	var half_view_pixels := get_viewport_rect().size * 0.5
	var camera_zoom := arena_camera.zoom
	var half_view := (half_view_pixels / camera_zoom).min(arena_bounds.size * 0.5)
	camera_target = camera_target.clamp(arena_bounds.position + half_view, arena_bounds.end - half_view)
	# Snap the viewport origin to a render pixel without discarding small mouse movements.
	var origin_pixels := (camera_target * camera_zoom - half_view_pixels).round()
	arena_camera.position = (origin_pixels + half_view_pixels) / camera_zoom
	var camera_offset := arena_camera.position - arena_bounds.get_center()
	for layer in wind_layers:
		layer.update_parallax(camera_offset)


func _update_shot_charge(delta: float) -> void:
	if not is_charging_shot:
		return
	if not shot_released:
		shot_charge = minf(shot_charge + delta, fire_charge_time)
		if not is_equal_approx(shot_charge, fire_charge_time):
			return
		shot_charge = fire_charge_time

	var muzzle := muzzle_left if facing < 0.0 else muzzle_right
	var direction := Vector2(facing, 0).rotated(muzzle.global_rotation)
	var charge_ratio := minf(shot_charge / fire_charge_time, 1.0)
	var power := lerpf(fire_min_amount, fire_max_amount, charge_ratio)
	_fire_rocket(muzzle, direction, power)
	is_charging_shot = false
	shot_released = false


func _fire_rocket(muzzle: Marker2D, direction: Vector2, power: float = 1.0) -> Rocket:
	var rocket := super(muzzle, direction, power)
	rocket.terrain = terrain
	rocket.terrain_pixel_size = terrain_view.scale
	rocket.wind_acceleration = wind_level * WIND_ACCELERATION_PER_LEVEL
	rocket.exploded_at.connect(_carve_terrain)
	rocket.impacted.connect(_roll_wind)
	return rocket


func _carve_terrain(world_pixel: Vector2i) -> void:
	var pixel := Vector2i((Vector2(world_pixel) / terrain_view.scale).floor())
	var radius := roundi(explosion_radius)
	var crater := terrain.carve_circle(pixel.x, pixel.y, radius, true)
	var scorch_width := roundi(scorch_radius_modifier)
	if scorch_width > 0:
		terrain_view.scorch_circle(pixel, radius + scorch_width, TERRAIN_BURN_COLOR)
	terrain_view.carve(crater)


func _roll_wind() -> void:
	var offset := randi_range(1, 2 * MAX_WIND_LEVEL)
	_set_wind(wrapi(wind_level + offset, -MAX_WIND_LEVEL, MAX_WIND_LEVEL + 1))


func _set_wind(level: int) -> void:
	wind_level = level
	var strength := float(level) / MAX_WIND_LEVEL
	for layer in wind_layers:
		layer.set_wind(strength)


func _update_aim_display(snapped_aim: float, delta: float) -> void:
	var target_column := roundi((90.0 - snapped_aim) / AIM_POSE_STEP)
	var column := target_column
	if restoring_launcher:
		column = roundi(launcher_column)
		launcher_column = move_toward(launcher_column, target_column, LAUNCHER_RETURN_SPEED * delta)
		restoring_launcher = launcher_column != target_column
	var row := 1 if facing < 0.0 else 0
	aim_pose.frame_coords = Vector2i(column, row)

	var angle := deg_to_rad(snapped_aim)
	var direction := Vector2(facing * cos(angle), -sin(angle))
	var origin := LEFT_AIM_ORIGIN if facing < 0.0 else RIGHT_AIM_ORIGIN
	aim_cursor.global_position = (aim_pose.to_global(origin) + direction * cursor_distance).round()
