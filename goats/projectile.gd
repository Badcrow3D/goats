extends Node2D

const GoatHurtbox := preload("res://goats/goat_hurtbox.gd")
const LevelItem := preload("res://goats/level_item.gd")

var shooter_hurtbox: GoatHurtbox

# Emitted by the missile and grenade scripts.
@warning_ignore("unused_signal")
signal impacted
@warning_ignore("unused_signal")
signal exploded_at(pixel: Vector2i, direct_hit: Area2D, travel_direction: Vector2)

@export var speed := 220.0
@export var gravity := 400.0
@export var blast_damage := 50

var velocity := Vector2.ZERO
var terrain: Terrain
var terrain_pixel_size := Vector2.ONE
