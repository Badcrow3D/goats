# goats — projectile sim (Godot 4.6)

Copy `sim/` and `main.gd` into project. Create `main.tscn` (root Node2D), attach `main.gd`, set it as the main scene. confirm Physics Ticks per Second at 60.

sim/
  player_data.gd   id, name, location, health
  level_data.gd    collision_map (Terrain), terrain_color, background_color
  world_data.gd    players, current_level
  game_state.gd    active_player, mode, simulation_step
  terrain.gd       bitmap mask, sampling, crater carving
  projectile.gd    16.16 fixed-point integrator, normal estimate, reflection
  simulation.gd    fixed-tick driver, turns, explosions/damage
