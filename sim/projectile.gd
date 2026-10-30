class_name Projectile
extends RefCounted
## Fixed-point (16.16) projectile. Only integer ops are used, so results are
## bit-identical on every machine.

const FP_SHIFT := 16
const ONE := 1 << FP_SHIFT

## Tunables (per tick, ticks are fixed at 60 Hz by the Simulation).
const GRAVITY_FP := 7282          # ~0.111 px/tick^2  (= 400 px/s^2 at 60 Hz)
const RESTITUTION := 600          # per mille of normal speed kept after a bounce
const FRICTION := 100             # per mille of tangent speed lost on a bounce
const NORMAL_RADIUS := 5          # sampling radius for surface normal
const MIN_BOUNCE_SPEED2 := 9268 * 9268  # (~0.14 px/tick)^2 in fixed-point; slower than this after a bounce = detonate

enum Event { NONE, BOUNCED, EXPLODED, LEFT_WORLD }

var x: int   # fixed-point pixels
var y: int
var vx: int  # fixed-point pixels per tick
var vy: int
var fuse: int          # ticks until detonation
var bounces: int = 0
var max_bounces: int = 4
var alive: bool = true

func _init(px: int, py: int, p_vx_fp: int, p_vy_fp: int, p_fuse: int = 240) -> void:
	x = px << FP_SHIFT
	y = py << FP_SHIFT
	vx = p_vx_fp
	vy = p_vy_fp
	fuse = p_fuse

func pixel_x() -> int:
	return x >> FP_SHIFT

func pixel_y() -> int:
	return y >> FP_SHIFT

## Advance exactly one fixed tick.
@warning_ignore("integer_division")
func step(terrain: Terrain) -> Event:
	if not alive:
		return Event.NONE
	fuse -= 1
	vy += GRAVITY_FP

	# Sub-step so we never move more than ~1 pixel between samples (no tunnelling).
	var n: int = (maxi(absi(vx), absi(vy)) >> FP_SHIFT) + 1
	var dx: int = vx / n
	var dy: int = vy / n
	var result := Event.NONE

	for i in n:
		var nx: int = x + dx
		var ny: int = y + dy
		var cx: int = nx >> FP_SHIFT
		var cy: int = ny >> FP_SHIFT
		if terrain.is_solid(cx, cy):
			_bounce(terrain, cx, cy)
			bounces += 1
			result = Event.BOUNCED
			break
		x = nx
		y = ny
		var px: int = x >> FP_SHIFT
		var py: int = y >> FP_SHIFT
		if px < 0 or px >= terrain.width or py >= terrain.height:
			alive = false
			return Event.LEFT_WORLD

	if fuse <= 0 or bounces > max_bounces or (result == Event.BOUNCED and vx * vx + vy * vy < MIN_BOUNCE_SPEED2):
		alive = false
		return Event.EXPLODED
	return result

## Surface normal estimate by sampling: every AIR pixel in a disc around the hit
## pixel pushes the normal toward itself. Returns an UN-normalised integer
## vector (only its direction matters, which keeps everything integer).
func estimate_normal(terrain: Terrain, hx: int, hy: int) -> Vector2i:
	var r2: int = NORMAL_RADIUS * NORMAL_RADIUS
	var sum := Vector2i.ZERO
	for oy in range(-NORMAL_RADIUS, NORMAL_RADIUS + 1):
		for ox in range(-NORMAL_RADIUS, NORMAL_RADIUS + 1):
			if ox * ox + oy * oy <= r2 and not terrain.is_solid(hx + ox, hy + oy):
				sum += Vector2i(ox, oy)
	if sum == Vector2i.ZERO:
		# Fully buried or perfectly symmetric: fall back to bouncing straight back.
		var back := Vector2i(-signi(vx), -signi(vy))
		return back if back != Vector2i.ZERO else Vector2i(0, -1)
	return sum

## Reflection with energy loss:
##   v_n = n * (v.n / n.n)         normal component
##   v_t = v - v_n                 tangent component
##   v'  = v_t * (1 - friction) - v_n * restitution
@warning_ignore("integer_division")
func _bounce(terrain: Terrain, hx: int, hy: int) -> void:
	var n: Vector2i = estimate_normal(terrain, hx, hy)
	var n2: int = n.x * n.x + n.y * n.y
	var dot: int = vx * n.x + vy * n.y
	if dot >= 0:
		return  # already moving away from the surface; just keep going
	var vnx: int = n.x * dot / n2
	var vny: int = n.y * dot / n2
	var vtx: int = vx - vnx
	var vty: int = vy - vny
	vx = vtx * (1000 - FRICTION) / 1000 - vnx * RESTITUTION / 1000
	vy = vty * (1000 - FRICTION) / 1000 - vny * RESTITUTION / 1000
