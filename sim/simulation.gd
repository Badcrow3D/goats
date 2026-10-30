class_name Simulation
extends RefCounted
## Owns world + state and advances them with a fixed timestep.
## Call tick() from _physics_process (set physics ticks/sec = TICKS_PER_SECOND),
## or loop it yourself for headless tests / replays.
## Record (tick, angle/velocity ints) of each fire() call to replay a game.

const TICKS_PER_SECOND := 60
const CRATER_RADIUS := 18
const MAX_DAMAGE := 40

var world: WorldData
var state := GameState.new()
var projectile: Projectile = null
var last_crater: Rect2i = Rect2i()   # for the view to redraw; size 0 = none
var crater_dirty: bool = false

func _init(p_world: WorldData) -> void:
	world = p_world
	if not world.players.is_empty():
		state.active_player = world.players[0].id

## Launch velocity is derived from angle/power with floats ONCE, then rounded to
## fixed-point ints. Store the ints if you need cross-machine replay.
func fire(angle_deg: int, power: int) -> void:
	if state.mode != GameState.Mode.AIMING:
		return
	var speed: float = float(power) * Projectile.ONE / 8.0   # power 100 = 12.5 px/tick
	var rad: float = deg_to_rad(float(angle_deg))
	fire_fixed(roundi(cos(rad) * speed), roundi(-sin(rad) * speed))


func fire_fixed(vx_fp: int, vy_fp: int) -> void:
	if state.mode != GameState.Mode.AIMING:
		return
	var p := world.get_player(state.active_player)
	projectile = Projectile.new(p.location.x, p.location.y - 6, vx_fp, vy_fp)
	state.mode = GameState.Mode.PROJECTILE_FLIGHT

func tick() -> void:
	state.simulation_step += 1
	match state.mode:
		GameState.Mode.PROJECTILE_FLIGHT:
			_tick_projectile()
		GameState.Mode.TURN_END:
			_next_turn()

func _tick_projectile() -> void:
	var terrain := world.current_level.collision_map
	var ev := projectile.step(terrain)
	if ev == Projectile.Event.EXPLODED:
		_explode(projectile.pixel_x(), projectile.pixel_y())
		state.mode = GameState.Mode.TURN_END
	elif ev == Projectile.Event.LEFT_WORLD:
		state.mode = GameState.Mode.TURN_END

@warning_ignore("integer_division")
func _explode(cx: int, cy: int) -> void:
	last_crater = world.current_level.collision_map.carve_circle(cx, cy, CRATER_RADIUS)
	crater_dirty = true
	var r2: int = CRATER_RADIUS * CRATER_RADIUS * 4   # damage reaches 2x crater radius
	for p in world.players:
		var dx: int = p.location.x - cx
		var dy: int = p.location.y - cy
		var d2: int = dx * dx + dy * dy
		if d2 < r2:
			p.health = maxi(p.health - MAX_DAMAGE * (r2 - d2) / r2, 0)

func _next_turn() -> void:
	projectile = null
	var alive: Array[PlayerData] = world.players.filter(func(p): return p.health > 0)
	if alive.size() <= 1:
		state.mode = GameState.Mode.GAME_OVER
		return
	# next living player after the current one, by list order
	var idx := 0
	for i in world.players.size():
		if world.players[i].id == state.active_player:
			idx = i
	for k in range(1, world.players.size() + 1):
		var cand := world.players[(idx + k) % world.players.size()]
		if cand.health > 0:
			state.active_player = cand.id
			break
	state.mode = GameState.Mode.AIMING
