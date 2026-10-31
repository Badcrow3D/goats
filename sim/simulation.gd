class_name Simulation
extends RefCounted
## Owns world + state and advances them with a fixed timestep.
## Call tick() from _physics_process (set physics ticks/sec = TICKS_PER_SECOND),
## or loop it yourself for headless tests / replays.
## Record (tick, angle/velocity ints) of each fire() call, and (tick, dir) of each walk() call, to replay a game.

const TICKS_PER_SECOND := 60
const CRATER_RADIUS := 18
const MAX_DAMAGE := 40

const WALK_INTERVAL := 4        # ticks per pixel walked (30 px/s at 60 Hz)
const MAX_STEP_UP := 2          # px climbed per step; 2 = ~63 degrees, use 1 for 45
const MAX_STEP_DOWN := 2        # px followed down per step before a drop becomes a fall
const MAX_FALL_FP := 8 << 16    # terminal velocity (8 px/tick)
## Jump tuning, in hundredths of a pixel per tick (gravity is ~0.111 px/tick^2).
## Apex height ~ Y^2 / (2 * g)   -> Y=200 gives ~18 px
## Air time    ~ 2 * Y / g        -> Y=200 gives ~36 ticks
## Distance    ~ X * air time     -> X=120 gives ~43 px
const JUMP_SPEED_X := 90
const JUMP_SPEED_Y := 210
## Sideways speed for a jump with no direction held, in hundredths of a pixel per tick.
## Distance ~ X * air time -> X=40 gives ~14 px with the default JUMP_SPEED_Y.
const JUMP_STANDING_SPEED_X := 15
const JUMP_STANDING_SPEED_Y := 20

var world: WorldData
var state := GameState.new()
var projectile: Projectile = null
var last_crater: Rect2i = Rect2i()   # for the view to redraw; size 0 = none
var crater_dirty: bool = false
var walk_cooldown: int = 0

func _init(p_world: WorldData) -> void:
	world = p_world
	if not world.players.is_empty():
		state.active_player = world.players[0].id
	var width: int = world.current_level.collision_map.width
	for p in world.players:
		p.facing = 1 if p.location.x * 2 < width else -1

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
	if p.falling:
		return
	projectile = Projectile.new(p.location.x, p.location.y - 6, vx_fp, vy_fp)
	state.mode = GameState.Mode.PROJECTILE_FLIGHT

func tick() -> void:
	state.simulation_step += 1
	if walk_cooldown > 0:
		walk_cooldown -= 1
	match state.mode:
		GameState.Mode.PROJECTILE_FLIGHT:
			_tick_projectile()
		GameState.Mode.TURN_END:
			# Let everyone land (e.g. after a crater) before the next turn.
			if not world.players.any(func(p): return p.falling and p.health > 0):
				_next_turn()
	for p in world.players:
		_settle_player(p)

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

# ---------------------------------------------------------------- movement

## dir: -1 = left, 1 = right, 0 = none. Call every tick the key is held.
func walk(dir: int) -> void:
	if state.mode != GameState.Mode.AIMING or dir == 0:
		return
	var p := world.get_player(state.active_player)
	p.facing = signi(dir)
	if walk_cooldown > 0 or p.falling:
		return
	var t := world.current_level.collision_map
	var nx: int = p.location.x + signi(dir)
	# Keep the whole body inside the world horizontally.
	if nx - PlayerData.BODY_HALF_W < 0 or nx - PlayerData.BODY_HALF_W + PlayerData.BODY_W > t.width:
		return
	for up in range(0, MAX_STEP_UP + 1):
		if _body_free(t, nx, p.location.y - up):
			var ny: int = p.location.y - up
			# Follow the slope down; anything bigger is left for _settle_player to turn into a fall.
			var d := 0
			while d < MAX_STEP_DOWN and not _supported(t, nx, ny):
				ny += 1
				d += 1
			p.location = Vector2i(nx, ny)
			walk_cooldown = WALK_INTERVAL
			return
	# No step height worked: too steep / wall, so the player is blocked.

func _body_free(t: Terrain, x: int, y: int) -> bool:
	return t.rect_is_free(x - PlayerData.BODY_HALF_W, y - PlayerData.BODY_H, PlayerData.BODY_W, PlayerData.BODY_H)

## Supported = the body can't move down one more pixel.
func _supported(t: Terrain, x: int, y: int) -> bool:
	return not _body_free(t, x, y + 1)

func _settle_player(p: PlayerData) -> void:
	if p.health <= 0:
		p.falling = false
		return
	var t := world.current_level.collision_map
	if not p.falling:
		# Embedded (e.g. spawned on a slope): pop up.
		while p.location.y > 0 and not _body_free(t, p.location.x, p.location.y):
			p.location.y -= 1
		if _supported(t, p.location.x, p.location.y):
			return
		# Walked off a ledge or lost the ground: start falling with no velocity.
		p.falling = true
		p.fall_vx = 0
		p.fall_vy = 0
		p.fall_fx = 0
		p.fall_frac = 0
	_tick_airborne(p, t)
	# Fell out the bottom of the world (crater reached the floor).
	if p.location.y > t.height + PlayerData.BODY_H:
		p.health = 0
		p.falling = false

## One tick of ballistic motion, moved one pixel at a time so nothing tunnels.
## Vertical first, then horizontal, so a jump rises before it tries to cross a wall.
func _tick_airborne(p: PlayerData, t: Terrain) -> void:
	p.fall_vy = mini(p.fall_vy + Projectile.GRAVITY_FP, MAX_FALL_FP)
	p.fall_fx += p.fall_vx
	p.fall_frac += p.fall_vy
	var sx: int = p.fall_fx >> Projectile.FP_SHIFT      # arithmetic shift: floors negatives
	var sy: int = p.fall_frac >> Projectile.FP_SHIFT
	p.fall_fx &= Projectile.ONE - 1
	p.fall_frac &= Projectile.ONE - 1

	# Vertical.
	var iy: int = signi(sy)
	for i in absi(sy):
		if _body_free(t, p.location.x, p.location.y + iy):
			p.location.y += iy
		elif iy > 0:
			# Landed.
			p.falling = false
			p.fall_vx = 0
			p.fall_vy = 0
			p.fall_fx = 0
			p.fall_frac = 0
			return
		else:
			p.fall_vy = 0     # bumped a ceiling
			p.fall_frac = 0
			break

	# Horizontal.
	var ix: int = signi(sx)
	for i in absi(sx):
		var nx: int = p.location.x + ix
		var in_world: bool = nx - PlayerData.BODY_HALF_W >= 0 \
			and nx - PlayerData.BODY_HALF_W + PlayerData.BODY_W <= t.width
		if in_world and _body_free(t, nx, p.location.y):
			p.location.x = nx
		else:
			# Blocked this tick. Keep the speed so we continue once above the obstacle,
			# but drop the sub-pixel remainder so it can't build up while pressed against it.
			p.fall_fx = 0
			break
				
## dir: -1 left, 1 right, 0 = hop forward in the facing direction. Record (tick, dir) for replays.
func jump(dir: int) -> void:
	if state.mode != GameState.Mode.AIMING:
		return
	var p := world.get_player(state.active_player)
	if p.falling or p.health <= 0:
		return
	var d: int = signi(dir)
	var speed_x: int = JUMP_SPEED_X
	var speed_y: int = JUMP_SPEED_Y
	if d == 0:
		d = p.facing
		speed_x = JUMP_STANDING_SPEED_X
		speed_y += JUMP_STANDING_SPEED_Y
	else:
		p.facing = d
	p.falling = true
	p.fall_vx = d * speed_x * Projectile.ONE / 100
	p.fall_vy = -speed_y * Projectile.ONE / 100
	p.fall_fx = 0
	p.fall_frac = 0
	
	
			
