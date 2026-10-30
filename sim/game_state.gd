class_name GameState
extends RefCounted

enum Mode { AIMING, PROJECTILE_FLIGHT, TURN_END, GAME_OVER }

var active_player: int = 0          # player id
var mode: Mode = Mode.AIMING
var simulation_step: int = 0        # number of fixed ticks simulated so far
