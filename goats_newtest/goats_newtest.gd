extends "res://goat_test/goat_test.gd"

const Goat := preload("res://goats_newtest/goat.gd")

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
const TUNING_PATH := "user://goats_newtest_tuning.cfg"
const TUNING_SECTION := "tuning"
const SPRITE_LAYERS_SECTION := "sprite_layers"
const TUNING_FIELDS := {
	"jump_minimum_x": {"label": "Jump minimum X", "step": 1.0, "floor": 1.0},
	"jump_minimum": {"label": "Jump minimum Y", "step": 1.0, "floor": 1.0},
	"jump_maximum_x": {"label": "Jump maximum X", "step": 1.0, "floor": 1.0},
	"jump_maximum": {"label": "Jump maximum Y", "step": 1.0, "floor": 1.0},
	"jump_charge_time": {"label": "Jump charge time (s)", "step": 0.1, "floor": 0.1},
	"fire_charge_time": {"label": "Fire charge time (s)", "step": 0.1, "floor": 0.1},
	"fire_min_amount": {"label": "Fire min amount", "step": 0.1, "floor": 0.1},
	"fire_max_amount": {"label": "Fire max amount", "step": 0.1, "floor": 0.1},
	"gravity_scale": {"label": "Gravity scale", "step": 0.1, "floor": 0.05},
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
@onready var tuning_overlay: CanvasLayer = $TuningOverlay
@onready var zoom_label: Label = $TuningOverlay/Panel/Margin/Settings/ZoomLabel
@onready var tuning_grid: GridContainer = $TuningOverlay/Panel/Margin/Settings/Values
@onready var layer_controls: HBoxContainer = $TuningOverlay/Panel/Margin/Settings/LayerControls

var fire_charge_time := 2.0
var fire_min_amount := 0.25
var fire_max_amount := 3.0
var tuning_labels: Dictionary[String, Label] = {}
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
	_build_tuning_controls()
	for layer: String in sprite_layers:
		var checkbox := CheckBox.new()
		checkbox.text = layer.capitalize()
		checkbox.focus_mode = Control.FOCUS_NONE
		checkbox.button_pressed = sprite_layers[layer]
		checkbox.toggled.connect(_toggle_sprite_layer.bind(layer))
		layer_controls.add_child(checkbox)
	_update_aim_display(0.0, 0.0)
	_apply_sprite_layers()


func _setup_level() -> void:
	var image := terrain_view.texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	terrain = Terrain.from_image(image)
	arena_bounds = Rect2(Vector2.ZERO, Vector2(terrain.width, terrain.height))

	var sky: Polygon2D = $Sky
	sky.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(terrain.width, 0), arena_bounds.end, Vector2(0, terrain.height),
	])
	RenderingServer.set_default_clear_color(sky.color)
	arena_camera.limit_left = 0
	arena_camera.limit_top = 0
	arena_camera.limit_right = terrain.width
	arena_camera.limit_bottom = terrain.height

	terrain_view.setup(terrain, image)

	var collider: CollisionShape2D = $Goat/CollisionShape2D
	var body_size := Vector2i((collider.shape as RectangleShape2D).size)
	goat_body = Rect2i(Vector2i(collider.position) - Vector2i(body_size / 2), body_size)
	player_spawn_x = roundi(terrain.width * 0.5)
	standing_spawn_x = roundi(terrain.width * 0.6)
	goat.position = _spawn_at(player_spawn_x)
	standing_goat.position = _spawn_at(standing_spawn_x)


func _spawn_at(preferred_x: int) -> Vector2:
	# Cast down through the mask across the goat's feet so slopes cannot bury its body.
	for offset in terrain.width:
		for x in [preferred_x + offset, preferred_x - offset]:
			if x + goat_body.position.x < 0 or x + goat_body.end.x > terrain.width:
				continue
			var surface := terrain.height
			for column in range(x + goat_body.position.x, x + goat_body.end.x):
				surface = mini(surface, terrain.surface_y(column))
			if surface < terrain.height:
				return Vector2(x, surface - goat_body.end.y)
	push_error("Level bitmap has no solid spawn surface.")
	return Vector2(preferred_x, 0)


func _body_is_free(at: Vector2) -> bool:
	var pixel := Vector2i(at.round()) + goat_body.position
	return terrain.rect_is_free(pixel.x, pixel.y, goat_body.size.x, goat_body.size.y)


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

	if goat.position.y > terrain.height or goat.position.x < -goat_body.size.x \
			or goat.position.x > terrain.width + goat_body.size.x:
		goat.position = _spawn_at(player_spawn_x)
		goat.velocity = Vector2.ZERO
	return goat.position.x - start.x


func _follow_slope(at: Vector2) -> Vector2:
	for up in range(Simulation.MAX_STEP_UP + 1):
		var candidate := at - Vector2(0, up)
		if _body_is_free(candidate):
			for down in Simulation.MAX_STEP_DOWN:
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
	if standing_goat.position.y > terrain.height:
		standing_goat.position = _spawn_at(standing_spawn_x)
		standing_fall_speed = 0.0


func _load_tuning() -> void:
	var config := ConfigFile.new()
	var error := config.load(TUNING_PATH)
	if error != OK:
		if error != ERR_FILE_NOT_FOUND:
			push_warning("Could not load tuning settings: %s" % error_string(error))
		return

	for field: String in TUNING_FIELDS:
		var saved: Variant = config.get_value(TUNING_SECTION, field, get(field))
		if (saved is float or saved is int) and is_finite(float(saved)):
			set(field, maxf(float(saved), TUNING_FIELDS[field].floor))
	jump_maximum = maxf(jump_minimum, jump_maximum)
	fire_max_amount = maxf(fire_min_amount, fire_max_amount)
	for layer: String in sprite_layers:
		var saved: Variant = config.get_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
		if saved is bool:
			sprite_layers[layer] = saved


func _build_tuning_controls() -> void:
	for field: String in TUNING_FIELDS:
		var label := Label.new()
		label.text = TUNING_FIELDS[field].label
		tuning_grid.add_child(label)

		var value := Label.new()
		value.custom_minimum_size.x = 44.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tuning_grid.add_child(value)
		tuning_labels[field] = value
		_update_tuning_label(field)

		var step: float = TUNING_FIELDS[field].step
		for direction: int in [-1, 1]:
			var button := Button.new()
			button.text = "-" if direction < 0 else "+"
			button.custom_minimum_size.x = 20.0
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_adjust_tuning.bind(field, direction * step))
			tuning_grid.add_child(button)


func _adjust_tuning(field: String, amount: float) -> void:
	var current: float = get(field)
	var value := maxf(snappedf(current + amount, 0.01), TUNING_FIELDS[field].floor)
	match field:
		"jump_minimum":
			value = minf(value, jump_maximum)
		"jump_maximum":
			value = maxf(value, jump_minimum)
		"fire_min_amount":
			value = minf(value, fire_max_amount)
		"fire_max_amount":
			value = maxf(value, fire_min_amount)
	if is_equal_approx(value, current):
		return

	set(field, value)
	_update_tuning_label(field)
	_save_tuning()


func _toggle_sprite_layer(enabled: bool, layer: String) -> void:
	sprite_layers[layer] = enabled
	_apply_sprite_layers()
	_save_tuning()


func _save_tuning() -> void:
	var config := ConfigFile.new()
	for key: String in TUNING_FIELDS:
		config.set_value(TUNING_SECTION, key, get(key))
	for layer: String in sprite_layers:
		config.set_value(SPRITE_LAYERS_SECTION, layer, sprite_layers[layer])
	var error := config.save(TUNING_PATH)
	if error != OK:
		push_warning("Could not save tuning settings: %s" % error_string(error))


func _update_tuning_label(field: String) -> void:
	tuning_labels[field].text = String.num(get(field), 2)


func _walk_direction() -> float:
	if Time.get_ticks_msec() < walk_start_msec:
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
	if can_aim:
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			tuning_overlay.visible = not tuning_overlay.visible
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_A or event.physical_keycode == KEY_D:
			var direction := -1.0 if event.physical_keycode == KEY_A else 1.0
			walk_start_msec = Time.get_ticks_msec() + WALK_HOLD_MSEC if direction != facing else 0
			if _is_grounded() and not is_charging_jump and jump_pause_remaining == 0.0:
				facing = direction
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed:
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


func _unhandled_input(event: InputEvent) -> void:
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
	zoom_label.text = "Camera zoom: %d%%" % (zoom_level * 100)
	_clamp_camera_position()


func _update_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mouse_unlocked else Input.MOUSE_MODE_CAPTURED


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
	rocket.wind_acceleration = wind_level * WIND_ACCELERATION_PER_LEVEL
	rocket.exploded_at.connect(_carve_terrain)
	rocket.impacted.connect(_roll_wind)
	return rocket


func _carve_terrain(pixel: Vector2i) -> void:
	terrain_view.carve(terrain.carve_circle(pixel.x, pixel.y, Simulation.CRATER_RADIUS))


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
