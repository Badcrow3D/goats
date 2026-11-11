extends Node2D

signal damaged(amount: int)

enum Facing { LEFT = -1, RIGHT = 1 }
enum Status { ACTIVE, ALIVE, DEAD }

@export var team_id := 0
@export var goat_name := ""
@export var health := 100
@export var energy := 100
@export var facing_direction := Facing.RIGHT
@export var status := Status.ALIVE

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	health = maxi(health - amount, 0)
	if health == 0:
		status = Status.DEAD
	damaged.emit(amount)
