@tool
extends CharacterBody2D

signal damaged(amount: int, hit_direction: Vector2)
signal mode_changed

enum Facing { LEFT = -1, RIGHT = 1 }
enum Status { ACTIVE, ALIVE, DEAD }
enum Mode { GOAT_ONLY = 0, GRAPPLE = 1, LAUNCHER = 2 }

const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const IDLE_SHEET := preload("res://sprites/goat_idle-24x24.png")
const IDLE_FRAME_SIZE := 24
const IDLE_ROW_LENGTHS := [6, 23, 7, 7, 3, 3, 41, 18]
const IDLE_ANIMATION_PREFIX := "idle_row_"
const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 4.0
const GRAPPLE_AIM_POSE_STEP := 45.0
const RIGHT_AIM_ORIGIN := Vector2(-3, -6)
const LEFT_AIM_ORIGIN := Vector2(2, -6)

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _bounce_pose: Sprite2D = $BouncePose
@onready var _grapple: Sprite2D = $AnimatedSprite2D/Grapple
@onready var _grapple_aim_pose: Sprite2D = $GrappleAimPose
@onready var _launcher: Sprite2D = $AnimatedSprite2D/Launcher
@onready var _muzzle_right: Marker2D = $MuzzleRight
@onready var _muzzle_left: Marker2D = $MuzzleLeft
@onready var _muzzle_tip: Marker2D = $MuzzleRight/MuzzleTip
@onready var _hurtbox: GoatHurtbox = $Hurtbox
@onready var _collider: CollisionShape2D = $CollisionShape2D
@onready var _aim_pose: Sprite2D = $AimPose
@onready var _aim_cursor: Sprite2D = $AimCursor
@onready var _jump_meter: Sprite2D = $JumpChargeMeter
@onready var _shot_meter: Sprite2D = $ShotChargeMeter
@onready var nameplate: Panel = $Nameplate
@onready var _nameplate_label: Label = $Nameplate/Label
@onready var _health_bar: ColorRect = $Nameplate/health
@onready var _full_health_width := _health_bar.size.x
@onready var _shot_meter_distance := absf(_shot_meter.position.x)

var last_ground_position := Vector2.ZERO
var has_ground_position := false
var walked_off_edge := false
var is_bouncing := false
var landing_pause_pending := false
var jump_pause_remaining := 0.0
var grapple_bounce_cooldown := 0.0
var jump_launch_speed := 0.0
var aim_degrees := 0.0

var _walking := false
var _showing_aim_pose := false
var aim_locked := false:
	set(value):
		aim_locked = value
		_apply_mode_layers()
var _idle_rows_remaining := 0

@export var team_id := 0
@export var goat_name := "":
	set(value):
		goat_name = value
		if is_node_ready():
			_nameplate_label.text = goat_name
@export var health := 100:
	set(value):
		health = value
		if is_node_ready():
			_update_health_bar()
@export var energy := 100
@export var facing_direction := Facing.RIGHT:
	set(value):
		if facing_direction == value:
			return
		facing_direction = value
		if is_node_ready() and not Engine.is_editor_hint():
			_apply_idle_facing()
@export var status := Status.ALIVE
@export var mode := Mode.LAUNCHER:
	set(value):
		if mode == value:
			return
		mode = value
		_showing_aim_pose = false
		if is_node_ready():
			_apply_mode_layers()
		mode_changed.emit()

@export_group("Goat Palette")
@export_color_no_alpha var highlight_color := Color("#ffffff"):
	set(value):
		highlight_color = value
		_apply_palette()
@export_color_no_alpha var light_color := Color("#c0c0c0"):
	set(value):
		light_color = value
		_apply_palette()
@export_color_no_alpha var midtone_color := Color("#b1cdce"):
	set(value):
		midtone_color = value
		_apply_palette()
@export_color_no_alpha var shadow_color := Color("#696a6a"):
	set(value):
		shadow_color = value
		_apply_palette()
@export_color_no_alpha var team_color := Color("#ff3f51"):
	set(value):
		team_color = value
		_apply_palette()


func _ready() -> void:
	_nameplate_label.text = goat_name
	_bounce_pose.material = _sprite.material
	_bounce_pose.scale = _sprite.scale
	_apply_palette()
	_update_health_bar()
	_apply_mode_layers()
	if not Engine.is_editor_hint():
		_add_idle_animations()
		_sprite.animation_changed.connect(_apply_mode_layers)
		_sprite.frame_changed.connect(_sync_equipment_pose)
		_sprite.animation_looped.connect(_on_walk_cycle_finished)
		_sprite.animation_finished.connect(_on_pose_finished)
		_apply_idle_facing()


func _add_idle_animations() -> void:
	var frames := _sprite.sprite_frames
	if frames.has_animation(IDLE_ANIMATION_PREFIX + "0"):
		return
	for row in IDLE_ROW_LENGTHS.size():
		var animation_name := StringName(IDLE_ANIMATION_PREFIX + str(row))
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, false)
		frames.set_animation_speed(animation_name, 12.5)
		for column in IDLE_ROW_LENGTHS[row]:
			var frame_texture := AtlasTexture.new()
			frame_texture.atlas = IDLE_SHEET
			frame_texture.region = Rect2(
				column * IDLE_FRAME_SIZE, row * IDLE_FRAME_SIZE, IDLE_FRAME_SIZE, IDLE_FRAME_SIZE
			)
			frames.add_frame(animation_name, frame_texture)


func can_play_idle_animation() -> bool:
	return status == Status.ALIVE and not is_bouncing and _sprite.animation == &"idle"


func play_idle_animation() -> void:
	_idle_rows_remaining = 2
	_play_next_idle_row()


func _play_next_idle_row() -> void:
	_idle_rows_remaining -= 1
	var row := randi_range(0, IDLE_ROW_LENGTHS.size() - 1)
	_sprite.stop()
	_sprite.play(StringName(IDLE_ANIMATION_PREFIX + str(row)))


func stop_idle_animation() -> void:
	if _is_playing_idle_animation():
		show_standing_pose()


func _is_playing_idle_animation() -> bool:
	return _sprite.animation.begins_with(IDLE_ANIMATION_PREFIX)


func _apply_palette() -> void:
	if not is_instance_valid(_sprite):
		return
	var palette := _sprite.material as ShaderMaterial
	palette.set_shader_parameter(&"highlight_color", highlight_color)
	palette.set_shader_parameter(&"light_color", light_color)
	palette.set_shader_parameter(&"midtone_color", midtone_color)
	palette.set_shader_parameter(&"shadow_color", shadow_color)
	palette.set_shader_parameter(&"team_color", team_color)
	_nameplate_label.add_theme_color_override(&"font_color", team_color)
	_health_bar.color = team_color


func _update_health_bar() -> void:
	_health_bar.size.x = _full_health_width * clampf(health / 100.0, 0.0, 1.0)


func set_nameplate_visible(visible_on_goat: bool) -> void:
	nameplate.visible = visible_on_goat


func _apply_idle_facing() -> void:
	if _sprite.animation != &"idle":
		return
	_sprite.flip_h = facing_direction == Facing.LEFT
	_sync_equipment_pose()


func update_walk_pose(walking: bool) -> void:
	_walking = walking
	if not _walking and _is_playing_idle_animation():
		return
	if _sprite.animation == &"land":
		_sprite.play()
		return
	if _walking:
		_sprite.flip_h = false
		_sprite.play(&"walk_left" if facing_direction == Facing.LEFT else &"walk_right")
	elif _sprite.animation == &"jump":
		show_standing_pose()
	elif _sprite.animation == &"idle":
		show_standing_pose()
	else:
		_sprite.play()
		var frame_count := _sprite.sprite_frames.get_frame_count(_sprite.animation)
		var finish_start := maxi(0, frame_count - 2)
		if _sprite.frame < finish_start:
			_sprite.set_frame_and_progress(finish_start, 0.0)
	_sync_equipment_pose()


func hold_current_pose() -> void:
	stop_idle_animation()
	_sprite.pause()


func show_jump_pose(frame: int) -> void:
	_walking = false
	_sprite.animation = &"jump"
	_sprite.pause()
	_sprite.frame = frame
	_sprite.flip_h = facing_direction == Facing.LEFT
	_sync_equipment_pose()


func show_bounce_pose() -> void:
	var column: int
	var row: int
	if _bounce_pose.visible:
		var previous := _bounce_pose.frame_coords
		row = previous.y
		column = randi_range(0, _bounce_pose.hframes - 2)
		if column >= previous.x:
			column += 1
	else:
		row = 1 if facing_direction == Facing.LEFT else 0
		column = randi_range(0, _bounce_pose.hframes - 1)
		hold_current_pose()
	_bounce_pose.frame_coords = Vector2i(column, row)
	_bounce_pose.show()
	_showing_aim_pose = false
	_apply_mode_layers()


func play_landing_pose() -> void:
	_hide_bounce_pose()
	_walking = false
	_sprite.flip_h = facing_direction == Facing.LEFT
	_sprite.stop()
	_sprite.play(&"land")
	_sync_equipment_pose()


func show_standing_pose() -> void:
	_idle_rows_remaining = 0
	_hide_bounce_pose()
	_sprite.play(&"idle")
	_apply_idle_facing()


func _hide_bounce_pose() -> void:
	if _bounce_pose.visible:
		_bounce_pose.hide()
		_apply_mode_layers()


func _on_pose_finished() -> void:
	if _is_playing_idle_animation() and _idle_rows_remaining > 0:
		_play_next_idle_row()
	elif _sprite.animation == &"land" or _is_playing_idle_animation():
		show_standing_pose()


func _on_walk_cycle_finished() -> void:
	if not _walking:
		_sprite.play(&"idle")
		_apply_idle_facing()


func _sync_equipment_pose() -> void:
	var column := _sprite.frame
	if _sprite.animation == &"walk_left":
		column += 5
	elif _sprite.animation == &"jump" or _sprite.animation == &"land" or _is_playing_idle_animation():
		column = 0
	_grapple.frame_coords = Vector2i(column, 0)
	_launcher.frame_coords = Vector2i(column, 1)
	_grapple.flip_h = _sprite.flip_h
	_launcher.flip_h = _sprite.flip_h


func update_aim_pose(can_aim: bool, aim_degrees: float, cursor_distance: float) -> void:
	# Let the layered sprite finish its walk tail before switching poses.
	_showing_aim_pose = can_aim and _sprite.animation == &"idle"
	var snapped_aim := snappedf(aim_degrees, AIM_CURSOR_STEP) if _showing_aim_pose or mode == Mode.GRAPPLE else 0.0
	var angle := deg_to_rad(snapped_aim)
	_muzzle_right.rotation = -angle
	_muzzle_left.rotation = angle
	if _showing_aim_pose:
		var faces_left := facing_direction == Facing.LEFT
		var row := 1 if faces_left else 0
		var origin: Vector2
		if mode == Mode.GRAPPLE:
			var column := roundi((90.0 - aim_degrees) / GRAPPLE_AIM_POSE_STEP)
			_grapple_aim_pose.frame_coords = Vector2i(column, row)
			origin = grapple_pivot_position()
		else:
			var column := roundi((90.0 - snapped_aim) / AIM_POSE_STEP)
			_aim_pose.frame_coords = Vector2i(column, row)
			origin = _aim_pose.to_global(LEFT_AIM_ORIGIN if faces_left else RIGHT_AIM_ORIGIN)
		var direction := Vector2(float(facing_direction) * cos(angle), -sin(angle))
		_aim_cursor.global_position = (origin + direction * cursor_distance).round()
	_apply_mode_layers()


func _apply_mode_layers() -> void:
	var show_equipment := not _is_playing_idle_animation()
	var show_grapple := mode == Mode.GRAPPLE and show_equipment
	var show_launcher := mode == Mode.LAUNCHER and show_equipment
	_aim_pose.visible = _showing_aim_pose and show_launcher
	_grapple.visible = show_grapple and not _showing_aim_pose
	_grapple_aim_pose.visible = show_grapple and _showing_aim_pose
	_launcher.visible = show_launcher
	var show_aim_pose := _aim_pose.visible or _grapple_aim_pose.visible
	_sprite.visible = not show_aim_pose and not _bounce_pose.visible
	_aim_cursor.visible = show_aim_pose and not aim_locked


func update_jump_meter(show_charge: bool, charge_ratio: float) -> void:
	_jump_meter.visible = show_charge
	if show_charge:
		var progress := clampf(charge_ratio, 0.0, 1.0)
		if is_equal_approx(progress, 1.0):
			progress = 1.0
		_jump_meter.frame = floori(progress * (_jump_meter.vframes - 2))


func update_shot_meter(show_meter: bool, charge_ratio: float) -> void:
	_shot_meter.visible = show_meter
	if show_meter:
		var progress := clampf(charge_ratio, 0.0, 1.0)
		_shot_meter.frame = floori(progress * (_shot_meter.hframes - 1))
		_shot_meter.position.x = -float(facing_direction) * _shot_meter_distance


func _active_muzzle() -> Marker2D:
	return _muzzle_left if facing_direction == Facing.LEFT else _muzzle_right


func aim_direction() -> Vector2:
	return Vector2(float(facing_direction), 0.0).rotated(_active_muzzle().global_rotation)


func grapple_pivot_position() -> Vector2:
	return _grapple_aim_pose.to_global(Vector2(-2.0 * facing_direction, 0.0))


func direction_to_target(target: Vector2) -> Vector2:
	return _active_muzzle().global_position.direction_to(target)


func muzzle_origin() -> Vector2:
	return _active_muzzle().global_position


func missile_spawn_position() -> Vector2:
	var tip_offset := Vector2(_muzzle_tip.position.x * float(facing_direction), _muzzle_tip.position.y)
	return _active_muzzle().to_global(tip_offset)


func get_hurtbox() -> GoatHurtbox:
	return _hurtbox


func bitmap_body_rect() -> Rect2i:
	var body_size := Vector2i((_collider.shape as RectangleShape2D).size)
	return Rect2i(Vector2i(_collider.position) - Vector2i(body_size / 2), body_size)


func take_damage(amount: int, hit_direction := Vector2.ZERO) -> void:
	if amount <= 0:
		return
	health = maxi(health - amount, 0)
	if health == 0:
		status = Status.DEAD
	damaged.emit(amount, hit_direction)
