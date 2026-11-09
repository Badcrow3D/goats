extends Node2D
## Demo harness. Attach to a Node2D in main.tscn.
## Controls: A/D = walk, W = jump. Left/Right = angle, Up/Down = power, Space = fire.
## Project Settings > Physics > Common > Physics Ticks per Second = 60.

## Art files. Anything missing falls back to simple placeholder shapes.
const TERRAIN_PNG := "res://art/terrain.png"        # transparent = air, opaque = solid
const BACKGROUND_PNG := "res://art/background.png"  # optional
const PLAYER_PNG := "res://art/goat.png"            # optional
const PROJECTILE_PNG := "res://art/shell.png"       # optional

## Where the sim position sits inside each sprite (0..1). (0.5, 1.0) = bottom centre = feet.
const PLAYER_PIVOT := Vector2(0.5, 1.0)
const PROJECTILE_PIVOT := Vector2(0.5, 0.5)
const PROJECTILE_ROTATES := true   # cosmetic: point the sprite along its velocity

var sim: Simulation
var terrain_view: TerrainView
var camera: Camera2D
var player_tex: Texture2D
var projectile_tex: Texture2D
var angle := 45
var power := 60

@warning_ignore("integer_division")
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Terrain: the PNG is both the artwork and (via alpha) the collision mask.
	var art := _load_image(TERRAIN_PNG)
	if art == null:
		art = _placeholder_art()
	var terrain := Terrain.from_image(art)
	var level := LevelData.new(terrain)

	var world := WorldData.new()
	world.current_level = level
	var spawns := [[0, "Billy", terrain.width * 50 / 100], [1, "Nanny", terrain.width * 60 / 100]]
	for s in spawns:
		var sy := terrain.surface_y(s[2])
		world.players.append(PlayerData.new(s[0], s[1], Vector2i(s[2], sy), 100))
	sim = Simulation.new(world)

	# Views, drawn back to front: background (-2), terrain (-1), units/projectile (this node's _draw).
	var bg_tex := _load_texture(BACKGROUND_PNG)
	if bg_tex:
		var bg := Sprite2D.new()
		bg.texture = bg_tex
		bg.centered = false
		bg.z_index = -2
		add_child(bg)
	else:
		RenderingServer.set_default_clear_color(level.background_color)

	terrain_view = TerrainView.new()
	terrain_view.z_index = -1
	add_child(terrain_view)
	terrain_view.setup(terrain, art)

	player_tex = _load_texture(PLAYER_PNG)
	projectile_tex = _load_texture(PROJECTILE_PNG)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = terrain.width
	camera.limit_bottom = terrain.height
	camera.position_smoothing_enabled = true
	add_child(camera)
	camera.make_current()
	_update_camera()
	camera.reset_smoothing()

func _physics_process(_dt: float) -> void:
	if sim.state.mode == GameState.Mode.AIMING:
		var dir := 0
		if Input.is_physical_key_pressed(KEY_A): dir -= 1
		if Input.is_physical_key_pressed(KEY_D): dir += 1
		sim.walk(dir)
		if Input.is_physical_key_pressed(KEY_W): sim.jump(dir)
		if Input.is_physical_key_pressed(KEY_LEFT):  angle = mini(angle + 1, 180)
		if Input.is_physical_key_pressed(KEY_RIGHT): angle = maxi(angle - 1, 0)
		if Input.is_physical_key_pressed(KEY_UP):    power = mini(power + 1, 100)
		if Input.is_physical_key_pressed(KEY_DOWN):  power = maxi(power - 1, 1)
		if Input.is_physical_key_pressed(KEY_SPACE): sim.fire(angle, power)
	sim.tick()
	if sim.crater_dirty:
		terrain_view.carve(sim.last_crater)
		sim.crater_dirty = false

	_update_camera()
	queue_redraw()

func _update_camera() -> void:
	# Camera follows the shot, otherwise the active player (view only, not part of the sim).
	if sim.projectile and sim.projectile.alive:
		camera.position = Vector2(sim.projectile.pixel_x(), sim.projectile.pixel_y())
	else:
		camera.position = Vector2(sim.world.get_player(sim.state.active_player).location) + Vector2(0, -20)

func _draw() -> void:
	for p in sim.world.players:
		if p.health <= 0:
			continue
		var pos := Vector2(p.location)
		var active: bool = p.id == sim.state.active_player
		var top := pos.y - 10.0
		if player_tex:
			_draw_sprite(player_tex, pos, PLAYER_PIVOT, Color.WHITE if active else Color(0.8, 0.8, 0.8))
			top = pos.y - player_tex.get_height() * PLAYER_PIVOT.y
		else:
			draw_rect(Rect2(pos.x - 3, pos.y - 10, 6, 10), Color.YELLOW if active else Color.WHITE)
		# Health bar sits above the art, not above the hitbox.
		draw_rect(Rect2(pos.x - 8, top - 6, 16.0 * p.health / 100.0, 2), Color.RED)

	if sim.projectile and sim.projectile.alive:
		var ppos := Vector2(sim.projectile.pixel_x(), sim.projectile.pixel_y())
		if projectile_tex:
			var rot := atan2(float(sim.projectile.vy), float(sim.projectile.vx)) if PROJECTILE_ROTATES else 0.0
			_draw_sprite(projectile_tex, ppos, PROJECTILE_PIVOT, Color.WHITE, rot)
		else:
			draw_circle(ppos, 2, Color.BLACK)

	if sim.state.mode == GameState.Mode.AIMING:
		var me := sim.world.get_player(sim.state.active_player)
		var dir := Vector2(cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))
		var o := Vector2(me.location + Simulation.MUZZLE_OFFSET)
		draw_line(o, o + dir * (10 + power * 0.3), Color.RED, 1.0)

## Draws tex so that its pivot (0..1) lands on pos, optionally rotated about that point.
func _draw_sprite(tex: Texture2D, pos: Vector2, pivot: Vector2, mod := Color.WHITE, rot := 0.0) -> void:
	draw_set_transform(pos, rot)
	draw_texture(tex, -tex.get_size() * pivot, mod)
	draw_set_transform(Vector2.ZERO, 0.0)

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Loads via the imported texture so it also works in exported builds.
func _load_image(path: String) -> Image:
	var tex := _load_texture(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

func _placeholder_art() -> Image:
	var t := Terrain.new(640, 360)
	t.generate(11222)
	return t.make_image(Color(0.55, 0.36, 0.2), Color(0, 0, 0, 0))
