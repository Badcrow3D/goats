extends Node2D
## Demo harness. Attach to a Node2D in main.tscn.
## Controls: Left/Right = angle, Up/Down = power, Space = fire.
## Project Settings > Physics > Common > Physics Ticks per Second = 60.

const W := 640
const H := 360

var sim: Simulation
var image: Image
var texture: ImageTexture
var angle := 45
var power := 60

func _ready() -> void:
	scale = Vector2(1, 1)
	var terrain := Terrain.new(W, H)
	terrain.generate(11222)
	var level := LevelData.new(terrain)

	var world := WorldData.new()
	world.current_level = level
	for data in [[0, "Billy", 100], [1, "Nanny", 540]]:
		var sy := terrain.surface_y(data[2])
		world.players.append(PlayerData.new(data[0], data[1], Vector2i(data[2], sy), 100))
	sim = Simulation.new(world)

	image = terrain.make_image(level.terrain_color, level.background_color)
	texture = ImageTexture.create_from_image(image)
	self.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
func _physics_process(_dt: float) -> void:
	var dir := 0
	if sim.state.mode == GameState.Mode.AIMING:
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
		var lvl := sim.world.current_level
		lvl.collision_map.update_image_region(image, sim.last_crater, lvl.terrain_color, lvl.background_color)
		texture.update(image)
		sim.crater_dirty = false
	queue_redraw()

func _draw() -> void:
	draw_texture(texture, Vector2.ZERO)
	for p in sim.world.players:
		if p.health <= 0:
			continue
		var col := Color.YELLOW if p.id == sim.state.active_player else Color.WHITE
		draw_rect(Rect2(p.location.x - 3, p.location.y - 10, 6, 10), col)
		draw_rect(Rect2(p.location.x - 8, p.location.y - 16, 16.0 * p.health / 100.0, 2), Color.RED)
	if sim.projectile and sim.projectile.alive:
		draw_circle(Vector2(sim.projectile.pixel_x(), sim.projectile.pixel_y()), 2, Color.BLACK)
	if sim.state.mode == GameState.Mode.AIMING:
		var me := sim.world.get_player(sim.state.active_player)
		var dir := Vector2(cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))
		var o := Vector2(me.location) + Vector2(0, -6)
		draw_line(o, o + dir * (10 + power * 0.3), Color.RED, 1.0)
