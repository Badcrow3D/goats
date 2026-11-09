extends Node2D

enum Equipment { GOAT_ONLY, BACKPACK, BACKPACK_AND_LAUNCHER }

const ROCKET := preload("res://goats/rocket.tscn")
const Rocket := preload("res://goats/rocket.gd")

@onready var goat: CharacterBody2D = $Goat
@onready var sprite: AnimatedSprite2D = $Goat/AnimatedSprite2D
@onready var backpack: Sprite2D = $Goat/AnimatedSprite2D/Backpack
@onready var launcher: Sprite2D = $Goat/AnimatedSprite2D/Launcher
@onready var muzzle_right: Marker2D = $Goat/MuzzleRight
@onready var muzzle_left: Marker2D = $Goat/MuzzleLeft
@onready var muzzle_tip: Marker2D = $Goat/MuzzleRight/MuzzleTip

@export var walk_speed := 32.0
@export var gravity_scale := 2.0
@export var equipment := Equipment.BACKPACK_AND_LAUNCHER
@export var jump_pause_duration := 0.0
@export var landing_pause_duration := 0.0

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
	backpack.visible = equipment != Equipment.GOAT_ONLY
	launcher.visible = equipment == Equipment.BACKPACK_AND_LAUNCHER
	sprite.frame_changed.connect(_sync_equipment_pose)
	sprite.animation_looped.connect(_on_walk_cycle_finished)


func _physics_process(delta: float) -> void:
	jump_pause_remaining = maxf(jump_pause_remaining - delta, 0.0)
	var was_on_floor := _is_grounded()
	var direction := _walk_direction()
	var can_walk := was_on_floor and not is_charging_jump and jump_pause_remaining == 0.0
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
	if not was_on_floor and _is_grounded() and landing_pause_duration > 0.0:
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
	goat.move_and_slide()
	return goat.get_real_velocity().x


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
	if event.physical_keycode != KEY_ENTER or event.echo:
		return
	if event.pressed and _is_grounded() and not is_charging_jump and jump_pause_remaining == 0.0:
		is_charging_jump = true
		jump_released = false
		jump_charge = 0.0
	elif not event.pressed and is_charging_jump and not jump_released:
		jump_released = true
		jump_pause_remaining = jump_pause_duration


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var muzzle := muzzle_left if facing < 0.0 else muzzle_right
		var direction := muzzle.global_position.direction_to(get_global_mouse_position())
		if direction == Vector2.ZERO:
			direction = Vector2(facing, 0)
		_fire_rocket(muzzle, direction)


func _fire_rocket(muzzle: Marker2D, direction: Vector2, power: float = 1.0) -> Rocket:
	var tip_offset := Vector2(muzzle_tip.position.x * facing, muzzle_tip.position.y)
	var rocket := ROCKET.instantiate() as Rocket
	rocket.position = to_local(muzzle.to_global(tip_offset))
	rocket.velocity = direction * rocket.speed * power
	rocket.shooter_hurtbox = goat.get_node("Hurtbox")
	add_child(rocket)
	return rocket
