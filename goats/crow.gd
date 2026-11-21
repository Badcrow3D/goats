extends AnimatedSprite2D

const SHEET := preload("res://sprites/crow-16x16.png")
const IDLE_SHEET := preload("res://sprites/crow-idle-16x16.png")
const FRAME_SIZE := 16
const FRAME_SECONDS := 0.08
const FLIGHT_SPEED := 150.0
const STAND_SECONDS := 10.0


func _ready() -> void:
	offset = Vector2(0, -FRAME_SIZE * 0.5)
	z_index = 1
	sprite_frames = SpriteFrames.new()
	sprite_frames.remove_animation(&"default")
	_add_animation(&"stand", 0, 1, false)
	_add_animation(&"jump", 1, 3, false)
	_add_animation(&"fly", 2, 4, true)
	_add_animation(&"land", 3, 4, false)
	_add_animation(&"peck", 0, 21, false, IDLE_SHEET)
	_add_animation(&"turn", 1, 19, false, IDLE_SHEET)


func _add_animation(animation_name: StringName, row: int, count: int, loop: bool,
		sheet: Texture2D = SHEET) -> void:
	sprite_frames.add_animation(animation_name)
	sprite_frames.set_animation_speed(animation_name, 1.0 / FRAME_SECONDS)
	sprite_frames.set_animation_loop(animation_name, loop)
	for column in count:
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = sheet
		frame_texture.region = Rect2(column * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		sprite_frames.add_frame(animation_name, frame_texture)


func _play_idle() -> void:
	play(&"peck" if randf() < 0.5 else &"turn")
	await animation_finished
	play(&"stand")


func visit(entry: Vector2, perch: Vector2, level_width: int) -> void:
	var incoming := perch - entry
	flip_h = incoming.x > 0.0
	position = entry
	play(&"fly")

	var approach := create_tween()
	approach.tween_property(self, "position", perch, incoming.length() / FLIGHT_SPEED)
	await approach.finished
	play(&"land")
	await animation_finished
	play(&"stand")
	var rest := create_tween()
	rest.tween_interval(STAND_SECONDS)
	# Leave enough time for either idle animation to finish within the first half.
	rest.parallel().tween_callback(_play_idle).set_delay(randf_range(0.0, STAND_SECONDS * 0.5 - 2.0))
	await rest.finished

	var outgoing := Vector2(incoming.x, -incoming.y)
	play(&"jump")
	await animation_finished
	play(&"fly")
	var exit_x := float(level_width + FRAME_SIZE if flip_h else -FRAME_SIZE)
	var exit_point := perch + outgoing * ((exit_x - perch.x) / outgoing.x)
	var departure := create_tween()
	departure.tween_property(self, "position", exit_point, position.distance_to(exit_point) / FLIGHT_SPEED)
	departure.tween_callback(queue_free)
