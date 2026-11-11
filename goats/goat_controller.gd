extends Node2D

const GoatState := preload("res://goats/goat.gd")
const ROCKET := preload("res://goats/rocket.tscn")
const Rocket := preload("res://goats/rocket.gd")

@onready var goat: GoatState = $Goat
@onready var sprite: AnimatedSprite2D = $Goat/AnimatedSprite2D
@onready var backpack: Sprite2D = $Goat/AnimatedSprite2D/Backpack
@onready var launcher: Sprite2D = $Goat/AnimatedSprite2D/Launcher
@onready var muzzle_right: Marker2D = $Goat/MuzzleRight
@onready var muzzle_left: Marker2D = $Goat/MuzzleLeft
@onready var muzzle_tip: Marker2D = $Goat/MuzzleRight/MuzzleTip

@export var walk_speed := 32.0
@export var gravity_scale := 2.0
@export var jump_pause_duration := 0.0
@export var landing_pause_duration := 0.0
@export var fall_control_loss_distance := 48.0
@export_range(0.0, 0.9) var bounce_restitution := 0.35
@export var bounce_stop_speed := 45.0

var last_ground_position := Vector2.ZERO
var has_ground_position := false
var is_bouncing := false

var facing := 1.0
var is_walking := false
var is_charging_jump := false
var jump_released := false
var jump_pause_remaining := 0.0
var jump_charge := 0.0
var jump_minimum_x := 160.0
var jump_maximum_x := 28.0
var jump_minimum := 200.0
var jump_maximum := 460.0
var jump_charge_time := 2.0


func _ready() -> void:
	sprite.frame_changed.connect(_sync_equipment_pose)
	sprite.animation_looped.connect(_on_walk_cycle_finished)


func _physics_process(delta: float) -> void:
	jump_pause_remaining = maxf(jump_pause_remaining - delta, 0.0)
	var was_on_floor := _is_grounded()
	if was_on_floor and not is_bouncing:
		last_ground_position = goat.position
		has_ground_position = true
	if not was_on_floor and is_charging_jump:
		is_charging_jump = false
		jump_released = false
	_check_fall_distance()
	var direction := _walk_direction()
	var can_walk := _can_control_movement() and not is_charging_jump
	if is_charging_jump:
		goat.velocity.x = 0.0
		if not jump_released:
			jump_charge = minf(jump_charge + delta, jump_charge_time)
		elif jump_pause_remaining == 0.0:
			var charge_ratio := minf(jump_charge / jump_charge_time, 1.0)
			goat.velocity = Vector2(
				lerpf(jump_minimum_x, jump_maximum_x, charge_ratio) * facing,
				-lerpf(jump_minimum, jump_maximum, charge_ratio)
			)
			is_charging_jump = false
	elif can_walk:
		goat.velocity.x = direction * walk_speed
		if not is_zero_approx(direction):
			facing = signf(direction)

	goat.velocity += goat.get_gravity() * gravity_scale * delta
	var moved_x := _move_goat(delta)
	_check_fall_distance()
	if _is_grounded() and not is_bouncing:
		last_ground_position = goat.position
		has_ground_position = true
	if not was_on_floor and _is_grounded() and not is_bouncing and landing_pause_duration > 0.0:
		jump_pause_remaining = landing_pause_duration
		goat.velocity.x = 0.0

	is_walking = can_walk and _is_grounded() and not is_zero_approx(moved_x)
	if is_walking:
		sprite.flip_h = false
		sprite.play(&"walk_left" if facing < 0.0 else &"walk_right")
	elif sprite.animation == &"idle":
		sprite.flip_h = facing < 0.0
	else:
		var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
		var finish_start := maxi(0, frame_count - 2)
		if sprite.frame < finish_start:
			sprite.set_frame_and_progress(finish_start, 0.0)
	_sync_equipment_pose()


func _is_grounded() -> bool:
	return goat.is_on_floor()


func _move_goat(_delta: float) -> float:
	var impact_velocity := goat.velocity
	goat.move_and_slide()
	if goat.is_on_floor() and impact_velocity.y > 0.0:
		_handle_ground_impact(impact_velocity)
	return goat.get_real_velocity().x


func _can_control_movement() -> bool:
	return _is_grounded() and not is_bouncing and jump_pause_remaining == 0.0


func _check_fall_distance() -> void:
	if has_ground_position and goat.position.y - last_ground_position.y >= fall_control_loss_distance:
		is_bouncing = true


func _handle_ground_impact(impact_velocity: Vector2, normal := Vector2.UP) -> void:
	_check_fall_distance()
	if not is_bouncing:
		return
	var rebound := _ground_rebound(impact_velocity, normal)
	if rebound.y < -bounce_stop_speed:
		goat.velocity = rebound
	else:
		goat.velocity = Vector2.ZERO
		is_bouncing = false
		last_ground_position = goat.position
		has_ground_position = true


func _ground_rebound(impact_velocity: Vector2, normal: Vector2) -> Vector2:
	var reflected := impact_velocity.bounce(normal)
	# A ground hit must send the goat clear of the floor, even at a grazing angle.
	if impact_velocity.dot(normal) >= 0.0 or reflected.y >= 0.0:
		reflected = impact_velocity.bounce(Vector2.UP)
	return reflected * bounce_restitution


func _reset_fall_state() -> void:
	is_bouncing = false
	is_charging_jump = false
	jump_released = false
	jump_pause_remaining = 0.0
	last_ground_position = goat.position
	has_ground_position = true


func _walk_direction() -> float:
	return Input.get_axis("ui_left", "ui_right")


func _on_walk_cycle_finished() -> void:
	if not is_walking:
		sprite.play(&"idle")
		sprite.flip_h = facing < 0.0
		_sync_equipment_pose()


func _sync_equipment_pose() -> void:
	var column := sprite.frame
	if sprite.animation == &"walk_left":
		column += 5
	backpack.frame_coords = Vector2i(column, 0)
	launcher.frame_coords = Vector2i(column, 1)
	backpack.flip_h = sprite.flip_h
	launcher.flip_h = sprite.flip_h


func _unhandled_key_input(event: InputEvent) -> void:
	if goat.mode == GoatState.Mode.LAUNCHER or event.physical_keycode != KEY_ENTER or event.echo:
		return
	if event.pressed and _can_control_movement() and not is_charging_jump:
		is_charging_jump = true
		jump_released = false
		jump_charge = 0.0
	elif not event.pressed and is_charging_jump and not jump_released:
		jump_released = true
		jump_pause_remaining = jump_pause_duration


func _unhandled_input(event: InputEvent) -> void:
	if is_bouncing or goat.mode != GoatState.Mode.LAUNCHER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var muzzle := muzzle_left if facing < 0.0 else muzzle_right
		var direction := muzzle.global_position.direction_to(get_global_mouse_position())
		if direction == Vector2.ZERO:
			direction = Vector2(facing, 0)
		_fire_rocket(muzzle, direction)


func _fire_rocket(muzzle: Marker2D, direction: Vector2, power: float = 1.0) -> Rocket:
	if goat.mode != GoatState.Mode.LAUNCHER:
		return null
	var tip_offset := Vector2(muzzle_tip.position.x * facing, muzzle_tip.position.y)
	var rocket := ROCKET.instantiate() as Rocket
	rocket.position = to_local(muzzle.to_global(tip_offset))
	rocket.velocity = direction * rocket.speed * power
	rocket.shooter_hurtbox = goat.get_node("Hurtbox")
	add_child(rocket)
	return rocket
