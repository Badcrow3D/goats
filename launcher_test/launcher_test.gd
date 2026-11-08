extends Node2D

const ANGLE_STEP := 9.0
const CURSOR_ANGLE_STEP := ANGLE_STEP / 4.0
const FRAME_CENTER := Vector2(24, 24)
const RIGHT_ORIGIN_PIXEL := Vector2(21, 18)
const LEFT_ORIGIN_PIXEL := Vector2(26, 18)

@export var aim_speed := 90.0
@export var cursor_distance := 40.0

@onready var launcher: Sprite2D = $Launcher
@onready var projectile_origin: Marker2D = $Launcher/ProjectileOrigin
@onready var aim_cursor: Sprite2D = $AimCursor

var aim_degrees := 0.0
var facing_left := false


func _ready() -> void:
	projectile_origin.position = RIGHT_ORIGIN_PIXEL - FRAME_CENTER
	_update_aim_display()


func _physics_process(delta: float) -> void:
	var facing_input := Input.get_axis("ui_left", "ui_right")
	if not is_zero_approx(facing_input):
		facing_left = facing_input < 0.0
		var origin_pixel := LEFT_ORIGIN_PIXEL if facing_left else RIGHT_ORIGIN_PIXEL
		projectile_origin.position = origin_pixel - FRAME_CENTER

	var aim_input := Input.get_axis("ui_down", "ui_up")
	aim_degrees = clampf(aim_degrees + aim_input * aim_speed * delta, -90.0, 90.0)
	_update_aim_display()


func _update_aim_display() -> void:
	var snapped_aim := snappedf(aim_degrees, CURSOR_ANGLE_STEP)
	# Both rows run from straight up to straight down.
	var column := roundi((90.0 - snapped_aim) / ANGLE_STEP)
	var row := 1 if facing_left else 0
	launcher.frame_coords = Vector2i(column, row)

	var aim_radians := deg_to_rad(snapped_aim)
	var facing_sign := -1.0 if facing_left else 1.0
	var direction := Vector2(facing_sign * cos(aim_radians), -sin(aim_radians))
	aim_cursor.global_position = (projectile_origin.global_position + direction * cursor_distance).round()
