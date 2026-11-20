extends Node2D

const GoatState := preload("res://goats/goat.gd")
const MISSILE := preload("res://goats/missile.tscn")
const Missile := preload("res://goats/missile.gd")
const ACTION_KEY := KEY_SPACE
const JUMP_CHARGE_FRAME_SECONDS := 0.08

@export var walk_speed := 32.0
@export var gravity_scale := 2.0
@export var landing_pause_duration := 0.0
@export var fall_animation_distance := 24.0
@export var fall_control_loss_distance := 48.0
@export_range(0.0, 0.9) var bounce_restitution := 0.35
@export var bounce_stop_speed := 45.0

var active_goat: GoatState
var facing: float:
	get:
		return float(active_goat.facing_direction)
	set(value):
		active_goat.facing_direction = GoatState.Facing.LEFT if value < 0.0 else GoatState.Facing.RIGHT
var is_charging_jump := false
var jump_released := false
var jump_charge := 0.0
var jump_charge_elapsed := 0.0
var jump_minimum_x := 160.0
var jump_maximum_x := 28.0
var jump_minimum := 200.0
var jump_maximum := 460.0
var jump_charge_time := 2.0


func _step_goat(target: GoatState, delta: float, direction: float) -> void:
	target.jump_pause_remaining = maxf(target.jump_pause_remaining - delta, 0.0)
	var was_on_floor := _is_grounded(target)
	if was_on_floor and not target.is_bouncing:
		target.last_ground_position = target.position
		target.has_ground_position = true
	var takes_input := target == active_goat
	if takes_input and is_charging_jump and (not was_on_floor or target.is_bouncing or not _mode_allows_jump()):
		_cancel_jump()
	_check_fall_distance(target)
	var can_walk := was_on_floor and not target.is_bouncing and target.jump_pause_remaining == 0.0
	var charging := takes_input and is_charging_jump
	if charging:
		target.velocity.x = 0.0
		if not jump_released:
			jump_charge_elapsed += delta
			jump_charge = minf(jump_charge + delta, jump_charge_time)
		else:
			var charge_ratio := minf(jump_charge / jump_charge_time, 1.0)
			target.velocity = Vector2(
				lerpf(jump_minimum_x, jump_maximum_x, charge_ratio) * facing,
				-lerpf(jump_minimum, jump_maximum, charge_ratio)
			)
			target.jump_launch_speed = -target.velocity.y
			_cancel_jump()
			target.landing_pause_pending = true
	elif can_walk:
		target.velocity.x = direction * walk_speed
		if not is_zero_approx(direction):
			target.facing_direction = GoatState.Facing.LEFT if direction < 0.0 else GoatState.Facing.RIGHT

	target.velocity += target.get_gravity() * gravity_scale * delta
	var moved_x := _move_goat(target, delta)
	_check_fall_distance(target)
	var on_floor := _is_grounded(target)
	if was_on_floor and not on_floor and can_walk and not charging and not is_zero_approx(moved_x):
		target.walked_off_edge = true
	if on_floor and not target.is_bouncing:
		target.walked_off_edge = false
		# A bitmap horizontal sweep can bring the goat onto a ledge after the vertical sweep.
		if target.jump_launch_speed > 0.0:
			target.jump_launch_speed = 0.0
			target.play_landing_pose()
		target.last_ground_position = target.position
		target.has_ground_position = true
		if not was_on_floor and target.landing_pause_pending and landing_pause_duration > 0.0:
			target.jump_pause_remaining = landing_pause_duration
			target.velocity.x = 0.0
		target.landing_pause_pending = false

	if target.is_bouncing:
		target.show_standing_pose()
	elif takes_input and is_charging_jump:
		var charge_frame := mini(int(jump_charge_elapsed / JUMP_CHARGE_FRAME_SECONDS), 2)
		target.show_jump_pose(charge_frame)
	elif not on_floor and target.jump_launch_speed > 0.0:
		var rise_ratio := -target.velocity.y / target.jump_launch_speed
		if rise_ratio < -0.1:
			target.show_jump_pose(7)
		elif rise_ratio <= 0.1:
			target.show_jump_pose(6)
		else:
			var rise_frame := clampi(int(3.0 * (1.0 - rise_ratio) / 0.9), 0, 2)
			target.show_jump_pose(3 + rise_frame)
	elif not on_floor and target.walked_off_edge:
		if target.position.y - target.last_ground_position.y >= fall_animation_distance:
			target.show_jump_pose(7)
		else:
			target.hold_current_pose()
	else:
		target.update_walk_pose(takes_input and can_walk and not charging and on_floor and not is_zero_approx(moved_x))


func _is_grounded(target: GoatState) -> bool:
	return target.is_on_floor()


func _move_goat(target: GoatState, _delta: float) -> float:
	var was_on_floor := target.is_on_floor() and target.velocity.y >= 0.0
	var impact_velocity := target.velocity
	target.move_and_slide()
	if target.is_on_floor() and impact_velocity.y > 0.0 and (not was_on_floor or target.is_bouncing):
		_handle_ground_impact(target, impact_velocity)
	return target.get_real_velocity().x


func _can_use_ground_controls() -> bool:
	return _is_grounded(active_goat) and not active_goat.is_bouncing


func _can_control_movement() -> bool:
	return _can_use_ground_controls() and active_goat.jump_pause_remaining == 0.0


func _check_fall_distance(target: GoatState) -> void:
	if target.has_ground_position and target.position.y - target.last_ground_position.y >= fall_control_loss_distance:
		target.is_bouncing = true


func _handle_ground_impact(target: GoatState, impact_velocity: Vector2, normal := Vector2.UP) -> void:
	_check_fall_distance(target)
	target.jump_launch_speed = 0.0
	if not target.is_bouncing:
		if not target.walked_off_edge or target.position.y - target.last_ground_position.y >= fall_animation_distance:
			target.play_landing_pose()
		return
	target.show_standing_pose()
	target.landing_pause_pending = true
	var rebound := _ground_rebound(impact_velocity, normal)
	if rebound.y < -bounce_stop_speed:
		target.velocity = rebound
	else:
		target.velocity = Vector2.ZERO
		target.is_bouncing = false
		target.last_ground_position = target.position
		target.has_ground_position = true


func _ground_rebound(impact_velocity: Vector2, normal: Vector2) -> Vector2:
	var reflected := impact_velocity.bounce(normal)
	# A ground hit must send the goat clear of the floor, even at a grazing angle.
	if impact_velocity.dot(normal) >= 0.0 or reflected.y >= 0.0:
		reflected = impact_velocity.bounce(Vector2.UP)
	return reflected * bounce_restitution


func _reset_fall_state(target: GoatState) -> void:
	target.is_bouncing = false
	target.walked_off_edge = false
	target.landing_pause_pending = false
	target.jump_pause_remaining = 0.0
	target.jump_launch_speed = 0.0
	target.show_standing_pose()
	target.last_ground_position = target.position
	target.has_ground_position = true
	if target == active_goat:
		_cancel_jump()


func _cancel_jump() -> void:
	is_charging_jump = false
	jump_released = false


func _mode_allows_jump() -> bool:
	return active_goat.mode != GoatState.Mode.LAUNCHER


func _unhandled_key_input(event: InputEvent) -> void:
	if not _mode_allows_jump() or event.physical_keycode != ACTION_KEY or event.echo:
		return
	if event.pressed and _can_control_movement() and not is_charging_jump:
		is_charging_jump = true
		jump_released = false
		jump_charge = 0.0
		jump_charge_elapsed = 0.0
	elif not event.pressed and is_charging_jump and not jump_released:
		jump_released = true


func _unhandled_input(event: InputEvent) -> void:
	if active_goat.is_bouncing or active_goat.mode != GoatState.Mode.LAUNCHER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var direction := active_goat.direction_to_target(get_global_mouse_position())
		if direction == Vector2.ZERO:
			direction = Vector2(facing, 0)
		_fire_missile(direction)


func _fire_missile(direction: Vector2, power: float = 1.0) -> Missile:
	if active_goat.mode != GoatState.Mode.LAUNCHER:
		return null
	var missile := MISSILE.instantiate() as Missile
	missile.position = to_local(active_goat.missile_spawn_position())
	missile.velocity = direction * missile.speed * power
	missile.shooter_hurtbox = active_goat.get_hurtbox()
	add_child(missile)
	return missile
