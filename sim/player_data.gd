class_name PlayerData
extends RefCounted

## Body occupies columns [x-3, x+2] and rows [y-10, y-1]; the solid row at y is what it stands on.
const BODY_W := 6
const BODY_H := 10
const BODY_HALF_W := 3

var id: int
var name: String
var location: Vector2i   # pixel position (feet), in terrain coordinates
var health: int
var facing: int = 1      # -1 = left, 1 = right

# Fall state (fixed-point, same scale as Projectile)
var falling: bool = false
var fall_vy: int = 0
var fall_frac: int = 0
var fall_vx: int = 0     # horizontal velocity while airborne (fixed-point)
var fall_fx: int = 0     # horizontal sub-pixel remainder

func _init(p_id: int, p_name: String, p_location: Vector2i, p_health: int = 100) -> void:
	id = p_id
	name = p_name
	location = p_location
	health = p_health
