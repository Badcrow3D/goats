@tool
extends CharacterBody2D

signal damaged(amount: int, hit_direction: Vector2)
signal mode_changed

enum Facing { LEFT = -1, RIGHT = 1 }
enum Status { ACTIVE, ALIVE, DEAD }
enum Mode { GOAT_ONLY = 0, GRAPPLE = 1, LAUNCHER = 2, GRENADE = 3, ROCKETS = 4, CANNON = 5 }

const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const IDLE_SHEET := preload("res://sprites/goat_idle-24x24.png")
const IDLE_FRAME_SIZE := 24
const IDLE_ROW_LENGTHS := [6, 23, 7, 7, 3, 3, 41, 18]
const IDLE_ANIMATION_PREFIX := "idle_row_"
# Marker offsets in source pixels, relative to (9, 16) in the first right walk frame.
const WALK_RIGHT_OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2(1, 0), Vector2(1, -2), Vector2(1, -1), Vector2(1, 0),
]
const WALK_LEFT_OFFSETS: Array[Vector2] = [
	Vector2(3, 0), Vector2(2, 0), Vector2(2, -2), Vector2(2, -1), Vector2(2, 0),
]
const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 8.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _bounce_pose: Sprite2D = $BouncePose
@onready var _rockets: Node2D = $Weapons/Rockets
@onready var _cannon: Node2D = $Weapons/Cannon
@onready var _grenade: Node2D = $Weapons/Grenade
@onready var _grapple: Node2D = $Weapons/Grapple
@onready var _grapple_pivot: Node2D = $Weapons/Grapple/Pivot
@onready var _weapons: Node2D = $Weapons
@onready var _missile: Node2D = $Weapons/Missile
var _pivot: Node2D
@onready var _weapons_rest_position := _weapons.position
var _muzzle_right: Marker2D
var _muzzle_left: Marker2D
var _muzzle_tip: Marker2D
@onready var _hurtbox: GoatHurtbox = $Hurtbox
@onready var _collider: CollisionShape2D = $CollisionShape2D
@onready var _aim_cursor: Sprite2D = $AimCursor
@onready var _jump_meter: Sprite2D = $ChargeMeters/Anchor/JumpChargeMeter
@onready var _shot_meter: Sprite2D = $ChargeMeters/Anchor/ShotChargeMeter
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
		if is_node_ready():
			_apply_weapon_facing()
			_apply_idle_facing()
@export var status := Status.ALIVE
@export var mode := Mode.LAUNCHER:
	set(value):
		if mode == value:
			return
		mode = value
		_showing_aim_pose = false
		if is_node_ready():
			_select_weapon()
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
	_select_weapon()
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


func _is_standing() -> bool:
	return _sprite.animation == &"idle" or _sprite.animation == &"idle_left"


func can_play_idle_animation() -> bool:
	return status == Status.ALIVE and not is_bouncing and _is_standing()


func play_idle_animation() -> void:
	_sprite.flip_h = facing_direction == Facing.LEFT
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


func has_charge_weapon() -> bool:
	return mode == Mode.LAUNCHER or mode == Mode.GRENADE


func _select_weapon() -> void:
	var weapon := _grapple if mode == Mode.GRAPPLE else _missile
	if mode == Mode.GRENADE:
		weapon = _grenade
	elif mode == Mode.ROCKETS:
		weapon = _rockets
	elif mode == Mode.CANNON:
		weapon = _cannon
	_pivot = weapon.get_node("Pivot")
	_muzzle_right = weapon.get_node("MuzzleRight")
	_muzzle_left = weapon.get_node("MuzzleLeft")
	_muzzle_tip = _muzzle_right.get_node("MuzzleTip")
	_apply_weapon_facing()


func _apply_weapon_facing() -> void:
	_sync_equipment_pose()
	for weapon: Node2D in [_missile, _grapple, _grenade, _rockets, _cannon]:
		weapon.transform = Transform2D(Vector2.RIGHT * float(facing_direction), Vector2.DOWN, weapon.position)


func _apply_idle_facing() -> void:
	if _is_standing():
		show_standing_pose()


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
	elif _is_standing():
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
	mode = Mode.GOAT_ONLY
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
	_sprite.flip_h = false
	_sprite.play(&"idle_left" if facing_direction == Facing.LEFT else &"idle")
	_sync_equipment_pose()


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
		show_standing_pose()


func _sync_equipment_pose() -> void:
	var offset := Vector2.ZERO
	if _sprite.animation == &"walk_right":
		offset = WALK_RIGHT_OFFSETS[_sprite.frame] * _sprite.scale
	elif _sprite.animation == &"walk_left" or _sprite.animation == &"idle_left":
		offset = WALK_LEFT_OFFSETS[_sprite.frame] * _sprite.scale
	elif facing_direction == Facing.LEFT:
		offset = _muzzle_left.position - _muzzle_right.position
	_weapons.position = _weapons_rest_position + offset



func update_aim_pose(can_aim: bool, pose_aim_degrees: float, cursor_distance: float) -> void:
	# Let the layered sprite finish its walk tail before switching poses.
	_showing_aim_pose = can_aim and _is_standing()
	var snapped_aim := snappedf(pose_aim_degrees, AIM_CURSOR_STEP) if _showing_aim_pose or mode == Mode.GRAPPLE else 0.0
	var angle := deg_to_rad(snapped_aim)
	_muzzle_right.rotation = -angle
	_pivot.rotation = -angle
	if _showing_aim_pose:
		var origin := muzzle_origin()
		var direction := aim_direction()
		_aim_cursor.global_position = (origin + direction * cursor_distance).round()
	_apply_mode_layers()


func _apply_mode_layers() -> void:
	var show_equipment := not _is_playing_idle_animation()
	var show_grapple := mode == Mode.GRAPPLE and show_equipment
	var show_launcher := mode == Mode.LAUNCHER and show_equipment
	_grapple.visible = show_grapple
	_grapple_pivot.visible = not aim_locked
	_rockets.visible = mode == Mode.ROCKETS and show_equipment
	_cannon.visible = mode == Mode.CANNON and show_equipment
	_grenade.visible = mode == Mode.GRENADE and show_equipment
	_missile.visible = show_launcher
	var show_aim_pose := _showing_aim_pose and show_equipment and mode != Mode.GOAT_ONLY
	_sprite.visible = not _bounce_pose.visible
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


func aim_direction() -> Vector2:
	return _muzzle_right.global_transform.x.normalized()


func direction_to_target(target: Vector2) -> Vector2:
	return _muzzle_right.global_position.direction_to(target)


func muzzle_origin() -> Vector2:
	return _muzzle_right.global_position


func rocket_muzzle_positions() -> PackedVector2Array:
	return PackedVector2Array([
		muzzle_tip_position(),
		_rockets.get_node("MuzzleRight/MuzzleTip2").global_position,
		_rockets.get_node("MuzzleRight/MuzzleTip3").global_position,
	])


func muzzle_tip_position() -> Vector2:
	return _muzzle_tip.global_position


func get_hurtbox() -> GoatHurtbox:
	return _hurtbox


func bitmap_body_rect() -> Rect2i:
	var body_size := Vector2i((_collider.shape as RectangleShape2D).size)
	@warning_ignore("integer_division")
	return Rect2i(Vector2i(_collider.position) - Vector2i(body_size / 2), body_size)


func take_damage(amount: int, hit_direction := Vector2.ZERO) -> void:
	if amount <= 0:
		return
	health = maxi(health - amount, 0)
	if health == 0:
		status = Status.DEAD
	damaged.emit(amount, hit_direction)
