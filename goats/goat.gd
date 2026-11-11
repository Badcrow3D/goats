@tool
extends CharacterBody2D

signal damaged(amount: int, hit_direction: Vector2)
signal mode_changed

enum Facing { LEFT = -1, RIGHT = 1 }
enum Status { ACTIVE, ALIVE, DEAD }
enum Mode { GOAT_ONLY = 0, BACKPACK = 1, LAUNCHER = 2 }

const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const AIM_POSE_STEP := 9.0
const AIM_CURSOR_STEP := AIM_POSE_STEP / 4.0
const RIGHT_AIM_ORIGIN := Vector2(-3, -6)
const LEFT_AIM_ORIGIN := Vector2(2, -6)

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _backpack: Sprite2D = $AnimatedSprite2D/Backpack
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
@onready var _shot_meter_distance := absf(_shot_meter.position.x)

var _walking := false
var _showing_aim_pose := false
var _preview_body := true
var _preview_backpack := true
var _preview_launcher := true

@export var team_id := 0
@export var goat_name := ""
@export var health := 100
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
		if mode != Mode.LAUNCHER:
			_showing_aim_pose = false
		if is_node_ready():
			_apply_mode_layers()
		mode_changed.emit()


func _ready() -> void:
	_apply_mode_layers()
	if not Engine.is_editor_hint():
		_sprite.frame_changed.connect(_sync_equipment_pose)
		_sprite.animation_looped.connect(_on_walk_cycle_finished)
		_apply_idle_facing()


func _apply_idle_facing() -> void:
	if _sprite.animation != &"idle":
		return
	_sprite.flip_h = facing_direction == Facing.LEFT
	_sync_equipment_pose()


func update_walk_pose(walking: bool) -> void:
	_walking = walking
	if _walking:
		_sprite.flip_h = false
		_sprite.play(&"walk_left" if facing_direction == Facing.LEFT else &"walk_right")
	elif _sprite.animation == &"idle":
		_sprite.flip_h = facing_direction == Facing.LEFT
	else:
		var frame_count := _sprite.sprite_frames.get_frame_count(_sprite.animation)
		var finish_start := maxi(0, frame_count - 2)
		if _sprite.frame < finish_start:
			_sprite.set_frame_and_progress(finish_start, 0.0)
	_sync_equipment_pose()


func _on_walk_cycle_finished() -> void:
	if not _walking:
		_sprite.play(&"idle")
		_apply_idle_facing()


func _sync_equipment_pose() -> void:
	var column := _sprite.frame
	if _sprite.animation == &"walk_left":
		column += 5
	_backpack.frame_coords = Vector2i(column, 0)
	_launcher.frame_coords = Vector2i(column, 1)
	_backpack.flip_h = _sprite.flip_h
	_launcher.flip_h = _sprite.flip_h


func update_aim_pose(can_aim: bool, aim_degrees: float, cursor_distance: float) -> void:
	# Let the layered sprite finish its walk tail before switching poses.
	_showing_aim_pose = can_aim and _sprite.animation == &"idle"
	var snapped_aim := snappedf(aim_degrees, AIM_CURSOR_STEP) if _showing_aim_pose else 0.0
	var angle := deg_to_rad(snapped_aim)
	_muzzle_right.rotation = -angle
	_muzzle_left.rotation = angle
	if _showing_aim_pose:
		var faces_left := facing_direction == Facing.LEFT
		var column := roundi((90.0 - snapped_aim) / AIM_POSE_STEP)
		_aim_pose.frame_coords = Vector2i(column, 1 if faces_left else 0)
		var direction := Vector2(float(facing_direction) * cos(angle), -sin(angle))
		var origin := LEFT_AIM_ORIGIN if faces_left else RIGHT_AIM_ORIGIN
		_aim_cursor.global_position = (_aim_pose.to_global(origin) + direction * cursor_distance).round()
	_apply_mode_layers()


func set_layer_preview(show_body: bool, show_backpack: bool, show_launcher: bool) -> void:
	_preview_body = show_body
	_preview_backpack = show_backpack
	_preview_launcher = show_launcher
	_apply_mode_layers()


func _apply_mode_layers() -> void:
	var show_backpack := mode != Mode.GOAT_ONLY and _preview_backpack
	var show_launcher := mode == Mode.LAUNCHER and _preview_launcher
	# The composited aim atlas can only show the full set of layers.
	_aim_pose.visible = _showing_aim_pose and _preview_body and show_backpack and show_launcher
	_sprite.visible = not _aim_pose.visible
	# Self-modulation hides only the body texture, leaving its child layers visible.
	_sprite.self_modulate.a = 1.0 if _preview_body else 0.0
	_backpack.visible = show_backpack
	_launcher.visible = show_launcher
	_aim_cursor.visible = _showing_aim_pose and show_launcher


func update_jump_meter(show_meter: bool, charge_ratio: float) -> void:
	_jump_meter.visible = show_meter
	if show_meter:
		var progress := clampf(charge_ratio, 0.0, 1.0)
		if is_equal_approx(progress, 1.0):
			progress = 1.0
		_jump_meter.frame = floori(progress * (_jump_meter.vframes - 1))


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


func direction_to_target(target: Vector2) -> Vector2:
	return _active_muzzle().global_position.direction_to(target)


func rocket_spawn_position() -> Vector2:
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
