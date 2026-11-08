extends "res://goat_test/goat_test.gd"

const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 4.0
const FLAT_LAUNCHER_COLUMN := 10.0
const LAUNCHER_RETURN_SPEED := 30.0
const RIGHT_AIM_ORIGIN := Vector2(-3, -6)
const LEFT_AIM_ORIGIN := Vector2(2, -6)
const TUNING_PATH := "user://goats_newtest_tuning.cfg"
const TUNING_SECTION := "tuning"
const TUNING_FIELDS := {
	"jump_minimum_x": {"label": "Jump minimum X", "step": 10.0, "floor": 0.0},
	"jump_minimum": {"label": "Jump minimum Y", "step": 10.0, "floor": 0.0},
	"jump_maximum_x": {"label": "Jump maximum X", "step": 10.0, "floor": 0.0},
	"jump_maximum": {"label": "Jump maximum Y", "step": 10.0, "floor": 0.0},
	"jump_charge_time": {"label": "Jump charge time (s)", "step": 0.1, "floor": 0.1},
	"fire_charge_time": {"label": "Fire charge time (s)", "step": 0.1, "floor": 0.1},
	"fire_min_amount": {"label": "Fire min amount", "step": 0.05, "floor": 0.0},
	"fire_max_amount": {"label": "Fire max amount", "step": 0.05, "floor": 0.0},
}

@export var aim_speed := 90.0
@export var cursor_distance := 40.0

@onready var aim_launcher: Sprite2D = $Goat/AimLauncher
@onready var aim_cursor: Sprite2D = $Goat/AimCursor
@onready var tuning_grid: GridContainer = $TuningOverlay/Panel/Margin/Settings/Values

var fire_charge_time := 2.0
var fire_min_amount := 0.25
var fire_max_amount := 3.0
var tuning_labels: Dictionary[String, Label] = {}
var aim_degrees := 0.0
var shot_charge := 0.0
var is_charging_shot := false
var shot_released := false
var restoring_launcher := false
var launcher_column := FLAT_LAUNCHER_COLUMN


func _ready() -> void:
	super()
	_load_tuning()
	_build_tuning_controls()
	_update_aim_display(0.0, 0.0)


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
	var config := ConfigFile.new()
	for key: String in TUNING_FIELDS:
		config.set_value(TUNING_SECTION, key, get(key))
	var error := config.save(TUNING_PATH)
	if error != OK:
		push_warning("Could not save tuning settings: %s" % error_string(error))


func _update_tuning_label(field: String) -> void:
	tuning_labels[field].text = String.num(get(field), 2)


func _walk_direction() -> float:
	return float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))


func _physics_process(delta: float) -> void:
	super(delta)
	if is_walking:
		restoring_launcher = true
		launcher_column = FLAT_LAUNCHER_COLUMN
	elif is_charging_jump or not goat.is_on_floor():
		restoring_launcher = false

	var can_aim := (
		goat.is_on_floor()
		and not is_charging_jump
		and jump_pause_remaining == 0.0
		and is_zero_approx(_walk_direction())
	)
	if can_aim:
		var turn := Input.get_axis("ui_left", "ui_right")
		if not is_zero_approx(turn):
			facing = signf(turn)
		var elevation := Input.get_axis("ui_down", "ui_up")
		aim_degrees = clampf(aim_degrees + elevation * aim_speed * delta, -90.0, 90.0)

	# Let the layered sprite finish its short walk tail before switching poses.
	var show_aim := can_aim and sprite.animation == &"idle"
	var snapped_aim := snappedf(aim_degrees, AIM_CURSOR_STEP) if show_aim else 0.0
	muzzle_right.rotation = -deg_to_rad(snapped_aim)
	muzzle_left.rotation = -muzzle_right.rotation
	if show_aim:
		_update_aim_display(snapped_aim, delta)
	aim_launcher.visible = show_aim
	aim_cursor.visible = show_aim
	sprite.visible = not show_aim
	_update_shot_charge(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.echo:
		if event.pressed and not is_charging_shot:
			is_charging_shot = true
			shot_charge = 0.0
		elif not event.pressed and is_charging_shot:
			shot_released = true
		get_viewport().set_input_as_handled()


func _update_shot_charge(delta: float) -> void:
	if not is_charging_shot:
		return
	if shot_released:
		var muzzle := muzzle_left if facing < 0.0 else muzzle_right
		var direction := Vector2(facing, 0).rotated(muzzle.global_rotation)
		var charge_ratio := minf(shot_charge / fire_charge_time, 1.0)
		var power := lerpf(fire_min_amount, fire_max_amount, charge_ratio)
		_fire_rocket(muzzle, direction, power)
		is_charging_shot = false
		shot_released = false
	else:
		shot_charge = minf(shot_charge + delta, fire_charge_time)


func _update_aim_display(snapped_aim: float, delta: float) -> void:
	var target_column := roundi((90.0 - snapped_aim) / AIM_POSE_STEP)
	var column := target_column
	if restoring_launcher:
		column = roundi(launcher_column)
		launcher_column = move_toward(launcher_column, target_column, LAUNCHER_RETURN_SPEED * delta)
		restoring_launcher = launcher_column != target_column
	var row := 1 if facing < 0.0 else 0
	aim_launcher.frame_coords = Vector2i(column, row)

	var angle := deg_to_rad(snapped_aim)
	var direction := Vector2(facing * cos(angle), -sin(angle))
	var origin := LEFT_AIM_ORIGIN if facing < 0.0 else RIGHT_AIM_ORIGIN
	aim_cursor.global_position = (aim_launcher.to_global(origin) + direction * cursor_distance).round()
